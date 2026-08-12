package mods

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/os-vector/wired/vars"
)

const (
	seekLinkPath     = "/data/data/com.anki.victor/persistent/seek/vector_link.json"
	seekLinkUDPPort  = 19734
	seekLinkMagic    = "SEEKLINK1"
	seekLinkHTTPPort = 8080
)

// SeekPeer is another Vector discovered or linked for synced moves.
type SeekPeer struct {
	ESN      string `json:"esn"`
	Name     string `json:"name"`
	IP       string `json:"ip"`
	IsMaster bool   `json:"isMaster"`
	LastSeen int64  `json:"lastSeen"` // unix ms
	Linked   bool   `json:"linked"`
}

type seekLinkState struct {
	IsMaster bool       `json:"isMaster"`
	Peers    []SeekPeer `json:"peers"`
}

type seekLinkBeacon struct {
	Magic    string `json:"magic"`
	ESN      string `json:"esn"`
	Name     string `json:"name"`
	IP       string `json:"ip"`
	IsMaster bool   `json:"isMaster"`
	LinkedN  int    `json:"linkedN"`
}

func (m *SeekDashboard) initLink() {
	m.linkOnce.Do(func() {
		m.linkMu.Lock()
		m.linkState = m.loadLinkState()
		m.linkSeen = map[string]SeekPeer{}
		m.linkMu.Unlock()
		go m.linkBeaconLoop()
		go m.linkListenLoop()
	})
}

func (m *SeekDashboard) loadLinkState() seekLinkState {
	b, err := os.ReadFile(seekLinkPath)
	if err != nil {
		return seekLinkState{}
	}
	var st seekLinkState
	if json.Unmarshal(b, &st) != nil {
		return seekLinkState{}
	}
	return st
}

func (m *SeekDashboard) saveLinkStateLocked() {
	_ = os.MkdirAll(filepath.Dir(seekLinkPath), 0755)
	b, _ := json.MarshalIndent(m.linkState, "", "  ")
	_ = os.WriteFile(seekLinkPath, b, 0600)
}

func seekRobotESN() string {
	out, err := exec.Command("/bin/emr-cat", "e").Output()
	if err == nil {
		if s := strings.TrimSpace(string(out)); s != "" {
			return s
		}
	}
	// Fallback: stable-ish id from machine-id / hostname
	if b, err := os.ReadFile("/etc/machine-id"); err == nil {
		s := strings.TrimSpace(string(b))
		if len(s) > 8 {
			return "VEC-" + strings.ToUpper(s[:8])
		}
	}
	h, _ := os.Hostname()
	if h == "" {
		h = "vector"
	}
	return "VEC-" + h
}

func seekRobotName() string {
	// Custom name if present (WireOS / Vector settings)
	for _, p := range []string{
		"/data/data/com.anki.victor/persistent/customRobotName",
		"/data/data/com.anki.victor/persistent/robot_name",
	} {
		if b, err := os.ReadFile(p); err == nil {
			if s := strings.TrimSpace(string(b)); s != "" && len(s) < 40 {
				return s
			}
		}
	}
	return "Vector"
}

func (m *SeekDashboard) linkSelfIP() string {
	return vars.PreferredLANIP()
}

func (m *SeekDashboard) linkBeaconLoop() {
	t := time.NewTicker(2 * time.Second)
	defer t.Stop()
	for range t.C {
		m.broadcastLinkBeacon()
	}
}

func (m *SeekDashboard) broadcastLinkBeacon() {
	ip := m.linkSelfIP()
	if ip == "" {
		return
	}
	m.linkMu.Lock()
	linkedN := 0
	for _, p := range m.linkState.Peers {
		if p.Linked {
			linkedN++
		}
	}
	msg, _ := json.Marshal(seekLinkBeacon{
		Magic:    seekLinkMagic,
		ESN:      seekRobotESN(),
		Name:     seekRobotName(),
		IP:       ip,
		IsMaster: m.linkState.IsMaster,
		LinkedN:  linkedN,
	})
	m.linkMu.Unlock()

	c, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero, Port: 0})
	if err != nil {
		return
	}
	defer c.Close()
	raw, err := c.SyscallConn()
	if err == nil {
		_ = raw.Control(func(fd uintptr) {
			_ = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_BROADCAST, 1)
		})
	}
	targets := []*net.UDPAddr{
		{IP: net.IPv4bcast, Port: seekLinkUDPPort},
	}
	if strings.HasPrefix(ip, "192.168.42.") {
		targets = append(targets, &net.UDPAddr{IP: net.ParseIP("192.168.42.255"), Port: seekLinkUDPPort})
	}
	// Derive /24 broadcast from our IP when possible
	if parts := strings.Split(ip, "."); len(parts) == 4 {
		bcast := net.ParseIP(parts[0] + "." + parts[1] + "." + parts[2] + ".255")
		if bcast != nil {
			targets = append(targets, &net.UDPAddr{IP: bcast, Port: seekLinkUDPPort})
		}
	}
	for _, a := range targets {
		_, _ = c.WriteToUDP(msg, a)
	}
}

func (m *SeekDashboard) linkListenLoop() {
	pc, err := net.ListenPacket("udp4", fmt.Sprintf(":%d", seekLinkUDPPort))
	if err != nil {
		return
	}
	defer pc.Close()
	buf := make([]byte, 1500)
	self := seekRobotESN()
	for {
		n, _, err := pc.ReadFrom(buf)
		if err != nil {
			return
		}
		var b seekLinkBeacon
		if json.Unmarshal(buf[:n], &b) != nil || b.Magic != seekLinkMagic {
			continue
		}
		if b.ESN == "" || b.ESN == self || b.IP == "" {
			continue
		}
		if b.IP == m.linkSelfIP() {
			continue
		}
		now := time.Now().UnixMilli()
		m.linkMu.Lock()
		prev, ok := m.linkSeen[b.ESN]
		peer := SeekPeer{
			ESN:      b.ESN,
			Name:     b.Name,
			IP:       b.IP,
			IsMaster: b.IsMaster,
			LastSeen: now,
			Linked:   ok && prev.Linked,
		}
		// Preserve linked flag from saved state
		for _, sp := range m.linkState.Peers {
			if sp.ESN == b.ESN && sp.Linked {
				peer.Linked = true
				break
			}
		}
		m.linkSeen[b.ESN] = peer
		m.linkMu.Unlock()
	}
}

func (m *SeekDashboard) handleLinkGet(w http.ResponseWriter, _ *http.Request) {
	m.initLink()
	m.linkMu.Lock()
	defer m.linkMu.Unlock()
	// Merge live sightings into response
	seen := make([]SeekPeer, 0, len(m.linkSeen)+len(m.linkState.Peers))
	byESN := map[string]SeekPeer{}
	for _, p := range m.linkState.Peers {
		byESN[p.ESN] = p
	}
	cutoff := time.Now().Add(-15 * time.Second).UnixMilli()
	for esn, p := range m.linkSeen {
		if p.LastSeen < cutoff && !p.Linked {
			continue
		}
		if saved, ok := byESN[esn]; ok {
			p.Linked = saved.Linked
		}
		byESN[esn] = p
	}
	linkedN := 0
	for _, p := range byESN {
		if p.Linked {
			linkedN++
		}
		seen = append(seen, p)
	}
	out, _ := json.Marshal(map[string]any{
		"isMaster":     m.linkState.IsMaster,
		"esn":          seekRobotESN(),
		"name":         seekRobotName(),
		"ip":           m.linkSelfIP(),
		"peers":        seen,
		"linkedCount":  linkedN,
		"canSyncDance": m.linkState.IsMaster && linkedN >= 1,
		// Vector's BT stack is reserved for the app/cubes; Seek links over Wi‑Fi.
		"transport": "wifi",
		"note":      "Vectors link on the same Wi‑Fi. Bluetooth stays free for the Vector app.",
	})
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.Write(out)
}

func (m *SeekDashboard) handleLinkSetMaster(r *http.Request) error {
	m.initLink()
	_ = r.ParseForm()
	v := strings.TrimSpace(r.FormValue("master"))
	on := v == "1" || strings.EqualFold(v, "true") || strings.EqualFold(v, "on")
	m.linkMu.Lock()
	defer m.linkMu.Unlock()
	m.linkState.IsMaster = on
	m.saveLinkStateLocked()
	return nil
}

func (m *SeekDashboard) handleLinkPeer(r *http.Request) error {
	m.initLink()
	_ = r.ParseForm()
	esn := strings.TrimSpace(r.FormValue("esn"))
	ip := strings.TrimSpace(r.FormValue("ip"))
	name := strings.TrimSpace(r.FormValue("name"))
	link := r.FormValue("link") == "1" || strings.EqualFold(r.FormValue("link"), "true")
	if esn == "" && ip == "" {
		return errors.New("need esn or ip")
	}
	m.linkMu.Lock()
	defer m.linkMu.Unlock()
	if esn == "" {
		// manual IP add
		esn = "IP-" + strings.ReplaceAll(ip, ".", "-")
	}
	if name == "" {
		name = "Vector"
	}
	if seen, ok := m.linkSeen[esn]; ok {
		if ip == "" {
			ip = seen.IP
		}
		if name == "Vector" && seen.Name != "" {
			name = seen.Name
		}
	}
	if ip == "" {
		return errors.New("unknown peer IP — scan first or enter IP")
	}

	found := false
	for i := range m.linkState.Peers {
		if m.linkState.Peers[i].ESN == esn || m.linkState.Peers[i].IP == ip {
			m.linkState.Peers[i].Linked = link
			m.linkState.Peers[i].IP = ip
			m.linkState.Peers[i].Name = name
			m.linkState.Peers[i].ESN = esn
			found = true
			break
		}
	}
	if !found && link {
		m.linkState.Peers = append(m.linkState.Peers, SeekPeer{
			ESN:    esn,
			Name:   name,
			IP:     ip,
			Linked: true,
		})
	}
	if !link {
		// drop unlinked from saved list
		next := m.linkState.Peers[:0]
		for _, p := range m.linkState.Peers {
			if p.Linked {
				next = append(next, p)
			}
		}
		m.linkState.Peers = next
	}
	if s, ok := m.linkSeen[esn]; ok {
		s.Linked = link
		s.IP = ip
		s.Name = name
		m.linkSeen[esn] = s
	}
	m.saveLinkStateLocked()

	// Notify peer so both sides show the link (best-effort).
	if link {
		go m.linkNotifyPeer(ip, true)
	} else {
		go m.linkNotifyPeer(ip, false)
	}
	return nil
}

func (m *SeekDashboard) linkNotifyPeer(ip string, link bool) {
	form := fmt.Sprintf("esn=%s&ip=%s&name=%s&link=%d&fromMaster=%d",
		seekRobotESN(), m.linkSelfIP(), seekRobotName(), boolInt(link), 1)
	url := fmt.Sprintf("http://%s:%d/api/mods/SeekDashboard/linkAccept", ip, seekLinkHTTPPort)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "POST", url, strings.NewReader(form))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return
	}
	_ = resp.Body.Close()
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

// handleLinkAccept is called by another Vector when they link/unlink us.
func (m *SeekDashboard) handleLinkAccept(r *http.Request) error {
	m.initLink()
	_ = r.ParseForm()
	esn := strings.TrimSpace(r.FormValue("esn"))
	ip := strings.TrimSpace(r.FormValue("ip"))
	name := strings.TrimSpace(r.FormValue("name"))
	link := r.FormValue("link") == "1"
	if esn == "" || ip == "" {
		return errors.New("bad linkAccept")
	}
	m.linkMu.Lock()
	defer m.linkMu.Unlock()
	if link {
		found := false
		for i := range m.linkState.Peers {
			if m.linkState.Peers[i].ESN == esn {
				m.linkState.Peers[i].Linked = true
				m.linkState.Peers[i].IP = ip
				m.linkState.Peers[i].Name = name
				found = true
				break
			}
		}
		if !found {
			m.linkState.Peers = append(m.linkState.Peers, SeekPeer{
				ESN: esn, Name: name, IP: ip, Linked: true,
			})
		}
		// Follower by default when accepted from a master
		if r.FormValue("fromMaster") == "1" {
			m.linkState.IsMaster = false
		}
	} else {
		next := m.linkState.Peers[:0]
		for _, p := range m.linkState.Peers {
			if p.ESN != esn {
				next = append(next, p)
			}
		}
		m.linkState.Peers = next
	}
	m.saveLinkStateLocked()
	return nil
}

func (m *SeekDashboard) linkedPeers() []SeekPeer {
	m.initLink()
	m.linkMu.Lock()
	defer m.linkMu.Unlock()
	out := make([]SeekPeer, 0, len(m.linkState.Peers))
	for _, p := range m.linkState.Peers {
		if p.Linked && p.IP != "" && p.IP != m.linkSelfIP() {
			out = append(out, p)
		}
	}
	return out
}

func (m *SeekDashboard) isLinkMaster() bool {
	m.initLink()
	m.linkMu.Lock()
	defer m.linkMu.Unlock()
	return m.linkState.IsMaster
}

// fanoutMacarena tells linked peers to start at the same unix-ms timestamp.
func (m *SeekDashboard) fanoutMacarena(t0Ms int64, volume uint32) (okN int, errs []string) {
	peers := m.linkedPeers()
	var wg sync.WaitGroup
	var mu sync.Mutex
	for _, p := range peers {
		wg.Add(1)
		go func(p SeekPeer) {
			defer wg.Done()
			url := fmt.Sprintf("http://%s:%d/api/mods/SeekDashboard/macarenaSync?t0=%d&volume=%d&master=%s",
				p.IP, seekLinkHTTPPort, t0Ms, volume, seekRobotESN())
			ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
			defer cancel()
			req, err := http.NewRequestWithContext(ctx, "POST", url, nil)
			if err != nil {
				mu.Lock()
				errs = append(errs, p.Name+": "+err.Error())
				mu.Unlock()
				return
			}
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				mu.Lock()
				errs = append(errs, p.Name+": "+err.Error())
				mu.Unlock()
				return
			}
			body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
			_ = resp.Body.Close()
			if resp.StatusCode >= 300 {
				mu.Lock()
				errs = append(errs, fmt.Sprintf("%s: %s", p.Name, bytes.TrimSpace(body)))
				mu.Unlock()
				return
			}
			mu.Lock()
			okN++
			mu.Unlock()
		}(p)
	}
	wg.Wait()
	return okN, errs
}

func (m *SeekDashboard) fanoutStopMedia() {
	for _, p := range m.linkedPeers() {
		go func(ip string) {
			ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
			defer cancel()
			url := fmt.Sprintf("http://%s:%d/api/mods/SeekDashboard/stopMedia", ip, seekLinkHTTPPort)
			req, err := http.NewRequestWithContext(ctx, "POST", url, nil)
			if err != nil {
				return
			}
			resp, err := http.DefaultClient.Do(req)
			if err == nil {
				_ = resp.Body.Close()
			}
		}(p.IP)
	}
}
