package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

func main() {
	base, err := exeDir()
	if err != nil {
		fail("Could not find exe folder: %v", err)
	}

	gameDir := filepath.Join(base, "gamedata")
	libDir := filepath.Join(base, "lib")
	natives := filepath.Join(base, "natives")

	if err := os.MkdirAll(gameDir, 0o755); err != nil {
		fail("Could not create gamedata: %v", err)
	}

	client := filepath.Join(libDir, "minecraft-client.jar")
	lwjgl := filepath.Join(libDir, "lwjgl.jar")
	lwjglUtil := filepath.Join(libDir, "lwjgl_util.jar")
	jinput := filepath.Join(libDir, "jinput.jar")

	for _, p := range []string{client, lwjgl, lwjglUtil, jinput, natives} {
		if _, err := os.Stat(p); err != nil {
			fail("Missing required file/folder:\n%s\nKeep the exe next to the lib/ and natives/ folders.", p)
		}
	}

	java := findJava(base)
	if java == "" {
		fail("No Java found.\n\nInstall Java 8, or keep Prism's JRE at:\n%%AppData%%\\Roaming\\PrismLauncher\\java\\jre-legacy\\bin\\javaw.exe")
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

	cmd := exec.Command(java, args...)
	cmd.Dir = gameDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	fmt.Println("Java:", java)
	fmt.Println("Game data:", gameDir)
	fmt.Println("Starting rd-132211 (oak planks mod)...")

	if err := cmd.Run(); err != nil {
		fail("Game exited with error: %v", err)
	}
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

func findJava(base string) string {
	candidates := []string{
		filepath.Join(base, "jre", "bin", "javaw.exe"),
		filepath.Join(base, "jre", "bin", "java.exe"),
		filepath.Join(base, "jre", "bin", "java"),
	}

	if home, err := os.UserHomeDir(); err == nil {
		candidates = append(candidates,
			filepath.Join(home, "AppData", "Roaming", "PrismLauncher", "java", "jre-legacy", "bin", "javaw.exe"),
			filepath.Join(home, "AppData", "Roaming", "PrismLauncher", "java", "jre-legacy", "bin", "java.exe"),
		)
	}

	if v := os.Getenv("JAVA_HOME"); v != "" {
		candidates = append(candidates,
			filepath.Join(v, "bin", "javaw.exe"),
			filepath.Join(v, "bin", "java.exe"),
			filepath.Join(v, "bin", "java"),
		)
	}

	candidates = append(candidates, "javaw.exe", "java.exe", "java")

	for _, c := range candidates {
		if filepath.IsAbs(c) {
			if st, err := os.Stat(c); err == nil && !st.IsDir() {
				return c
			}
			continue
		}
		if path, err := exec.LookPath(c); err == nil {
			return path
		}
	}
	return ""
}

func fail(format string, args ...any) {
	msg := fmt.Sprintf(format, args...)
	fmt.Fprintln(os.Stderr, msg)
	if runtime.GOOS == "windows" {
		fmt.Println("\nPress Enter to close...")
		_, _ = fmt.Scanln()
	}
	os.Exit(1)
}
