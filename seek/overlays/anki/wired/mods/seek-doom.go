package mods

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/digital-dream-labs/vector-go-sdk/pkg/vectorpb"
	"github.com/os-vector/wired/vars"
)

const (
	doomRunDir     = "/run/seek-doom"
	doomStartFlag  = "/run/seek-doom/start"
	doomFrameSock  = "/run/seek-doom/frames.sock"
	doomKeysPath   = "/run/seek-doom/keys"
	doomBin        = "/usr/bin/seek-doom"
	doomWad        = "/usr/share/seek-doom/freedoom1.wad"
	doomFaceW      = 184
	doomFaceH      = 96
	doomFaceBytes  = doomFaceW * doomFaceH * 2
	doomFrameMagic = "FRAM"
)

// SeekDoom hosts Doom on Vector's face and accepts key events from the dashboard.
type SeekDoom struct {
	vars.Modification

	mu      sync.Mutex
	running bool
	cmd     *exec.Cmd
	keysFd  *os.File
	cancel  context.CancelFunc
}

func NewSeekDoom() *SeekDoom {
	return &SeekDoom{}
}

func (m *SeekDoom) Name() string { return "SeekDoom" }

func (m *SeekDoom) Description() string {
	return "Play Doom on Vector's face (Freedoom) with dashboard controls"
}

func (m *SeekDoom) Load() error {
	_ = os.MkdirAll(doomRunDir, 0755)
	go m.watchStartFlag()
	return nil
}

func (m *SeekDoom) watchStartFlag() {
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	for range ticker.C {
		if _, err := os.Stat(doomStartFlag); err != nil {
			continue
		}
		_ = os.Remove(doomStartFlag)
		_ = m.Start()
	}
}

func (m *SeekDoom) IsRunning() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.running
}

func (m *SeekDoom) Start() error {
	m.mu.Lock()
	if m.running {
		m.mu.Unlock()
		return errors.New("doom already running")
	}
	m.mu.Unlock()

	if _, err := os.Stat(doomBin); err != nil {
		return fmt.Errorf("seek-doom binary missing (%s) — reinstall Seek OTA", doomBin)
	}
	if _, err := os.Stat(doomWad); err != nil {
		return fmt.Errorf("freedoom wad missing (%s) — reinstall Seek OTA", doomWad)
	}

	_ = os.MkdirAll(doomRunDir, 0755)
	_ = os.Remove(doomFrameSock)
	_ = os.Remove(doomKeysPath)

	// Named pipe for key events (dashboard → doom).
	if err := syscall.Mkfifo(doomKeysPath, 0666); err != nil && !errors.Is(err, os.ErrExist) {
		return fmt.Errorf("keys fifo: %w", err)
	}

	ln, err := net.Listen("unix", doomFrameSock)
	if err != nil {
		return fmt.Errorf("frame socket: %w", err)
	}
	_ = os.Chmod(doomFrameSock, 0666)

	// Open keys for writing (keep open so doom's open(O_RDONLY) doesn't block forever).
	keysFd, err := os.OpenFile(doomKeysPath, os.O_RDWR, 0666)
	if err != nil {
		_ = ln.Close()
		return fmt.Errorf("open keys: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())

	cmd := exec.CommandContext(ctx, doomBin,
		"-iwad", doomWad,
	)
	cmd.Dir = doomRunDir
	cmd.Env = append(os.Environ(), "HOME="+doomRunDir)
	cmd.Stdout = nil
	cmd.Stderr = nil
	m.mu.Lock()
	m.running = true
	m.cmd = cmd
	m.keysFd = keysFd
	m.cancel = cancel
	m.mu.Unlock()

	go m.serveFrames(ctx, ln)

	if err := cmd.Start(); err != nil {
		cancel()
		_ = keysFd.Close()
		_ = ln.Close()
		m.mu.Lock()
		m.running = false
		m.cmd = nil
		m.keysFd = nil
		m.cancel = nil
		m.mu.Unlock()
		return fmt.Errorf("start doom: %w", err)
	}

	go m.waitCmd(cmd)

	return nil
}

func (m *SeekDoom) waitCmd(cmd *exec.Cmd) {
	_ = cmd.Wait()
	m.Stop()
}

func (m *SeekDoom) Stop() {
	m.mu.Lock()
	cancel := m.cancel
	cmd := m.cmd
	keysFd := m.keysFd
	was := m.running
	m.running = false
	m.cancel = nil
	m.cmd = nil
	m.keysFd = nil
	m.mu.Unlock()

	if !was && cancel == nil && cmd == nil {
		return
	}
	if cancel != nil {
		cancel()
	}
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Signal(syscall.SIGTERM)
		time.Sleep(200 * time.Millisecond)
		_ = cmd.Process.Kill()
	}
	if keysFd != nil {
		_ = keysFd.Close()
	}
	_ = os.Remove(doomFrameSock)
	_ = os.Remove(doomStartFlag)
}

func (m *SeekDoom) serveFrames(ctx context.Context, ln net.Listener) {
	defer ln.Close()
	go func() {
		<-ctx.Done()
		_ = ln.Close()
	}()

	for {
		conn, err := ln.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				return
			}
		}
		go m.handleFrameConn(ctx, conn)
	}
}

func (m *SeekDoom) handleFrameConn(ctx context.Context, conn net.Conn) {
	defer conn.Close()
	buf := make([]byte, 4+doomFaceBytes)

	// Take behavior control once for this session.
	dash := findSeekDashboard()
	if dash != nil {
		_ = dash.controlStartPriority(vectorpb.ControlRequest_OVERRIDE_BEHAVIORS)
	}

	for {
		select {
		case <-ctx.Done():
			if dash != nil {
				dash.controlEnd()
			}
			return
		default:
		}
		if err := conn.SetReadDeadline(time.Now().Add(3 * time.Second)); err != nil {
			return
		}
		if _, err := io.ReadFull(conn, buf); err != nil {
			return
		}
		if string(buf[0:4]) != doomFrameMagic {
			continue
		}
		if dash == nil {
			continue
		}
		dash.mu.Lock()
		v := dash.vec
		holding := dash.holding
		dash.mu.Unlock()
		if !holding || v == nil {
			_ = dash.controlStartPriority(vectorpb.ControlRequest_OVERRIDE_BEHAVIORS)
			dash.mu.Lock()
			v = dash.vec
			dash.mu.Unlock()
			if v == nil {
				continue
			}
		}
		_, _ = v.Conn.DisplayFaceImageRGB(context.Background(), &vectorpb.DisplayFaceImageRGBRequest{
			FaceData:         append([]byte(nil), buf[4:]...),
			DurationMs:       50,
			InterruptRunning: true,
		})
	}
}

func (m *SeekDoom) sendKey(pressed bool, key byte) error {
	m.mu.Lock()
	fd := m.keysFd
	m.mu.Unlock()
	if fd == nil {
		return errors.New("doom not running")
	}
	pair := []byte{0, key}
	if pressed {
		pair[0] = 1
	}
	_, err := fd.Write(pair)
	return err
}

func (m *SeekDoom) HTTP(w http.ResponseWriter, r *http.Request) {
	prefix := "/api/mods/" + m.Name() + "/"
	if !strings.HasPrefix(r.URL.Path, prefix) {
		return
	}
	action := strings.TrimPrefix(r.URL.Path, prefix)
	switch action {
	case "status":
		out, _ := json.Marshal(map[string]any{
			"running": m.IsRunning(),
			"binary":  fileExists(doomBin),
			"wad":     fileExists(doomWad),
		})
		w.Header().Set("Content-Type", "application/json")
		w.Write(out)
		return
	case "start":
		if err := m.Start(); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "stop":
		m.Stop()
		if dash := findSeekDashboard(); dash != nil {
			dash.controlEnd()
		}
	case "key":
		pressed := r.FormValue("pressed") == "1" || r.FormValue("pressed") == "true"
		ks := r.FormValue("code")
		if ks == "" {
			vars.HTTPError(w, r, "missing code")
			return
		}
		n, err := strconv.Atoi(ks)
		if err != nil || n < 0 || n > 255 {
			vars.HTTPError(w, r, "bad code")
			return
		}
		if err := m.sendKey(pressed, byte(n)); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	default:
		vars.HTTPError(w, r, "unknown action")
		return
	}
	vars.HTTPSuccess(w, r)
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// findSeekDashboard locates the registered SeekDashboard instance.
func findSeekDashboard() *SeekDashboard {
	for _, mod := range vars.EnabledMods {
		if d, ok := mod.(*SeekDashboard); ok {
			return d
		}
	}
	return nil
}
