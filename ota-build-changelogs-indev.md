# Indev ota changelogs
## https://anki2.ca/otas/1.6-rebuild/indev/

## 1.6.1.0094 (2026/09/05
### HOTFIX
### oelinux side change:
- Actually add the needed update-engine-rebuild service.

## 1.6.1.0093 (2026/09/05)
### Victor side changes:
Update Victor to `1ca901bb1ea07db0993386c2e55124edab5cdcc8`:
- Adjust some colors in the CCIS config menu.
- Make vic-robot not crash when running updates from CCIS.

### oelinux side changes:
- Bump `VICTOR_COMPAT_VERSION`
- `update-engine-rebuild` now slightly overclocks Vector to install updates faster.
- Add new systemd service required to fix victor side crashing.

## 1.6.1.0092 (2026/09/04)
### Victor side changes:
Update Victor to `1dfb5bd1b389a0bcc68edfadc1e84908766b8eaf`:
- Fix gazedirection.
- Rebuild eyes now saves every 3 hours instead of 5.
- CCIS now has some nice colored text.
- Network screen now shows status of my server.

## 1.6.1.0091 (2026/09/01)
### Victor side changes:
Update Victor to `2f2d62f8e15705a01a4302dfd56ed6b9794684d2`:
- Make snake activate slightly more.
- Add a command to ask Vector his snake high score.
- Make charger docking more reliable.
- Fix asking Vector for the date.

## 1.6.1.0090 (2026/08/29)
### Victor side changes:
Update Victor to `a509aa16a116eb703b4ea6558275edcd4de82bb7`:
- Actually implement toastito's rock paper scissors anims.
- Add snake game to Vector, it's been made to activate rarely so that it's actually special instead of being common.

## 1.6.1.0089 (2026/08/28)
### Victor side changes:
Update Victor to `c85f47e94e7b7a5cb5848b2b5f85965f1c48af67`:
- Config menu navigation changes:
    - You now use the backpack button to navigate the config menu.
    - 5 pages were condensed down to 3.
- New animations for rock paper scissors made by toastito
- Potentially fix gazedirection looping issue.

## 1.6.1.0088 (2026/08/18)
### Victor side changes:
Update Victor to `d2fb86bf139ae564b8241e7193cf87ef2025581f`:
- 1.6-rebuild settings are now located in a json at `/data/data/rebuild/settings.json`
- Backpack dot light options:
    - Enable/Disable it blinking blue/green (Disabled by default)
    - Enable/Disable it fading between blue/green when blinking is enabled (Disabled by default)

## 1.6.1.0087 (2026/08/16)
### Victor side changes:
Update Victor to `5448a3624b592421d6956d33086fcc1f2768692a`:
- Add way to disable the blinking circle light by sshing in and running `touch /data/data/rebuild/do-not-blink-circle-light` and then restarting robot processes.

## 1.6.1.0086 (2026/08/15)
### Victor side changes:
Update Victor to `d9d487fe6cf530642b7b40870da318713da5ebe6`:
- Let Vector choose to socialize or explore in Dance To The Beat.
- Fistbump Voice Command now looks for face.
- Keepaway can now randomly activate via the `Do a trick` voice command.
- Fix custom and WireOS backpack lights
- Make the code in vic-anim for checking for updates crash vic-robot less
- Make the code in vic-anim only check for updates if connected to the internet.
- Add a option to set robot locale in `:8888/consolevars` --> `RobotSettings` tab.
- Stop vic-engine from crashing if Vector boots up at midnight with `Rebuild Eyes` enabled.
- Make the backpack circle light blink always. (Restores behavior of old bodyboard firmwares)
- Add a toggle for vic-cloudless in CCIS.
- General code cleanup.

### oelinux side changes:
- Bundle my fork of vic-cloudless in builds, off by default but can be enabled in CCIS config menu.
- Fix hanging in internal built otas (non release/indev)
- Add pigz to the system image

## 1.6.1.0085 (2026/07/27)
## Victor side changes:
Update Victor to `925036318b72f05f52c212e710a7892c3050f36d`:
- Different backpack lights when the bot is overheating.

### oelinux side changes:
- Actually apply the pronouns implementation in Wired, my bad.

## 1.6.1.0084 (2026/07/22)
### Victor side changes:
Update Victor to `f47347a3eff50af711e1a1692a1577eb68317c6f`:
- Fix vic-robot crashing due to anim freezing.
- Fix CCIS screen 1 taking a long time to draw.
- Make mic mute/unmute anim render in eye hue again.

## 1.6.1.0083 (2026/07/21)
### Victor side changes:
Update Victor to `e5cf2e7d10c9528734595516f9f092c05b29841e`:
- 60fps bootanims.
- Working pronouns implementation. (Managed in `vector-ip:8080` in a web browser)
- Add a way to manually update Vector from within CCIS.
- Remove WiFi SSID from screen 1 of CCIS, still in screen 2.
- With the extra space the ESN can be shown on screen 1 along with the bot name.
- Bump compat ver

### oelinux side changes
- `update-engine-rebuild` has been cleaned up.
- `update-engine-rebuild` now runs only when the network is actually online.
- A new service was added so that victor can reboot the bot once `update-engine-rebuild` finished when triggered in CCIS.
- Bump compat ver

## 1.6.1.0082 (2026/07/15)
### Victor side changes:
Update Victor to `eb0c10791fa14a10541c60dbff68595706d262e4`:
- Fixed server information screen in CCIS when using a custom server config.
- Added the ability to disable check for person / react to sound check when sleeping to [CCIS](https://github.com/Victor-Rebuild/victor-1.6-rebuild-2/blob/master/CONFIG_MENU.md).
- Building with newer cmake, go, protoc, and upx versions.

## 1.6.1.0081 (2026/07/08)
### Victor side changes:
Update Victor to `47211e07243f11ed6b1cd66da97c48f3273b62b2`:
- Pronouns behavior is implemented, not callable yet via voice command or Wired.
- Fix starry night weather not working correctly.
- Older 1.4-era voice command idk timings
- Bump 2.0 eye saturation again
- Going home now has dynamic brightness so that older Vectors with their original batteries can get home better.

## 1.6.1.0080 (2026/06/26)
### Victor side changes:
Update Victor to `2bbebe7c9889d86f40b3badd71a03d4eaaa3075b`:
- Restore pitch values for TTS to their normal defaults.
- Fix the robot sometimes saying the name wrong.

## 1.6.1.0079 (2026/06/23)
### Victor side changes:
Update Victor to `420bd7c8691971e5b8d48b3b821165965c85985a`:
- New Eye color: Mystery Eyes! Eye color is randomly set every time it's chosen and every boot.
- Fully functional rock paper scissors! (Play by asking Vector to "Play rock paper scissors").
- Fix SDK display image on Vector 2.0
- Can now load custom TTS config from `/data/data/rebuild/tts_config.json`.
- TTS pitch and shaping have had their limits increased to 1k.

## 1.6.1.0078 (2026/06/13)
### Victor side changes:
Update Victor to `0af18cc3d651361f9637fe706aeb3cb89333c899`:
- Rainbow eyes no longer hangs vic-engine

### oelinux side changes:
- Go back to my original rebooter implementation where it's all self-contained in the service.

## 1.6.1.0077 (2026/06/11)
### Victor side changes:
Update Victor to `82a408c848ca58b23d7c96e05efca7966bccaec6`:
- Add the ability to activate keepaway using a Voice Command.
- Add Cubedrive.
- Be able to trigger cubedrive via a Voice Command.

## 1.6.1.0076 (2026/06/08)
### Victor side changes:
Update Victor to `eb9b86fec1d31d79dca4d1e1961552e4a486fe82`:
- Fix drive off charger bugs.
- Daydream no longer colored to fix crashes.
- General code cleanup.

## 1.6.1.0075 (2026/06/04)
### Victor side changes:
Update Victor to `ed9539500dd610c605b6fedb9b42b7145956c053`:
- Fix indev/release showing ? in CCIS.
- Remove custom weather implementation, might return.
- [Black desk compatibility mode](https://github.com/Victor-Rebuild/victor-1.6-rebuild-2/commit/c93e933691f04880d60cc0bf0a17d6e459e7ff3d)
- Space daydream is now colored
- Bring SDK support in line with firmware 2.0.1
- Make Vector go home on "I am satisfied with my care" intent (rebuild server only)

## 1.6.1.0074 (2026/05/30)
End of may yayyyyyyy, hopefully this should be the build that goes to main.
### Victor side changes:
Update Victor to `a7351991849b82dec39f624dee7cfc69a48b386f`:
- Victor side change to allow you to enroll faces in the Wired UI (<vector-ip>:8080 in a web browser).
- Better alexa pairing text scaling on Vector 2.0 since it was really small.
- Rebuild eyes are now never fully white and always have a tint of the color.
- Fix trying to leave charger trying to activate when not on charger resulting in looping causing Vector to sit still.
- Fix Vector not wanting to interact with cubes.
- Fix path planner constantly looping.

## 1.6.1.0073 (2026/05/22)
(Mostly just stability and cleaned up code)
### Victor side changes:
Update Victor to `bfe02a40488cb609bd951e61f368e819d32deed5`:
- More code cleanup throughout the codebase.
- On inital setup, instead of showing Vector's ID plus the link, it now shows "Setup Robot at:" plus the link, the ID still shows on the pairing screen.
- Rebuild eyes now only updates every 30 seconds instead of every 45 milliseconds like before, seems a bit more efficient.
- Rebuild eyes also no longer hangs vic-engine when switching to/from it.
- CCIS now shows if the current base build is indev or release, shows branch if it is a deployed build

## 1.6.1.0072 (2026/05/19)
### Victor side changes:
Update Victor to `48b1bdfdb1f35bcb8ae28608e4f80c8852285edb`:
- Cozmo cube support by AmyMC.
- Prototype "eyes" charger support (Mostly AmyMC, I put some supporting code in).
- Weather no longer bugs and plays the starry anim when it's sunny.
- Vector no longer plays the snowglobe anim when shaken since it's basically summer now.
- Show enabled/disabled status of auto updates in CCIS.

### oelinux side changes:
- Build system is a bit cleaner as victor-1.6 is now a submodule (Didn't work last time but seems to work now).

## 1.6.1.0071 (2026/05/11)
### The optimization update

### Victor side changes:
Update Victor to `5b40d9f64263041fc5ad0fe43c0218833425eeca`:
- Don't play the eye color transition anim if the target eye color is the same as current.
- Ram the cube out of the way of the charger since it seems to work a bit better than pickup.

Small optimizations and cleanup applied in a bunch of places:
- Change it everywhere so that animProcess doesn't check for 30/60fps every LCD draw and instead only checks on start.
- Have a global static cast value for `proceduralFace.cpp` instead of having a new one for each use.
- Rebuild eyes code in `settingsManager.cpp` is cleaner and easier to read.
- Remove a bunch of extra `emrHelper.h`'s since they're dupes due to `cozmoConfig.h` and other headers that are included containing it.
- Date intent is now it's own folder but still shares some parts of timer.

- Don't try to generate ready text for intent graph, fixes Japanese intent graph.
- ^^^^ DDL's implementation was to just make the ready text blank and ask the TTS to generate the blank text, this used up extra processing time and made the Japanese TTS not work right since at the end of each TTS utterance it adds a little extra sound when there should be none. I skipped generating the TTS upon intent graph and kept the default flow for non-intent-graph requests.

### oelinux side changes:
- Wired now saves the botname in `/data/data/rebuild/customBotName` instead of `/data/data/customBotName`.

## 1.6.1.0070 (2026/05/03)
### Victor side changes:
- Update victor to `0cbf5519bb1c2f0e842db5f74dcd1a0c9b3dbe0f`.
- Power off and reboot voice command (rebuild voice server only).
- Reimplement anki pairing screen

### oelinux side changes:
- Can change/set custom eye color from the `:8080` webserver.
- Update wired for the :8080 webserver changes.
- Bump victor compat

## 1.6.1.0069 (nice) (2026/04/27) 
-# aaaa someone stop me
### Victor side changes
- Update victor to `492063e0f2b2489cc8c1b95d67504acb4e48baec`.
- Fix config submenu not defaulting to page 1.
- Restore Anki's text spacing for CCIS screen 2. (network)
- Change conncheck address to the real conncheck.
- Custom preset eye color support. (copy `/anki/data/assets/cozmo_resources/config/engine/eye_color_config.json` to `/data/data/rebuild/eye_color_config.json` and make your changes)
- Rebuild eyes are a little more saturated on 2.0. (+ 0.15 instead of + 0.1)
- Can now mute volume, rebuild servers only. (Hey Vector, Volume Mute)
- Reenable older 1.4 reacttohand animations
- Fix rebuild eyes crash when no internet is available and Vector is waiting for onboarding, make them default again as well.

## 1.6.1.0068 (2026/04/21)
### Victor side changes:
- Update victor to `bd80b055567d682ee88ffd9ef8a8c01f84137842`.
- Can now disable or enable snoring at night within the CCIS config menu.
- Fix spine-select error (898) ([Anki commit](https://github.com/Victor-Rebuild/victor-1.6-rebuild-2/commit/f570a7dc580bb50dcb7ff413c36da4053b7c1192))
- More accurate weather conditions (1.6-rebuild VC server only)
- More range for held in palm

### OE-Linux side changes:
- Use 2.0.1.6076's syscon.dfu, a bot was erroring and having charging issues with 1.6's syscon.dfu.
- Have update-engine-rebuild do a random delay of up to a hour so my server doesn't hurt when every Vector hits the update server at once.

## 1.6.1.0067 (2026/04/14)
Update victor to `7a28490220e639bf5f7eb77fb475b33a0af9b9ab`:
- Add toggle for 60 or 30 fps to the CCIS config menu.
- Beta alexa has been restored and can also be enabled in the CCIS config menu.
- CONF / CONFIGURATION is now the last option in CCIS to keep the size in order on Vector 1.0.
- Explore VC now works again and Vector leaves the charger more often.
- SSID won't show on the main CCIS screen if Vector has a set name.
- Options that previously required a reboot in CCIS except clearing user data now restart just anki-robot processes.
- Options can also be changed in bulk and will apply when you exit the config menu.

## 1.6.1.0066 (2026/04/08)
Update victor to `32bf9fef7589d42bedb31cc3021c50025192b062`:
- Different animation for hooking Vector up to wirepod.
- Update poky submodules
- I think it's finally ready...

## 1.6.1.0065 (2026/04/06)
Update victor to `9566988d4a728a442f241d05fcb093339ad762be`:
- Reacttohand is more forgiving on the angle Vector is at.
- New image for when Vector can't calibrate his gyro.
- Update opencv: more optimized with -O3 and faster libjpeg-turbo for better camera performance.

## 1.6.1.0064 (2026/03/29)
Update victor to `404d7018a212df9ab5956db139c16f7a2161ba58`.
- Rebuild eyes is no longer default due to a big crash that it causes on first time setup.
- CCIS text for Dance to the Beat rainbow eyes changed from `DTTB RANDOM COLORS` to `DTTB RANDOM EYES`.
- Blackjack now gives Vector more autonomy by allowing him to play on/off the charger depending on how he feels, if Vector wants to stay on the charger we skip looking for faces, no need for it since we're on the charger, if Vector wants to leave normal flow will happen (Leave --> Search for faces --> Play blackjack).
- A Bunch of unused animations for wheelstands were reimplemented. 

## 1.6.1.0063 (2026/03/20)
- Emergancy update to fix the bootloop

## 1.6.1.0062 (2026/03/19)
Update victor to `9bcf11e4e4c982126a6512c845b01a6989df8518`:
- Fix day of week, increase the chance of performances when leaving charger.
- Make update-engine-rebuild emulate the original auto update implementation.

## 1.6.1.0061 (2026/03/16)
Update victor to `203dbad471b7ef2de4f5f1a2962fc9cf78400e1a`.
- Add performance profile changing to CCIS.
- Add auto update toggle to CCIS.
- Add day of week to date voice command.
- Localize date behavior.
- Fix BLE text position on Vector 1.0.
- Custom backpack lights in the same way as I implemented into WireOS.
- Add ability for DTTB to randomize eye color when dancing using a toggle in CCIS.

## 1.6.1.0060 (2026/03/05)
Emergency patch:
- Update victor to `52c9f0f28f5d25178a4ba16506b45118fe128c33`.
- ACTUALLY FIX COLON.
- Fix `/data/data/rebuild/` not being created.
- point name vc to new path.

## 1.6.1.0059 (2026/03/05)
Update victor to `ce34cbce3fccbef129296dbc89349a2e84b9ae0f`, Vector can have his ssh key downloaded from logs again, fix `/` in date intent showing up as `:`, new go-to-sleep and low battery animations, mic info CCIS screen now shows the correct circle size on Vector 2.0, add option to toggle WireOS lights in CCIS, add a new `CONFIGURATION` screen to CCIS, add reboot to recovery screen in CCIS, move rebuild-specific stuff to `/data/data/rebuild/` from `/data/data/`.

## 1.6.1.0058 (2026/02/26)
Update victor to `41ab2cb9847bff833212f6be6943593a81550f54`, can now ask Vector `What's the date` and Vector will give you the date, bit rushed but it'll prolly be fiine.

## 1.6.1.0057 (2026/02/23)
Update victor to `287a5d0dcf1b187afb418919cc71af4eaec5b55f`, pure green bootup backpack lights, opencv has compiler optimizations now to speed things up, scanlines work, old onboarding wakeup anim, a much better Rebuild Eyes implementation for keeping eye color through reboots [here](https://github.com/Victor-Rebuild/victor-1.6-rebuild-2/commit/ef89b337970e3729f36906667c4a62bed321c09b).

## 1.6.1.0056 (2026/02/21)
Update victor to `258e4c699c713246d78dbd2e478106037333b6d8`, make performances happen more again, port true evil bump from Viccyware, bump max photos to 300 photos, show a animation if photo storage is full, fix timer cancel countdown on Vector 2.0. Update vic-verbose: Remove random lights, make init faster, set lights to green while logging, make em blue when starting processes, remove unneeded date string.

## 1.6.1.0055 (2026/02/19)
Update victor to `064e3f748430e1a8c68f2e88e2de64ae14e263d1`, make rebuild eyes persist colors through reboots.

## 1.6.1.0054 (2026/02/17)
Update victor to `8354726adbb1e00f5d067fabc223c837cbffc8f2`, more clear pairing screen.

## 1.6.1.0053 (2026/02/16)
Update victor to `fe0b958215ef3c3002447016250ae1af048c7423`, skip body overheat check on Vector 2.0, restart chrony when Vector connects to wifi, fix 914 when telling Vector to explore.

## 1.6.1.0052 (2026/02/14)
Switch to victor-1.6 public, update to commit `eca0a2ed1c7fd479855c589cb7948afddc9526f7`. Implement the oneoff charger docking animations to decrease the chances of loosepixel or binaryeyes when leaving charger in a way similar to how anki would have done it, allow more range when running over a object, changes to the age finding system: First try to get the age from `/data/persist`, if the age from `/data/persist` is older than 2016 fall back to the onboarding state file, if that's still older than 2016 rely on `onboardingState.json`, and if it doesn't exist just use the stats tracker. Rebuild (XMB) eyes uses less system resources as it now refreshes every 3/4ths of a second instead of every 1/2 of a second, upgrade mpg123 library, restore pet detection timing to 6 events, much more clearer pairing screen.

## 1.6.1.0051 (2026/02/10)
Update victor-1.6(-private) to `e2f8fc20162af484a724392ec9edeb385fb9fc74`, lessen screen tearing on 2.0, make pet detection trigger less, fix petting lights from showing up when they aren't supposed to, put held in palm in webViz, fix video in 8890, use 1.6 syscon firmware for better compatibility.

## 1.6.1.0050 (2026/02/04)
Restart victor-1.6, all previous features have remained intact, repo still private. Vector runs at 60fps now, saturaton on 2.0 is more accurate to 1.0, set vc timing back to 1.5's timing, stop tracks from moving when unexpected, port 1.7's held on palm edge reactions, more sensitive cliff detection, fix explore vc being ignored, better scale robot name and pin for 1.0 and 2.0.

## 1.6.1.0049 (2026/01/24)
Update victor to `46259d0c5e1a9d38f5cfebbdb32732d4346fd378`, just a tiny little hack to "fix" put down 914"

## 1.6.1.0048 (2026/01/24)
Update victor to `d39ee530283e6b419db7c248ef1dfb961b8baf54`, update opencv, adjust the rebuild eyes schedule to be almost matching with the PS3.

## 1.6.1.0047 (2026/01/23)
Update victor to `ed6ac69b0e2b68505a5b59a34cdc59667488f47a`, add rebuild eyes as the new eye color, rainbow eyes voice command, custom eye color now plays the transition animation, timer works up to 1 day now, you can see what server Vector is connected to for voice commands within ccis, vic-cloud is now built instead of copied in.

## 1.6.1.0046 (2026/01/18)
Update victor to `efc92b1ce8771befcb326fe44ae349083c3a42e4`, remove denoising function.

## 1.6.1.0045 (2026/01/17)
Update victor to `fa16d8816d27524bad9703dfc277ceecedefae84`, add PurplPKG, add gamma correction, add Wire's 2.0 cam fixes.

## 1.6.1.0044 (2026/01/16)
Update victor to `3ecd4f59f347dae89ec5642f2baca0d05b8a6a73`, finish multilanguage support, now french, german, and japanese have proper translated strings, albeit google translated. OpenCV updated to `6950bedb5ce1827bc025bea7c1b23df6e947a437`.

## 1.6.1.0043 (2026/01/13)
Update victor to `2119d31c9a034ccdeb91e8d63d29ed66ae358a56`, fix botname not showing full name, more 914s killed, new wired interface from WireOS, fix multilanguage support.

## 1.6.1.0042 (2026/01/11)
Update victor to `efc6fdd96204e7f19ff0d89b9a91b1c85f385e8e`, fix more 914 agaiiiin.

## 1.6.1.0041 (2026/01/06)
Update victor to `a174420402e561c6250fbf01e9d59559f65e4eac`, fix more 914 errors, new charger leaving loosepixel animation, make Vector play more and go to charger less, mainline OpenCV, indev builds now have vic-verbose for the boot anim.

## 1.6.1.0040 (2026/01/03)
Update victor to `5561c89c85a1ddede69e4cb735965b36e20f4076`, update OpenCV to 4.13, make backtraces work, add pet detection, prevent log spam from body tracks being locked.

## 1.6.1.0039 (2026/01/02)
Update victor to `326780cc7341344b8161993dd8b6a75beabe33a2`, fix blackjack and weather positions on Vector 2.0, make crashes reboot faster, 2.0 can now show low battery / overheated battery images correctly, ANKI_VERIFY won't kill the bot with 914 anymore, restore unused holiday lights anim.

## 1.6.1.0038 (2025/12/30)
Update victor to `13491153f40c922b85a8df5ceced9af4b09e9c35`, add wp detection logic to select the correct link. This WILL be the real 1.6.1.3.

## 1.6.1.0037 (2025/12/30)
Update victor to `ac1c77e7affae8e815cf1ee3e3c29e87b28ff0c6`, extremely fast knowledge graph, add system slot switch option to ccis, fix error 914, fix mirrormode, identical to release 1.6.1.3

## 1.6.1.0036 (2025/12/26)
Update victor to `ce361379d862afa70c34f09c902ac71d34f87af5`, new onboarding animation.

## 1.6.1.0035 (2025/12/25)
Christmas update! Update victor to `ca5e652b69472d22e3a4e8acd55a5c709ca92694`, add Bot Naming in :8080, you can ask Vector "What's your name" and Vector will say whatever nickname you set, Vector 2.0 no longer gets overclocked when weather or blackjack happens, fix weather crashes that seem to happen whenever weather is in the negatives, change kernel name in neofetch, update all submodules.

## 1.6.1.0034 (2025/12/19)
Update Victor to `0472bc1c3b4d011dbb149cf432c906045ef71eb2`, Reonboarding clears wirepod server status, full mute/unmute animation plays for mics, 2.0 now has the correct screen pixel count, vcs should work better since mics are more sensitive now, fix update engine weirdness.

## 1.6.1.0033 (2025/12/16)
Fix nightly reboots waking up instead of starting asleep. Identical to release.

## 1.6.1.0032 (2025/12/10)
Release today, add reonboard option, update victor-1.6 to f0ba9987427026ab1a765346b86315d7f1b5c867

## 1.6.1.0031 (2025/12/09)
Release tommorow, change rampost to show the new website

## 1.6.1.0030 (2025/12/06)
Updated submodules for bitbake, openembedded-core, and meta-openembedded.

## 1.6.1.0029 (2025/12/06)
Upgrade victor-1.6 to `ca9d49bbc1a0a418d8b63531df32eb09e674a9db`, new custom server environment up at https://anki2.ca/1.6/, new concheck endpoint to not stress froggitti's server, slightly faster build time.

## 1.6.1.0028 (2025/12/05)
Fix build id again

## 1.6.1.0027 (2025/12/03)
Set prod build id correctly to fix auto updates

## 1.6.1.0026 (2025/12/03)
FULL build system refactor, compile victor-1.6 within oelinux, refactor `update-engine-rebuild` a bit, huge ota size drop.

## 1.6.1.0025 (2025/12/02)
Update victor-1.6 to c6bf8681b9e9a07fdc37c4beb04b5b844ee83e48, rename `rebuild-update-unengine` to `update-engine-rebuild` add oskr and prod cloudless builds, add auto update urls for cloudless, add downgrade support to `rebuild-update-engine`, add emergancy force install flag just in case.

## 1.6.1.0024 (2025/11/26)
Update victor-1.6 to 5c17cea29bffd02c170add60c4e1baca890060d2, adjust timing of success/fail sound effect, fix nightly reboots staying awake.

## 1.6.1.0023 (2025/11/20)
Update victor-1.6 to 6d8c2e5c3a29ad8fd49a1e793f79ff60c4b13ea2, add snowglobe animation since it snowed here, remove now obsolete wired freqchange methods, restore frequency to what it was before instead of defaulting to balanced, tighten button press window, make crashs reboot faster.

## 1.6.1.0022 (2025/11/09)
Update victor-1.6 to 97e0c05353e8302891a4174173a266ae1555a9f1, fix authing with servers, better 2.0 eyes, correct wired typo.

## 1.6.1.0021 (2025/11/03)
Fix btop warning, hardcode neofetch ascii art, useful command aliases, add vim-tiny.

## 1.6.1.0020 (2025/10/25)
I hate myself and rebooter

## 1.6.1.0019 (2025/10/24)
Rebooter works, make it only activate if uptime is over a hour.

## 1.6.1.0018 (2025/10/24)
Can rebooter just work?

## 1.6.1.0017 (2025/10/23)
Ugh rebooter...

## 1.6.1.0016 (2025/10/23)
Actually actually "fix" rebooter, update victor to b21be4d18ea34519e0653509ec44a42380c7edbc which allows Vector to count age in years, add "wire_os" to build.prop so wp doesn't swap out vic-cloud.

## 1.6.1.0015 (2025/10/18)
Actually fix rebooter

## 1.6.1.0014 (2025/10/15)
Fix rebooter, update to victor commit ed60b0d96132bb5980e980783f023c2328a2562e, fix blackjack dealer tts, add user customizable backpack lights

## 1.6.1.0013 (2025/09/18)
Uncan prod builds, update victor to 0b916a6fe7291a1dae66cc7d371c174952066532.

## 1.6.1.0012 (2025/09/17)
Prod builds are canned, actually add the auto update stuff, nothing else right now.

## 1.6.1.0011 (2025/09/14), hotpatch
Add auto updates back in, fix wired user prefs tab by updating vic-cloud and removing gateway (Victor bumped to 0b73d0dfd0a8f18047db6cfd7f96f7be25220650).

## 1.6.1.0011 (2025/09/14)
Remove python, add rainbow rampost lights back, C++ update engine and rewritten rebooter, put toastito's bot-specific ramposts back in, add prodperf build option so proddev builds work right and we can still make user builds, make the rampost error images point to `error.vicw.xyz` instead of the now dead `support.anki.com`.

## 1.6.1.0010 (2025/09/13)
First yocto ota, remove 1.6-specific customization temporarily, temp remove auto update implementation, no need to auth to change wifi networks, re-enable alexa, change faultcodehandler time limits, remove blackjack requests.

## 1.6.1.0009 (2025/09/01)
Dev only, change 1.6 settings to 1.6-rebuild settings, add face overlays, add Falling and Space Daydream animations, mm-anki-camera always trys to target 30 fps now, brand new auto update system rerwitten from scratch.

## 1.6.1.0008 (2025/08/20)
Wired broke due to it calling for /usr/bin/sleep and not /bin/sleep, this ota is just a fix for that

## 1.6.1.0007 (2025/08/20)
Manully cleaned update-os for this build, nothing else.

## 1.6.1.0006 (2025/08/20 (Actually 2025/08/19 but it's like 11:45pm and I really don't wanna build any otas right now))
Use new rampost boot images made by Toastito in V&F, make /data executable by default, make update-os up the cpu speeds and stop anki processes remove sb_server since we use picovoice now, port over wireutils from wireOS, re-enable HMP, cleaned kernel.

## 1.6.1.0005 (2025/08/19)
Don't copy in prebuilt ramposts and modules, use the one made with the ota, remove unneeded stuff from dvcbs-reloaded to hopefully cut down repo size a little, fix dynamic cpu speed on Vector 2.0 by updating Victor commit to [dd358480a177c6fa6d9a78dcd18a51900b806bb4](https://github.com/Switch-modder/victor-1.6-rebuild/commit/dd358480a177c6fa6d9a78dcd18a51900b806bb4).

## 1.6.1.0004 (2025/08/19)
Actually make the new different ramposts apply, don't clean anki every rebuild since cmake should be able to figure out what it needs to recompile should it have to happen.

## 1.6.1.0003 (2025/08/18)
Add a seperate proddev bitbake option, use different ramposts to confirm that we can have build specific ramposts.

## 1.6.1.0002 (2025/08/18)
Fixed the prod boot images so that they boot again, add new 1.6-rebuild rampost images.

## 1.6.1.0001 (2025/08/18)
Wired fully works, PicoVoice wakeword training works, changed OSKR messages to ankidevunit.

## 1.6.1.0000 (2025/08/16)
Dev only, first ota run, basically plain vicos-oelinux-nosign but with 1.6 anki.
