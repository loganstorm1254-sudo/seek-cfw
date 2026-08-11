package vars

import (
	"errors"
	"strings"
	"time"

	"github.com/digital-dream-labs/vector-go-sdk/pkg/vector"
)

var guidLocation string = "/run/vic-cloud/perRuntimeToken"

func GetGUID() (string, error) {
	return ReadFile(guidLocation)
}

// SDKReady reports whether the per-runtime token exists (vic-cloud up).
func SDKReady() bool {
	guid, err := ReadFile(guidLocation)
	return err == nil && strings.TrimSpace(guid) != ""
}

func GetVec() (*vector.Vector, error) {
	var last error
	// Short retry — after reboot the token can appear a moment late.
	for i := 0; i < 6; i++ {
		guid, err := ReadFile(guidLocation)
		if err != nil || strings.TrimSpace(guid) == "" {
			last = errors.New("robot not ready yet (waiting for SDK token)")
			time.Sleep(400 * time.Millisecond)
			continue
		}
		v, err := vector.New(
			vector.WithToken(strings.TrimSpace(guid)),
			vector.WithTarget("localhost:443"),
		)
		if err != nil {
			last = err
			time.Sleep(400 * time.Millisecond)
			continue
		}
		return v, nil
	}
	if last == nil {
		last = errors.New("robot not ready yet")
	}
	return nil, last
}
