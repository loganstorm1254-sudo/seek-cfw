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

// ListNetAddrs returns robot IPv4 addresses for the dashboard / phone help.
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
		kind := "other"
		phoneOK := false
		switch {
		case name == "wlan0" || strings.HasPrefix(name, "wlan"):
			kind = "wifi"
			phoneOK = true
		case name == "usb0" || name == "rndis0" || name == "tether" || strings.HasPrefix(name, "usb"):
			kind = "usb"
			phoneOK = false
		}
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
			// Classic Vector USB subnet — PC-only, phones can't reach it.
			if strings.HasPrefix(ip, "192.168.42.") {
				kind = "usb"
				phoneOK = false
			}
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

// PreferredPhoneURL returns a Wi‑Fi dashboard URL when available.
func PreferredPhoneURL() string {
	for _, a := range ListNetAddrs() {
		if a.PhoneOK {
			return a.URL
		}
	}
	return ""
}
