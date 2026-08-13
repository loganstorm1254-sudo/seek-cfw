package mods

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

const (
	seekOTADir        = "/data/ota"
	seekOTAFile       = "/data/ota/v.ota"
	seekOTAMaxBytes   = 220 << 20 // 220 MiB
	seekOTAMinBytes   = 8 << 20   // 8 MiB — real Seek OTAs are ~170MB
	seekOTAChunkMax   = 2 << 20
	seekOTALocalURL   = "http://127.0.0.1:8765/v.ota"
	seekOTAStatusFile = "/run/seek-ota.status"
)

func (m *SeekDashboard) handleOTABegin(r *http.Request) error {
	size, _ := strconv.ParseInt(r.FormValue("size"), 10, 64)
	if size < seekOTAMinBytes || size > seekOTAMaxBytes {
		return fmt.Errorf("OTA size must be between 8MB and 220MB (got %d)", size)
	}
	name := strings.ToLower(r.FormValue("name"))
	if name != "" && !strings.HasSuffix(name, ".ota") {
		return errors.New("file must be a .ota")
	}
	if err := os.MkdirAll(seekOTADir, 0755); err != nil {
		return err
	}
	f, err := os.OpenFile(seekOTAFile, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	_ = f.Close()
	_ = os.WriteFile(seekOTAFile+".size", []byte(strconv.FormatInt(size, 10)), 0644)
	writeSeekOTAStatus("ready", "Upload started", 0, "")
	return nil
}

func (m *SeekDashboard) handleOTAChunk(w http.ResponseWriter, r *http.Request) error {
	off, err := strconv.ParseInt(r.URL.Query().Get("off"), 10, 64)
	if err != nil || off < 0 {
		return errors.New("bad offset")
	}
	if _, err := os.Stat(seekOTAFile); err != nil {
		return errors.New("call otaBegin first")
	}
	body := io.LimitReader(r.Body, seekOTAChunkMax+1)
	data, err := io.ReadAll(body)
	if err != nil {
		return err
	}
	if int64(len(data)) > seekOTAChunkMax {
		return errors.New("chunk too large")
	}
	if off+int64(len(data)) > seekOTAMaxBytes {
		return errors.New("OTA too large")
	}
	f, err := os.OpenFile(seekOTAFile, os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err := f.WriteAt(data, off); err != nil {
		return err
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}

func (m *SeekDashboard) handleOTAStatus(w http.ResponseWriter) {
	st, err := os.Stat(seekOTAFile)
	var n int64
	if err == nil {
		n = st.Size()
	}
	out := map[string]any{
		"bytes": n,
		"path":  seekOTAFile,
		"url":   seekOTALocalURL,
	}
	if b, err := os.ReadFile(seekOTAStatusFile); err == nil {
		var status map[string]any
		if json.Unmarshal(b, &status) == nil {
			for k, v := range status {
				out[k] = v
			}
		}
	}
	// Live update-engine progress when flashing.
	if prog, err := os.ReadFile("/run/update-engine/progress"); err == nil {
		out["engineProgress"] = strings.TrimSpace(string(prog))
	}
	if exp, err := os.ReadFile("/run/update-engine/expected-size"); err == nil {
		out["engineExpected"] = strings.TrimSpace(string(exp))
	}
	if errb, err := os.ReadFile("/run/update-engine/error"); err == nil {
		msg := strings.TrimSpace(string(errb))
		if msg != "" && msg != "Unclean exit" {
			out["engineError"] = msg
		}
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(out)
}

func writeSeekOTAStatus(phase, detail string, pct int, errMsg string) {
	_ = os.MkdirAll("/run", 0755)
	payload := map[string]any{
		"phase":  phase,
		"detail": detail,
		"pct":    pct,
		"ts":     time.Now().Unix(),
	}
	if errMsg != "" {
		payload["error"] = errMsg
	}
	b, _ := json.Marshal(payload)
	_ = os.WriteFile(seekOTAStatusFile, b, 0644)
}

func (m *SeekDashboard) handleOTAInstall() error {
	st, err := os.Stat(seekOTAFile)
	if err != nil {
		return errors.New("no OTA file on robot — upload it first")
	}
	if st.Size() < seekOTAMinBytes {
		return fmt.Errorf("uploaded file is too small (%d bytes)", st.Size())
	}
	if wantRaw, err := os.ReadFile(seekOTAFile + ".size"); err == nil {
		want, _ := strconv.ParseInt(strings.TrimSpace(string(wantRaw)), 10, 64)
		if want > 0 && st.Size() != want {
			return fmt.Errorf("upload incomplete: have %d bytes, expected %d", st.Size(), want)
		}
	}
	// Never call update-os here: older scripts delete /data/ota/v.ota then
	// re-download from the same path (cloud-with-! face). Flash the uploaded
	// file through the loopback server instead.
	writeSeekOTAStatus("starting", "Starting local flash", 0, "")
	go flashUploadedSeekOTA(st.Size())
	return nil
}

func flashUploadedSeekOTA(size int64) {
	writeSeekOTAStatus("probe", "Checking local OTA server", 0, "")
	client := &http.Client{Timeout: 15 * time.Second}
	req, err := http.NewRequest(http.MethodGet, seekOTALocalURL, nil)
	if err != nil {
		writeSeekOTAStatus("error", "Bad local URL", 0, err.Error())
		return
	}
	req.Header.Set("Range", "bytes=0-1048575")
	resp, err := client.Do(req)
	if err != nil {
		writeSeekOTAStatus("error", "Local OTA server not reachable", 0,
			"127.0.0.1:8765 failed — restart wired, then retry")
		return
	}
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 2<<20))
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusPartialContent {
		writeSeekOTAStatus("error", "Local OTA probe failed", 0,
			fmt.Sprintf("HTTP %d from %s", resp.StatusCode, seekOTALocalURL))
		return
	}

	_ = exec.Command("systemctl", "stop", "update-engine.timer", "update-engine").Run()
	_ = os.RemoveAll("/run/update-engine")
	_ = os.MkdirAll("/run/update-engine", 0755)
	_ = os.MkdirAll("/run/vic-switchboard", 0755)

	env := strings.Join([]string{
		"UPDATE_ENGINE_ENABLED=True",
		"UPDATE_ENGINE_MAX_SLEEP=1",
		"UPDATE_ENGINE_ALLOW_DOWNGRADE=True",
		"UPDATE_ENGINE_DEBUG=True",
		"UPDATE_ENGINE_URL=" + seekOTALocalURL,
		"",
	}, "\n")
	if err := os.WriteFile("/run/vic-switchboard/update-engine.env", []byte(env), 0644); err != nil {
		writeSeekOTAStatus("error", "Could not write update-engine.env", 0, err.Error())
		return
	}
	_ = exec.Command("chown", "-R", "net:anki", "/run/vic-switchboard").Run()

	_ = exec.Command("systemctl", "reset-failed", "update-engine").Run()
	if err := exec.Command("systemctl", "start", "update-engine").Run(); err != nil {
		writeSeekOTAStatus("error", "update-engine failed to start", 0, err.Error())
		_ = exec.Command("systemctl", "start", "anki-robot.target").Run()
		return
	}

	writeSeekOTAStatus("flashing", "Flashing from phone upload (local)", 1, "")
	// Local file — Wi‑Fi not needed; free CPU for the flash.
	time.Sleep(2 * time.Second)
	_ = exec.Command("systemctl", "stop", "anki-robot.target").Run()

	deadline := time.Now().Add(60 * time.Minute)
	var last int64
	stall := 0
	for time.Now().Before(deadline) {
		if b, err := os.ReadFile("/run/update-engine/error"); err == nil {
			msg := strings.TrimSpace(string(b))
			if msg != "" && msg != "Unclean exit" {
				writeSeekOTAStatus("error", "Update failed", 0, msg)
				_ = exec.Command("systemctl", "start", "anki-robot.target").Run()
				return
			}
		}
		var progress, expected int64
		if b, err := os.ReadFile("/run/update-engine/progress"); err == nil {
			progress, _ = strconv.ParseInt(strings.TrimSpace(string(b)), 10, 64)
		}
		if b, err := os.ReadFile("/run/update-engine/expected-size"); err == nil {
			expected, _ = strconv.ParseInt(strings.TrimSpace(string(b)), 10, 64)
		}
		pct := 0
		if expected > 0 {
			pct = int(100 * progress / expected)
			if pct > 99 {
				pct = 99
			}
		}
		writeSeekOTAStatus("flashing",
			fmt.Sprintf("Flashing… %d%% (%d / %d)", pct, progress, expected),
			pct, "")

		if progress == last {
			stall++
		} else {
			stall = 0
			last = progress
		}
		if progress == 0 && stall > 90 {
			writeSeekOTAStatus("error", "Stuck at 0%", 0,
				"update-engine never started reading the local OTA")
			_ = exec.Command("systemctl", "stop", "update-engine").Run()
			_ = exec.Command("systemctl", "start", "anki-robot.target").Run()
			return
		}

		if _, err := os.Stat("/run/update-engine/done"); err == nil {
			if _, err := os.Stat("/run/update-engine/manifest.ini"); err != nil {
				_ = os.Remove("/run/update-engine/done")
				writeSeekOTAStatus("error", "Did not flash (stale done)", 0,
					"manifest missing — not rebooting")
				_ = exec.Command("systemctl", "start", "anki-robot.target").Run()
				return
			}
			writeSeekOTAStatus("rebooting", "Flash complete — rebooting", 100, "")
			time.Sleep(2 * time.Second)
			_ = exec.Command("sync").Run()
			_ = exec.Command("reboot").Start()
			return
		}
		_ = size // keep size available for future checks
		time.Sleep(2 * time.Second)
	}
	writeSeekOTAStatus("error", "Timed out", 0, "flash did not finish within 60 minutes")
	_ = exec.Command("systemctl", "start", "anki-robot.target").Run()
}
