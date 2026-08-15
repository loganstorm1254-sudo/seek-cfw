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

// it works well at 533MHz, but transcription is instant at 730
var doFreqStuff bool = true

const (
	seekOpenAIKeyPath   = "/data/data/com.anki.victor/persistent/seek/openai_api_key"
	seekHoundifyIDPath  = "/data/data/com.anki.victor/persistent/seek/houndify_client_id"
	seekHoundifyKeyPath = "/data/data/com.anki.victor/persistent/seek/houndify_client_key"
	seekVoiceAskURL     = "http://127.0.0.1:8080/api/mods/SeekDashboard/voiceAsk"
	// ~5s of 16 kHz mono s16le
	seekMaxPCMBytes = 16000 * 2 * 5
)

func seekAIKeyPresent() bool {
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

// Seek cloudless: Vector hosts his own voice NLU (Vosk + local intents).
// Never dials remote Chipper — that is what caused the cloud-with-X face
// when fistbump / social voice commands failed against vicapi.pvic.xyz.
func (strm *Streamer) init(streamSize int) {
	go strm.cancelResponse()
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
		}()
		return
	}

	// Tell the engine the "cloud" stream opened so it does not treat silence as a server timeout.
	strm.receiver.OnStreamOpen(sessionID)
	log.Println("Seek cloudless: local voice stream", sessionID)

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

		for data := range strm.audioStream {
			if aiOn && len(pcm) < seekMaxPCMBytes {
				pcm = append(pcm, data...)
			}

			text := vtr.Process(data)
			if text == "" {
				continue
			}

			intent, iParam, _ := vtr.ProcessTextAll(text, vtr.IntentList)

			// Seek ChatGPT: free-form questions when an API key is saved.
			if aiOn && (seekLooksLikeQuestion(text) || intent == "intent_system_noaudio") {
				if len(pcm) > 3200 {
					if tr, ans, err := seekCallVoiceAsk(pcm); err == nil && ans != "" {
						q := tr
						if q == "" {
							q = text
						}
						seekSendAIAnswer(strm, q, ans)
						return
					}
				}
				if ans := seekAskTextHTTP(text); ans != "" {
					seekSendAIAnswer(strm, text, ans)
					return
				}
			}

			sendIntentGraphResponse(&chippergrpc2.IntentGraphResponse{
				ResponseType: chippergrpc2.IntentGraphMode_INTENT,
				IsFinal:      true,
				IntentResult: &chippergrpc2.IntentResult{
					Action:     intent,
					Parameters: iParam,
				},
			}, strm.receiver)
			return
		}

		if aiOn && len(pcm) > 3200 {
			if tr, ans, err := seekCallVoiceAsk(pcm); err == nil && ans != "" {
				q := tr
				if q == "" {
					q = "question"
				}
				seekSendAIAnswer(strm, q, ans)
			}
		}
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
