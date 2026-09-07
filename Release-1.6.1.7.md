# Info about release 1.6.1.7

## What happened?
1.6-rebuild was becoming extremely unstable past 1.6.1.6. So with indev 1.6.1.0050 I completely restarted development of 1.6-rebuild from just plain 1.6. And from there I slowly added the rebuild features back to it and it's finally stable again now.

## Why'd it get to that point in the first place
Truth be told I never wanted it to get to that point. What essentially happened was that I started to focus too much on pumping out features that I ended up forgetting about keeping it stable. From indev 1.6.1.0050 and onwards I've been adding features, but while adding them I've also been improving them constantly at the same time. And they're now always at the very least functional so they don't cause errors before they go into otas.

## Will rebuild ever get to that point again
I hope it doesn't, these last 3 months have been spent fully rebuilding all my work from the ground up in the most stable way it can be, I hope it can remain stable now so we don't have a update drought again. Either way, I'm 1 person working on this, I can't say anything with 100% certainty and I'm really sorry for that. Anyways, lets get down to the changelogs.

## Changelogs
### These changelogs include over 25 indev builds which were in and of themselved absolutely packed with content. You can see those builds themselves in [ota-build-changelogs-indev.md](./ota-build-changelogs-indev.md) starting from 1.6.1.0047 to 1.6.1.0069. The below is a condensed version.

Victor side changes:
- New repository: [https://github.com/Victor-Rebuild/victor-1.6-rebuild-2](https://github.com/Victor-Rebuild/victor-1.6-rebuild-2).
- Victor is at commit `492063e0f2b2489cc8c1b95d67504acb4e48baec`.
- Rebuild Eyes! New eye color that matches the PS3 home screen colors. and can be set by asking Vector to change eye color to `Cross Media Bar`
- Custom eye color now plays the transition animation.
- Timer works up to 24 hours.
- You can see what Voice Command server Vector is using within the CCIS screen now.
- 914s almost fully fixed.
- Colors on Vector 2.0 are more saturated now and no longer look washed out.
- Voice Command audio timing is now 1.5's again.
- Vector runs at 60fps now which makes it a much smoother experience.
- Stop tracks from moving when unexpected.
- Backport 1.7's held in palm reactions.
- More sensitive cliff detection.
- Fix explore voice command getting ignored.
- More pitch range for when Vector is moving over a object.
- New pairing screen.
- Restart crony when Vector gets on wifi.
- Evil bump ported from Viccyware.
- Redo of the age finding system (Specifics at the end).
- Max photo storage bumped from 10 to 300 photos.
- Show short animation if photo storage is full.
- Fix timer cancel countdown on Vector 2.0.
- Old onboarding wakeup animation from 1.0.0 has been readded.
- Can now ask Vector `What is the date` (Rebuild vc server only).
- Add reboot to recovery screen to CCIS.
- Can toggle WireOS's lights from CCIS.
- Vector's ssh key can be downloaded from logs once again.
- New `CONFIGURATION` option in CCIS
- Add performance profile changing to CCIS.
- Add auto update toggle to CCIS.
- Custom backpack lights in the same way as I implemented into WireOS.
- Add ability for DTTB to randomize eye color when dancing using a toggle in CCIS.
- Blackjack now gives Vector more autonomy by allowing him to play on/off the charger depending on how he feels, if Vector wants to stay on the charger we skip looking for faces, no need for it since we're on the charger, if Vector wants to leave normal flow will happen (Leave --> Search for faces --> Play blackjack).
- A Bunch of unused animations for wheelstands were reimplemented. 
- Reacttohand is more forgiving on the angle Vector is at.
- New image for when Vector can't calibrate his gyro.
- Different animation for hooking Vector up to wirepod.
- SSID won't show on the main CCIS screen if Vector has a set name.
- Add toggle for 60 or 30 fps to the CCIS config menu.
- Beta alexa has been restored and can also be enabled in the CCIS config menu.
- Have update-engine-rebuild do a random delay of up to a hour so my server doesn't hurt when every Vector hits the update server at once.
- Can now disable or enable snoring at night within the CCIS config menu.
- Fix spine-select error (898) ([Anki commit](https://github.com/Victor-Rebuild/victor-1.6-rebuild-2/commit/f570a7dc580bb50dcb7ff413c36da4053b7c1192))
- More accurate weather conditions (1.6-rebuild VC server only)
- More range for held in palm
- Can now mute volume, rebuild servers only. (Hey Vector, Volume Mute)
- Reenable older 1.4 reacttohand animations
- Fix config submenu not defaulting to page 1.
- Restore Anki's text spacing for CCIS screen 2. (network)
- Change conncheck address to the real conncheck.
- Custom preset eye color support. (copy `/anki/data/assets/cozmo_resources/config/engine/eye_color_config.json` to `/data/data/rebuild/eye_color_config.json` and make your changes)

<details>
<summary>The redo of the age finding system:</summary>
First try to get the age from `/data/persist`, if the age from `/data/persist` is older than 2016 fall back to the onboarding state file, if that's still older than 2016 rely on `onboardingState.json`, and if it doesn't exist just use the stats tracker.
</details>
