package mods

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/digital-dream-labs/vector-go-sdk/pkg/vectorpb"
	"github.com/os-vector/wired/vars"
)

func (m *SeekDashboard) handleDrive(r *http.Request) error {
	left, err := strconv.ParseFloat(r.FormValue("left"), 32)
	if err != nil {
		return errors.New("invalid left speed")
	}
	right, err := strconv.ParseFloat(r.FormValue("right"), 32)
	if err != nil {
		return errors.New("invalid right speed")
	}
	if left < -120 || left > 120 || right < -120 || right > 120 {
		return errors.New("wheel speed must be -120..120 mm/s")
	}
	// Require an existing grant — never acquire+drive in the same request.
	// DriveWheels without control (or racing grant) was crashing victor.
	m.mu.Lock()
	holding := m.holding
	m.mu.Unlock()
	if !holding {
		return errors.New("not armed — click Take control first")
	}
	m.setDriveIntent(float32(left), float32(right))
	return nil
}

func (m *SeekDashboard) handleStopMotors() error {
	m.setDriveIntent(0, 0)
	m.mu.Lock()
	holding := m.holding
	v := m.vec
	m.mu.Unlock()
	if holding && v != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_, err := v.Conn.DriveWheels(ctx, &vectorpb.DriveWheelsRequest{
			LeftWheelMmps:  0,
			RightWheelMmps: 0,
		})
		if err == nil {
			return nil
		}
	}
	// Fallback: fresh connection + StopAllMotors (covers control-lost / crash paths).
	m.emergencyStopWheels()
	return nil
}

func (m *SeekDashboard) handleMoveHead(r *http.Request) error {
	speed, err := strconv.ParseFloat(r.FormValue("speed"), 32)
	if err != nil {
		return errors.New("invalid head speed")
	}
	if speed < -5 || speed > 5 {
		return errors.New("head speed must be -5..5 rad/s")
	}
	m.mu.Lock()
	holding := m.holding
	v := m.vec
	m.mu.Unlock()
	if !holding || v == nil {
		return errors.New("not armed — click Take control first")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, err = v.Conn.MoveHead(ctx, &vectorpb.MoveHeadRequest{
		SpeedRadPerSec: float32(speed),
	})
	return err
}

func (m *SeekDashboard) handleMoveLift(r *http.Request) error {
	speed, err := strconv.ParseFloat(r.FormValue("speed"), 32)
	if err != nil {
		return errors.New("invalid lift speed")
	}
	if speed < -5 || speed > 5 {
		return errors.New("lift speed must be -5..5 rad/s")
	}
	m.mu.Lock()
	holding := m.holding
	v := m.vec
	m.mu.Unlock()
	if !holding || v == nil {
		return errors.New("not armed — click Take control first")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_, err = v.Conn.MoveLift(ctx, &vectorpb.MoveLiftRequest{
		SpeedRadPerSec: float32(speed),
	})
	return err
}

func (m *SeekDashboard) cameraStart() error {
	m.camMu.Lock()
	defer m.camMu.Unlock()
	if m.camRunning {
		return nil
	}
	v, err := vars.GetVec()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithCancel(context.Background())
	stream, err := v.Conn.CameraFeed(ctx, &vectorpb.CameraFeedRequest{})
	if err != nil {
		cancel()
		return err
	}
	m.camCancel = cancel
	m.camRunning = true
	m.camLatest = nil

	go func() {
		defer func() {
			m.camMu.Lock()
			m.camRunning = false
			m.camCancel = nil
			m.camLatest = nil
			m.camMu.Unlock()
		}()
		for {
			resp, err := stream.Recv()
			if err != nil {
				return
			}
			data := resp.GetData()
			if len(data) == 0 {
				continue
			}
			cp := append([]byte(nil), data...)
			m.camMu.Lock()
			m.camLatest = cp
			m.camSeq++
			m.camMu.Unlock()
		}
	}()
	return nil
}

func (m *SeekDashboard) cameraStop() {
	m.camMu.Lock()
	cancel := m.camCancel
	m.camCancel = nil
	m.camRunning = false
	m.camLatest = nil
	m.camMu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func (m *SeekDashboard) cameraLatest() ([]byte, uint64, bool) {
	m.camMu.Lock()
	defer m.camMu.Unlock()
	if len(m.camLatest) == 0 {
		return nil, m.camSeq, false
	}
	out := make([]byte, len(m.camLatest))
	copy(out, m.camLatest)
	return out, m.camSeq, true
}

func (m *SeekDashboard) handleCameraFrame(w http.ResponseWriter, r *http.Request) {
	if err := m.cameraStart(); err != nil {
		vars.HTTPError(w, r, err.Error())
		return
	}
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		data, _, ok := m.cameraLatest()
		if ok {
			w.Header().Set("Content-Type", "image/jpeg")
			w.Header().Set("Cache-Control", "no-store")
			w.Write(data)
			return
		}
		time.Sleep(40 * time.Millisecond)
	}
	vars.HTTPError(w, r, "no camera frame yet")
}

func (m *SeekDashboard) handleCameraMjpeg(w http.ResponseWriter, r *http.Request) {
	if err := m.cameraStart(); err != nil {
		vars.HTTPError(w, r, err.Error())
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		vars.HTTPError(w, r, "streaming unsupported")
		return
	}
	w.Header().Set("Content-Type", "multipart/x-mixed-replace; boundary=seekframe")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Connection", "close")
	flusher.Flush()

	var lastSeq uint64
	ticker := time.NewTicker(200 * time.Millisecond) // 5 fps — cooler than 10
	defer ticker.Stop()
	for {
		select {
		case <-r.Context().Done():
			return
		case <-ticker.C:
			data, seq, ok := m.cameraLatest()
			if !ok || seq == lastSeq {
				continue
			}
			lastSeq = seq
			if _, err := fmt.Fprintf(w, "--seekframe\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\n\r\n", len(data)); err != nil {
				return
			}
			if _, err := w.Write(data); err != nil {
				return
			}
			if _, err := io.WriteString(w, "\r\n"); err != nil {
				return
			}
			flusher.Flush()
		}
	}
}
