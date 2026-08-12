package mods

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/digital-dream-labs/vector-go-sdk/pkg/vector"
	"github.com/digital-dream-labs/vector-go-sdk/pkg/vectorpb"
	"github.com/os-vector/wired/vars"
)

const (
	seekFaceWidth         = 184
	seekFaceHeight        = 96
	seekFaceBytes         = seekFaceWidth * seekFaceHeight * 2
	seekMaxUpload         = 32 << 20 // 32 MiB
	seekEyeOverlayPath    = "/data/data/customFaceOverlay.jpg"
	seekEyeReloadFlag     = "/run/seek-eyes/reload"
	seekEyeMaxJPEG        = 2 << 20 // 2 MiB resized JPEG
	seekCustomLightsDir   = "/data/data/customBackpackLights"
	seekAnkiLightsFlag    = "/data/data/enableankilights"
	seekLightsClearedMark = "/data/data/com.anki.victor/persistent/seek/cleared_ld_lights_v1"
)

// SeekDashboard hosts eye color, volume, TTS, media, drive, and camera on Vector's IP.
type SeekDashboard struct {
	vars.Modification

	mu         sync.Mutex
	starting   bool
	holding    bool
	vec        *vector.Vector
	cancel     context.CancelFunc
	ctrlStream vectorpb.ExternalInterface_BehaviorControlClient
	ctrlLost   chan struct{}
	ctrlErr    chan error

	driveMu      sync.Mutex
	driveRunning bool
	driveCancel  context.CancelFunc
	driveL       float32
	driveR       float32
	lastDriveAt  time.Time // last client drive command (watchdog)

	camMu      sync.Mutex
	camRunning bool
	camCancel  context.CancelFunc
	camLatest  []byte
	camSeq     uint64

	audioMu     sync.Mutex
	audioCancel context.CancelFunc
	audioGen    uint64

	danceMu      sync.Mutex
	dancing      bool
	danceCancel  context.CancelFunc
	danceLastErr string
	actionID     uint32

	lastActivity time.Time
	idleOnce     sync.Once
}

func NewSeekDashboard() *SeekDashboard {
	return &SeekDashboard{lastActivity: time.Now()}
}

func (modu *SeekDashboard) Name() string {
	return "SeekDashboard"
}

func (modu *SeekDashboard) Description() string {
	return "Seek web dashboard: eyes, volume, speak, media, drive, camera"
}

func (m *SeekDashboard) Load() error {
	m.touchActivity()
	m.idleOnce.Do(func() {
		go m.idleWatch()
	})
	return nil
}

func (m *SeekDashboard) touchActivity() {
	m.mu.Lock()
	m.lastActivity = time.Now()
	m.mu.Unlock()
}

// idleWatch gently releases SDK control + camera after a few quiet minutes
// so long dashboard sessions don't keep the robot warm. Thermal safety stays intact.
func (m *SeekDashboard) idleWatch() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		m.mu.Lock()
		holding := m.holding
		idleFor := time.Since(m.lastActivity)
		m.mu.Unlock()
		m.camMu.Lock()
		cam := m.camRunning
		m.camMu.Unlock()
		if idleFor < 2*time.Minute {
			continue
		}
		if m.isDancing() {
			continue
		}
		if cam {
			m.cameraStop()
		}
		if holding {
			m.controlEnd()
		}
	}
}

func (m *SeekDashboard) HTTP(w http.ResponseWriter, r *http.Request) {
	if !strings.HasPrefix(r.URL.Path, "/api/mods/"+m.Name()) {
		return
	}
	action := strings.TrimPrefix(r.URL.Path, "/api/mods/"+m.Name()+"/")
	switch action {
	case "status", "moves", "getEyeColor", "getVolume", "cameraFrame", "cameraMjpeg", "getEyeOverlay", "getOpenAIKey", "getSeekLights", "getWifiStatus":
		// read-only / streaming — don't count as "user activity" for idle release
	default:
		m.touchActivity()
	}
	switch action {
	case "getWifiStatus":
		st, err := m.handleGetWifiStatus()
		if err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
		writeWifiJSON(w, st)
		return
	case "wifiScan":
		nets, err := m.handleWifiScan()
		if err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
		writeWifiJSON(w, map[string]any{"networks": nets})
		return
	case "wifiConnect":
		if err := m.handleWifiConnect(r.FormValue("ssid"), r.FormValue("password"), r.FormValue("serviceId")); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
		vars.HTTPSuccess(w, r)
		return
	case "getSeekLights":
		_, errOff := os.Stat(filepath.Join(seekCustomLightsDir, "off.json"))
		_, errAnki := os.Stat(seekAnkiLightsFlag)
		out, _ := json.Marshal(map[string]any{
			"customActive": errOff == nil,
			"ankiLights":   errAnki == nil,
			"path":         seekCustomLightsDir,
		})
		w.Header().Set("Content-Type", "application/json")
		w.Write(out)
		return
	case "applySeekLights":
		if err := m.handleApplySeekLights(); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
		vars.HTTPSuccess(w, r)
		return
	case "getEyeColor":
		resp, err := getEyeColor()
		if err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
		out, _ := json.Marshal(resp)
		w.Header().Set("Content-Type", "application/json")
		w.Write(out)
		return
	case "setEyeColor":
		if err := m.handleSetEyeColor(r); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "getOpenAIKey":
		m.handleGetOpenAIKey(w, r)
		return
	case "setOpenAIKey":
		if err := m.handleSetOpenAIKey(r); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "askAI":
		answer, err := m.handleAskAI(r)
		if err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
		out, _ := json.Marshal(map[string]string{"answer": answer})
		w.Header().Set("Content-Type", "application/json")
		w.Write(out)
		return
	case "voiceAsk":
		m.handleVoiceAsk(w, r)
		return
	case "getEyeOverlay":
		st, err := os.Stat(seekEyeOverlayPath)
		active := err == nil && st.Size() > 0
		var nbytes int64
		if active {
			nbytes = st.Size()
		}
		out, _ := json.Marshal(map[string]any{
			"active": active,
			"bytes":  nbytes,
		})
		w.Header().Set("Content-Type", "application/json")
		w.Write(out)
		return
	case "setEyeOverlay":
		if err := m.handleSetEyeOverlay(r); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "clearEyeOverlay":
		if err := m.handleClearEyeOverlay(); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "getVolume":
		vol, err := getVolume()
		if err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
		w.Write([]byte(strconv.Itoa(vol)))
		return
	case "setVolume":
		v := r.FormValue("volume")
		if v == "" {
			vars.HTTPError(w, r, "empty volume")
			return
		}
		n, err := strconv.Atoi(v)
		if err != nil || n < 0 || n > 5 {
			vars.HTTPError(w, r, "volume must be 0-5")
			return
		}
		if err := setSettingSDKintbool("master_volume", strconv.Itoa(n)); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "sayText":
		text := strings.TrimSpace(r.FormValue("text"))
		if text == "" {
			vars.HTTPError(w, r, "empty text")
			return
		}
		if len(text) > 500 {
			vars.HTTPError(w, r, "text too long (max 500)")
			return
		}
		useVoice := r.FormValue("vectorVoice") != "0"
		if err := m.sayText(text, useVoice); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "playAudio":
		if err := m.handlePlayAudio(w, r); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
		vars.HTTPSuccess(w, r)
		return
	case "playPcm":
		if err := m.handlePlayPcm(r); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "controlStart":
		if err := m.controlStart(); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "controlEnd":
		m.controlEnd()
	case "stopMedia":
		m.stopMedia()
	case "stopAudio":
		m.stopAudio()
	case "macarena":
		vol := parseAudioVolume(r.FormValue("volume"))
		if err := m.startMacarena(vol); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "frame":
		if err := m.handleFrame(r); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "drive":
		if err := m.handleDrive(r); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "stopMotors":
		if err := m.handleStopMotors(); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "moveHead":
		if err := m.handleMoveHead(r); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "moveLift":
		if err := m.handleMoveLift(r); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "cameraStart":
		if err := m.cameraStart(); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "cameraStop":
		m.cameraStop()
	case "cameraFrame":
		m.handleCameraFrame(w, r)
		return
	case "cameraMjpeg":
		m.handleCameraMjpeg(w, r)
		return
	case "moves":
		m.writeMovesCatalog(w)
		return
	case "appIntent":
		if err := m.handleAppIntent(r.FormValue("intent"), r.FormValue("param")); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "playAnim":
		if err := m.handlePlayAnimTrigger(r.FormValue("name")); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "listen":
		if err := m.handleListen(); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "status":
		m.mu.Lock()
		holding := m.holding
		m.mu.Unlock()
		m.camMu.Lock()
		cam := m.camRunning
		m.camMu.Unlock()
		out, _ := json.Marshal(map[string]any{
			"holding":  holding,
			"camera":   cam,
			"dancing":  m.isDancing(),
			"danceErr": m.getDanceErr(),
			"ready":    vars.SDKReady(),
			"macarena": true,
		})
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Type", "application/json")
		w.Write(out)
		return
	default:
		vars.HTTPError(w, r, "unknown action (try /seek.html or /)")
		return
	}
	vars.HTTPSuccess(w, r)
}

func (m *SeekDashboard) handleSetEyeColor(r *http.Request) error {
	mode := r.FormValue("mode")
	if mode == "preset" {
		preset := r.FormValue("preset")
		n, err := strconv.Atoi(preset)
		if err != nil || n < 0 || n > 8 {
			return errors.New("preset must be 0-8")
		}
		// Disable custom color then set preset.
		if err := setSettingSDKJSON(`{"update_settings":true,"settings":{"custom_eye_color":{"enabled":false,"hue":0,"saturation":0}}}`); err != nil {
			return err
		}
		return setSettingSDKintbool("eye_color", strconv.Itoa(n))
	}

	hue, err := strconv.ParseFloat(r.FormValue("hue"), 64)
	if err != nil || hue < 0 || hue > 1 {
		return errors.New("hue must be 0.0-1.0")
	}
	sat, err := strconv.ParseFloat(r.FormValue("saturation"), 64)
	if err != nil || sat < 0 || sat > 1 {
		return errors.New("saturation must be 0.0-1.0")
	}
	payload := fmt.Sprintf(
		`{"update_settings":true,"settings":{"custom_eye_color":{"enabled":true,"hue":%g,"saturation":%g}}}`,
		hue, sat,
	)
	return setSettingSDKJSON(payload)
}

func (m *SeekDashboard) handleSetEyeOverlay(r *http.Request) error {
	// Prefer raw JPEG body (from canvas.toBlob). Also accept multipart "file".
	var data []byte
	ct := r.Header.Get("Content-Type")
	if strings.HasPrefix(ct, "multipart/") {
		if err := r.ParseMultipartForm(seekEyeMaxJPEG + (1 << 20)); err != nil {
			return errors.New("bad multipart upload")
		}
		f, _, err := r.FormFile("file")
		if err != nil {
			return errors.New("missing file")
		}
		defer f.Close()
		data, err = io.ReadAll(io.LimitReader(f, seekEyeMaxJPEG+1))
		if err != nil {
			return err
		}
	} else {
		data, _ = io.ReadAll(io.LimitReader(r.Body, seekEyeMaxJPEG+1))
	}
	if len(data) == 0 {
		return errors.New("empty image")
	}
	if len(data) > seekEyeMaxJPEG {
		return errors.New("image too large (max 2 MiB after resize)")
	}
	// Soft check for JPEG SOI
	if len(data) < 3 || data[0] != 0xff || data[1] != 0xd8 {
		return errors.New("expected JPEG image (resize in the browser first)")
	}

	if err := os.MkdirAll(filepath.Dir(seekEyeOverlayPath), 0755); err != nil {
		return err
	}
	tmp := seekEyeOverlayPath + ".tmp"
	if err := os.WriteFile(tmp, data, 0644); err != nil {
		return err
	}
	if err := os.Rename(tmp, seekEyeOverlayPath); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	_ = os.MkdirAll("/run/seek-eyes", 0755)
	_ = os.WriteFile(seekEyeReloadFlag, []byte("1"), 0644)
	return nil
}

func (m *SeekDashboard) handleClearEyeOverlay() error {
	_ = os.Remove(seekEyeOverlayPath)
	_ = os.MkdirAll("/run/seek-eyes", 0755)
	_ = os.WriteFile(seekEyeReloadFlag, []byte("1"), 0644)
	return nil
}

// handleApplySeekLights removes LD/other custom backpack light packs under /data
// so anim loads Seek WireOS orange/red from the OTA, then restarts anki-robot.
func (m *SeekDashboard) handleApplySeekLights() error {
	_ = os.RemoveAll(seekCustomLightsDir)
	_ = os.Remove(seekAnkiLightsFlag)
	if err := os.MkdirAll(filepath.Dir(seekLightsClearedMark), 0755); err != nil {
		return err
	}
	if err := os.WriteFile(seekLightsClearedMark, []byte("1\n"), 0644); err != nil {
		return err
	}
	go vars.RestartVic()
	return nil
}

func setSettingSDKJSON(payload string) error {
	url := "https://localhost:443/v1/update_settings"
	req, err := http.NewRequest("POST", url, bytes.NewBufferString(payload))
	if err != nil {
		return err
	}
	guid, err := vars.GetGUID()
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+guid)
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Transport: transCfg, Timeout: 15 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("update_settings failed: %s %s", resp.Status, string(body))
	}
	return nil
}

func (m *SeekDashboard) sayText(text string, useVectorVoice bool) error {
	text = strings.TrimSpace(text)
	if text == "" {
		return errors.New("empty text")
	}
	if err := sayTextViaGateway(text, useVectorVoice); err == nil {
		return nil
	} else if !vars.SDKReady() {
		return fmt.Errorf("speak failed (%v) — wait for Vector cloud/SDK to finish starting", err)
	}
	// Fallback: gRPC SDK (needs valid perRuntimeToken + behavior control).
	return m.withControl(func(ctx context.Context, v *vector.Vector) error {
		_, err := v.Conn.SayText(ctx, &vectorpb.SayTextRequest{
			Text:           text,
			UseVectorVoice: useVectorVoice,
			DurationScalar: 1.0,
		})
		return err
	})
}

func sayTextViaGateway(text string, useVectorVoice bool) error {
	guid, err := vars.GetGUID()
	if err != nil {
		return err
	}
	guid = strings.TrimSpace(guid)
	payload := map[string]any{
		"text":           text,
		"useVectorVoice": useVectorVoice,
		"durationScalar": 1.0,
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequest("POST", "https://localhost:443/v1/say_text", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+guid)
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Transport: transCfg, Timeout: 90 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode >= 300 {
		return fmt.Errorf("say_text %s: %s", resp.Status, strings.TrimSpace(string(raw)))
	}
	return nil
}

func (m *SeekDashboard) handlePlayAudio(w http.ResponseWriter, r *http.Request) error {
	_ = w
	if err := r.ParseMultipartForm(seekMaxUpload); err != nil {
		return errors.New("invalid multipart form (max 32MB)")
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		return errors.New("missing file")
	}
	defer file.Close()

	data, err := io.ReadAll(io.LimitReader(file, seekMaxUpload))
	if err != nil {
		return err
	}
	name := strings.ToLower(header.Filename)
	vol := parseAudioVolume(r.FormValue("volume"))

	pcm, rate, err := decodeAudioToPCM(data, name)
	if err != nil {
		return err
	}
	return m.withControl(func(ctx context.Context, v *vector.Vector) error {
		return m.streamPCM(ctx, v, bytes.NewReader(pcm), rate, vol)
	})
}

func (m *SeekDashboard) handlePlayPcm(r *http.Request) error {
	rate := uint32(16000)
	if s := r.FormValue("rate"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n < 8000 || n > 16025 {
			return errors.New("rate must be 8000-16025")
		}
		rate = uint32(n)
	}
	vol := parseAudioVolume(r.FormValue("volume"))
	limited := io.LimitReader(r.Body, seekMaxUpload)

	m.mu.Lock()
	holding := m.holding
	v := m.vec
	m.mu.Unlock()
	if holding && v != nil {
		return m.streamPCM(context.Background(), v, limited, rate, vol)
	}
	return m.withControl(func(ctx context.Context, vec *vector.Vector) error {
		return m.streamPCM(ctx, vec, limited, rate, vol)
	})
}

func (m *SeekDashboard) stopAudio() {
	m.audioMu.Lock()
	cancel := m.audioCancel
	m.audioCancel = nil
	m.audioGen++
	m.audioMu.Unlock()
	if cancel != nil {
		cancel()
	}
}

// stopMedia cancels audio + Macarena + motors + releases control (Stop button).
func (m *SeekDashboard) stopMedia() {
	m.stopDance()
	m.stopAudio()
	m.emergencyStopWheels()
	// Always release — don't wait for the dance goroutine; Stop must feel instant.
	m.controlEnd()
}

func parseAudioVolume(s string) uint32 {
	if s == "" {
		return 100
	}
	n, err := strconv.Atoi(s)
	if err != nil || n < 0 {
		return 100
	}
	if n > 100 {
		return 100
	}
	return uint32(n)
}

func (m *SeekDashboard) handleFrame(r *http.Request) error {
	durationMs := uint32(100)
	if s := r.FormValue("duration_ms"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n < 16 || n > 60000 {
			return errors.New("duration_ms must be 16-60000")
		}
		durationMs = uint32(n)
	}
	data, err := io.ReadAll(io.LimitReader(r.Body, seekFaceBytes+16))
	if err != nil {
		return err
	}
	if len(data) != seekFaceBytes {
		return fmt.Errorf("frame must be %d RGB565 bytes", seekFaceBytes)
	}

	m.mu.Lock()
	holding := m.holding
	v := m.vec
	m.mu.Unlock()
	if !holding || v == nil {
		return errors.New("call controlStart before sending frames")
	}
	_, err = v.Conn.DisplayFaceImageRGB(context.Background(), &vectorpb.DisplayFaceImageRGBRequest{
		FaceData:         data,
		DurationMs:       durationMs,
		InterruptRunning: true,
	})
	return err
}

func (m *SeekDashboard) streamPCM(parent context.Context, v *vector.Vector, pcm io.Reader, rate uint32, volume uint32) error {
	// Replace any in-flight audio so Stop / a new play actually cuts off the old stream.
	m.stopAudio()
	ctx, cancel := context.WithCancel(parent)
	m.audioMu.Lock()
	m.audioCancel = cancel
	m.audioGen++
	myGen := m.audioGen
	m.audioMu.Unlock()
	defer func() {
		m.audioMu.Lock()
		if m.audioGen == myGen {
			m.audioCancel = nil
		}
		m.audioMu.Unlock()
		cancel()
	}()

	stream, err := v.Conn.ExternalAudioStreamPlayback(ctx)
	if err != nil {
		return err
	}
	done := make(chan struct{})
	defer close(done)
	go func() {
		for {
			resp, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case <-done:
				return
			default:
				_ = resp
			}
		}
	}()

	sendCancel := func() {
		_ = stream.Send(&vectorpb.ExternalAudioStreamRequest{
			AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamCancel{
				AudioStreamCancel: &vectorpb.ExternalAudioStreamCancel{},
			},
		})
	}

	if err := stream.Send(&vectorpb.ExternalAudioStreamRequest{
		AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamPrepare{
			AudioStreamPrepare: &vectorpb.ExternalAudioStreamPrepare{
				AudioFrameRate: rate,
				AudioVolume:    volume,
			},
		},
	}); err != nil {
		return err
	}

	const chunkBytes = 1024 // engine max
	buf := make([]byte, chunkBytes)
	var leftover []byte
	start := time.Now()
	sentSamples := 0
	totalRead := 0
	for {
		select {
		case <-ctx.Done():
			sendCancel()
			return nil
		default:
		}
		n, readErr := pcm.Read(buf)
		if n > 0 {
			totalRead += n
			if totalRead > seekMaxUpload {
				return errors.New("audio too large")
			}
			chunk := append(leftover, buf[:n]...)
			for len(chunk) >= 2 {
				select {
				case <-ctx.Done():
					sendCancel()
					return nil
				default:
				}
				take := len(chunk)
				if take > chunkBytes {
					take = chunkBytes
				}
				if take%2 == 1 {
					take--
				}
				if take < 2 {
					break
				}
				send := append([]byte(nil), chunk[:take]...)
				chunk = chunk[take:]
				if err := stream.Send(&vectorpb.ExternalAudioStreamRequest{
					AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamChunk{
						AudioStreamChunk: &vectorpb.ExternalAudioStreamChunk{
							AudioChunkSizeBytes: uint32(len(send)),
							AudioChunkSamples:   send,
						},
					},
				}); err != nil {
					if ctx.Err() != nil {
						sendCancel()
						return nil
					}
					return err
				}
				sentSamples += len(send) / 2
				elapsed := time.Since(start).Seconds()
				expected := elapsed * float64(rate)
				ahead := (float64(sentSamples) - expected) / float64(rate)
				if ahead > 0.75 {
					sleep := time.Duration((ahead - 0.35) * float64(time.Second))
					timer := time.NewTimer(sleep)
					select {
					case <-ctx.Done():
						timer.Stop()
						sendCancel()
						return nil
					case <-timer.C:
					}
				}
			}
			leftover = chunk
		}
		if readErr != nil {
			if errors.Is(readErr, io.EOF) {
				break
			}
			return readErr
		}
	}
	if ctx.Err() != nil {
		sendCancel()
		return nil
	}
	if len(leftover) >= 2 {
		if len(leftover)%2 == 1 {
			leftover = leftover[:len(leftover)-1]
		}
		if err := stream.Send(&vectorpb.ExternalAudioStreamRequest{
			AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamChunk{
				AudioStreamChunk: &vectorpb.ExternalAudioStreamChunk{
					AudioChunkSizeBytes: uint32(len(leftover)),
					AudioChunkSamples:   leftover,
				},
			},
		}); err != nil {
			return err
		}
	}
	if sentSamples == 0 {
		return errors.New("no pcm audio received")
	}
	if err := stream.Send(&vectorpb.ExternalAudioStreamRequest{
		AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamComplete{
			AudioStreamComplete: &vectorpb.ExternalAudioStreamComplete{},
		},
	}); err != nil {
		return err
	}
	time.Sleep(200 * time.Millisecond)
	return nil
}

// streamPCMLive pumps an open-ended mono s16le PCM stream (Doom SFX).
// Unlike streamPCM, it has no upload size cap and stays open until ctx ends.
func (m *SeekDashboard) streamPCMLive(parent context.Context, v *vector.Vector, pcm io.Reader, rate uint32, volume uint32) error {
	m.stopAudio()
	ctx, cancel := context.WithCancel(parent)
	m.audioMu.Lock()
	m.audioCancel = cancel
	m.audioGen++
	myGen := m.audioGen
	m.audioMu.Unlock()
	defer func() {
		m.audioMu.Lock()
		if m.audioGen == myGen {
			m.audioCancel = nil
		}
		m.audioMu.Unlock()
		cancel()
	}()

	stream, err := v.Conn.ExternalAudioStreamPlayback(ctx)
	if err != nil {
		return err
	}
	done := make(chan struct{})
	defer close(done)
	go func() {
		for {
			resp, err := stream.Recv()
			if err != nil {
				return
			}
			select {
			case <-done:
				return
			default:
				_ = resp
			}
		}
	}()

	sendCancel := func() {
		_ = stream.Send(&vectorpb.ExternalAudioStreamRequest{
			AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamCancel{
				AudioStreamCancel: &vectorpb.ExternalAudioStreamCancel{},
			},
		})
	}

	if err := stream.Send(&vectorpb.ExternalAudioStreamRequest{
		AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamPrepare{
			AudioStreamPrepare: &vectorpb.ExternalAudioStreamPrepare{
				AudioFrameRate: rate,
				AudioVolume:    volume,
			},
		},
	}); err != nil {
		return err
	}

	const chunkBytes = 1024
	buf := make([]byte, chunkBytes)
	var leftover []byte
	start := time.Now()
	sentSamples := 0
	for {
		select {
		case <-ctx.Done():
			sendCancel()
			return nil
		default:
		}
		n, readErr := pcm.Read(buf)
		if n > 0 {
			chunk := append(leftover, buf[:n]...)
			for len(chunk) >= 2 {
				select {
				case <-ctx.Done():
					sendCancel()
					return nil
				default:
				}
				take := len(chunk)
				if take > chunkBytes {
					take = chunkBytes
				}
				if take%2 == 1 {
					take--
				}
				if take < 2 {
					break
				}
				send := append([]byte(nil), chunk[:take]...)
				chunk = chunk[take:]
				if err := stream.Send(&vectorpb.ExternalAudioStreamRequest{
					AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamChunk{
						AudioStreamChunk: &vectorpb.ExternalAudioStreamChunk{
							AudioChunkSizeBytes: uint32(len(send)),
							AudioChunkSamples:   send,
						},
					},
				}); err != nil {
					if ctx.Err() != nil {
						sendCancel()
						return nil
					}
					return err
				}
				sentSamples += len(send) / 2
				elapsed := time.Since(start).Seconds()
				expected := elapsed * float64(rate)
				ahead := (float64(sentSamples) - expected) / float64(rate)
				if ahead > 0.6 {
					sleep := time.Duration((ahead - 0.25) * float64(time.Second))
					timer := time.NewTimer(sleep)
					select {
					case <-ctx.Done():
						timer.Stop()
						sendCancel()
						return nil
					case <-timer.C:
					}
				}
			}
			leftover = chunk
		}
		if readErr != nil {
			if errors.Is(readErr, io.EOF) {
				// Doom reconnects between sessions; keep listening only if parent wants.
				if len(leftover) >= 2 {
					if len(leftover)%2 == 1 {
						leftover = leftover[:len(leftover)-1]
					}
					_ = stream.Send(&vectorpb.ExternalAudioStreamRequest{
						AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamChunk{
							AudioStreamChunk: &vectorpb.ExternalAudioStreamChunk{
								AudioChunkSizeBytes: uint32(len(leftover)),
								AudioChunkSamples:   leftover,
							},
						},
					})
					leftover = nil
				}
				return nil
			}
			return readErr
		}
	}
}
