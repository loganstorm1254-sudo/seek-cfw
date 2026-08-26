package vtr

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
)

type JsonIntent struct {
	Name              string   `json:"name"`
	Keyphrases        []string `json:"keyphrases"`
	RequireExactMatch bool     `json:"requiresexact"`
}

var IntentList []JsonIntent

func loadIntents() {
	file, err := os.ReadFile("/anki/data/assets/cozmo_resources/cloudless/en-US/en-US.json")
	if err != nil {
		log.Println("loadIntents:", err)
		IntentList = nil
		return
	}
	err = json.Unmarshal(file, &IntentList)
	if err != nil {
		fmt.Println(err)
		IntentList = nil
	}
}
