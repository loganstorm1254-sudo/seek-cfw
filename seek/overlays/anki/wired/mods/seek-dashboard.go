package mods

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/digital-dream-labs/vector-go-sdk/pkg/vector"
	"github.com/digital-dream-labs/vector-go-sdk/pkg/vectorpb"
	"github.com/os-vector/wired/vars"
)

const (
	seekFaceWidth  = 184
	seekFaceHeight = 96
	seekFaceBytes  = seekFaceWidth * seekFaceHeight * 2
	seekMaxUpload  = 12 << 20 // 12 MiB
)

// SeekDashboard hosts eye color, volume, TTS, and media controls on Vector's IP.
type SeekDashboard struct {
	vars.Modification

	mu      sync.Mutex
	holding bool
	stop    chan bool
	start   chan bool
	vec     *vector.Vector
	cancel  context.CancelFunc
}

func NewSeekDashboard() *SeekDashboard {
	return &SeekDashboard{}
}

func (modu *SeekDashboard) Name() string {
	return "SeekDashboard"
}

func (modu *SeekDashboard) Description() string {
	return "Seek web dashboard: eyes, volume, say text, play audio/video"
}

func (modu *SeekDashboard) Load() error {
	return nil
}

func (m *SeekDashboard) HTTP(w http.ResponseWriter, r *http.Request) {
	if !strings.HasPrefix(r.URL.Path, "/api/mods/"+m.Name()) {
		return
	}
	action := strings.TrimPrefix(r.URL.Path, "/api/mods/"+m.Name()+"/")
	switch action {
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
	case "frame":
		if err := m.handleFrame(r); err != nil {
			vars.HTTPError(w, r, err.Error())
			return
		}
	case "status":
		m.mu.Lock()
		holding := m.holding
		m.mu.Unlock()
		out, _ := json.Marshal(map[string]any{"holding": holding})
		w.Header().Set("Content-Type", "application/json")
		w.Write(out)
		return
	default:
		vars.HTTPError(w, r, "404 not found")
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
	return m.withControl(func(ctx context.Context, v *vector.Vector) error {
		_, err := v.Conn.SayText(ctx, &vectorpb.SayTextRequest{
			Text:           text,
			UseVectorVoice: useVectorVoice,
			DurationScalar: 1.0,
		})
		return err
	})
}

func (m *SeekDashboard) handlePlayAudio(w http.ResponseWriter, r *http.Request) error {
	_ = w
	if err := r.ParseMultipartForm(seekMaxUpload); err != nil {
		return errors.New("invalid multipart form (max 12MB)")
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
		return streamPCM(ctx, v, pcm, rate, vol)
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
	data, err := io.ReadAll(io.LimitReader(r.Body, seekMaxUpload))
	if err != nil {
		return err
	}
	if len(data) < 2 || len(data)%2 != 0 {
		return errors.New("pcm must be 16-bit little-endian mono")
	}

	m.mu.Lock()
	holding := m.holding
	v := m.vec
	m.mu.Unlock()
	if holding && v != nil {
		return streamPCM(context.Background(), v, data, rate, vol)
	}
	return m.withControl(func(ctx context.Context, vec *vector.Vector) error {
		return streamPCM(ctx, vec, data, rate, vol)
	})
}

func parseAudioVolume(s string) uint32 {
	if s == "" {
		return 80
	}
	n, err := strconv.Atoi(s)
	if err != nil || n < 0 {
		return 80
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

func (m *SeekDashboard) controlStart() error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.holding {
		return nil
	}
	v, err := vars.GetVec()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithCancel(context.Background())
	start := make(chan bool, 1)
	stop := make(chan bool, 1)
	errCh := make(chan error, 1)
	go func() {
		errCh <- v.BehaviorControl(ctx, start, stop)
	}()
	select {
	case <-start:
		m.holding = true
		m.stop = stop
		m.start = start
		m.vec = v
		m.cancel = cancel
		return nil
	case err := <-errCh:
		cancel()
		if err == nil {
			err = errors.New("behavior control ended early")
		}
		return err
	case <-time.After(20 * time.Second):
		cancel()
		stop <- true
		return errors.New("timeout waiting for behavior control")
	}
}

func (m *SeekDashboard) controlEnd() {
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.holding {
		return
	}
	select {
	case m.stop <- true:
	default:
	}
	if m.cancel != nil {
		m.cancel()
	}
	m.holding = false
	m.vec = nil
	m.stop = nil
	m.start = nil
	m.cancel = nil
}

func (m *SeekDashboard) withControl(fn func(context.Context, *vector.Vector) error) error {
	m.mu.Lock()
	if m.holding && m.vec != nil {
		v := m.vec
		m.mu.Unlock()
		return fn(context.Background(), v)
	}
	m.mu.Unlock()

	v, err := vars.GetVec()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	start := make(chan bool, 1)
	stop := make(chan bool, 1)
	errCh := make(chan error, 1)
	go func() {
		errCh <- v.BehaviorControl(ctx, start, stop)
	}()
	select {
	case <-start:
	case err := <-errCh:
		if err == nil {
			err = errors.New("behavior control ended early")
		}
		return err
	case <-time.After(20 * time.Second):
		stop <- true
		return errors.New("timeout waiting for behavior control")
	}
	defer func() {
		select {
		case stop <- true:
		default:
		}
	}()
	return fn(ctx, v)
}

func streamPCM(ctx context.Context, v *vector.Vector, pcm []byte, rate uint32, volume uint32) error {
	stream, err := v.Conn.ExternalAudioStreamPlayback(ctx)
	if err != nil {
		return err
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

	const chunkSamples = 512 // 1024 bytes max
	chunkBytes := chunkSamples * 2
	start := time.Now()
	sentSamples := 0
	for offset := 0; offset < len(pcm); offset += chunkBytes {
		end := offset + chunkBytes
		if end > len(pcm) {
			end = len(pcm)
		}
		chunk := pcm[offset:end]
		if err := stream.Send(&vectorpb.ExternalAudioStreamRequest{
			AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamChunk{
				AudioStreamChunk: &vectorpb.ExternalAudioStreamChunk{
					AudioChunkSizeBytes: uint32(len(chunk)),
					AudioChunkSamples:   chunk,
				},
			},
		}); err != nil {
			return err
		}
		sentSamples += len(chunk) / 2
		elapsed := time.Since(start).Seconds()
		expected := elapsed * float64(rate)
		ahead := (float64(sentSamples) - expected) / float64(rate)
		if ahead > 1.0 {
			time.Sleep(time.Duration((ahead - 0.5) * float64(time.Second)))
		}
	}
	if err := stream.Send(&vectorpb.ExternalAudioStreamRequest{
		AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamComplete{
			AudioStreamComplete: &vectorpb.ExternalAudioStreamComplete{},
		},
	}); err != nil {
		return err
	}
	for {
		resp, err := stream.Recv()
		if err != nil {
			if errors.Is(err, io.EOF) {
				return nil
			}
			return err
		}
		if resp.GetAudioStreamPlaybackComplete() != nil {
			return nil
		}
		if resp.GetAudioStreamPlaybackFailyer() != nil {
			return errors.New("audio playback failure")
		}
		if resp.GetAudioStreamBufferOverrun() != nil {
			return errors.New("audio buffer overrun")
		}
	}
}
