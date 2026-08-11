package mods

import (
	"context"
	"errors"
	"time"

	"github.com/digital-dream-labs/vector-go-sdk/pkg/vector"
	"github.com/digital-dream-labs/vector-go-sdk/pkg/vectorpb"
	"github.com/os-vector/wired/vars"
)

// Behavior control hold without the upstream go-sdk busy-loop.
//
// Long-lived drive uses DEFAULT priority. OVERRIDE + re-assert-on-lost was
// fighting Victor mid-drive and rebooting some units. One-shot actions
// (say/audio) may still request OVERRIDE briefly via withControl.
func (m *SeekDashboard) controlStart() error {
	return m.controlStartPriority(vectorpb.ControlRequest_DEFAULT)
}

func (m *SeekDashboard) controlStartPriority(priority vectorpb.ControlRequest_Priority) error {
	m.mu.Lock()
	if m.holding || m.starting {
		m.mu.Unlock()
		return nil
	}
	m.starting = true
	m.mu.Unlock()

	defer func() {
		m.mu.Lock()
		m.starting = false
		m.mu.Unlock()
	}()

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
	errCh := make(chan error, 1)

	go func() {
		for {
			resp, err := stream.Recv()
			if err != nil {
				select {
				case errCh <- err:
				default:
				}
				return
			}
			if resp.GetControlGrantedResponse() != nil {
				m.mu.Lock()
				if m.ctrlStream == stream {
					m.holding = true
				}
				m.mu.Unlock()
				select {
				case granted <- struct{}{}:
				default:
				}
			}
			// Never re-request on lost — that fight was crashing units.
			// Drop holding so we cannot send DriveWheels without a grant.
			if resp.GetControlLostEvent() != nil {
				m.mu.Lock()
				if m.ctrlStream == stream {
					m.holding = false
					m.driveL = 0
					m.driveR = 0
					c := m.cancel
					m.ctrlStream = nil
					m.vec = nil
					m.cancel = nil
					m.mu.Unlock()
					m.stopDriveLoop()
					if c != nil {
						c()
					}
					return
				}
				m.mu.Unlock()
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
	case <-time.After(10 * time.Second):
		cancel()
		return errors.New("timeout waiting for behavior control")
	}

	m.mu.Lock()
	m.holding = true
	m.vec = v
	m.cancel = cancel
	m.ctrlStream = stream
	m.driveL = 0
	m.driveR = 0
	m.lastActivity = time.Now()
	m.mu.Unlock()

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

	// Prefer zero wheels over StopAllMotors — gentler on the behavior system.
	if v != nil {
		ctx, cancelW := context.WithTimeout(context.Background(), 2*time.Second)
		_, _ = v.Conn.DriveWheels(ctx, &vectorpb.DriveWheelsRequest{})
		cancelW()
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

	// Short one-shots: OVERRIDE so say/audio can interrupt idle animations.
	if err := m.controlStartPriority(vectorpb.ControlRequest_OVERRIDE_BEHAVIORS); err != nil {
		return err
	}
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
	return m.controlStartPriority(vectorpb.ControlRequest_DEFAULT)
}

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
	// 5 Hz drive loop — enough for teleop, cooler than 10 Hz.
	ticker := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()
	var lastL, lastR float32
	var haveLast bool
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
			// Never send wheel commands without an active grant.
			if !holding || v == nil {
				haveLast = false
				continue
			}
			if haveLast && l == lastL && r == lastR {
				continue
			}
			ctxW, cancelW := context.WithTimeout(context.Background(), 1500*time.Millisecond)
			_, err := v.Conn.DriveWheels(ctxW, &vectorpb.DriveWheelsRequest{
				LeftWheelMmps:   l,
				RightWheelMmps:  r,
				LeftWheelMmps2:  abs32(l),
				RightWheelMmps2: abs32(r),
			})
			cancelW()
			if err != nil {
				continue
			}
			lastL, lastR = l, r
			haveLast = true
		}
	}
}

func (m *SeekDashboard) setDriveIntent(left, right float32) {
	if left < -120 {
		left = -120
	}
	if left > 120 {
		left = 120
	}
	if right < -120 {
		right = -120
	}
	if right > 120 {
		right = 120
	}
	m.mu.Lock()
	m.driveL = left
	m.driveR = right
	holding := m.holding
	if left != 0 || right != 0 {
		m.lastActivity = time.Now()
	}
	m.mu.Unlock()
	if holding && (left != 0 || right != 0) {
		m.startDriveLoop()
	}
	if holding && left == 0 && right == 0 {
		m.stopDriveLoop()
	}
}

func abs32(v float32) float32 {
	if v < 0 {
		return -v
	}
	return v
}
