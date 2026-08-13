package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path"
	"strings"
	"time"

	"github.com/os-vector/wired/mods"
	"github.com/os-vector/wired/vars"
)

//go:embed update-os.sh
var seekUpdateOSScript []byte

var EnabledMods []vars.Modification = []vars.Modification{
	mods.NewFreqChange(),
	mods.NewWakeWordPV(),
	mods.NewAutoUpdate(),
	mods.NewSensitivityPV(),
	mods.NewJdocSettings(),
	mods.NewFaces(),
	mods.NewSeekDashboard(),
	mods.NewSeekDoom(),
}

func installFastUpdateOS() {
	if err := os.MkdirAll("/data", 0755); err != nil {
		fmt.Println("update-os mkdir:", err)
		return
	}
	if err := os.WriteFile("/data/update-os.sh", seekUpdateOSScript, 0644); err != nil {
		fmt.Println("update-os write:", err)
		return
	}
	// /data is noexec. Copy to /run (tmpfs, executable) then bind-mount.
	if err := os.WriteFile("/run/update-os", seekUpdateOSScript, 0755); err != nil {
		fmt.Println("update-os /run write:", err)
		return
	}
	_ = exec.Command("umount", "/usr/sbin/update-os").Run()
	if err := exec.Command("mount", "--bind", "/run/update-os", "/usr/sbin/update-os").Run(); err != nil {
		fmt.Println("update-os bind mount:", err)
	}
}

func main() {
	installFastUpdateOS()
	http.HandleFunc("/api/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"ok":    true,
			"ready": vars.SDKReady(),
			"ts":    time.Now().Unix(),
		})
	})
	http.HandleFunc("/api/netinfo", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		lanIP := vars.PreferredLANIP()
		url := vars.PreferredPhoneURL()
		hotIP := vars.PreferredHotspotIP()
		_ = json.NewEncoder(w).Encode(map[string]any{
			"addrs":        vars.ListNetAddrs(),
			"lanIp":        lanIP,
			"phoneUrl":     url,
			"phoneUrl8080": vars.PreferredPhoneURL8080(),
			"canonicalUrl": url,
			"oneAddress":   url,
			"hotspotIp":    hotIP,
			"ssid":         vars.WifiSSID(),
			"hint":         "Put the phone on the same home Wi‑Fi as Vector (VPN and Private Relay off). Do not join Vector’s pairing hotspot.",
		})
	})

	vars.EnabledMods = EnabledMods
	vars.InitMods()
	startLocalOTAServer()
	startweb()
}

// startLocalOTAServer serves /data/ota on loopback for update-os.
// GitHub HTTPS from Vector never gets a real Content-Length (stuck at 0%);
// a local file + this server lets update-engine flash at LAN/loopback speed.
func startLocalOTAServer() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		name := path.Base(path.Clean("/" + strings.TrimPrefix(r.URL.Path, "/")))
		if name == "" || name == "." || name == "/" || strings.Contains(name, "..") {
			http.NotFound(w, r)
			return
		}
		http.ServeFile(w, r, path.Join("/data/ota", name))
	})
	srv := &http.Server{
		Addr:              "127.0.0.1:8765",
		Handler:           mux,
		ReadHeaderTimeout: 8 * time.Second,
	}
	go func() {
		fmt.Println("local OTA server at 127.0.0.1:8765 (/data/ota)")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Println("local OTA server:", err)
		}
	}()
}

func setStaticContentType(w http.ResponseWriter, reqPath string) {
	clean := path.Clean("/" + strings.TrimPrefix(reqPath, "/"))
	ext := strings.ToLower(path.Ext(clean))
	switch {
	case ext == ".js":
		w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
	case ext == ".css":
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
	case ext == ".html" || clean == "/" || clean == "/index.html" || clean == "/seek.html" || clean == "/seek":
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
	case ext == ".json":
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
	case ext == ".svg":
		w.Header().Set("Content-Type", "image/svg+xml")
	case ext == ".png":
		w.Header().Set("Content-Type", "image/png")
	case ext == ".jpg", ext == ".jpeg":
		w.Header().Set("Content-Type", "image/jpeg")
	case ext == ".webp":
		w.Header().Set("Content-Type", "image/webp")
	case ext == ".mp3":
		w.Header().Set("Content-Type", "audio/mpeg")
	case ext == ".wav":
		w.Header().Set("Content-Type", "audio/wav")
	case ext == ".ico":
		w.Header().Set("Content-Type", "image/x-icon")
	}
}

func serveFile(w http.ResponseWriter, r *http.Request, name string) {
	setStaticContentType(w, name)
	w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
	http.ServeFile(w, r, path.Join("/etc/wired/webroot", name))
}

func seekCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, HEAD")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
		w.Header().Set("Access-Control-Max-Age", "600")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
func startweb() {
	root := http.Dir("/etc/wired/webroot")
	fs := http.FileServer(root)

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("Expires", "0")
		w.Header().Set("Access-Control-Allow-Origin", "*")

		p := path.Clean("/" + strings.TrimPrefix(r.URL.Path, "/"))
		if p == "/" {
			p = "/"
		}

		switch p {
		case "/favicon.ico":
			w.WriteHeader(http.StatusNoContent)
			return
		case "/", "/seek", "/seek/":
			// Phone-friendly: bare IP:8080 opens Seek (avoids "404" confusion).
			serveFile(w, r, "seek.html")
			return
		case "/settings", "/settings/", "/wired", "/wired/":
			serveFile(w, r, "index.html")
			return
		}

		// If someone requests a missing path, send Seek instead of a bare 404 page.
		full := path.Join("/etc/wired/webroot", strings.TrimPrefix(p, "/"))
		if !strings.HasPrefix(full, "/etc/wired/webroot") {
			serveFile(w, r, "seek.html")
			return
		}
		if st, err := os.Stat(full); err != nil || st.IsDir() {
			// Don't mask real asset 404s for css/js — only HTML-ish navigations.
			if path.Ext(p) == "" || path.Ext(p) == ".html" {
				serveFile(w, r, "seek.html")
				return
			}
			http.NotFound(w, r)
			return
		}

		setStaticContentType(w, p)
		fs.ServeHTTP(w, r)
	})
	handler := seekCORS(http.DefaultServeMux)
	srv := &http.Server{
		Addr:              "0.0.0.0:8080",
		Handler:           handler,
		ReadHeaderTimeout: 8 * time.Second,
		ReadTimeout:       20 * time.Minute,
		WriteTimeout:      20 * time.Minute,
		IdleTimeout:       70 * time.Second,
	}
	// Phones that type just the IP hit :80, not :8080.
	go func() {
		s80 := &http.Server{
			Addr:              "0.0.0.0:80",
			Handler:           handler,
			ReadHeaderTimeout: 8 * time.Second,
			ReadTimeout:       20 * time.Minute,
			WriteTimeout:      20 * time.Minute,
			IdleTimeout:       70 * time.Second,
		}
		fmt.Println("starting web at port 80 (all interfaces)")
		if err := s80.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			fmt.Println("port 80:", err)
		}
	}()
	fmt.Println("starting web at port 8080 (all interfaces)")
	if err := srv.ListenAndServe(); err != nil {
		fmt.Println("ListenAndServe:", err)
		panic(err)
	}
}
