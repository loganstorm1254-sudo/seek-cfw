# rd-132211 oak planks mod

## Download

- [minecraft-rd-132211-client-oakplanks.jar](./minecraft-rd-132211-client-oakplanks.jar)
- SHA1: `e3524029afa856c4a5a17006ee6b23da0703b9f8`
- Size: `24997` bytes

## Fix the “not writable” error

That happened because the jar was marked **read-only**. Undo that first:

```powershell
attrib -R "$env:APPDATA\Roaming\PrismLauncher\libraries\com\mojang\minecraft\rd-132211\minecraft-rd-132211-client.jar"
```

Do **not** use read-only. Pin the checksum instead (below).

## Install (Prism 11) — keeps the modded jar

1. Quit Prism completely.
2. Copy the modded jar over:
   ```
   %AppData%\Roaming\PrismLauncher\libraries\com\mojang\minecraft\rd-132211\minecraft-rd-132211-client.jar
   ```
   Keep that exact filename.
3. Edit this file in Notepad:
   ```
   %AppData%\Roaming\PrismLauncher\meta\net.minecraft\rd-132211.json
   ```
   Find `mainJar` → `downloads` → `artifact` and set:
   ```json
   "sha1": "e3524029afa856c4a5a17006ee6b23da0703b9f8",
   "size": 24997
   ```
   Remove the `"url"` line under that artifact (so Prism cannot re-fetch Mojang’s jar).
4. Start Prism and launch **offline** once to confirm.

### Confirm

```powershell
Get-FileHash "$env:APPDATA\Roaming\PrismLauncher\libraries\com\mojang\minecraft\rd-132211\minecraft-rd-132211-client.jar" -Algorithm SHA1
```

Must be `E3524029AFA856C4A5A17006EE6B23DA0703B9F8`.

If Prism refreshes meta and restores vanilla hashes, re-do step 3, or customize the instance version (Edit Instance → Version → Minecraft → Customize) and apply the same sha1/size/no-url edit there.

## In-game

- Place on **top of grass** → oak planks (brown).
- Place elsewhere → rock, and it should not “revert” by height.
