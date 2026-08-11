package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"path"
	"strings"
	"time"

	"github.com/os-vector/wired/mods"
	"github.com/os-vector/wired/vars"
)

var EnabledMods []vars.Modification = []vars.Modification{
	mods.NewFreqChange(),
	mods.NewWakeWordPV(),
	mods.NewAutoUpdate(),
	mods.NewSensitivityPV(),
	mods.NewJdocSettings(),
	mods.NewFaces(),
	mods.NewSeekDashboard(),
}

func main() {
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
		_ = json.NewEncoder(w).Encode(map[string]any{
			"addrs":        vars.ListNetAddrs(),
			"lanIp":        lanIP,
			"phoneUrl":     url,
			"canonicalUrl": url,
			"oneAddress":   url,
			"hint":         "Open http://<vector-ip>:8080/seek.html in any browser on the same Wi‑Fi as Vector.",
		})
	})

	vars.EnabledMods = EnabledMods
	vars.InitMods()
	startweb()
}

func setStaticContentType(w http.ResponseWriter, reqPath string) {
	clean := path.Clean("/" + strings.TrimPrefix(reqPath, "/"))
	ext := strings.ToLower(path.Ext(clean))
	switch {
	case ext == ".js":
		w.Header().Set("Content-Type", "application/javascript; charset=utf-8")
	case ext == ".css":
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
	case ext == ".html" || clean == "/" || clean == "/index.html" || clean == "/seek.html":
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
	}
}

func startweb() {
	fmt.Println("starting web at port 8080 (all interfaces)")
	fs := http.FileServer(http.Dir("/etc/wired/webroot"))
	// Listen on every interface so http://192.168.42.209:8080 works from any
	// browser that can reach Vector on the LAN (phone or PC).
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("Expires", "0")
		w.Header().Set("Access-Control-Allow-Origin", "*")
		setStaticContentType(w, r.URL.Path)
		fs.ServeHTTP(w, r)
	})
	if err := http.ListenAndServe("0.0.0.0:8080", nil); err != nil {
		fmt.Println("ListenAndServe:", err)
		panic(err)
	}
}
