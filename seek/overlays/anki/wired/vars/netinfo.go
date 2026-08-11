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

func ifaceKind(name string) string {
	name = strings.ToLower(name)
	switch {
	case name == "wlan0" || strings.HasPrefix(name, "wlan"):
		return "wifi"
	case name == "usb0" || name == "rndis0" || name == "tether" || strings.HasPrefix(name, "usb"):
		return "usb"
	default:
		return "other"
	}
}

// ListNetAddrs returns robot IPv4 addresses. Every address is a valid dashboard
// URL if the client can route to it (same LAN / Wi‑Fi as Vector).
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
		kind := ifaceKind(name)
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
				PhoneOK: true, // webpage is on the robot; any browser on the LAN can open it
				URL:     "http://" + ip + ":8080/seek.html",
			})
		}
	}
	return out
}

// PreferredLANIP picks the address users should bookmark.
// Prefer 192.168.42.209 / 192.168.42.x when present (common WireOS LAN), else Wi‑Fi, else any.
func PreferredLANIP() string {
	addrs := ListNetAddrs()
	for _, a := range addrs {
		if a.IP == "192.168.42.209" {
			return a.IP
		}
	}
	for _, a := range addrs {
		if strings.HasPrefix(a.IP, "192.168.42.") {
			return a.IP
		}
	}
	for _, a := range addrs {
		if a.Kind == "wifi" {
			return a.IP
		}
	}
	if len(addrs) > 0 {
		return addrs[0].IP
	}
	return ""
}

// PreferredPhoneURL is http://<PreferredLANIP>:8080/seek.html
func PreferredPhoneURL() string {
	ip := PreferredLANIP()
	if ip == "" {
		return ""
	}
	return "http://" + ip + ":8080/seek.html"
}
