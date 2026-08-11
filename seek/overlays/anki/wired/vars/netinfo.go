package vars

import (
	"net"
	"strings"
)

// NetAddr is one IPv4 address on a robot interface.
type NetAddr struct {
	Iface   string `json:"iface"`
	IP      string `json:"ip"`
	Kind    string `json:"kind"` // wifi | usb | other
	PhoneOK bool   `json:"phoneOk"`
	URL     string `json:"url"`
}

func ifaceKind(name string) (kind string, phoneOK bool) {
	name = strings.ToLower(name)
	switch {
	case name == "wlan0" || strings.HasPrefix(name, "wlan"):
		return "wifi", true
	case name == "usb0" || name == "rndis0" || name == "tether" || strings.HasPrefix(name, "usb"):
		return "usb", false
	default:
		return "other", false
	}
}

// ListNetAddrs returns robot IPv4 addresses for the dashboard / phone help.
// Kind is based on interface name (wlan* = wifi). Do NOT treat 192.168.42.x as
// USB-only — some home routers use that subnet on Wi‑Fi.
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
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		kind, phoneOK := ifaceKind(name)
		for _, a := range addrs {
			ipnet, ok := a.(*net.IPNet)
			if !ok || ipnet.IP == nil {
				continue
			}
			ip4 := ipnet.IP.To4()
			if ip4 == nil || ip4.IsLoopback() {
				continue
			}
			ip := ip4.String()
			out = append(out, NetAddr{
				Iface:   name,
				IP:      ip,
				Kind:    kind,
				PhoneOK: phoneOK,
				URL:     "http://" + ip + ":8080/seek.html",
			})
		}
	}
	return out
}

// PreferredLANIP is the single address everyone should use (Wi‑Fi).
func PreferredLANIP() string {
	for _, a := range ListNetAddrs() {
		if a.PhoneOK {
			return a.IP
		}
	}
	return ""
}

// PreferredPhoneURL returns the Wi‑Fi dashboard URL when available.
func PreferredPhoneURL() string {
	ip := PreferredLANIP()
	if ip == "" {
		return ""
	}
	return "http://" + ip + ":8080/seek.html"
}

// CanonicalHostnames users can type instead of an IP (mDNS).
func CanonicalHostnames() []string {
	return []string{"seek.local", "vector.local"}
}

// IsUSBHost reports whether the HTTP Host is the USB/RNDIS interface.
func IsUSBHost(host string) bool {
	h := host
	if i := strings.IndexByte(h, ':'); i >= 0 {
		h = h[:i]
	}
	h = strings.TrimSpace(h)
	if h == "" {
		return false
	}
	for _, a := range ListNetAddrs() {
		if a.Kind == "usb" && a.IP == h {
			return true
		}
	}
	return false
}
