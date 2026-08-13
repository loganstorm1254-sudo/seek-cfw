package mods

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"math"
	"os"
	"runtime"
	"sync/atomic"
	"time"

	"github.com/digital-dream-labs/vector-go-sdk/pkg/vector"
	"github.com/digital-dream-labs/vector-go-sdk/pkg/vectorpb"
)

// Pre-decoded 16 kHz mono WAV on the robot (MP3 decode on Vector was too slow
// and made Stop look dead while the CPU chewed the file).
const macarenaWavPath = "/etc/wired/webroot/media/macarena.wav"

// Los del Río Macarena ~103 BPM.
const macarenaBPM = 103.0

// Countdown after every bot is armed — room for HTTP + audio Prepare on all units.
const macarenaSyncLeadMs = 2800

func (m *SeekDashboard) nextActionID() int32 {
	return int32(atomic.AddUint32(&m.actionID, 1))
}

func (m *SeekDashboard) isDancing() bool {
	m.danceMu.Lock()
	defer m.danceMu.Unlock()
	return m.dancing
}

func (m *SeekDashboard) setDanceErr(err error) {
	m.danceMu.Lock()
	if err != nil {
		m.danceLastErr = err.Error()
	} else {
		m.danceLastErr = ""
	}
	m.danceMu.Unlock()
}

func (m *SeekDashboard) getDanceErr() string {
	m.danceMu.Lock()
	defer m.danceMu.Unlock()
	return m.danceLastErr
}

func (m *SeekDashboard) stopDance() {
	m.danceMu.Lock()
	cancel := m.danceCancel
	m.danceMu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func waitUntilUnixMs(t0Ms int64) {
	for {
		now := time.Now().UnixMilli()
		if now >= t0Ms {
			return
		}
		d := time.Duration(t0Ms-now) * time.Millisecond
		if d > 40*time.Millisecond {
			time.Sleep(d - 20*time.Millisecond)
		} else if d > 3*time.Millisecond {
			time.Sleep(1 * time.Millisecond)
		} else {
			runtime.Gosched()
		}
	}
}

func loadMacarenaPCM() ([]byte, uint32, error) {
	raw, err := os.ReadFile(macarenaWavPath)
	if err != nil {
		return nil, 0, fmt.Errorf("macarena.wav missing on robot — reinstall Seek OTA (%v)", err)
	}
	pcm, rate, err := decodeWAV(raw)
	if err != nil {
		return nil, 0, fmt.Errorf("macarena wav decode: %w", err)
	}
	return normalizePCM16(pcm), rate, nil
}

// armMacarena loads audio and takes SDK control, ready for a shared t0 go signal.
func (m *SeekDashboard) armMacarena(volume uint32) error {
	if volume == 0 {
		volume = 100
	}
	m.danceMu.Lock()
	if m.dancing {
		m.danceMu.Unlock()
		return errors.New("already dancing — hit Stop first")
	}
	m.danceMu.Unlock()

	m.macArenaMu.Lock()
	defer m.macArenaMu.Unlock()
	if m.macArmed {
		return nil
	}

	pcm, rate, err := loadMacarenaPCM()
	if err != nil {
		return err
	}

	m.touchActivity()
	m.cameraStop()
	m.stopAudio()
	m.stopDriveLoop()
	m.controlEnd()
	time.Sleep(150 * time.Millisecond)
	if err := m.controlStartPriority(vectorpb.ControlRequest_OVERRIDE_BEHAVIORS); err != nil {
		return fmt.Errorf("could not take control: %w", err)
	}
	m.mu.Lock()
	v := m.vec
	m.mu.Unlock()
	if v == nil {
		m.controlEnd()
		return errors.New("no robot connection after control grant")
	}

	m.macArmed = true
	m.macPCM = pcm
	m.macRate = rate
	m.macVol = volume
	return nil
}

func (m *SeekDashboard) disarmMacarena() {
	m.macArenaMu.Lock()
	m.macArmed = false
	m.macPCM = nil
	m.macRate = 0
	m.macVol = 0
	m.macArenaMu.Unlock()
}

// goMacarenaAt starts a previously armed Macarena exactly at unix-ms t0.
func (m *SeekDashboard) goMacarenaAt(t0Ms int64) error {
	if t0Ms <= 0 {
		return errors.New("missing sync time")
	}
	if d := time.Until(time.UnixMilli(t0Ms)); d < -500*time.Millisecond {
		return errors.New("sync time already passed — try again")
	}

	var pcm []byte
	var rate, volume uint32
	m.macArenaMu.Lock()
	if !m.macArmed {
		m.macArenaMu.Unlock()
		return errors.New("not armed for sync — master must arm first")
	}
	pcm = m.macPCM
	rate = m.macRate
	volume = m.macVol
	m.macArmed = false
	m.macPCM = nil
	m.macArenaMu.Unlock()

	m.danceMu.Lock()
	if m.dancing {
		m.danceMu.Unlock()
		return errors.New("already dancing")
	}
	m.danceMu.Unlock()

	m.mu.Lock()
	v := m.vec
	m.mu.Unlock()
	if v == nil {
		m.controlEnd()
		return errors.New("no robot connection")
	}

	ctx, cancel := context.WithCancel(context.Background())
	m.danceMu.Lock()
	m.dancing = true
	m.danceCancel = cancel
	m.danceLastErr = ""
	m.danceMu.Unlock()

	go m.runMacarenaSynced(ctx, cancel, v, pcm, rate, volume, t0Ms)
	return nil
}

// startMacarena solo or master-synced (arm all → shared t0 → go).
func (m *SeekDashboard) startMacarena(volume uint32) error {
	if volume == 0 {
		volume = 100
	}
	if m.isLinkMaster() {
		peers := m.linkedPeers()
		if len(peers) >= 1 {
			if err := m.armMacarena(volume); err != nil {
				return err
			}
			okN, errs := m.fanoutMacarenaArm(volume)
			if okN != len(peers) {
				m.disarmMacarena()
				m.controlEnd()
				return fmt.Errorf("only %d/%d linked Vectors armed (%v)", okN, len(peers), errs)
			}
			t0Ms := time.Now().UnixMilli() + macarenaSyncLeadMs
			go m.fanoutMacarenaGo(t0Ms)
			return m.goMacarenaAt(t0Ms)
		}
	}
	return m.startMacarenaSolo(volume)
}

func (m *SeekDashboard) startMacarenaSolo(volume uint32) error {
	m.danceMu.Lock()
	if m.dancing {
		m.danceMu.Unlock()
		return errors.New("already dancing — hit Stop first")
	}
	m.danceMu.Unlock()

	pcm, rate, err := loadMacarenaPCM()
	if err != nil {
		return err
	}
	if volume == 0 {
		volume = 100
	}

	m.touchActivity()
	m.cameraStop()
	m.stopAudio()
	m.stopDriveLoop()
	m.controlEnd()
	time.Sleep(150 * time.Millisecond)
	if err := m.controlStartPriority(vectorpb.ControlRequest_OVERRIDE_BEHAVIORS); err != nil {
		return fmt.Errorf("could not take control: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	m.danceMu.Lock()
	m.dancing = true
	m.danceCancel = cancel
	m.danceLastErr = ""
	m.danceMu.Unlock()

	m.mu.Lock()
	v := m.vec
	m.mu.Unlock()
	if v == nil {
		cancel()
		m.danceMu.Lock()
		m.dancing = false
		m.danceCancel = nil
		m.danceMu.Unlock()
		return errors.New("no robot connection after control grant")
	}

	go m.runMacarena(ctx, cancel, v, pcm, rate, volume)
	return nil
}

func (m *SeekDashboard) runMacarenaSynced(ctx context.Context, cancel context.CancelFunc, v *vector.Vector, pcm []byte, rate uint32, volume uint32, t0Ms int64) {
	defer cancel()
	defer func() {
		m.macFreeze(v)
		m.stopAudio()
		m.emergencyStopWheels()
		m.danceMu.Lock()
		m.dancing = false
		m.danceCancel = nil
		m.danceMu.Unlock()
		m.controlEnd()
	}()

	// Open + Prepare audio before t0 so the first chunk fires on the beat.
	audioCtx, audioCancel := context.WithCancel(ctx)
	defer audioCancel()
	m.stopAudio()
	m.audioMu.Lock()
	m.audioCancel = audioCancel
	m.audioGen++
	m.audioMu.Unlock()

	stream, err := v.Conn.ExternalAudioStreamPlayback(audioCtx)
	if err != nil {
		m.setDanceErr(err)
		return
	}
	if err := stream.Send(&vectorpb.ExternalAudioStreamRequest{
		AudioRequestType: &vectorpb.ExternalAudioStreamRequest_AudioStreamPrepare{
			AudioStreamPrepare: &vectorpb.ExternalAudioStreamPrepare{
				AudioFrameRate: rate,
				AudioVolume:    volume,
			},
		},
	}); err != nil {
		m.setDanceErr(err)
		return
	}

	waitUntilUnixMs(t0Ms)
	if ctx.Err() != nil {
		return
	}
	clockStart := time.UnixMilli(t0Ms)

	samples := len(pcm) / 2
	if samples < 1 {
		samples = 1
	}
	dur := time.Duration(float64(samples)/float64(rate)*float64(time.Second)) + 2*time.Second
	danceCtx, danceCancel := context.WithTimeout(ctx, dur)
	defer danceCancel()

	audioDone := make(chan error, 1)
	danceDone := make(chan error, 1)
	go func() {
		audioDone <- m.streamPCMOnPreparedStream(audioCtx, stream, bytes.NewReader(pcm), rate, volume, clockStart, true)
	}()
	go func() {
		danceDone <- m.macarenaDanceLoop(danceCtx, v, clockStart)
	}()

	select {
	case err := <-audioDone:
		if err != nil && !errors.Is(err, context.Canceled) && ctx.Err() == nil {
			m.setDanceErr(err)
		}
	case <-ctx.Done():
	case <-time.After(dur + 5*time.Second):
	}

	danceCancel()
	_ = <-danceDone
}

func (m *SeekDashboard) runMacarena(ctx context.Context, cancel context.CancelFunc, v *vector.Vector, pcm []byte, rate uint32, volume uint32) {
	defer cancel()
	defer func() {
		m.macFreeze(v)
		m.stopAudio()
		m.emergencyStopWheels()
		m.danceMu.Lock()
		m.dancing = false
		m.danceCancel = nil
		m.danceMu.Unlock()
		m.controlEnd()
	}()

	audioDone := make(chan error, 1)
	go func() {
		audioDone <- m.streamPCM(ctx, v, bytes.NewReader(pcm), rate, volume)
	}()

	samples := len(pcm) / 2
	if samples < 1 {
		samples = 1
	}
	dur := time.Duration(float64(samples)/float64(rate)*float64(time.Second)) + 2*time.Second
	danceCtx, danceCancel := context.WithTimeout(ctx, dur)
	defer danceCancel()

	if err := m.macarenaDanceLoop(danceCtx, v, time.Now()); err != nil && !errors.Is(err, context.Canceled) && !errors.Is(err, context.DeadlineExceeded) {
		m.setDanceErr(err)
	}

	select {
	case err := <-audioDone:
		if err != nil && !errors.Is(err, context.Canceled) && ctx.Err() == nil {
			m.setDanceErr(err)
		}
	case <-ctx.Done():
	case <-time.After(3 * time.Second):
	}
}

// macarenaDanceLoop stays on an absolute beat grid (clockStart + n*beat)
// so SDK RPC latency cannot accumulate. Both linked Vectors share the same
// clockStart from t0, which is why music stays together — moves now do too.
func (m *SeekDashboard) macarenaDanceLoop(ctx context.Context, v *vector.Vector, clockStart time.Time) error {
	if clockStart.IsZero() {
		clockStart = time.Now()
	}
	beatMs := 60000.0 / macarenaBPM
	cursor := 0.0 // beats from clockStart
	at := func(beats float64) time.Time {
		ms := int64(math.Round(beats * beatMs))
		return clockStart.Add(time.Duration(ms) * time.Millisecond)
	}
	phrase := 0
	for {
		if err := ctx.Err(); err != nil {
			m.macFreeze(v)
			return err
		}
		m.touchActivity()
		phrase++
		turnDir := float32(1)
		if phrase%2 == 0 {
			turnDir = -1
		}

		type step struct {
			kind  string
			speed float32
			beats float64
			lx    float32
			rx    float32
		}
		steps := []step{
			{kind: "lift", speed: 3.5, beats: 1},
			{kind: "lift", speed: 4.5, beats: 1},
			{kind: "head", speed: 3.0, beats: 1},
			{kind: "head", speed: -2.5, beats: 1},
			{kind: "lift", speed: -3.0, beats: 1},
			{kind: "head", speed: 2.0, beats: 1},
			{kind: "lift", speed: 3.0, beats: 1},
			{kind: "head", speed: -3.0, beats: 1},
			{kind: "lift", speed: 2.5, beats: 0.9},
			{kind: "lift", speed: -2.5, beats: 0.9},
			{kind: "lift", speed: 3.5, beats: 0.9},
			{kind: "lift", speed: -2.0, beats: 0.9},
			{kind: "wheels", lx: 75, rx: -75, beats: 0.5},
			{kind: "wheels", lx: -75, rx: 75, beats: 0.5},
			{kind: "wheels", lx: 75, rx: -75, beats: 0.5},
			{kind: "wheels", lx: -75, rx: 75, beats: 0.5},
			{kind: "wheels", lx: -90 * turnDir, rx: 90 * turnDir, beats: 2},
		}
		for _, s := range steps {
			startAt := at(cursor)
			endAt := at(cursor + s.beats)
			if err := m.macWaitUntil(ctx, startAt); err != nil {
				m.macFreeze(v)
				return err
			}
			switch s.kind {
			case "lift":
				go m.macFireLift(ctx, v, s.speed)
			case "head":
				go m.macFireHead(ctx, v, s.speed)
			default:
				go m.macFireWheels(ctx, v, s.lx, s.rx)
			}
			if err := m.macWaitUntil(ctx, endAt); err != nil {
				m.macFreeze(v)
				return err
			}
			switch s.kind {
			case "lift":
				go m.macFireLift(ctx, v, 0)
			case "head":
				go m.macFireHead(ctx, v, 0)
			default:
				go m.macFireWheels(ctx, v, 0, 0)
			}
			cursor += s.beats
		}
	}
}

func (m *SeekDashboard) macWaitUntil(ctx context.Context, deadline time.Time) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	waitUntilUnixMs(deadline.UnixMilli())
	return ctx.Err()
}

func (m *SeekDashboard) macFireLift(ctx context.Context, v *vector.Vector, speed float32) {
	cctx, cancel := context.WithTimeout(ctx, 80*time.Millisecond)
	_, _ = v.Conn.MoveLift(cctx, &vectorpb.MoveLiftRequest{SpeedRadPerSec: speed})
	cancel()
}

func (m *SeekDashboard) macFireHead(ctx context.Context, v *vector.Vector, speed float32) {
	cctx, cancel := context.WithTimeout(ctx, 80*time.Millisecond)
	_, _ = v.Conn.MoveHead(cctx, &vectorpb.MoveHeadRequest{SpeedRadPerSec: speed})
	cancel()
}

func (m *SeekDashboard) macFireWheels(ctx context.Context, v *vector.Vector, left, right float32) {
	cctx, cancel := context.WithTimeout(ctx, 80*time.Millisecond)
	_, _ = v.Conn.DriveWheels(cctx, &vectorpb.DriveWheelsRequest{
		LeftWheelMmps:   left,
		RightWheelMmps:  right,
		LeftWheelMmps2:  abs32(left),
		RightWheelMmps2: abs32(right),
	})
	cancel()
}

func (m *SeekDashboard) macFreeze(v *vector.Vector) {
	if v == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 800*time.Millisecond)
	defer cancel()
	_, _ = v.Conn.MoveLift(ctx, &vectorpb.MoveLiftRequest{SpeedRadPerSec: 0})
	_, _ = v.Conn.MoveHead(ctx, &vectorpb.MoveHeadRequest{SpeedRadPerSec: 0})
	_, _ = v.Conn.DriveWheels(ctx, &vectorpb.DriveWheelsRequest{})
	_, _ = v.Conn.StopAllMotors(ctx, &vectorpb.StopAllMotorsRequest{})
}
