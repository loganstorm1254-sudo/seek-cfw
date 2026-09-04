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
	doomFrameSock  = "/run/seek-doom/frames.sock"
	doomAudioSock  = "/run/seek-doom/audio.sock"
	doomKeysPath   = "/run/seek-doom/keys"
	doomLogPath    = "/run/seek-doom/doom.log"
	doomBin        = "/usr/bin/seek-doom"
	doomWad        = "/usr/share/seek-doom/freedoom1.wad"
	doomFaceW      = 184
	doomFaceH      = 96
	doomFaceBytes  = doomFaceW * doomFaceH * 2
	doomFrameMagic = "FRAM"
	doomAudioRate  = 16000
	doomAudioVol   = 70
	// Keep face updates gentle — DisplayFaceImageRGB spam was crashing units.
	doomMinFrameGap = 160 * time.Millisecond // ~6 fps
	doomFaceHoldMs  = 200
)

// SeekDoom hosts Doom on Vector's face; start/stop/keys are web-dashboard only.
type SeekDoom struct {
	vars.Modification

	mu       sync.Mutex
	running  bool
	wantSFX  bool
	cmd      *exec.Cmd
	keysFd   *os.File
	cancel   context.CancelFunc
	lastFace time.Time
}

func NewSeekDoom() *SeekDoom {
	return &SeekDoom{}
}

func (m *SeekDoom) Name() string { return "SeekDoom" }

func (m *SeekDoom) Description() string {
	return "Play Doom on Vector's face (Freedoom) — control from the Seek dashboard"
}

func (m *SeekDoom) Load() error {
	_ = os.MkdirAll(doomRunDir, 0755)
	_ = os.Remove(doomRunDir + "/start")
	return nil
}

func (m *SeekDoom) IsRunning() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.running
}

func (m *SeekDoom) Start(withSFX bool) error {
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

	dash := findSeekDashboard()
	if dash == nil {
		return errors.New("Seek dashboard not loaded")
	}

	// Stop anything else using the speaker/face before we take control.
	dash.stopMedia()
	dash.stopAudio()

	// Long-lived session: DEFAULT priority only.
	// OVERRIDE + re-assert was rebooting units (same bug as Drive).
	if err := dash.controlStartPriority(vectorpb.ControlRequest_DEFAULT); err != nil {
		return fmt.Errorf("behavior control: %w", err)
	}

	_ = os.MkdirAll(doomRunDir, 0755)
	_ = os.Remove(doomFrameSock)
	_ = os.Remove(doomAudioSock)
	_ = os.Remove(doomKeysPath)

	if err := syscall.Mkfifo(doomKeysPath, 0666); err != nil && !errors.Is(err, os.ErrExist) {
		dash.controlEnd()
		return fmt.Errorf("keys fifo: %w", err)
	}

	frameLn, err := net.Listen("unix", doomFrameSock)
	if err != nil {
		dash.controlEnd()
		return fmt.Errorf("frame socket: %w", err)
	}
	_ = os.Chmod(doomFrameSock, 0666)

	var audioLn net.Listener
	if withSFX {
		audioLn, err = net.Listen("unix", doomAudioSock)
		if err != nil {
			_ = frameLn.Close()
			dash.controlEnd()
			return fmt.Errorf("audio socket: %w", err)
		}
		_ = os.Chmod(doomAudioSock, 0666)
	}

	keysFd, err := os.OpenFile(doomKeysPath, os.O_RDWR, 0666)
	if err != nil {
		_ = frameLn.Close()
		if audioLn != nil {
			_ = audioLn.Close()
		}
		dash.controlEnd()
		return fmt.Errorf("open keys: %w", err)
	}

	logFile, _ := os.OpenFile(doomLogPath, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0644)

	ctx, cancel := context.WithCancel(context.Background())

	args := []string{
		"-iwad", doomWad,
		"-skill", "3",
		"-warp", "1", "1",
		"-nomusic",
	}
	if !withSFX {
		args = append(args, "-nosound")
	}

	cmd := exec.CommandContext(ctx, doomBin, args...)
	cmd.Dir = doomRunDir
	cmd.Env = append(os.Environ(), "HOME="+doomRunDir)
	if logFile != nil {
		cmd.Stdout = logFile
		cmd.Stderr = logFile
	}

	m.mu.Lock()
	m.running = true
	m.wantSFX = withSFX
	m.cmd = cmd
	m.keysFd = keysFd
	m.cancel = cancel
	m.lastFace = time.Time{}
	m.mu.Unlock()

	go m.serveFrames(ctx, frameLn, dash)
	if audioLn != nil {
		go m.serveAudio(ctx, audioLn, dash)
	}

	if err := cmd.Start(); err != nil {
		cancel()
		_ = keysFd.Close()
		_ = frameLn.Close()
		if audioLn != nil {
			_ = audioLn.Close()
		}
		if logFile != nil {
			_ = logFile.Close()
		}
		dash.controlEnd()
		m.mu.Lock()
		m.running = false
		m.wantSFX = false
		m.cmd = nil
		m.keysFd = nil
		m.cancel = nil
		m.mu.Unlock()
		return fmt.Errorf("start doom: %w", err)
	}

	// Lower CPU priority so victor/anim keep the robot stable.
	if cmd.Process != nil {
		_ = syscall.Setpriority(syscall.PRIO_PROCESS, cmd.Process.Pid, 10)
	}

	go func() {
		_ = cmd.Wait()
		if logFile != nil {
			_ = logFile.Close()
		}
		m.Stop()
	}()

	return nil
}

func (m *SeekDoom) Stop() {
	m.mu.Lock()
	cancel := m.cancel
	cmd := m.cmd
	keysFd := m.keysFd
	was := m.running
	m.running = false
	m.wantSFX = false
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
	if dash := findSeekDashboard(); dash != nil {
		dash.stopAudio()
	}
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Signal(syscall.SIGTERM)
		time.Sleep(150 * time.Millisecond)
		_ = cmd.Process.Kill()
	}
	if keysFd != nil {
		_ = keysFd.Close()
	}
	_ = os.Remove(doomFrameSock)
	_ = os.Remove(doomAudioSock)
	if dash := findSeekDashboard(); dash != nil {
		dash.controlEnd()
	}
}

func (m *SeekDoom) serveFrames(ctx context.Context, ln net.Listener, dash *SeekDashboard) {
	defer ln.Close()
	go func() {
		<-ctx.Done()
		_ = ln.Close()
	}()

	for {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		go m.handleFrameConn(ctx, conn, dash)
	}
}

func (m *SeekDoom) serveAudio(ctx context.Context, ln net.Listener, dash *SeekDashboard) {
	defer ln.Close()
	go func() {
		<-ctx.Done()
		_ = ln.Close()
	}()

	// Give the game a moment to settle before opening the speaker stream.
	select {
	case <-ctx.Done():
		return
	case <-time.After(1500 * time.Millisecond):
	}

	for {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		go func(c net.Conn) {
			defer c.Close()
			dash.mu.Lock()
			v := dash.vec
			holding := dash.holding
			dash.mu.Unlock()
			// Never re-request control here — that fight reboots units.
			if !holding || v == nil {
				return
			}
			_ = dash.streamPCMLive(ctx, v, c, doomAudioRate, doomAudioVol)
		}(conn)
	}
}

func (m *SeekDoom) handleFrameConn(ctx context.Context, conn net.Conn, dash *SeekDashboard) {
	defer conn.Close()

	frames := make(chan []byte, 1)
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			select {
			case <-ctx.Done():
				return
			case face, ok := <-frames:
				if !ok {
					return
				}
				m.showFace(dash, face)
			}
		}
	}()

	buf := make([]byte, 4+doomFaceBytes)
	defer func() {
		close(frames)
		wg.Wait()
	}()

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}
		if err := conn.SetReadDeadline(time.Now().Add(2 * time.Second)); err != nil {
			return
		}
		if _, err := io.ReadFull(conn, buf); err != nil {
			return
		}
		if string(buf[0:4]) != doomFrameMagic {
			continue
		}
		face := append([]byte(nil), buf[4:]...)
		select {
		case frames <- face:
		default:
			select {
			case <-frames:
			default:
			}
			select {
			case frames <- face:
			default:
			}
		}
	}
}

func (m *SeekDoom) showFace(dash *SeekDashboard, face []byte) {
	if dash == nil || len(face) != doomFaceBytes {
		return
	}

	m.mu.Lock()
	if !m.lastFace.IsZero() && time.Since(m.lastFace) < doomMinFrameGap {
		m.mu.Unlock()
		return
	}
	m.lastFace = time.Now()
	m.mu.Unlock()

	dash.mu.Lock()
	v := dash.vec
	holding := dash.holding
	dash.mu.Unlock()
	// Never re-acquire control mid-session — OVERRIDE/re-assert reboots Vector.
	if !holding || v == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 350*time.Millisecond)
	defer cancel()
	_, _ = v.Conn.DisplayFaceImageRGB(ctx, &vectorpb.DisplayFaceImageRGBRequest{
		FaceData:         face,
		DurationMs:       doomFaceHoldMs,
		InterruptRunning: true,
	})
}

func (m *SeekDoom) sendKey(pressed bool, key byte) error {
	m.mu.Lock()
	fd := m.keysFd
	running := m.running
	m.mu.Unlock()
	if !running || fd == nil {
		return errors.New("doom not running — tap Play Doom first")
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
		m.mu.Lock()
		running := m.running
		sfx := m.wantSFX
		m.mu.Unlock()
		out, _ := json.Marshal(map[string]any{
			"running": running,
			"sfx":     sfx,
			"binary":  fileExists(doomBin),
			"wad":     fileExists(doomWad),
		})
		w.Header().Set("Content-Type", "application/json")
		w.Write(out)
		return
	case "start":
		sfx := r.FormValue("sfx") == "1" || r.FormValue("sfx") == "true"
		if err := m.Start(sfx); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "stop":
		m.Stop()
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

func findSeekDashboard() *SeekDashboard {
	for _, mod := range vars.EnabledMods {
		if d, ok := mod.(*SeekDashboard); ok {
			return d
		}
	}
	return nil
}
