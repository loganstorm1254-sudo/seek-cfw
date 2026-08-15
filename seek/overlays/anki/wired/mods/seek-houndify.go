package mods

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	seekHoundifyIDPath   = "/data/data/com.anki.victor/persistent/seek/houndify_client_id"
	seekHoundifyKeyPath  = "/data/data/com.anki.victor/persistent/seek/houndify_client_key"
	seekHoundifyTextURL  = "https://api.houndify.com/v1/text"
	seekHoundifyAudioURL = "https://api.houndify.com/v1/audio"
	seekHoundifyUserID   = "vector"
)

func seekHoundifyConfigured() bool {
	id, key, err := seekReadHoundifyCreds()
	return err == nil && id != "" && key != ""
}

func seekReadHoundifyCreds() (id, key string, err error) {
	ib, err := os.ReadFile(seekHoundifyIDPath)
	if err != nil {
		return "", "", errors.New("no Houndify client ID — add one in Speak")
	}
	kb, err := os.ReadFile(seekHoundifyKeyPath)
	if err != nil {
		return "", "", errors.New("no Houndify client key — add one in Speak")
	}
	id = strings.TrimSpace(string(ib))
	key = strings.TrimSpace(string(kb))
	if len(id) < 8 || len(key) < 20 {
		return "", "", errors.New("Houndify client ID/key missing or too short")
	}
	return id, key, nil
}

func seekQuestionBackendReady() bool {
	return seekAnyAIConfigured()
}

func (m *SeekDashboard) handleGetHoundify(w http.ResponseWriter, r *http.Request) {
	configured := false
	masked := ""
	if id, _, err := seekReadHoundifyCreds(); err == nil {
		configured = true
		if len(id) > 10 {
			masked = id[:4] + "…" + id[len(id)-4:]
		} else {
			masked = id[:2] + "…"
		}
	}
	out, _ := json.Marshal(map[string]any{
		"configured": configured,
		"masked":     masked,
	})
	w.Header().Set("Content-Type", "application/json")
	w.Write(out)
}

func (m *SeekDashboard) handleSetHoundify(r *http.Request) error {
	_ = r.ParseMultipartForm(1 << 20)
	_ = r.ParseForm()
	id := strings.TrimSpace(r.FormValue("clientId"))
	key := strings.TrimSpace(r.FormValue("clientKey"))
	if id == "" && key == "" {
		body, _ := io.ReadAll(io.LimitReader(r.Body, 16<<10))
		raw := strings.TrimSpace(string(body))
		if strings.HasPrefix(raw, "{") {
			var j struct {
				ClientID  string `json:"clientId"`
				ClientKey string `json:"clientKey"`
			}
			if json.Unmarshal([]byte(raw), &j) == nil {
				id = strings.TrimSpace(j.ClientID)
				key = strings.TrimSpace(j.ClientKey)
			}
		}
	}
	if id == "" || key == "" || strings.EqualFold(id, "clear") || strings.EqualFold(key, "clear") {
		_ = os.Remove(seekHoundifyIDPath)
		_ = os.Remove(seekHoundifyKeyPath)
		return nil
	}
	if len(id) < 8 {
		return errors.New("Houndify Client ID looks too short")
	}
	if len(key) < 20 {
		return errors.New("Houndify Client Key looks too short")
	}
	if err := os.MkdirAll(filepath.Dir(seekHoundifyIDPath), 0755); err != nil {
		return err
	}
	if err := os.WriteFile(seekHoundifyIDPath, []byte(id+"\n"), 0600); err != nil {
		return err
	}
	return os.WriteFile(seekHoundifyKeyPath, []byte(key+"\n"), 0600)
}

func seekHoundifyUnescapeBase64URL(input string) string {
	s := strings.ReplaceAll(strings.ReplaceAll(input, "-", "+"), "_", "/")
	switch len(s) % 4 {
	case 2:
		s += "=="
	case 3:
		s += "="
	}
	return s
}

func seekHoundifyEscapeBase64URL(input string) string {
	return strings.ReplaceAll(strings.ReplaceAll(input, "+", "-"), "/", "_")
}

// seekHoundifyAuth builds the official Houndify HMAC headers
// (same algorithm as soundhound/houndify-sdk-go).
func seekHoundifyAuth(clientID, clientKey, userID, requestID string, ts int64) (clientAuth, requestAuth string, err error) {
	decoded, err := base64.StdEncoding.DecodeString(seekHoundifyUnescapeBase64URL(clientKey))
	if err != nil {
		return "", "", errors.New("failed to decode Houndify client key")
	}
	mac := hmac.New(sha256.New, decoded)
	_, _ = mac.Write([]byte(userID + ";" + requestID + fmt.Sprintf("%d", ts)))
	sig := seekHoundifyEscapeBase64URL(base64.StdEncoding.EncodeToString(mac.Sum(nil)))
	return fmt.Sprintf("%s;%d;%s", clientID, ts, sig), userID + ";" + requestID, nil
}

func seekHoundifyRequestID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}

type houndifyResult struct {
	SpokenResponseLong  string `json:"SpokenResponseLong"`
	SpokenResponse      string `json:"SpokenResponse"`
	WrittenResponseLong string `json:"WrittenResponseLong"`
	WrittenResponse     string `json:"WrittenResponse"`
	Transcription       string `json:"Transcription"`
}

type houndifyResponse struct {
	Status     string           `json:"Status"`
	AllResults []houndifyResult `json:"AllResults"`
}

func seekParseHoundify(raw []byte) (transcript, answer string, err error) {
	var parsed houndifyResponse
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return "", "", err
	}
	if !strings.EqualFold(parsed.Status, "OK") && parsed.Status != "" {
		return "", "", fmt.Errorf("houndify status %s", parsed.Status)
	}
	if len(parsed.AllResults) == 0 {
		return "", "", errors.New("empty Houndify response")
	}
	r := parsed.AllResults[0]
	answer = strings.TrimSpace(firstNonEmpty(
		r.SpokenResponseLong,
		r.SpokenResponse,
		r.WrittenResponseLong,
		r.WrittenResponse,
	))
	answer = strings.ReplaceAll(answer, "\n", " ")
	if len(answer) > seekAIMaxAnswer {
		answer = strings.TrimSpace(answer[:seekAIMaxAnswer])
		if i := strings.LastIndex(answer, "."); i > 40 {
			answer = answer[:i+1]
		}
	}
	transcript = strings.TrimSpace(firstNonEmpty(r.Transcription, r.WrittenResponse, r.SpokenResponse))
	if answer == "" {
		return transcript, "", errors.New("empty Houndify answer")
	}
	return transcript, answer, nil
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func seekHoundifyDo(method, endpoint string, body io.Reader, extra map[string]any) ([]byte, error) {
	id, key, err := seekReadHoundifyCreds()
	if err != nil {
		return nil, err
	}
	reqID := seekHoundifyRequestID()
	ts := time.Now().Unix()
	clientAuth, requestAuth, err := seekHoundifyAuth(id, key, seekHoundifyUserID, reqID, ts)
	if err != nil {
		return nil, err
	}
	info := map[string]any{
		"TimeStamp":                ts,
		"ClientID":                 id,
		"RequestID":                reqID,
		"UserID":                   seekHoundifyUserID,
		"SDK":                      "go",
		"SDKVersion":               "0.2.0",
		"UnitPreference":           "US",
		"InputLanguageEnglishName": "English",
		"InputLanguageIETFTag":     "en-US",
	}
	for k, v := range extra {
		info[k] = v
	}
	infoJSON, _ := json.Marshal(info)

	req, err := http.NewRequest(method, endpoint, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "SeekOS-Houndify/1.0")
	req.Header.Set("Hound-Request-Authentication", requestAuth)
	req.Header.Set("Hound-Client-Authentication", clientAuth)
	req.Header.Set("Hound-Request-Info", string(infoJSON))
	if strings.Contains(endpoint, "/v1/audio") {
		req.Header.Set("Content-Type", "audio/wav")
	}

	resp, err := seekOpenAIHTTP(45 * time.Second).Do(req)
	if err != nil {
		return nil, fmt.Errorf("robot cannot reach Houndify (%v)", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("houndify %s: %s", resp.Status, truncate(string(raw), 180))
	}
	return raw, nil
}

func seekHoundifyText(question string) (string, error) {
	q := strings.TrimSpace(question)
	if q == "" {
		return "", errors.New("empty question")
	}
	endpoint := seekHoundifyTextURL + "?query=" + url.PathEscape(q)
	raw, err := seekHoundifyDo("POST", endpoint, bytes.NewReader(nil), nil)
	if err != nil {
		return "", err
	}
	_, answer, err := seekParseHoundify(raw)
	return answer, err
}

func seekHoundifyVoice(wav []byte) (transcript, answer string, err error) {
	if len(wav) < 1600 {
		return "", "", errors.New("need more audio")
	}
	raw, err := seekHoundifyDo("POST", seekHoundifyAudioURL, bytes.NewReader(wav), nil)
	if err != nil {
		return "", "", err
	}
	return seekParseHoundify(raw)
}

func seekAnyAIConfigured() bool {
	return seekOvalConfigured() || seekHoundifyConfigured() || seekOpenAIKeyConfigured()
}

func seekAnswerQuestion(question string) (string, error) {
	var lastErr error
	if seekOvalConfigured() {
		ans, err := seekOvalChat(question)
		if err == nil && strings.TrimSpace(ans) != "" {
			return ans, nil
		}
		lastErr = err
	}
	if seekHoundifyConfigured() {
		ans, err := seekHoundifyText(question)
		if err == nil && strings.TrimSpace(ans) != "" {
			return ans, nil
		}
		if lastErr == nil {
			lastErr = err
		}
	}
	if seekOpenAIKeyConfigured() {
		return seekChatGPT(question)
	}
	if lastErr != nil {
		return "", lastErr
	}
	return "", errors.New("save an Oval, Houndify, or OpenAI key in Speak")
}
