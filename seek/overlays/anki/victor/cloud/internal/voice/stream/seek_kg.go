package stream

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	_ "embed"

	"github.com/digital-dream-labs/api-clients/chipper"
	"github.com/digital-dream-labs/vector-cloud/internal/log"
)

//go:embed seek_chatgpt_logo.jpg
var seekChatGPTLogoJPEG []byte

const (
	seekOpenAIKeyPath    = "/data/data/com.anki.victor/persistent/seek/openai_api_key"
	seekOvalKeyPath      = "/data/data/com.anki.victor/persistent/seek/oval_api_key"
	seekHoundifyIDPath   = "/data/data/com.anki.victor/persistent/seek/houndify_client_id"
	seekHoundifyKeyPath  = "/data/data/com.anki.victor/persistent/seek/houndify_client_key"
	seekVoiceAskURL      = "http://127.0.0.1:8080/api/mods/SeekDashboard/voiceAsk"
	seekEyeOverlayPath   = "/data/data/customFaceOverlay.jpg"
	seekEyeOverlayBackup = "/data/data/customFaceOverlay.jpg.seekbak"
	// ~10s of 16 kHz mono s16le (matches KG streamingTimeout)
	seekMaxPCMBytes = 16000 * 2 * 10
)

var (
	seekLogoMu  sync.Mutex
	seekLogoOn  bool
	seekLogoGen uint64
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

func seekShowChatGPTLogo() {
	seekLogoMu.Lock()
	defer seekLogoMu.Unlock()
	if seekLogoOn {
		return
	}
	// Preserve a user-uploaded overlay so Look-tab eyes come back after Q&A.
	if _, err := os.Stat(seekEyeOverlayPath); err == nil {
		if _, err := os.Stat(seekEyeOverlayBackup); err != nil {
			_ = os.Rename(seekEyeOverlayPath, seekEyeOverlayBackup)
		} else {
			_ = os.Remove(seekEyeOverlayPath)
		}
	}
	if err := os.WriteFile(seekEyeOverlayPath, seekChatGPTLogoJPEG, 0644); err != nil {
		log.Println("Seek ChatGPT: could not write face logo:", err)
		return
	}
	seekLogoOn = true
	seekLogoGen++
	gen := seekLogoGen
	log.Println("Seek ChatGPT: face logo on")
	// Safety: if KG never starts / times out, don't leave the logo stuck.
	go func() {
		time.Sleep(60 * time.Second)
		seekLogoMu.Lock()
		still := seekLogoOn && seekLogoGen == gen
		seekLogoMu.Unlock()
		if still {
			seekClearChatGPTLogo()
		}
	}()
}

func seekClearChatGPTLogo() {
	seekLogoMu.Lock()
	defer seekLogoMu.Unlock()
	if !seekLogoOn {
		return
	}
	_ = os.Remove(seekEyeOverlayPath)
	if _, err := os.Stat(seekEyeOverlayBackup); err == nil {
		_ = os.Rename(seekEyeOverlayBackup, seekEyeOverlayPath)
	}
	seekLogoOn = false
	log.Println("Seek ChatGPT: face logo off")
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

// seekKGConn answers Knowledge Graph turns locally via Whisper + ChatGPT
// (wired SeekDashboard /api/mods/SeekDashboard/voiceAsk) instead of Chipper KG.
type seekKGConn struct {
	mu     sync.Mutex
	pcm    []byte
	done   chan struct{}
	once   sync.Once
	resp   interface{}
	err    error
	closed bool
}

func newSeekKGConn(_ *Streamer) *seekKGConn {
	return &seekKGConn{done: make(chan struct{})}
}

func (c *seekKGConn) SendAudio(samples []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return errors.New("seek KG stream closed")
	}
	remain := seekMaxPCMBytes - len(c.pcm)
	if remain <= 0 {
		return nil
	}
	if len(samples) > remain {
		samples = samples[:remain]
	}
	c.pcm = append(c.pcm, samples...)
	return nil
}

func (c *seekKGConn) CloseSend() error {
	c.once.Do(func() {
		go c.finish()
	})
	return nil
}

func (c *seekKGConn) WaitForResponse() (interface{}, error) {
	<-c.done
	return c.resp, c.err
}

func (c *seekKGConn) Close() error {
	c.mu.Lock()
	c.closed = true
	c.mu.Unlock()
	c.once.Do(func() {
		go c.finish()
	})
	<-c.done
	seekClearChatGPTLogo()
	return nil
}

func (c *seekKGConn) finish() {
	defer close(c.done)
	defer seekClearChatGPTLogo()

	c.mu.Lock()
	pcm := c.pcm
	c.mu.Unlock()

	if len(pcm) < 3200 {
		c.err = errors.New("seek KG: not enough audio")
		log.Println(c.err)
		return
	}

	log.Println("Seek ChatGPT: transcribing", len(pcm), "bytes of KG audio")
	tr, ans, err := seekCallVoiceAsk(pcm)
	if err != nil {
		c.err = err
		log.Println("Seek ChatGPT KG error:", err)
		return
	}
	if ans == "" {
		c.err = errors.New("seek KG: empty ChatGPT answer")
		log.Println(c.err)
		return
	}
	q := tr
	if q == "" {
		q = "question"
	}
	log.Println("Seek ChatGPT KG ok:", truncateRunes(q, 80))
	c.resp = &chipper.KnowledgeGraphResponse{
		QueryText:   q,
		SpokenText:  ans,
		CommandType: "seek_chatgpt",
	}
}

func truncateRunes(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}
