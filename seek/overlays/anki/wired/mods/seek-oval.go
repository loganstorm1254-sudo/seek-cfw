package mods

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	seekOvalKeyPath = "/data/data/com.anki.victor/persistent/seek/oval_api_key"
	seekOvalBaseURL = "https://oval.drpug.shop/v1"
	seekOvalModel   = "vector-engine"
)

func seekOvalConfigured() bool {
	b, err := os.ReadFile(seekOvalKeyPath)
	return err == nil && len(strings.TrimSpace(string(b))) > 8
}

func seekReadOvalKey() (string, error) {
	b, err := os.ReadFile(seekOvalKeyPath)
	if err != nil {
		return "", errors.New("no Oval API key — add one in Speak → Oval")
	}
	key := strings.TrimSpace(string(b))
	if len(key) < 8 {
		return "", errors.New("Oval API key missing or too short")
	}
	return key, nil
}

func (m *SeekDashboard) handleGetOvalKey(w http.ResponseWriter, r *http.Request) {
	configured := false
	masked := ""
	if b, err := os.ReadFile(seekOvalKeyPath); err == nil {
		k := strings.TrimSpace(string(b))
		if len(k) > 6 {
			configured = true
			if len(k) > 10 {
				masked = k[:3] + "…" + k[len(k)-4:]
			} else {
				masked = k[:2] + "…"
			}
		}
	}
	out, _ := json.Marshal(map[string]any{
		"configured": configured,
		"masked":     masked,
		"baseUrl":    seekOvalBaseURL,
		"model":      seekOvalModel,
	})
	w.Header().Set("Content-Type", "application/json")
	w.Write(out)
}

func (m *SeekDashboard) handleSetOvalKey(r *http.Request) error {
	_ = r.ParseMultipartForm(1 << 20)
	_ = r.ParseForm()
	key := strings.TrimSpace(r.FormValue("key"))
	if key == "" {
		body, _ := io.ReadAll(io.LimitReader(r.Body, 8<<10))
		key = strings.TrimSpace(string(body))
		if strings.HasPrefix(key, "{") {
			var j struct {
				Key string `json:"key"`
			}
			if json.Unmarshal([]byte(key), &j) == nil {
				key = strings.TrimSpace(j.Key)
			}
		}
	}
	if key == "" || strings.EqualFold(key, "clear") || strings.EqualFold(key, "delete") {
		_ = os.Remove(seekOvalKeyPath)
		return nil
	}
	if len(key) < 8 {
		return errors.New("Oval API key looks too short")
	}
	if err := os.MkdirAll(filepath.Dir(seekOvalKeyPath), 0755); err != nil {
		return err
	}
	return os.WriteFile(seekOvalKeyPath, []byte(key+"\n"), 0600)
}

// seekOvalChat calls Oval's OpenAI-compatible chat completions API.
func seekOvalChat(question string) (string, error) {
	key, err := seekReadOvalKey()
	if err != nil {
		return "", err
	}
	payload := map[string]any{
		"model": seekOvalModel,
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
	req, err := http.NewRequest("POST", seekOvalBaseURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+key)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "SeekOS-Oval/1.0")
	resp, err := seekOpenAIHTTP(50 * time.Second).Do(req)
	if err != nil {
		return "", fmt.Errorf("robot cannot reach Oval (%v)", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return "", fmt.Errorf("oval %s: %s", resp.Status, truncate(string(raw), 180))
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
		return "", errors.New("empty Oval response")
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
		return "", errors.New("empty Oval answer")
	}
	return ans, nil
}
