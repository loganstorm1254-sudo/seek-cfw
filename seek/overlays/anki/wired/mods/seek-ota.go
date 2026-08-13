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
	seekOTADir      = "/data/ota"
	seekOTAFile     = "/data/ota/v.ota"
	seekOTAMaxBytes = 220 << 20 // 220 MiB
	seekOTAMinBytes = 8 << 20   // 8 MiB — real Seek OTAs are ~170MB
	seekOTAChunkMax = 2 << 20
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
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"bytes": n,
		"path":  seekOTAFile,
	})
}

func (m *SeekDashboard) handleOTAInstall() error {
	st, err := os.Stat(seekOTAFile)
	if err != nil {
		return errors.New("no OTA file on robot — upload it first")
	}
	if st.Size() < seekOTAMinBytes {
		return fmt.Errorf("uploaded file is too small (%d bytes)", st.Size())
	}
	// Local httpd is already serving /data/ota on 127.0.0.1:8765.
	go func() {
		time.Sleep(400 * time.Millisecond)
		cmd := exec.Command("/bin/sh", "-c",
			"systemctl stop update-engine.timer update-engine; rm -rf /run/update-engine; "+
				"/usr/sbin/update-os http://127.0.0.1:8765/v.ota")
		_ = cmd.Start()
	}()
	return nil
}
