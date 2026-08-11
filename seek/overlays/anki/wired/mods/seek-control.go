package mods

import (
	"context"
	"errors"
	"time"

	"github.com/digital-dream-labs/vector-go-sdk/pkg/vector"
	"github.com/digital-dream-labs/vector-go-sdk/pkg/vectorpb"
	"github.com/os-vector/wired/vars"
)

// Proper behavior-control hold.
//
// The upstream go-sdk BehaviorControl() busy-loops after grant (default: continue),
// which pegs a CPU core on Vector and can cause thermal shutdowns. We never use it
// for long-lived control — only this blocking Recv()-based hold.
func (m *SeekDashboard) controlStart() error {
	return m.controlStartPriority(vectorpb.ControlRequest_OVERRIDE_BEHAVIORS)
}

func (m *SeekDashboard) controlStartPriority(priority vectorpb.ControlRequest_Priority) error {
	m.mu.Lock()
	if m.holding {
		m.mu.Unlock()
		return nil
	}
	m.mu.Unlock()

	v, err := vars.GetVec()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithCancel(context.Background())
	stream, err := v.Conn.BehaviorControl(ctx)
	if err != nil {
		cancel()
		return err
	}
	if err := stream.Send(&vectorpb.BehaviorControlRequest{
		RequestType: &vectorpb.BehaviorControlRequest_ControlRequest{
			ControlRequest: &vectorpb.ControlRequest{Priority: priority},
		},
	}); err != nil {
		cancel()
		return err
	}

	granted := make(chan struct{}, 1)
	lost := make(chan struct{}, 1)
	errCh := make(chan error, 1)

	go func() {
		for {
			resp, err := stream.Recv()
			if err != nil {
				errCh <- err
				return
			}
			if resp.GetControlGrantedResponse() != nil {
				select {
				case granted <- struct{}{}:
				default:
				}
			}
			if resp.GetControlLostEvent() != nil {
				select {
				case lost <- struct{}{}:
				default:
				}
				// Immediately re-assert OVERRIDE so Vector can't reclaim mid-drive.
				_ = stream.Send(&vectorpb.BehaviorControlRequest{
					RequestType: &vectorpb.BehaviorControlRequest_ControlRequest{
						ControlRequest: &vectorpb.ControlRequest{Priority: priority},
					},
				})
			}
		}
	}()

	select {
	case <-granted:
	case err := <-errCh:
		cancel()
		if err == nil {
			err = errors.New("behavior control ended early")
		}
		return err
	case <-time.After(12 * time.Second):
		cancel()
		return errors.New("timeout waiting for full behavior control")
	}

	m.mu.Lock()
	m.holding = true
	m.vec = v
	m.cancel = cancel
	m.ctrlStream = stream
	m.ctrlLost = lost
	m.ctrlErr = errCh
	m.mu.Unlock()

	// Watchdog: if the stream dies, clear holding so the UI can reacquire.
	go func() {
		select {
		case <-ctx.Done():
			return
		case <-errCh:
		}
		m.mu.Lock()
		if m.ctrlStream == stream {
			m.holding = false
			m.vec = nil
			m.ctrlStream = nil
			m.cancel = nil
			m.driveL = 0
			m.driveR = 0
		}
		m.mu.Unlock()
		m.stopDriveLoop()
	}()

	m.startDriveLoop()
	return nil
}

func (m *SeekDashboard) controlEnd() {
	m.stopDriveLoop()

	m.mu.Lock()
	stream := m.ctrlStream
	cancel := m.cancel
	v := m.vec
	m.holding = false
	m.ctrlStream = nil
	m.vec = nil
	m.cancel = nil
	m.driveL = 0
	m.driveR = 0
	m.mu.Unlock()

	if v != nil {
		_, _ = v.Conn.StopAllMotors(context.Background(), &vectorpb.StopAllMotorsRequest{})
	}
	if stream != nil {
		_ = stream.Send(&vectorpb.BehaviorControlRequest{
			RequestType: &vectorpb.BehaviorControlRequest_ControlRelease{
				ControlRelease: &vectorpb.ControlRelease{},
			},
		})
	}
	if cancel != nil {
		cancel()
	}
}

func (m *SeekDashboard) withControl(fn func(context.Context, *vector.Vector) error) error {
	m.mu.Lock()
	if m.holding && m.vec != nil {
		v := m.vec
		m.mu.Unlock()
		return fn(context.Background(), v)
	}
	m.mu.Unlock()

	if err := m.controlStartPriority(vectorpb.ControlRequest_OVERRIDE_BEHAVIORS); err != nil {
		return err
	}
	// Temporary control for one-shot actions (say/audio): release after.
	defer m.controlEnd()

	m.mu.Lock()
	v := m.vec
	m.mu.Unlock()
	if v == nil {
		return errors.New("no robot connection")
	}
	return fn(context.Background(), v)
}

func (m *SeekDashboard) ensureControl() error {
	m.mu.Lock()
	holding := m.holding
	m.mu.Unlock()
	if holding {
		return nil
	}
	return m.controlStartPriority(vectorpb.ControlRequest_OVERRIDE_BEHAVIORS)
}

// ---- Server-side drive loop (keeps motors authoritative; UI only sets intent) ----

func (m *SeekDashboard) startDriveLoop() {
	m.driveMu.Lock()
	defer m.driveMu.Unlock()
	if m.driveRunning {
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	m.driveCancel = cancel
	m.driveRunning = true
	go m.driveLoop(ctx)
}

func (m *SeekDashboard) stopDriveLoop() {
	m.driveMu.Lock()
	cancel := m.driveCancel
	m.driveRunning = false
	m.driveCancel = nil
	m.driveMu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func (m *SeekDashboard) driveLoop(ctx context.Context) {
	ticker := time.NewTicker(40 * time.Millisecond)
	defer ticker.Stop()
	var lastL, lastR float32
	var lastSent time.Time
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			m.mu.Lock()
			holding := m.holding
			v := m.vec
			l := m.driveL
			r := m.driveR
			m.mu.Unlock()
			if !holding || v == nil {
				continue
			}
			changed := l != lastL || r != lastR
			stale := time.Since(lastSent) > 250*time.Millisecond
			if !changed && !stale && l == 0 && r == 0 {
				continue
			}
			_, _ = v.Conn.DriveWheels(context.Background(), &vectorpb.DriveWheelsRequest{
				LeftWheelMmps:   l,
				RightWheelMmps:  r,
				LeftWheelMmps2:  abs32(l) * 4,
				RightWheelMmps2: abs32(r) * 4,
			})
			lastL, lastR = l, r
			lastSent = time.Now()
		}
	}
}

func (m *SeekDashboard) setDriveIntent(left, right float32) {
	if left < -200 {
		left = -200
	}
	if left > 200 {
		left = 200
	}
	if right < -200 {
		right = -200
	}
	if right > 200 {
		right = 200
	}
	m.mu.Lock()
	m.driveL = left
	m.driveR = right
	m.mu.Unlock()
}

func abs32(v float32) float32 {
	if v < 0 {
		return -v
	}
	return v
}