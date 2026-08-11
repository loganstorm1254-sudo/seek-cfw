package mods

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/os-vector/wired/vars"
)

const (
	seekOpenAIKeyPath = "/data/data/com.anki.victor/persistent/seek/openai_api_key"
	seekAIModel       = "gpt-4o-mini"
	seekAIMaxAnswer   = 280 // keep SayText / KG answers short
)

func seekOpenAIKeyConfigured() bool {
	b, err := os.ReadFile(seekOpenAIKeyPath)
	return err == nil && len(strings.TrimSpace(string(b))) > 10
}

func (m *SeekDashboard) handleGetOpenAIKey(w http.ResponseWriter, r *http.Request) {
	configured := false
	masked := ""
	if b, err := os.ReadFile(seekOpenAIKeyPath); err == nil {
		k := strings.TrimSpace(string(b))
		if len(k) > 8 {
			configured = true
			masked = k[:3] + "…" + k[len(k)-4:]
		}
	}
	out, _ := json.Marshal(map[string]any{
		"configured": configured,
		"masked":     masked,
	})
	w.Header().Set("Content-Type", "application/json")
	w.Write(out)
}

func (m *SeekDashboard) handleSetOpenAIKey(r *http.Request) error {
	key := strings.TrimSpace(r.FormValue("key"))
	if key == "" {
		// raw body fallback
		body, _ := io.ReadAll(io.LimitReader(r.Body, 256))
		key = strings.TrimSpace(string(body))
	}
	if key == "" || strings.EqualFold(key, "clear") || strings.EqualFold(key, "delete") {
		_ = os.Remove(seekOpenAIKeyPath)
		return nil
	}
	if !strings.HasPrefix(key, "sk-") || len(key) < 20 {
		return errors.New("expected an OpenAI API key starting with sk-")
	}
	if err := os.MkdirAll(filepath.Dir(seekOpenAIKeyPath), 0755); err != nil {
		return err
	}
	return os.WriteFile(seekOpenAIKeyPath, []byte(key+"\n"), 0600)
}

func (m *SeekDashboard) handleAskAI(r *http.Request) (string, error) {
	q := strings.TrimSpace(r.FormValue("text"))
	if q == "" {
		body, _ := io.ReadAll(io.LimitReader(r.Body, 4096))
		q = strings.TrimSpace(string(body))
		// Also accept JSON {"text":"..."}
		if strings.HasPrefix(q, "{") {
			var j struct {
				Text string `json:"text"`
			}
			if json.Unmarshal([]byte(q), &j) == nil {
				q = strings.TrimSpace(j.Text)
			}
		}
	}
	if q == "" {
		return "", errors.New("empty question")
	}
	if len(q) > 800 {
		return "", errors.New("question too long")
	}
	answer, err := seekChatGPT(q)
	if err != nil {
		return "", err
	}
	// speak=0 skips TTS (cloudless voice path speaks via Knowledge Graph).
	if r.FormValue("speak") != "0" {
		_ = m.sayText(answer, true)
	}
	return answer, nil
}

// handleVoiceAsk receives raw s16le @16kHz PCM (or a tiny WAV) from cloudless
// after "Hey Vector", runs Whisper + ChatGPT, returns JSON {answer,transcript}.
func (m *SeekDashboard) handleVoiceAsk(w http.ResponseWriter, r *http.Request) {
	data, err := io.ReadAll(io.LimitReader(r.Body, 2<<20))
	if err != nil || len(data) < 1600 {
		vars.HTTPError(w, r, "need more audio")
		return
	}
	wav := data
	if !(len(data) > 12 && string(data[0:4]) == "RIFF") {
		wav = pcm16ToWav(data, 16000)
	}
	transcript, err := seekWhisper(wav)
	if err != nil {
		vars.HTTPError(w, r, "whisper: "+err.Error())
		return
	}
	transcript = strings.TrimSpace(transcript)
	if transcript == "" {
		vars.HTTPError(w, r, "could not hear a question")
		return
	}
	answer, err := seekChatGPT(transcript)
	if err != nil {
		vars.HTTPError(w, r, "chatgpt: "+err.Error())
		return
	}
	out, _ := json.Marshal(map[string]string{
		"transcript": transcript,
		"answer":     answer,
	})
	w.Header().Set("Content-Type", "application/json")
	w.Write(out)
}

func seekReadAPIKey() (string, error) {
	b, err := os.ReadFile(seekOpenAIKeyPath)
	if err != nil {
		return "", errors.New("no OpenAI key — add one in Speak → ChatGPT")
	}
	key := strings.TrimSpace(string(b))
	if len(key) < 20 {
		return "", errors.New("OpenAI key missing or invalid")
	}
	return key, nil
}

func seekChatGPT(question string) (string, error) {
	key, err := seekReadAPIKey()
	if err != nil {
		return "", err
	}
	payload := map[string]any{
		"model": seekAIModel,
		"messages": []map[string]string{
			{
				"role": "system",
				"content": "You are Vector, a small friendly robot. Answer briefly out loud " +
					"(1-3 short sentences, under 220 characters). No markdown, no lists, no emojis.",
			},
			{"role": "user", "content": question},
		},
		"max_tokens":  120,
		"temperature": 0.7,
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequest("POST", "https://api.openai.com/v1/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+key)
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 45 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("openai %s: %s", resp.Status, truncate(string(raw), 180))
	}
	var parsed struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", err
	}
	if len(parsed.Choices) == 0 {
		return "", errors.New("empty ChatGPT response")
	}
	ans := strings.TrimSpace(parsed.Choices[0].Message.Content)
	ans = strings.ReplaceAll(ans, "\n", " ")
	if len(ans) > seekAIMaxAnswer {
		ans = strings.TrimSpace(ans[:seekAIMaxAnswer])
		if i := strings.LastIndex(ans, "."); i > 40 {
			ans = ans[:i+1]
		}
	}
	if ans == "" {
		return "", errors.New("empty answer")
	}
	return ans, nil
}

func seekWhisper(wav []byte) (string, error) {
	key, err := seekReadAPIKey()
	if err != nil {
		return "", err
	}
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	_ = w.WriteField("model", "whisper-1")
	_ = w.WriteField("language", "en")
	_ = w.WriteField("response_format", "json")
	part, err := w.CreateFormFile("file", "vector.wav")
	if err != nil {
		return "", err
	}
	if _, err := part.Write(wav); err != nil {
		return "", err
	}
	_ = w.Close()

	req, err := http.NewRequest("POST", "https://api.openai.com/v1/audio/transcriptions", &buf)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+key)
	req.Header.Set("Content-Type", w.FormDataContentType())
	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("whisper %s: %s", resp.Status, truncate(string(raw), 180))
	}
	var parsed struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", err
	}
	return strings.TrimSpace(parsed.Text), nil
}

func pcm16ToWav(pcm []byte, rate int) []byte {
	dataLen := len(pcm)
	buf := make([]byte, 44+dataLen)
	copy(buf[0:], []byte("RIFF"))
	binary.LittleEndian.PutUint32(buf[4:], uint32(36+dataLen))
	copy(buf[8:], []byte("WAVE"))
	copy(buf[12:], []byte("fmt "))
	binary.LittleEndian.PutUint32(buf[16:], 16)
	binary.LittleEndian.PutUint16(buf[20:], 1) // PCM
	binary.LittleEndian.PutUint16(buf[22:], 1) // mono
	binary.LittleEndian.PutUint32(buf[24:], uint32(rate))
	binary.LittleEndian.PutUint32(buf[28:], uint32(rate*2))
	binary.LittleEndian.PutUint16(buf[32:], 2)
	binary.LittleEndian.PutUint16(buf[34:], 16)
	copy(buf[36:], []byte("data"))
	binary.LittleEndian.PutUint32(buf[40:], uint32(dataLen))
	copy(buf[44:], pcm)
	return buf
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
