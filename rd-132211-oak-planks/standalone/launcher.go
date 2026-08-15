package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	base, err := exeDir()
	if err != nil {
		fatal(nil, "Could not find exe folder: %v", err)
	}

	logPath := filepath.Join(base, "launch.log")
	logf, _ := os.Create(logPath)
	defer func() {
		if logf != nil {
			_ = logf.Close()
		}
	}()
	log := func(format string, args ...any) {
		line := fmt.Sprintf(format, args...)
		fmt.Println(line)
		if logf != nil {
			fmt.Fprintln(logf, line)
			_ = logf.Sync()
		}
	}

	log("Launcher base: %s", base)
	log("Time: %s", time.Now().Format(time.RFC3339))

	gameDir := filepath.Join(base, "gamedata")
	libDir := filepath.Join(base, "lib")
	natives := filepath.Join(base, "natives")

	if err := os.MkdirAll(gameDir, 0o755); err != nil {
		fatal(log, "Could not create gamedata: %v", err)
	}

	client := filepath.Join(libDir, "minecraft-client.jar")
	lwjgl := filepath.Join(libDir, "lwjgl.jar")
	lwjglUtil := filepath.Join(libDir, "lwjgl_util.jar")
	jinput := filepath.Join(libDir, "jinput.jar")

	for _, p := range []string{client, lwjgl, lwjglUtil, jinput} {
		if st, err := os.Stat(p); err != nil || st.IsDir() {
			fatal(log, "Missing required file:\n%s\n\nExtract the WHOLE zip (exe + lib + natives together).", p)
		}
		log("Found %s (%d bytes)", p, mustSize(p))
	}
	if st, err := os.Stat(natives); err != nil || !st.IsDir() {
		fatal(log, "Missing natives folder:\n%s", natives)
	}

	java := findJava(base, log)
	if java == "" {
		fatal(log, "No usable Java 8 found.\n\nEasiest fix: keep Prism installed so this exists:\n%%AppData%%\\Roaming\\PrismLauncher\\java\\jre-legacy\\bin\\java.exe\n\nOr install Temurin/Oracle Java 8 x64 and reopen this exe.\n\nAlso see launch.log next to the exe.")
	}
	log("Using Java: %s", java)

	// Prefer java.exe (console) so LWJGL errors are visible; rewrite javaw -> java
	if strings.HasSuffix(strings.ToLower(java), "javaw.exe") {
		alt := java[:len(java)-len("javaw.exe")] + "java.exe"
		if _, err := os.Stat(alt); err == nil {
			java = alt
			log("Switched to console java: %s", java)
		}
	}

	sep := string(os.PathListSeparator)
	cp := strings.Join([]string{client, lwjgl, lwjglUtil, jinput}, sep)

	args := []string{
		"-Xms512M",
		"-Xmx1024M",
		"-Djava.library.path=" + natives,
		"-cp", cp,
		"com.mojang.rubydung.RubyDung",
	}
	log("Classpath: %s", cp)
	log("Natives: %s", natives)
	log("Cwd: %s", gameDir)
	log("Args: %v", args)

	cmd := exec.Command(java, args...)
	cmd.Dir = gameDir
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out

	err = cmd.Run()
	output := strings.TrimSpace(out.String())
	if output != "" {
		log("---- Java output ----\n%s", output)
	}
	if err != nil {
		fatal(log, "Game failed to start: %v\n\nFull log saved to:\n%s", err, logPath)
	}

	log("Game exited normally.")
	pause()
}

func mustSize(path string) int64 {
	st, err := os.Stat(path)
	if err != nil {
		return 0
	}
	return st.Size()
}

func exeDir() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	return filepath.Dir(exe), nil
}

func findJava(base string, log func(string, ...any)) string {
	var candidates []string

	if home, err := os.UserHomeDir(); err == nil {
		// Prefer Prism's known-good Java 8 first
		candidates = append(candidates,
			filepath.Join(home, "AppData", "Roaming", "PrismLauncher", "java", "jre-legacy", "bin", "java.exe"),
			filepath.Join(home, "AppData", "Roaming", "PrismLauncher", "java", "jre-legacy", "bin", "javaw.exe"),
		)
	}

	candidates = append(candidates,
		filepath.Join(base, "jre", "bin", "java.exe"),
		filepath.Join(base, "jre", "bin", "javaw.exe"),
	)

	if v := os.Getenv("JAVA_HOME"); v != "" {
		candidates = append(candidates,
			filepath.Join(v, "bin", "java.exe"),
			filepath.Join(v, "bin", "javaw.exe"),
		)
	}

	// PATH last — WindowsApps stubs often sit here
	if p, err := exec.LookPath("java.exe"); err == nil {
		candidates = append(candidates, p)
	}
	if p, err := exec.LookPath("javaw.exe"); err == nil {
		candidates = append(candidates, p)
	}
	if p, err := exec.LookPath("java"); err == nil {
		candidates = append(candidates, p)
	}

	for _, c := range candidates {
		log("Checking Java candidate: %s", c)
		if !fileExists(c) {
			log("  skip (not found)")
			continue
		}
		if isWindowsStoreStub(c) {
			log("  skip (Windows Store stub)")
			continue
		}
		if ver, ok := javaVersion(c); ok {
			log("  ok (%s)", ver)
			return c
		}
		log("  skip (could not run -version)")
	}
	return ""
}

func fileExists(path string) bool {
	st, err := os.Stat(path)
	return err == nil && !st.IsDir()
}

func isWindowsStoreStub(path string) bool {
	p := strings.ToLower(filepath.Clean(path))
	return strings.Contains(p, `\windowsapps\`) || strings.Contains(p, `/windowsapps/`)
}

func javaVersion(java string) (string, bool) {
	cmd := exec.Command(java, "-version")
	out, err := cmd.CombinedOutput()
	s := strings.TrimSpace(string(out))
	if s == "" && err != nil {
		return "", false
	}
	// First line is usually: java version "1.8.0_51"
	line := s
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		line = s[:i]
	}
	return strings.TrimSpace(line), true
}

func fatal(log func(string, ...any), format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintln(os.Stderr, msg)
	if log != nil {
		log("FATAL: %s", msg)
	}
	pause()
	os.Exit(1)
}

func pause() {
	fmt.Println()
	// cmd pause is reliable when double-clicked from Explorer
	cmd := exec.Command("cmd", "/C", "echo. & echo Press any key to close... & pause >nul")
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println("Press Enter to close...")
		_, _ = fmt.Scanln()
		time.Sleep(15 * time.Second)
	}
}
