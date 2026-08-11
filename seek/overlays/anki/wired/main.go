package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
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
			"hint":         "Open http://192.168.42.209:8080/ in any browser on the same Wi‑Fi.",
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

func startweb() {
	fmt.Println("starting web at port 8080 (all interfaces)")
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
	if err := http.ListenAndServe("0.0.0.0:8080", nil); err != nil {
		fmt.Println("ListenAndServe:", err)
		panic(err)
	}
}
