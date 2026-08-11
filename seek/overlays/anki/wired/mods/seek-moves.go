package mods

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/digital-dream-labs/vector-go-sdk/pkg/vector"
	"github.com/digital-dream-labs/vector-go-sdk/pkg/vectorpb"
	"github.com/os-vector/wired/vars"
)

// Whitelisted AppIntent names (must exist as app_intent in user_intent_map.json).
var seekAppIntents = map[string]string{
	"intent_play_fistbump":          "Fist bump",
	"intent_play_blackjack":         "Blackjack",
	"intent_play_pickupcube":        "Pick up cube",
	"intent_play_popawheelie":       "Pop a wheelie",
	"intent_play_rollcube":          "Roll cube",
	"intent_play_anytrick":          "Do a trick",
	"intent_play_anygame":           "Play a game",
	"explore_start":                 "Explore",
	"intent_imperative_come":        "Come here",
	"intent_imperative_dance":       "Dance",
	"intent_imperative_lookatme":    "Look at me",
	"intent_imperative_fetchcube":   "Fetch cube",
	"intent_imperative_findcube":    "Find cube",
	"intent_imperative_quiet":       "Be quiet",
	"intent_imperative_shutup":      "Shut up",
	"intent_imperative_affirmative": "Yes",
	"intent_imperative_negative":    "No",
	"intent_imperative_praise":      "Good robot",
	"intent_imperative_apologize":   "Sorry",
	"intent_imperative_scold":       "Bad robot",
	"intent_imperative_love":        "I love you",
	"intent_greeting_goodbye":       "Goodbye",
	"intent_greeting_goodmorning":   "Good morning",
	"intent_greeting_goodnight":     "Good night",
	"intent_system_sleep":           "Go to sleep",
	"intent_system_charger":         "Go to charger",
	"intent_status_feeling":         "How are you?",
	"intent_clock_time":             "What time is it?",
	"intent_character_age":          "How old are you?",
	"intent_imperative_volumeup":    "Volume up",
	"intent_imperative_volumedown":  "Volume down",
	"intent_names_ask":              "What's my name?",
	"intent_meet_victor":            "Meet Vector",
	"intent_seasonal_happynewyear":  "Happy New Year",
	"intent_seasonal_happyholidays": "Happy Holidays",
	"intent_global_stop_extend":     "Stop",
}

// Whitelisted animation triggers (PlayAnimationTrigger).
var seekAnimTriggers = map[string]string{
	"GreetAfterLongTime":    "Hello wave",
	"ReactToGreeting":       "Greeting react",
	"FistBumpRequestOnce":   "Fist bump pose",
	"ComeHereStart":         "Come-here look",
	"GoToSleepGetIn":        "Sleepy",
	"ExploringLookAround":   "Look around",
	"DriveLoopHappy":        "Happy drive",
	"PRDemoGreeting":        "Demo greeting",
	"SeasonalHappyHolidays": "Holidays",
	"SeasonalHappyNewYear":  "New Year",
}

func (m *SeekDashboard) handleAppIntent(intent, param string) error {
	intent = strings.TrimSpace(intent)
	if intent == "" {
		return errors.New("empty intent")
	}
	if _, ok := seekAppIntents[intent]; !ok {
		return errors.New("unknown or blocked intent")
	}
	if len(param) > 64 {
		return errors.New("param too long")
	}

	// Behavior tree needs the robot free — drop any SDK hold first.
	m.controlEnd()
	time.Sleep(120 * time.Millisecond)

	v, err := vars.GetVec()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	_, err = v.Conn.AppIntent(ctx, &vectorpb.AppIntentRequest{
		Intent: intent,
		Param:  param,
	})
	return err
}

func (m *SeekDashboard) handlePlayAnimTrigger(name string) error {
	name = strings.TrimSpace(name)
	if name == "" {
		return errors.New("empty animation")
	}
	if _, ok := seekAnimTriggers[name]; !ok {
		return errors.New("unknown or blocked animation")
	}
	return m.withControl(func(ctx context.Context, v *vector.Vector) error {
		ctxT, cancel := context.WithTimeout(ctx, 30*time.Second)
		defer cancel()
		_, err := v.Conn.PlayAnimationTrigger(ctxT, &vectorpb.PlayAnimationTriggerRequest{
			AnimationTrigger: &vectorpb.AnimationTrigger{Name: name},
			Loops:            1,
			UseLiftSafe:      true,
		})
		return err
	})
}

// handleListen frees SDK control so Vector can hear "Hey Vector" / backpack wake.
func (m *SeekDashboard) handleListen() error {
	m.controlEnd()
	return nil
}

func (m *SeekDashboard) writeMovesCatalog(w http.ResponseWriter) {
	type item struct {
		ID    string `json:"id"`
		Label string `json:"label"`
	}
	intents := make([]item, 0, len(seekAppIntents))
	for id, label := range seekAppIntents {
		intents = append(intents, item{ID: id, Label: label})
	}
	anims := make([]item, 0, len(seekAnimTriggers))
	for id, label := range seekAnimTriggers {
		anims = append(anims, item{ID: id, Label: label})
	}
	out, _ := json.Marshal(map[string]any{
		"intents": intents,
		"anims":   anims,
	})
	w.Header().Set("Content-Type", "application/json")
	w.Write(out)
}
