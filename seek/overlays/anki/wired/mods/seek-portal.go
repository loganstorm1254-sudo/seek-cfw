package mods

import (
	"bytes"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/os-vector/wired/vars"
	"golang.org/x/net/websocket"
)

const seekPortalPath = "/data/data/com.anki.victor/persistent/seek/portal.json"

type seekPortalCfg struct {
	URL string `json:"url"`
}

type seekPortalMsg struct {
	T      string            `json:"t"`
	ID     string            `json:"id,omitempty"`
	IP     string            `json:"ip,omitempty"`
	SSID   string            `json:"ssid,omitempty"`
	ESN    string            `json:"esn,omitempty"`
	Method string            `json:"method,omitempty"`
	Path   string            `json:"path,omitempty"`
	Header map[string]string `json:"header,omitempty"`
	Body   string            `json:"body,omitempty"` // base64
	Status int               `json:"status,omitempty"`
	Err    string            `json:"err,omitempty"`
}

func (m *SeekDashboard) initPortal() {
	m.portalOnce.Do(func() {
		go m.portalLoop()
	})
}

func seekLoadPortalURL() string {
	b, err := os.ReadFile(seekPortalPath)
	if err != nil {
		return ""
	}
	var c seekPortalCfg
	if json.Unmarshal(b, &c) != nil {
		return strings.TrimSpace(string(b))
	}
	return strings.TrimSpace(c.URL)
}

func seekSavePortalURL(u string) error {
	u = strings.TrimSpace(u)
	if err := os.MkdirAll(filepath.Dir(seekPortalPath), 0755); err != nil {
		return err
	}
	b, _ := json.MarshalIndent(seekPortalCfg{URL: u}, "", "  ")
	return os.WriteFile(seekPortalPath, b, 0600)
}

func (m *SeekDashboard) handleGetPortal(w http.ResponseWriter) {
	m.portalMu.Lock()
	ok := m.portalOK
	m.portalMu.Unlock()
	out, _ := json.Marshal(map[string]any{
		"url":       seekLoadPortalURL(),
		"connected": ok,
		"ip":        vars.PreferredLANIP(),
		"ssid":      vars.WifiSSID(),
	})
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.Write(out)
}

func (m *SeekDashboard) handleSetPortal(r *http.Request) error {
	_ = r.ParseForm()
	u := strings.TrimSpace(r.FormValue("url"))
	if strings.EqualFold(u, "clear") || strings.EqualFold(u, "delete") {
		u = ""
	}
	if u != "" {
		if !strings.HasPrefix(u, "ws://") && !strings.HasPrefix(u, "wss://") {
			if strings.HasPrefix(u, "https://") {
				u = "wss://" + strings.TrimPrefix(u, "https://")
			} else if strings.HasPrefix(u, "http://") {
				u = "ws://" + strings.TrimPrefix(u, "http://")
			} else {
				u = "wss://" + u
			}
		}
		u = strings.TrimRight(u, "/")
		if !strings.HasSuffix(u, "/vector") {
			u += "/vector"
		}
	}
	if err := seekSavePortalURL(u); err != nil {
		return err
	}
	m.portalMu.Lock()
	m.portalKick = true
	m.portalMu.Unlock()
	return nil
}

func (m *SeekDashboard) portalLoop() {
	for {
		urlStr := seekLoadPortalURL()
		if urlStr == "" {
			m.portalMu.Lock()
			m.portalOK = false
			m.portalMu.Unlock()
			time.Sleep(5 * time.Second)
			continue
		}
		if err := m.portalConnect(urlStr); err != nil {
			m.portalMu.Lock()
			m.portalOK = false
			m.portalMu.Unlock()
			time.Sleep(4 * time.Second)
		}
	}
}

func (m *SeekDashboard) portalConnect(rawURL string) error {
	cfg, err := websocket.NewConfig(rawURL, "http://localhost/")
	if err != nil {
		return err
	}
	cfg.TlsConfig = &tls.Config{InsecureSkipVerify: true}
	cfg.Header = http.Header{}
	cfg.Header.Set("User-Agent", "SeekOS-Vector")
	ws, err := websocket.DialConfig(cfg)
	if err != nil {
		return err
	}
	defer ws.Close()
	m.portalMu.Lock()
	m.portalOK = true
	m.portalKick = false
	m.portalMu.Unlock()

	hello, _ := json.Marshal(seekPortalMsg{
		T:    "hello",
		IP:   vars.PreferredLANIP(),
		SSID: vars.WifiSSID(),
		ESN:  seekRobotESN(),
	})
	if err := websocket.Message.Send(ws, string(hello)); err != nil {
		return err
	}

	local := &http.Client{Timeout: 90 * time.Second}
	for {
		m.portalMu.Lock()
		kick := m.portalKick
		m.portalMu.Unlock()
		if kick || seekLoadPortalURL() != rawURL {
			return nil
		}
		_ = ws.SetReadDeadline(time.Now().Add(45 * time.Second))
		var raw string
		if err := websocket.Message.Receive(ws, &raw); err != nil {
			return err
		}
		var msg seekPortalMsg
		if json.Unmarshal([]byte(raw), &msg) != nil {
			continue
		}
		if msg.T == "ping" {
			pong, _ := json.Marshal(seekPortalMsg{T: "pong"})
			_ = websocket.Message.Send(ws, string(pong))
			continue
		}
		if msg.T != "http" || msg.ID == "" || msg.Path == "" {
			continue
		}
		go m.portalServeHTTP(ws, local, msg)
	}
}

func (m *SeekDashboard) portalServeHTTP(ws *websocket.Conn, local *http.Client, msg seekPortalMsg) {
	method := msg.Method
	if method == "" {
		method = "GET"
	}
	p := msg.Path
	if !strings.HasPrefix(p, "/") {
		p = "/" + p
	}
	u := "http://127.0.0.1:8080" + p
	var body io.Reader
	if msg.Body != "" {
		b, err := base64.StdEncoding.DecodeString(msg.Body)
		if err == nil && len(b) > 0 {
			body = bytes.NewReader(b)
		}
	}
	req, err := http.NewRequest(method, u, body)
	if err != nil {
		m.portalReply(ws, seekPortalMsg{T: "http-res", ID: msg.ID, Status: 500, Err: err.Error()})
		return
	}
	for k, v := range msg.Header {
		if strings.EqualFold(k, "Host") || strings.EqualFold(k, "Content-Length") {
			continue
		}
		req.Header.Set(k, v)
	}
	resp, err := local.Do(req)
	if err != nil {
		m.portalReply(ws, seekPortalMsg{T: "http-res", ID: msg.ID, Status: 502, Err: err.Error()})
		return
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	hdr := map[string]string{}
	if ct := resp.Header.Get("Content-Type"); ct != "" {
		hdr["Content-Type"] = ct
	}
	m.portalReply(ws, seekPortalMsg{
		T:      "http-res",
		ID:     msg.ID,
		Status: resp.StatusCode,
		Header: hdr,
		Body:   base64.StdEncoding.EncodeToString(raw),
	})
}

var portalWriteMu sync.Mutex

func (m *SeekDashboard) portalReply(ws *websocket.Conn, msg seekPortalMsg) {
	b, _ := json.Marshal(msg)
	portalWriteMu.Lock()
	defer portalWriteMu.Unlock()
	_ = ws.SetWriteDeadline(time.Now().Add(30 * time.Second))
	_ = websocket.Message.Send(ws, string(b))
}
