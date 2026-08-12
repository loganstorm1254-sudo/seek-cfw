package mods

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"math"
	"os"
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

// startMacarena loads the bundled WAV (fast), takes control, then dances + plays
// audio on the real robot. When this Vector is master with ≥1 linked peer, it
// fans out a shared start time so everyone hits the beat together.
func (m *SeekDashboard) startMacarena(volume uint32) error {
	if volume == 0 {
		volume = 100
	}
	var t0Ms int64
	if m.isLinkMaster() {
		peers := m.linkedPeers()
		if len(peers) >= 1 {
			t0Ms = time.Now().Add(900 * time.Millisecond).UnixMilli()
			okN, errs := m.fanoutMacarena(t0Ms, volume)
			if okN == 0 {
				return fmt.Errorf("no linked Vector answered — check they are on SeekOS and same Wi‑Fi (%v)", errs)
			}
		}
	}
	return m.startMacarenaAt(volume, t0Ms)
}

// startMacarenaAt arms Macarena, optionally waiting until unix-ms t0 (0 = now).
func (m *SeekDashboard) startMacarenaAt(volume uint32, t0Ms int64) error {
	m.danceMu.Lock()
	if m.dancing {
		m.danceMu.Unlock()
		return errors.New("already dancing — hit Stop first")
	}
	m.danceMu.Unlock()

	raw, err := os.ReadFile(macarenaWavPath)
	if err != nil {
		return fmt.Errorf("macarena.wav missing on robot — reinstall Seek OTA (%v)", err)
	}
	pcm, rate, err := decodeWAV(raw)
	if err != nil {
		return fmt.Errorf("macarena wav decode: %w", err)
	}
	pcm = normalizePCM16(pcm)
	if volume == 0 {
		volume = 100
	}

	m.touchActivity()
	m.cameraStop()
	m.stopAudio()
	m.stopDriveLoop()

	// Fresh control for the routine.
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

	go func() {
		if t0Ms > 0 {
			wait := time.Until(time.UnixMilli(t0Ms))
			if wait > 0 && wait < 5*time.Second {
				t := time.NewTimer(wait)
				select {
				case <-ctx.Done():
					t.Stop()
					m.danceMu.Lock()
					m.dancing = false
					m.danceCancel = nil
					m.danceMu.Unlock()
					m.controlEnd()
					return
				case <-t.C:
				}
			}
		}
		if ctx.Err() != nil {
			m.danceMu.Lock()
			m.dancing = false
			m.danceCancel = nil
			m.danceMu.Unlock()
			m.controlEnd()
			return
		}
		m.runMacarena(ctx, cancel, v, pcm, rate, volume)
	}()
	return nil
}

func (m *SeekDashboard) runMacarena(ctx context.Context, cancel context.CancelFunc, v *vector.Vector, pcm []byte, rate uint32, volume uint32) {
	defer cancel()
	defer func() {
		// Always freeze motors / audio even if controlEnd races.
		m.macFreeze(v)
		m.stopAudio()
		m.emergencyStopWheels()
		// Clear dancing before controlEnd so controlEnd's stopDance is a no-op path.
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

	beat := time.Duration(math.Round(60000.0/macarenaBPM)) * time.Millisecond
	if err := m.macarenaDanceLoop(danceCtx, v, beat); err != nil && !errors.Is(err, context.Canceled) && !errors.Is(err, context.DeadlineExceeded) {
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

func (m *SeekDashboard) macarenaDanceLoop(ctx context.Context, v *vector.Vector, beat time.Duration) error {
	phrase := 0
	for {
		if err := ctx.Err(); err != nil {
			m.macFreeze(v)
			return err
		}
		m.touchActivity()
		phrase++

		// 16-count Macarena mapped to lift / head / wheels (non-blocking teleop
		// so Stop can cancel between beats instead of sitting in SetLiftHeight).
		steps := []func() error{
			func() error { return m.macPulseLift(ctx, v, 3.5, beat) },
			func() error { return m.macPulseLift(ctx, v, 4.5, beat) },
			func() error { return m.macPulseHead(ctx, v, 3.0, beat) },
			func() error { return m.macPulseHead(ctx, v, -2.5, beat) },
			func() error { return m.macPulseLift(ctx, v, -3.0, beat) },
			func() error { return m.macPulseHead(ctx, v, 2.0, beat) },
			func() error { return m.macPulseLift(ctx, v, 3.0, beat) },
			func() error { return m.macPulseHead(ctx, v, -3.0, beat) },
			func() error { return m.macPulseLift(ctx, v, 2.5, beat*9/10) },
			func() error { return m.macPulseLift(ctx, v, -2.5, beat*9/10) },
			func() error { return m.macPulseLift(ctx, v, 3.5, beat*9/10) },
			func() error { return m.macPulseLift(ctx, v, -2.0, beat*9/10) },
			func() error { return m.macWiggle(ctx, v, beat) },
			func() error {
				turnDir := float32(1)
				if phrase%2 == 0 {
					turnDir = -1
				}
				return m.macSpin(ctx, v, turnDir, beat*2)
			},
		}
		for _, step := range steps {
			if err := step(); err != nil {
				m.macFreeze(v)
				return err
			}
		}
	}
}

func (m *SeekDashboard) macSleep(ctx context.Context, d time.Duration) error {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
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

func (m *SeekDashboard) macPulseLift(ctx context.Context, v *vector.Vector, speed float32, hold time.Duration) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}
	cctx, cancel := context.WithTimeout(ctx, time.Second)
	_, err := v.Conn.MoveLift(cctx, &vectorpb.MoveLiftRequest{SpeedRadPerSec: speed})
	cancel()
	if err != nil && ctx.Err() != nil {
		return ctx.Err()
	}
	// Keep going even if one pulse fails (transient SDK blip).
	if err := m.macSleep(ctx, hold); err != nil {
		return err
	}
	cctx2, cancel2 := context.WithTimeout(ctx, 500*time.Millisecond)
	_, _ = v.Conn.MoveLift(cctx2, &vectorpb.MoveLiftRequest{SpeedRadPerSec: 0})
	cancel2()
	return nil
}

func (m *SeekDashboard) macPulseHead(ctx context.Context, v *vector.Vector, speed float32, hold time.Duration) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}
	cctx, cancel := context.WithTimeout(ctx, time.Second)
	_, err := v.Conn.MoveHead(cctx, &vectorpb.MoveHeadRequest{SpeedRadPerSec: speed})
	cancel()
	if err != nil && ctx.Err() != nil {
		return ctx.Err()
	}
	if err := m.macSleep(ctx, hold); err != nil {
		return err
	}
	cctx2, cancel2 := context.WithTimeout(ctx, 500*time.Millisecond)
	_, _ = v.Conn.MoveHead(cctx2, &vectorpb.MoveHeadRequest{SpeedRadPerSec: 0})
	cancel2()
	return nil
}

func (m *SeekDashboard) macSpin(ctx context.Context, v *vector.Vector, dir float32, hold time.Duration) error {
	// Wheel spin ≈ 90° turn without blocking TurnInPlace (which ignored Stop).
	speed := float32(90) * dir
	cctx, cancel := context.WithTimeout(ctx, time.Second)
	_, _ = v.Conn.DriveWheels(cctx, &vectorpb.DriveWheelsRequest{
		LeftWheelMmps:   -speed,
		RightWheelMmps:  speed,
		LeftWheelMmps2:  abs32(speed),
		RightWheelMmps2: abs32(speed),
	})
	cancel()
	if err := m.macSleep(ctx, hold); err != nil {
		cctx2, cancel2 := context.WithTimeout(context.Background(), 500*time.Millisecond)
		_, _ = v.Conn.DriveWheels(cctx2, &vectorpb.DriveWheelsRequest{})
		cancel2()
		return err
	}
	cctx2, cancel2 := context.WithTimeout(ctx, 500*time.Millisecond)
	_, _ = v.Conn.DriveWheels(cctx2, &vectorpb.DriveWheelsRequest{})
	cancel2()
	return nil
}

func (m *SeekDashboard) macWiggle(ctx context.Context, v *vector.Vector, beat time.Duration) error {
	half := beat / 2
	steps := [][2]float32{
		{75, -75},
		{-75, 75},
		{75, -75},
		{-75, 75},
	}
	for _, s := range steps {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		cctx, cancel := context.WithTimeout(ctx, time.Second)
		_, _ = v.Conn.DriveWheels(cctx, &vectorpb.DriveWheelsRequest{
			LeftWheelMmps:   s[0],
			RightWheelMmps:  s[1],
			LeftWheelMmps2:  abs32(s[0]),
			RightWheelMmps2: abs32(s[1]),
		})
		cancel()
		if err := m.macSleep(ctx, half); err != nil {
			return err
		}
	}
	cctx, cancel := context.WithTimeout(ctx, time.Second)
	_, _ = v.Conn.DriveWheels(cctx, &vectorpb.DriveWheelsRequest{})
	cancel()
	return nil
}
