package mods

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os/exec"
	"regexp"
	"strings"
	"time"
)

type seekWifiNetwork struct {
	SSID      string `json:"ssid"`
	ServiceID string `json:"serviceId"`
	Connected bool   `json:"connected"`
	Secured   bool   `json:"secured"`
}

var seekWifiServiceRe = regexp.MustCompile(`wifi_[^\s]+`)

func (m *SeekDashboard) handleGetWifiStatus() (map[string]any, error) {
	ssid := strings.TrimSpace(seekRunCmd("iwgetid", "-r"))
	stateOut := seekRunCmd("connmanctl", "state")
	connected := strings.Contains(stateOut, "online") || strings.Contains(stateOut, "ready")
	ip := ""
	if addrs := seekListWifiIPs(); len(addrs) > 0 {
		ip = addrs[0]
	}
	return map[string]any{
		"ssid":      ssid,
		"connected": ssid != "" && connected,
		"ip":        ip,
		"state":     strings.TrimSpace(stateOut),
	}, nil
}

func seekListWifiIPs() []string {
	out := seekRunCmd("ip", "-4", "-o", "addr", "show", "wlan0")
	var ips []string
	for _, line := range strings.Split(out, "\n") {
		fields := strings.Fields(line)
		for i, f := range fields {
			if f == "inet" && i+1 < len(fields) {
				ip := strings.Split(fields[i+1], "/")[0]
				if ip != "" {
					ips = append(ips, ip)
				}
			}
		}
	}
	return ips
}

func (m *SeekDashboard) handleWifiScan() ([]seekWifiNetwork, error) {
	_ = seekRunCmd("connmanctl", "enable", "wifi")
	_ = seekRunCmd("connmanctl", "scan", "wifi")
	time.Sleep(3 * time.Second)
	out := seekRunCmd("connmanctl", "services")
	currentSSID := strings.TrimSpace(seekRunCmd("iwgetid", "-r"))
	seen := map[string]bool{}
	var nets []seekWifiNetwork
	for _, line := range strings.Split(out, "\n") {
		net, ok := parseConnmanWifiLine(line, currentSSID)
		if !ok || net.SSID == "" || seen[net.SSID] {
			continue
		}
		seen[net.SSID] = true
		nets = append(nets, net)
	}
	return nets, nil
}

func parseConnmanWifiLine(line, currentSSID string) (seekWifiNetwork, bool) {
	line = strings.TrimRight(line, " \t\r")
	if !strings.Contains(line, "wifi_") {
		return seekWifiNetwork{}, false
	}
	m := seekWifiServiceRe.FindString(line)
	if m == "" {
		return seekWifiNetwork{}, false
	}
	idx := strings.Index(line, m)
	left := strings.TrimSpace(line[:idx])
	name := strings.TrimSpace(left)
	if name != "" {
		fields := strings.Fields(name)
		if len(fields) > 1 && len(fields[0]) <= 4 {
			name = strings.Join(fields[1:], " ")
		} else if len(fields) == 1 && strings.ContainsAny(fields[0], "*ARCDEF") {
			name = ""
		}
	}
	if name == "" {
		return seekWifiNetwork{}, false
	}
	connected := strings.Contains(left, "*") && name == currentSSID
	if name == currentSSID {
		connected = true
	}
	secured := strings.Contains(m, "_psk") || strings.Contains(m, "_eap")
	return seekWifiNetwork{
		SSID:      name,
		ServiceID: m,
		Connected: connected,
		Secured:   secured,
	}, true
}

func (m *SeekDashboard) handleWifiConnect(ssid, password, serviceID string) error {
	ssid = strings.TrimSpace(ssid)
	if ssid == "" {
		return errors.New("SSID required")
	}
	_ = seekRunCmd("connmanctl", "enable", "wifi")
	if serviceID == "" {
		_, _ = m.handleWifiScan()
		out := seekRunCmd("connmanctl", "services")
		for _, line := range strings.Split(out, "\n") {
			net, ok := parseConnmanWifiLine(line, "")
			if ok && strings.EqualFold(net.SSID, ssid) {
				serviceID = net.ServiceID
				break
			}
		}
	}
	if serviceID == "" {
		return fmt.Errorf("network %q not found — tap Scan and pick from the list", ssid)
	}
	if strings.Contains(serviceID, "_psk") || strings.Contains(serviceID, "_eap") {
		if strings.TrimSpace(password) == "" {
			return errors.New("password required for this network")
		}
		if out, err := seekRunCmdErr("connmanctl", "config", serviceID, "--passphrase", password); err != nil {
			return fmt.Errorf("wifi config: %s", strings.TrimSpace(out))
		}
	}
	out, err := seekRunCmdErr("connmanctl", "connect", serviceID)
	if err != nil {
		msg := strings.TrimSpace(out)
		if msg == "" {
			msg = err.Error()
		}
		if strings.Contains(strings.ToLower(msg), "invalid key") ||
			strings.Contains(strings.ToLower(msg), "passphrase") {
			return errors.New("wrong Wi‑Fi password")
		}
		return fmt.Errorf("connect failed: %s", msg)
	}
	time.Sleep(2 * time.Second)
	newSSID := strings.TrimSpace(seekRunCmd("iwgetid", "-r"))
	if !strings.EqualFold(newSSID, ssid) {
		return fmt.Errorf("connect issued but still on %q (check password or signal)", newSSID)
	}
	return nil
}

func seekRunCmd(name string, args ...string) string {
	out, _ := seekRunCmdErr(name, args...)
	return out
}

func seekRunCmdErr(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	raw, err := cmd.CombinedOutput()
	return string(raw), err
}

func writeWifiJSON(w http.ResponseWriter, v any) {
	out, _ := json.Marshal(v)
	w.Header().Set("Content-Type", "application/json")
	w.Write(out)
}
