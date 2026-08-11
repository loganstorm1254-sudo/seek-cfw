package vars

import (
	"fmt"
	"net"
	"time"

	"github.com/grandcat/zeroconf"
)

// StartMDNS advertises seek.local / vector.local on Wi‑Fi so phone + PC
// share one discovery name that resolves to the LAN (wlan) IP.
func StartMDNS() {
	go func() {
		var server *zeroconf.Server
		var alias *zeroconf.Server
		for {
			wifiIPs, ifaces := wifiIPsAndIfaces()
			if len(wifiIPs) == 0 || len(ifaces) == 0 {
				if server != nil {
					server.Shutdown()
					server = nil
				}
				if alias != nil {
					alias.Shutdown()
					alias = nil
				}
				time.Sleep(5 * time.Second)
				continue
			}

			if server != nil {
				server.Shutdown()
				server = nil
			}
			if alias != nil {
				alias.Shutdown()
				alias = nil
			}

			txt := []string{
				"path=/seek.html",
				"vendor=SeekOS",
			}
			s, err := zeroconf.RegisterProxy(
				"Seek Dashboard",
				"_http._tcp",
				"local.",
				8080,
				"seek",
				wifiIPs,
				txt,
				ifaces,
			)
			if err != nil {
				fmt.Println("mdns register:", err)
				time.Sleep(5 * time.Second)
				continue
			}
			server = s
			fmt.Println("mdns: advertising seek.local ->", wifiIPs)

			s2, err := zeroconf.RegisterProxy(
				"Vector Seek",
				"_http._tcp",
				"local.",
				8080,
				"vector",
				wifiIPs,
				txt,
				ifaces,
			)
			if err != nil {
				fmt.Println("mdns vector alias:", err)
			} else {
				alias = s2
			}

			time.Sleep(60 * time.Second)
		}
	}()
}

func wifiIPsAndIfaces() ([]string, []net.Interface) {
	all, err := net.Interfaces()
	if err != nil {
		return nil, nil
	}
	ips := make([]string, 0, 2)
	ifaces := make([]net.Interface, 0, 2)
	seen := map[string]bool{}
	for _, iface := range all {
		kind, phoneOK := ifaceKind(iface.Name)
		if !phoneOK || kind != "wifi" {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		hasIP := false
		for _, a := range addrs {
			ipnet, ok := a.(*net.IPNet)
			if !ok || ipnet.IP == nil {
				continue
			}
			ip4 := ipnet.IP.To4()
			if ip4 == nil || ip4.IsLoopback() {
				continue
			}
			key := ip4.String()
			if seen[key] {
				continue
			}
			seen[key] = true
			ips = append(ips, key)
			hasIP = true
		}
		if hasIP {
			ifaces = append(ifaces, iface)
		}
	}
	return ips, ifaces
}
