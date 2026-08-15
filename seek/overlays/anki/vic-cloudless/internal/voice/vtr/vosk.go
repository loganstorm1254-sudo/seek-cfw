package vtr

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"time"

	vosk "github.com/os-vector/vosk-api/go"
)

var model *vosk.VoskModel
var rec *vosk.VoskRecognizer

func InitVosk() {
	loadIntents()
	const modelPath = "/anki/data/assets/cozmo_resources/cloudless/en-US/model"
	var err error
	for attempt := 1; attempt <= 5; attempt++ {
		model, err = vosk.NewModel(modelPath)
		if err == nil {
			break
		}
		log.Println("vosk model not ready (attempt", attempt, "):", err)
		time.Sleep(time.Duration(attempt) * time.Second)
	}
	if err != nil || model == nil {
		// Keep vic-cloud alive — voice ASR degraded, no 923 reboot loop.
		log.Println("vosk: giving up on model load; continuing without ASR:", err)
		return
	}
	rec, err = vosk.NewRecognizerGrm(model, 16000, GetGrammerList("en-US"))
	if err != nil {
		log.Println("vosk: error making recognizer; continuing without ASR:", err)
		rec = nil
		return
	}
	rec.SetMaxAlternatives(0)
	rec.SetEndpointerDelays(3, 0, 0)
}

func Process(chunk []byte) string {
	if rec == nil {
		return ""
	}
	if len(chunk) == 0 {
		fmt.Println("empty chunk")
		return ""
	}
	stop, _ := DetectEndOfSpeech(chunk)
	rec.AcceptWaveform(chunk)
	if stop {
		var jres map[string]interface{}
		json.Unmarshal([]byte(rec.FinalResult()), &jres)
		transcribedText, _ := jres["text"].(string)
		fmt.Println("transcribed text: " + transcribedText)
		go rec.Reset()
		return transcribedText
	}
	return ""
}

func GetFreq() string {
	file, err := os.ReadFile("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq")
	if err == nil {
		return strings.TrimSpace(string(file))
	}
	return "533333"
}

func SetFreq(cpu, ram string) {
	go exec.Command("/usr/bin/sudo", "/usr/sbin/setfreq", cpu, ram).Run()
}
