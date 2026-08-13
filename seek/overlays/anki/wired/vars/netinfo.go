package vars

import (
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// NetAddr is one IPv4 address on a robot interface.
type NetAddr struct {
	Iface   string `json:"iface"`
	IP      string `json:"ip"`
	Kind    string `json:"kind"` // wifi | hotspot | usb | other
	PhoneOK bool   `json:"phoneOk"`
	Hotspot bool   `json:"hotspot"`
	URL     string `json:"url"`     // http://IP/  (port 80)
	URL8080 string `json:"url8080"` // http://IP:8080/
}

func ifaceKind(name string) string {
	name = strings.ToLower(name)
	switch {
	case name == "usb0" || name == "rndis0" || name == "tether" || strings.HasPrefix(name, "usb"):
		return "usb"
	case name == "uap0" || name == "wlan1" || strings.Contains(name, "ap"):
		return "hotspot"
	case name == "wlan0" || strings.HasPrefix(name, "wlan"):
		return "wifi"
	default:
		return "other"
	}
}

func isHotspotAddr(kind, ip string) bool {
	if kind == "hotspot" {
		return true
	}
	// Pairing AP gateway. USB also uses this IP — callers must check kind != usb.
	return kind == "wifi" && ip == "192.168.42.1"
}

func phoneURLs(ip string) (string, string) {
	return "http://" + ip + "/", "http://" + ip + ":8080/"
}

// ListNetAddrs returns robot IPv4 addresses on interfaces that are up.
func ListNetAddrs() []NetAddr {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	out := make([]NetAddr, 0, 4)
	for _, iface := range ifaces {
		name := iface.Name
		if name == "lo" || strings.HasPrefix(name, "dummy") {
			continue
		}
		if iface.Flags&net.FlagUp == 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		kind := ifaceKind(name)
		for _, a := range addrs {
			ipnet, ok := a.(*net.IPNet)
			if !ok || ipnet.IP == nil {
				continue
			}
			ip4 := ipnet.IP.To4()
			if ip4 == nil || ip4.IsLoopback() || ip4.IsLinkLocalUnicast() {
				continue
			}
			ip := ip4.String()
			hotspot := isHotspotAddr(kind, ip)
			if kind == "usb" {
				hotspot = false
			}
			u80, u8080 := phoneURLs(ip)
			out = append(out, NetAddr{
				Iface:   name,
				IP:      ip,
				Kind:    kind,
				PhoneOK: kind != "usb",
				Hotspot: hotspot,
				URL:     u80,
				URL8080: u8080,
			})
		}
	}
	return out
}

// PreferredLANIP is the Wi‑Fi address a phone on the home network should open.
// Never USB (192.168.42.1 over the cable) — that is what made phones say unreachable.
func PreferredLANIP() string {
	addrs := ListNetAddrs()
	for _, a := range addrs {
		if a.Kind == "wifi" && a.PhoneOK && !a.Hotspot {
			return a.IP
		}
	}
	for _, a := range addrs {
		if a.Hotspot && a.PhoneOK {
			return a.IP
		}
	}
	for _, a := range addrs {
		if a.PhoneOK {
			return a.IP
		}
	}
	return ""
}

func PreferredHotspotIP() string {
	for _, a := range ListNetAddrs() {
		if a.Hotspot && a.PhoneOK {
			return a.IP
		}
	}
	return ""
}

// PreferredPhoneURL is http://<PreferredLANIP>/ (port 80).
func PreferredPhoneURL() string {
	ip := PreferredLANIP()
	if ip == "" {
		return ""
	}
	u, _ := phoneURLs(ip)
	return u
}

func PreferredPhoneURL8080() string {
	ip := PreferredLANIP()
	if ip == "" {
		return ""
	}
	_, u := phoneURLs(ip)
	return u
}

// WifiSSID is the current Wi‑Fi network name (empty if unknown / USB-only).
func WifiSSID() string {
	try := func(name string, args ...string) string {
		out, err := exec.Command(name, args...).Output()
		if err != nil {
			return ""
		}
		return strings.TrimSpace(string(out))
	}
	if s := try("iwgetid", "-r"); s != "" {
		return s
	}
	if s := try("iwgetid", "wlan0", "-r"); s != "" {
		return s
	}
	matches, _ := filepath.Glob("/var/lib/connman/wifi_*/settings")
	for _, p := range matches {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(b), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "Name=") {
				s := strings.TrimSpace(strings.TrimPrefix(line, "Name="))
				if s != "" {
					return s
				}
			}
		}
	}
	return ""
}
