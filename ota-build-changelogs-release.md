# Release ota changelogs
## https://anki2.ca/otas/1.6-rebuild/release/

## 1.6.1.8 (2026/06/26)
### Victor side changes:
Update Victor to `eb9b86fec1d31d79dca4d1e1961552e4a486fe82`:
- Don't play the eye color transition anim if the target eye color is the same as current.
- Power off and reboot voice command (rebuild voice server only).
- Reimplement anki pairing screen
- Don't try to generate ready text for intent graph, fixes Japanese intent graph.
- Cozmo cube support by AmyMC.
- Prototype "eyes" charger support (Mostly AmyMC, I put some supporting code in).
- Weather no longer bugs and plays the starry anim when it's sunny.
- Vector no longer plays the snowglobe anim when shaken since it's basically summer now.
- Show enabled/disabled status of auto updates in CCIS.
- On inital setup, instead of showing Vector's ID plus the link, it now shows "Setup Robot at:" plus the link, the ID still shows on the pairing screen.
- Rebuild eyes no longer hangs vic-engine when switching to/from it.
- CCIS now shows if the current base build is indev or release, shows branch if it is a deployed build.
- Victor side change to allow you to enroll faces in the Wired UI (<vector-ip>:8080 in a web browser).
- Better alexa pairing text scaling on Vector 2.0 since it was really small.
- Rebuild eyes are now never fully white and always have a tint of the color.
- Fix trying to leave charger trying to activate when not on charger resulting in looping causing Vector to sit still.
- Fix Vector not wanting to interact with cubes.
- Fix path planner constantly looping.
- Remove custom weather implementation, might return.
- [Black desk compatibility mode](https://github.com/Victor-Rebuild/victor-1.6-rebuild-2/commit/c93e933691f04880d60cc0bf0a17d6e459e7ff3d)
- Bring SDK support in line with firmware 2.0.1
- Make Vector go home on "I am satisfied with my care" intent (rebuild server only)
- Fix drive off charger bugs.
- Add the ability to activate keepaway using a Voice Command.
- Add Cubedrive.
- Be able to trigger cubedrive via a Voice Command.
- New Eye color: Mystery Eyes! Eye color is randomly set every time it's chosen and every boot.
- Fully functional rock paper scissors! (Play by asking Vector to "Play rock paper scissors").
- Fix SDK display image on Vector 2.0
- Can now load custom TTS config from `/data/data/rebuild/tts_config.json`.
- Fix the robot sometimes saying the name wrong.

Small optimizations and cleanup applied in a bunch of places:
- Change it everywhere so that Vector's processes don't check for 30/60fps every LCD draw and instead only checks on start.
- Have a global static cast value for `proceduralFace.cpp` instead of having a new one for each use.
- Rebuild eyes code in `settingsManager.cpp` is cleaner and easier to read.
- Rebuild eyes now only updates every 30 seconds instead of every 45 milliseconds like before, seems a bit more efficient.
- Remove a bunch of extra `emrHelper.h`'s since they're dupes due to `cozmoConfig.h` and other headers that are included containing it.
- Date intent is now it's own folder but still shares some parts of timer.

### oelinux side changes:
- Can change/set custom eye color from the `:8080` webserver.
- Update wired for the :8080 webserver changes.
- Bump victor compat
- Wired now saves the botname in `/data/data/rebuild/customBotName` instead of `/data/data/customBotName`.
- Build system is a bit cleaner as victor-1.6 is now a submodule (Didn't work last time but seems to work now).

## 1.6.1.7 (2026/04/30)
### aaaaaa this is a load of barnacles, I hope bots don't break when they update to this.
This is in a seperate readme, it is NOT fitting in here: [1.6.1.7 changelog](./Release-1.6.1.7.md)

## 1.6.1.6 (2026/01/18)
Update victor to `efc92b1ce8771befcb326fe44ae349083c3a42e4`, remove denoising function. Identical to 1.6.1.0046.

## 1.6.1.5 (2026/01/17)
Update victor to `fa16d8816d27524bad9703dfc277ceecedefae84`, add PurplPKG, add gamma correction, add Wire's 2.0 cam fixes. Identical to 1.6.1.0045.

## 1.6.1.4 (2026/01/16)
Update victor to `3ecd4f59f347dae89ec5642f2baca0d05b8a6a73`, finish multilanguage support, now french, german, and japanese have proper translated strings, albeit google translated, OpenCV updated to `6950bedb5ce1827bc025bea7c1b23df6e947a437`, fix more 914/915s, new wired interface, new charger leaving loosepixel animation, make Vector play more and go to charger less, add pet detection, fix blackjack and weather positions on Vector 2.0, make crashes reboot faster, 2.0 can now show low battery / overheated battery images correctly, restore unused holiday lights anim.

## 1.6.1.3 (2025/12/30)
Update victor to `ac1c77e7affae8e815cf1ee3e3c29e87b28ff0c6`, extremely fast knowledge graph, add system slot switch option to ccis, fix error 914, fix mirrormode, new onboarding animations, add Bot Naming in :8080, you can ask Vector "What's your name" and Vector will say whatever nickname you set, Vector 2.0 no longer gets overclocked when weather or blackjack happens, fix weather crashes that seem to happen whenever weather is in the negatives, change kernel name in neofetch, update all submodules, reonboarding clears wirepod server status, full mute/unmute animation plays for mics, 2.0 now has the correct screen pixel count, vcs should work better since mics are more sensitive now, fix update engine weirdness, add wp detection logic to select the correct link during onboarding. Includes all indev otas up to 1.6.1.0038!

## 1.6.1.2 (2025/12/16)
Fix nightly reboots waking up instead of starting asleep, fix release ota installing not working right and checking the indev releases instead for the install flag. Identical to indev 1.6.1.0033

## 1.6.1.1 (2025/12/10)
Initial release, includes all indev otas up to 1.6.1.0032
