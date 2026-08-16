# SeekOS 3.0.1.65d

Build with: `./build/build.sh -bt devcloudless -v 65 …`

## Changes vs 64d

### Cloudless voice
- Local stock intents win over Oval/Houndify/OpenAI (no more AI stealing “how old are you”, explore, play, etc.)
- Softer VAD / longer endpointer — fewer cut-off listen turns

### Table / cliff safety (closer to classic 1.0 Vector)
- Re-enable `CLAMP_TO_CLIFF_SAFE_SPEEDS` on path following
- Explore speed 120 → 80 mm/s (more stop margin at unknown edges)

### update-os
- Always create `/data/keep-update-os` so `update-os` survives OTAs and Seek dashboard updates
- `install-seek.sh` / `update-seek.sh` honor keep flag

Full build still includes Doom, Vosk, sounds, wrap v11, everything.
