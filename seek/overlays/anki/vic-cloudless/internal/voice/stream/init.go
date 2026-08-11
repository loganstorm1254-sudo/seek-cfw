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
	"github.com/digital-dream-labs/vector-cloud/internal/voice/vtr"
)

// it works well at 533MHz, but transcription is instant at 730
var doFreqStuff bool = true

const (
	seekOpenAIKeyPath = "/data/data/com.anki.victor/persistent/seek/openai_api_key"
	seekVoiceAskURL   = "http://127.0.0.1:8080/api/mods/SeekDashboard/voiceAsk"
	// ~5s of 16 kHz mono s16le
	seekMaxPCMBytes = 16000 * 2 * 5
)

func seekAIKeyPresent() bool {
	b, err := os.ReadFile(seekOpenAIKeyPath)
	return err == nil && len(strings.TrimSpace(string(b))) > 20
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

// WIRE: main entrypoint for a request!
// we are keeping the OG code commented in case we want to make some sort of hybrid solution

func (strm *Streamer) init(streamSize int) {
	// set up error response if context times out/is canceled
	go strm.cancelResponse()

	go strm.bufferRoutine(streamSize)

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
				// Prefer Whisper over the buffered utterance for free-form accuracy.
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
				// Fallback: ask ChatGPT using the (grammar-limited) transcript via HTTP text.
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

		// Stream ended with no Vosk hit — try Whisper+ChatGPT on the buffer.
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
