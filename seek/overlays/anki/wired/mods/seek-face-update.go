package mods

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/os-vector/wired/vars"
)

const (
	seekFaceUpdateDisableFlag = "/data/data/user-do-not-face-os-update"
	seekFaceUpdateStatusFile  = "/run/seek-face-update.status"
	seekFaceUpdateDetailFile  = "/run/seek-face-update.detail"
	seekGitHubRepoAPI         = "https://api.github.com/repos/loganstorm1254-sudo/seek-cfw/releases/latest"
	seekGitHubOTANamePrefix   = "vicos-"
)

type SeekFaceUpdate struct {
	vars.Modification
	mu      sync.Mutex
	running bool
}

func NewSeekFaceUpdate() *SeekFaceUpdate {
	return &SeekFaceUpdate{}
}

func (m *SeekFaceUpdate) Name() string { return "SeekFaceUpdate" }

func (m *SeekFaceUpdate) Description() string {
	return "Face-menu Update OS: check GitHub for a newer Seek OTA and install it."
}

func (m *SeekFaceUpdate) Load() error {
	writeFaceUpdateStatus("idle", "")
	return nil
}

func (m *SeekFaceUpdate) HTTP(w http.ResponseWriter, r *http.Request) {
	if !strings.HasPrefix(r.URL.Path, "/api/mods/"+m.Name()) {
		return
	}
	action := strings.TrimPrefix(r.URL.Path, "/api/mods/"+m.Name()+"/")
	switch action {
	case "isEnabled":
		if faceOSUpdateEnabled() {
			fmt.Fprint(w, "true")
		} else {
			fmt.Fprint(w, "false")
		}
	case "setEnabled":
		_ = os.Remove(seekFaceUpdateDisableFlag)
		vars.HTTPSuccess(w, r)
	case "setDisabled":
		_ = os.MkdirAll(filepath.Dir(seekFaceUpdateDisableFlag), 0755)
		_ = os.WriteFile(seekFaceUpdateDisableFlag, []byte("1"), 0644)
		vars.HTTPSuccess(w, r)
	case "status":
		st, _ := os.ReadFile(seekFaceUpdateStatusFile)
		detail, _ := os.ReadFile(seekFaceUpdateDetailFile)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{
			"status": strings.TrimSpace(string(st)),
			"detail": strings.TrimSpace(string(detail)),
		})
	case "run":
		if !faceOSUpdateEnabled() {
			writeFaceUpdateStatus("disabled", "")
			fmt.Fprint(w, "disabled")
			return
		}
		m.mu.Lock()
		if m.running {
			m.mu.Unlock()
			fmt.Fprint(w, "busy")
			return
		}
		m.running = true
		m.mu.Unlock()
		writeFaceUpdateStatus("checking", "")
		go func() {
			defer func() {
				m.mu.Lock()
				m.running = false
				m.mu.Unlock()
			}()
			m.checkAndInstall()
		}()
		fmt.Fprint(w, "started")
	default:
		vars.HTTPError(w, r, "404 not found")
	}
}

func faceOSUpdateEnabled() bool {
	_, err := os.Stat(seekFaceUpdateDisableFlag)
	return err != nil
}

func writeFaceUpdateStatus(status, detail string) {
	_ = os.WriteFile(seekFaceUpdateStatusFile, []byte(status+"\n"), 0644)
	_ = os.WriteFile(seekFaceUpdateDetailFile, []byte(detail+"\n"), 0644)
}

func currentOSVersion() string {
	out, err := exec.Command("getprop", "ro.anki.version").CombinedOutput()
	if err == nil {
		v := strings.TrimSpace(string(out))
		if v != "" {
			return v
		}
	}
	b, err := os.ReadFile("/anki/etc/version")
	if err == nil {
		return strings.TrimSpace(string(b))
	}
	return ""
}

var verRe = regexp.MustCompile(`(?i)^v?(\d+)\.(\d+)\.(\d+)\.(\d+)([a-z]?)$`)

func parseSeekVersion(s string) (parts [4]int, letter byte, ok bool) {
	s = strings.TrimSpace(s)
	m := verRe.FindStringSubmatch(s)
	if m == nil {
		return parts, 0, false
	}
	for i := 0; i < 4; i++ {
		n, err := strconv.Atoi(m[i+1])
		if err != nil {
			return parts, 0, false
		}
		parts[i] = n
	}
	if m[5] != "" {
		letter = m[5][0]
		if letter >= 'A' && letter <= 'Z' {
			letter += 'a' - 'A'
		}
	}
	return parts, letter, true
}

// seekVersionNewer reports whether remote is strictly newer than current.
func seekVersionNewer(remote, current string) bool {
	rp, rl, rok := parseSeekVersion(remote)
	cp, cl, cok := parseSeekVersion(current)
	if !rok || !cok {
		return strings.TrimPrefix(strings.ToLower(remote), "v") != strings.ToLower(current)
	}
	for i := 0; i < 4; i++ {
		if rp[i] > cp[i] {
			return true
		}
		if rp[i] < cp[i] {
			return false
		}
	}
	return rl > cl
}

type ghRelease struct {
	TagName string `json:"tag_name"`
	Assets  []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
	} `json:"assets"`
}

func (m *SeekFaceUpdate) checkAndInstall() {
	writeFaceUpdateStatus("checking", "")
	cur := currentOSVersion()

	client := &http.Client{Timeout: 25 * time.Second}
	req, err := http.NewRequest(http.MethodGet, seekGitHubRepoAPI, nil)
	if err != nil {
		writeFaceUpdateStatus("error", "request")
		return
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "SeekOS-FaceUpdate")

	resp, err := client.Do(req)
	if err != nil {
		writeFaceUpdateStatus("no-network", err.Error())
		return
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil || resp.StatusCode != 200 {
		writeFaceUpdateStatus("error", fmt.Sprintf("github %d", resp.StatusCode))
		return
	}

	var rel ghRelease
	if err := json.Unmarshal(body, &rel); err != nil {
		writeFaceUpdateStatus("error", "parse")
		return
	}
	tag := strings.TrimPrefix(rel.TagName, "v")
	var otaURL string
	for _, a := range rel.Assets {
		name := strings.ToLower(a.Name)
		if strings.HasPrefix(name, seekGitHubOTANamePrefix) && strings.HasSuffix(name, ".ota") {
			otaURL = a.BrowserDownloadURL
			break
		}
	}
	if otaURL == "" {
		writeFaceUpdateStatus("error", "no-ota")
		return
	}

	if cur != "" && !seekVersionNewer(tag, cur) {
		writeFaceUpdateStatus("none", cur)
		return
	}

	writeFaceUpdateStatus("installing", tag)
	time.Sleep(800 * time.Millisecond) // let face show "updating"

	script := "/run/update-os"
	if _, err := os.Stat(script); err != nil {
		if _, err2 := os.Stat("/data/update-os.sh"); err2 == nil {
			script = "/data/update-os.sh"
		} else {
			script = "/usr/sbin/update-os"
		}
	}
	cmd := exec.Command("/bin/bash", script, otaURL)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		writeFaceUpdateStatus("error", err.Error())
		return
	}
	// update-os reboots on success; keep "installing" status.
	_ = cmd.Process.Release()
}
