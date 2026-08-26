package stream

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/digital-dream-labs/api-clients/chipper"
	chippergrpc2 "github.com/digital-dream-labs/api/go/chipperpb"
	"github.com/digital-dream-labs/vector-cloud/internal/clad/cloud"
	"github.com/digital-dream-labs/vector-cloud/internal/log"
	"github.com/digital-dream-labs/vector-cloud/internal/voice/vtr"
	"github.com/google/uuid"
)

// CPU freq thrash around every voice turn was correlating with random
// anki-robot restarts on some units. Leave the governor alone.
var doFreqStuff bool = false

const (
	seekOpenAIKeyPath   = "/data/data/com.anki.victor/persistent/seek/openai_api_key"
	seekOvalKeyPath     = "/data/data/com.anki.victor/persistent/seek/oval_api_key"
	seekHoundifyIDPath  = "/data/data/com.anki.victor/persistent/seek/houndify_client_id"
	seekHoundifyKeyPath = "/data/data/com.anki.victor/persistent/seek/houndify_client_key"
	seekVoiceAskURL     = "http://127.0.0.1:8080/api/mods/SeekDashboard/voiceAsk"
	// ~8s of 16 kHz mono s16le (KG follow-up listens a bit longer)
	seekMaxPCMBytes = 16000 * 2 * 8
)

func seekAIKeyPresent() bool {
	if b, err := os.ReadFile(seekOvalKeyPath); err == nil && len(strings.TrimSpace(string(b))) > 8 {
		return true
	}
	if b, err := os.ReadFile(seekOpenAIKeyPath); err == nil && len(strings.TrimSpace(string(b))) > 20 {
		return true
	}
	id, err1 := os.ReadFile(seekHoundifyIDPath)
	key, err2 := os.ReadFile(seekHoundifyKeyPath)
	return err1 == nil && err2 == nil &&
		len(strings.TrimSpace(string(id))) > 8 &&
		len(strings.TrimSpace(string(key))) > 20
}

func seekLooksLikeQuestion(text string) bool {
	t := strings.ToLower(strings.TrimSpace(text))
	if t == "" {
		return false
	}
	// Bare prompt phrases are handled separately (open follow-up listen).
	if seekIsQuestionPrompt(t) {
		return false
	}
	if strings.HasSuffix(t, "?") {
		return true
	}
	keys := []string{
		"what", "who", "why", "how", "when", "where", "which",
		"tell me", "ask", "explain", "define", "is it", "are you",
		"can you", "do you", "will you",
	}
	for _, k := range keys {
		if strings.Contains(t, k) {
			return true
		}
	}
	return false
}

// Stock Vector commands that must never be stolen by Oval/Houndify/OpenAI.
func seekIsLocalCommandIntent(intent string) bool {
	switch intent {
	case "", "intent_system_noaudio", "intent_imperative_unknown":
		return false
	case "intent_knowledge_promptquestion":
		// Handled by Seek: open follow-up listen; answer via Houndify, never Chipper.
		return false
	default:
		return !strings.HasPrefix(intent, "intent_knowledge_")
	}
}

func seekIsQuestionPrompt(text string) bool {
	t := strings.ToLower(strings.TrimSpace(text))
	t = strings.Trim(t, " .,!?")
	t = strings.TrimPrefix(t, "hey vector")
	t = strings.Trim(t, " .,!?")
	switch t {
	case "question", "a question", "i have a question", "i've a question",
		"look up a question", "look up a question for me":
		return true
	default:
		return false
	}
}

func seekIsKnowledgeIntent(intent string) bool {
	return strings.HasPrefix(intent, "intent_knowledge_")
}

func seekCallVoiceAsk(pcm []byte) (transcript, answer string, err error) {
	req, err := http.NewRequest("POST", seekVoiceAskURL, bytes.NewReader(pcm))
	if err != nil {
		return "", "", err
	}
	req.Header.Set("Content-Type", "application/octet-stream")
	client := &http.Client{Timeout: 70 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return "", "", fmt.Errorf("voiceAsk %s: %s", resp.Status, string(raw))
	}
	var parsed struct {
		Transcript string `json:"transcript"`
		Answer     string `json:"answer"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", "", err
	}
	return strings.TrimSpace(parsed.Transcript), strings.TrimSpace(parsed.Answer), nil
}

func seekSendAIAnswer(strm *Streamer, query, answer string) {
	sendKGResponse(&chipper.KnowledgeGraphResponse{
		QueryText:   query,
		SpokenText:  answer,
		CommandType: "seek_chatgpt",
	}, strm.receiver, true)
}

// seekFinishOK stops further responses and tears down the stream context.
// Prefer seekSendSilence / seekSendIntent — finishing with no intent still
// maps to NoIntentHeard → NoCloud (cloud-with-X) in the engine.
func (strm *Streamer) seekFinishOK() {
	strm.respOnce.Do(func() {})
	if strm.cancel != nil {
		strm.cancel()
	}
}

// seekSendSilence tells the engine we heard nothing useful. That is
// EIntentStatus::SilenceTimeout — confused/neutral get-out, NOT NoCloud.
func (strm *Streamer) seekSendSilence() {
	strm.seekSendIntent("intent_system_noaudio", nil)
}

// seekCancelSoft replaces cancelResponse for local Seek streams.
// Stock cancelResponse calls OnError(Timeout) when the 9s deadline hits;
// with Wi‑Fi up the engine maps that to the cloud-with-X face. Houndify
// answers often take longer than 9s, so we must never emit Timeout here.
func (strm *Streamer) seekCancelSoft() {
	done := strm.ctx.Done()
	if done == nil {
		return
	}
	<-done
	if strm.closed {
		return
	}
	log.Println("Seek cloudless: soft close (no Timeout/OnError → no cloud-with-X)")
	if strm.cancel != nil {
		strm.cancel()
	}
}

func (strm *Streamer) seekSendIntent(intent string, params map[string]string) {
	sendIntentGraphResponse(&chippergrpc2.IntentGraphResponse{
		ResponseType: chippergrpc2.IntentGraphMode_INTENT,
		IsFinal:      true,
		IntentResult: &chippergrpc2.IntentResult{
			Action:     intent,
			Parameters: params,
		},
	}, strm.receiver)
	strm.seekFinishOK()
}

func (strm *Streamer) seekAnswerOrFallback(pcm []byte, textHint string) {
	q := strings.TrimSpace(textHint)
	if q == "" {
		q = "question"
	}
	if !seekAIKeyPresent() {
		seekSendAIAnswer(strm, q, "Save a Houndify Client ID and Key on my dash to answer questions.")
		strm.seekFinishOK()
		return
	}
	if ans := seekAskTextHTTP(q); ans != "" && !seekIsQuestionPrompt(q) {
		seekSendAIAnswer(strm, q, ans)
		strm.seekFinishOK()
		return
	}
	if len(pcm) > 3200 {
		if tr, ans, err := seekCallVoiceAsk(pcm); err == nil && ans != "" {
			if strings.TrimSpace(tr) != "" {
				q = tr
			}
			seekSendAIAnswer(strm, q, ans)
			strm.seekFinishOK()
			return
		} else if err != nil {
			log.Println("Seek voiceAsk error:", err)
		}
	}
	seekSendAIAnswer(strm, q, "I couldn't reach Houndify. Check Wi-Fi and your Client ID and Key on the dash.")
	strm.seekFinishOK()
}

// Seek cloudless: Vector hosts his own voice NLU (Vosk + local intents).
// Never dials remote Chipper — that is what caused the cloud-with-X face
// when fistbump / social voice commands failed against vicapi.pvic.xyz.
func (strm *Streamer) init(streamSize int) {
	go strm.seekCancelSoft()
	go strm.bufferRoutine(streamSize)

	sessionID := "seek-local-" + uuid.New().String()[:8]

	// Face-info / CheckCloud: report Available without touching the internet.
	if strm.opts.checkOpts != nil {
		go func() {
			strm.receiver.OnStreamOpen(sessionID)
			exp := uint8(0)
			if strm.opts.checkOpts.AudioPerRequestMs > 0 {
				exp = uint8(strm.opts.checkOpts.TotalAudioMs / strm.opts.checkOpts.AudioPerRequestMs)
			}
			strm.receiver.OnConnectionResult(&cloud.ConnectionResult{
				Code:            cloud.ConnectionCode_Available,
				Status:          "Success",
				NumPackets:      exp,
				ExpectedPackets: exp,
			})
			log.Println("Seek cloudless: connection check → Available (local)")
			strm.seekFinishOK()
		}()
		return
	}

	// Tell the engine the "cloud" stream opened so it does not treat silence as a server timeout.
	strm.receiver.OnStreamOpen(sessionID)
	kgMode := strm.opts.kgOpts != nil
	log.Println("Seek cloudless: local voice stream", sessionID, "kg=", kgMode)

	go func() {
		var curFreq string
		var underClockAfter bool
		if doFreqStuff {
			curFreq = vtr.GetFreq()
			o, err := strconv.Atoi(curFreq)
			if err == nil {
				if o < 729600 {
					underClockAfter = true
					go vtr.SetFreq("729600", "600000")
				}
			}
		}
		defer func() {
			if doFreqStuff && underClockAfter {
				vtr.SetFreq(curFreq, "400000")
			}
		}()

		aiOn := seekAIKeyPresent()
		var pcm []byte
		var lastText string

		for data := range strm.audioStream {
			if len(pcm) < seekMaxPCMBytes {
				pcm = append(pcm, data...)
			}

			// Knowledge Graph follow-up ("Go ahead…"): free speech — don't force
			// Vosk grammar matches; buffer PCM and answer via Houndify at end.
			if kgMode {
				continue
			}

			text := vtr.Process(data)
			if text == "" {
				continue
			}
			lastText = text

			intent, iParam, _ := vtr.ProcessTextAll(text, vtr.IntentList)

			// "I have a question" → open stock follow-up listen (second stream is kgMode).
			if seekIsQuestionPrompt(text) || intent == "intent_knowledge_promptquestion" {
				log.Println("Seek cloudless: question prompt → open KG follow-up")
				strm.seekSendIntent("intent_knowledge_promptquestion", iParam)
				return
			}

			// Prefer stock local intents (explore, play, greetings, how old, …).
			if seekIsLocalCommandIntent(intent) {
				strm.seekSendIntent(intent, iParam)
				return
			}

			// Free-form question on the first listen (no separate "I have a question").
			if aiOn && (seekLooksLikeQuestion(text) || intent == "intent_system_noaudio" || seekIsKnowledgeIntent(intent)) {
				strm.seekAnswerOrFallback(pcm, text)
				return
			}

			strm.seekSendIntent(intent, iParam)
			return
		}

		// End of audio (AudioDone / soft close closed the channel).
		if kgMode {
			log.Println("Seek cloudless: KG follow-up → Houndify/voiceAsk")
			strm.seekAnswerOrFallback(pcm, lastText)
			return
		}
		if aiOn && len(pcm) > 3200 {
			// Free-form / empty ASR: still try Houndify on PCM (soft-cancel
			// already prevents Timeout→cloud-with-X while voiceAsk runs).
			strm.seekAnswerOrFallback(pcm, lastText)
			return
		}
		// No match / empty ASR — silence intent, never bare finish (NoCloud).
		log.Println("Seek cloudless: no match → silence (avoid cloud-with-X)")
		strm.seekSendSilence()
	}()
}

func seekAskTextHTTP(question string) string {
	form := strings.NewReader("text=" + url.QueryEscape(question) + "&speak=0")
	r, err := http.NewRequest("POST", "http://127.0.0.1:8080/api/mods/SeekDashboard/askAI", form)
	if err != nil {
		return ""
	}
	r.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	client := &http.Client{Timeout: 50 * time.Second}
	resp, err := client.Do(r)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return ""
	}
	var parsed struct {
		Answer string `json:"answer"`
	}
	if json.Unmarshal(raw, &parsed) != nil {
		return ""
	}
	return strings.TrimSpace(parsed.Answer)
}
