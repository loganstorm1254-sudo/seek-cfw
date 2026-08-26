package stream

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"

	"github.com/digital-dream-labs/api-clients/chipper"
	pb "github.com/digital-dream-labs/api/go/chipperpb"
	"github.com/digital-dream-labs/vector-cloud/internal/log"
)

const seekVoiceTranscribeURL = "http://127.0.0.1:8080/api/mods/SeekDashboard/voiceTranscribe"

func seekCallVoiceTranscribe(pcm []byte) (string, error) {
	req, err := http.NewRequest("POST", seekVoiceTranscribeURL, bytes.NewReader(pcm))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/octet-stream")
	client := &http.Client{Timeout: 45 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("voiceTranscribe %s: %s", resp.Status, string(raw))
	}
	var parsed struct {
		Transcript string `json:"transcript"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", err
	}
	return strings.TrimSpace(parsed.Transcript), nil
}

// Phrases that should enter the Seek ChatGPT Q&A behavior (KnowledgeGraphQuestion).
var seekQuestionPromptRE = regexp.MustCompile(`(?i)^(hey\s+vector[,.]?\s*)?(i\s+have\s+a\s+)?question[.!?]?$|^(hey\s+vector[,.]?\s*)?look\s+up\s+a\s+question(\s+for\s+me)?[.!?]?$`)

func seekIsQuestionPromptText(text string) bool {
	t := strings.TrimSpace(text)
	if t == "" {
		return false
	}
	return seekQuestionPromptRE.MatchString(t)
}

func seekIntentAction(resp *chipper.IntentGraphResponse) string {
	if resp == nil || resp.IntentResult == nil {
		return ""
	}
	return strings.TrimSpace(resp.IntentResult.Action)
}

func seekIntentQuery(resp *chipper.IntentGraphResponse) string {
	if resp == nil {
		return ""
	}
	if q := strings.TrimSpace(resp.QueryText); q != "" {
		return q
	}
	if resp.IntentResult != nil {
		return strings.TrimSpace(resp.IntentResult.QueryText)
	}
	return ""
}

func seekNeedsQuestionRemap(resp *chipper.IntentGraphResponse) bool {
	action := strings.ToLower(seekIntentAction(resp))
	if action == "intent_knowledge_promptquestion" {
		return false
	}
	// Chipper often returns these when the utterance is short / unrecognized.
	if action == "" ||
		strings.Contains(action, "unmatched") ||
		strings.Contains(action, "noaudio") ||
		strings.Contains(action, "no_audio") ||
		strings.Contains(action, "system_unknown") {
		return true
	}
	// Also remap if Chipper transcribed the prompt but bound a different intent.
	return seekIsQuestionPromptText(seekIntentQuery(resp))
}

func seekKnowledgePromptResponse(query string) *chipper.IntentGraphResponse {
	if query == "" {
		query = "question"
	}
	return &chipper.IntentGraphResponse{
		ResponseType: pb.IntentGraphMode_INTENT,
		IsFinal:      true,
		QueryText:    query,
		IntentResult: &chipper.IntentResult{
			QueryText:        query,
			Action:           "intent_knowledge_promptquestion",
			IntentConfidence: 1,
			SpeechConfidence: 1,
		},
	}
}

// seekIntentConn wraps Chipper IntentGraph: buffers PCM so bare "question"
// can be recovered via Whisper when Chipper misses the knowledge prompt.
type seekIntentConn struct {
	inner Conn
	mu    sync.Mutex
	pcm   []byte
}

func newSeekIntentConn(inner Conn) *seekIntentConn {
	return &seekIntentConn{inner: inner}
}

func (c *seekIntentConn) SendAudio(samples []byte) error {
	c.mu.Lock()
	remain := seekMaxPCMBytes - len(c.pcm)
	if remain > 0 {
		chunk := samples
		if len(chunk) > remain {
			chunk = chunk[:remain]
		}
		c.pcm = append(c.pcm, chunk...)
	}
	c.mu.Unlock()
	return c.inner.SendAudio(samples)
}

func (c *seekIntentConn) CloseSend() error {
	return c.inner.CloseSend()
}

func (c *seekIntentConn) Close() error {
	return c.inner.Close()
}

func (c *seekIntentConn) WaitForResponse() (interface{}, error) {
	resp, err := c.inner.WaitForResponse()
	if err != nil {
		return nil, err
	}
	ig, ok := resp.(*chipper.IntentGraphResponse)
	if !ok || ig == nil {
		return resp, nil
	}

	action := seekIntentAction(ig)
	query := seekIntentQuery(ig)

	if action == "intent_knowledge_promptquestion" || seekIsQuestionPromptText(query) {
		seekShowChatGPTLogo()
		if action != "intent_knowledge_promptquestion" {
			log.Println("Seek ChatGPT: remapping transcript to knowledge prompt:", query)
			return seekKnowledgePromptResponse(query), nil
		}
		log.Println("Seek ChatGPT: knowledge prompt — logo on, will say I'm ready")
		return ig, nil
	}

	if !seekNeedsQuestionRemap(ig) {
		return ig, nil
	}

	c.mu.Lock()
	pcm := append([]byte(nil), c.pcm...)
	c.mu.Unlock()
	if len(pcm) < 3200 {
		return ig, nil
	}

	tr, werr := seekCallVoiceTranscribe(pcm)
	if werr != nil {
		log.Println("Seek ChatGPT: question-remap whisper skipped:", werr)
		return ig, nil
	}
	if seekIsQuestionPromptText(tr) {
		seekShowChatGPTLogo()
		log.Println("Seek ChatGPT: Whisper remapped to knowledge prompt:", tr)
		return seekKnowledgePromptResponse(tr), nil
	}
	return ig, nil
}
