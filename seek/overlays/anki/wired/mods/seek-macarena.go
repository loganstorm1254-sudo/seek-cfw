package mods

import (
	"bytes"
	"context"
	"errors"
	"math"
	"os"
	"sync/atomic"
	"time"

	"github.com/digital-dream-labs/vector-go-sdk/pkg/vector"
	"github.com/digital-dream-labs/vector-go-sdk/pkg/vectorpb"
)

// Bundled on the robot at /etc/wired/webroot/media/macarena.mp3 (Seek overlay).
const macarenaPath = "/etc/wired/webroot/media/macarena.mp3"

// Los del Río Macarena is ~103 BPM. Vector dances the classic 16-count
// phrase (arms → shoulders → hips → 90° turn) using lift, head, and wheels.
const macarenaBPM = 103.0

func (m *SeekDashboard) nextActionID() int32 {
	return int32(atomic.AddUint32(&m.actionID, 1))
}

func (m *SeekDashboard) isDancing() bool {
	m.danceMu.Lock()
	defer m.danceMu.Unlock()
	return m.dancing
}

func (m *SeekDashboard) stopDance() {
	m.danceMu.Lock()
	cancel := m.danceCancel
	m.danceMu.Unlock()
	if cancel != nil {
		cancel()
	}
}

// startMacarena plays the bundled Macarena on Vector's speaker and runs a
// real choreography on lift/head/wheels. Returns immediately; use Stop to abort.
func (m *SeekDashboard) startMacarena(volume uint32) error {
	if _, err := os.Stat(macarenaPath); err != nil {
		return errors.New("macarena.mp3 missing on robot (reinstall Seek OTA)")
	}

	m.danceMu.Lock()
	if m.dancing {
		m.danceMu.Unlock()
		return errors.New("already dancing — hit Stop first")
	}
	ctx, cancel := context.WithCancel(context.Background())
	m.dancing = true
	m.danceCancel = cancel
	m.danceMu.Unlock()

	m.touchActivity()
	m.cameraStop()
	m.stopAudio()

	go m.runMacarena(ctx, cancel, volume)
	return nil
}

func (m *SeekDashboard) runMacarena(ctx context.Context, cancel context.CancelFunc, volume uint32) {
	defer cancel()
	defer func() {
		m.emergencyStopWheels()
		m.stopAudio()
		m.controlEnd()
		m.danceMu.Lock()
		m.dancing = false
		m.danceCancel = nil
		m.danceMu.Unlock()
	}()

	raw, err := os.ReadFile(macarenaPath)
	if err != nil {
		return
	}
	pcm, rate, err := decodeAudioToPCM(raw, "macarena.mp3")
	if err != nil {
		return
	}
	if volume == 0 {
		volume = 100
	}

	if err := m.controlStartPriority(vectorpb.ControlRequest_OVERRIDE_BEHAVIORS); err != nil {
		return
	}
	m.mu.Lock()
	v := m.vec
	m.mu.Unlock()
	if v == nil {
		return
	}

	_ = m.macLift(ctx, v, 50, 0.35)
	_ = m.macHead(ctx, v, 0.25, 0.35)

	audioDone := make(chan struct{})
	go func() {
		defer close(audioDone)
		_ = m.streamPCM(ctx, v, bytes.NewReader(pcm), rate, volume)
	}()

	samples := len(pcm) / 2
	if samples < 1 {
		samples = 1
	}
	dur := time.Duration(float64(samples)/float64(rate)*float64(time.Second)) + time.Second
	danceCtx, danceCancel := context.WithTimeout(ctx, dur)
	defer danceCancel()

	beat := time.Duration(math.Round(60000.0/macarenaBPM)) * time.Millisecond
	_ = m.macarenaDanceLoop(danceCtx, v, beat)

	select {
	case <-audioDone:
	case <-ctx.Done():
	case <-time.After(2 * time.Second):
	}
}

func (m *SeekDashboard) macarenaDanceLoop(ctx context.Context, v *vector.Vector, beat time.Duration) error {
	beatSec := float32(beat.Seconds())
	phrase := 0
	for {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		m.touchActivity()
		phrase++

		// Counts 1–4: "arms" out / palms up via lift + head
		if err := m.macLift(ctx, v, 62, beatSec); err != nil {
			return err
		}
		if err := m.macLift(ctx, v, 88, beatSec); err != nil {
			return err
		}
		if err := m.macHead(ctx, v, 0.55, beatSec); err != nil {
			return err
		}
		if err := m.macHead(ctx, v, 0.72, beatSec); err != nil {
			return err
		}

		// Counts 5–8: shoulders / behind head
		if err := m.macLift(ctx, v, 70, beatSec); err != nil {
			return err
		}
		if err := m.macHead(ctx, v, 0.15, beatSec); err != nil {
			return err
		}
		if err := m.macLift(ctx, v, 45, beatSec); err != nil {
			return err
		}
		if err := m.macHead(ctx, v, -0.15, beatSec); err != nil {
			return err
		}

		// Counts 9–12: hips (lift bounces)
		if err := m.macLift(ctx, v, 55, beatSec*0.9); err != nil {
			return err
		}
		if err := m.macLift(ctx, v, 40, beatSec*0.9); err != nil {
			return err
		}
		if err := m.macLift(ctx, v, 70, beatSec*0.9); err != nil {
			return err
		}
		if err := m.macLift(ctx, v, 50, beatSec*0.9); err != nil {
			return err
		}

		// Counts 13–14: hip wiggle (wheels)
		if err := m.macWiggle(ctx, v, beat); err != nil {
			return err
		}

		// Counts 15–16: classic Macarena 90° jump-turn (alternate side each phrase)
		turn := float32(math.Pi / 2)
		if phrase%2 == 0 {
			turn = -turn
		}
		if err := m.macTurn(ctx, v, turn); err != nil {
			return err
		}
	}
}

func (m *SeekDashboard) macLift(ctx context.Context, v *vector.Vector, heightMm, durationSec float32) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if heightMm < 32 {
		heightMm = 32
	}
	if heightMm > 92 {
		heightMm = 92
	}
	cctx, cancel := context.WithTimeout(ctx, time.Duration(durationSec*float32(time.Second))+2*time.Second)
	defer cancel()
	_, err := v.Conn.SetLiftHeight(cctx, &vectorpb.SetLiftHeightRequest{
		HeightMm:          heightMm,
		MaxSpeedRadPerSec: 8,
		AccelRadPerSec2:   20,
		DurationSec:       durationSec,
		IdTag:             m.nextActionID(),
	})
	return err
}

func (m *SeekDashboard) macHead(ctx context.Context, v *vector.Vector, angleRad, durationSec float32) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if angleRad < -0.38 {
		angleRad = -0.38
	}
	if angleRad > 0.78 {
		angleRad = 0.78
	}
	cctx, cancel := context.WithTimeout(ctx, time.Duration(durationSec*float32(time.Second))+2*time.Second)
	defer cancel()
	_, err := v.Conn.SetHeadAngle(cctx, &vectorpb.SetHeadAngleRequest{
		AngleRad:          angleRad,
		MaxSpeedRadPerSec: 8,
		AccelRadPerSec2:   20,
		DurationSec:       durationSec,
		IdTag:             m.nextActionID(),
	})
	return err
}

func (m *SeekDashboard) macTurn(ctx context.Context, v *vector.Vector, angleRad float32) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}
	cctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	_, err := v.Conn.TurnInPlace(cctx, &vectorpb.TurnInPlaceRequest{
		AngleRad:        angleRad,
		SpeedRadPerSec:  2.2,
		AccelRadPerSec2: 6,
		TolRad:          0.08,
		IdTag:           m.nextActionID(),
	})
	return err
}

func (m *SeekDashboard) macWiggle(ctx context.Context, v *vector.Vector, beat time.Duration) error {
	half := beat / 2
	steps := [][2]float32{
		{70, -70},
		{-70, 70},
		{70, -70},
		{-70, 70},
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
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(half):
		}
	}
	cctx, cancel := context.WithTimeout(ctx, time.Second)
	_, _ = v.Conn.DriveWheels(cctx, &vectorpb.DriveWheelsRequest{})
	cancel()
	return nil
}
