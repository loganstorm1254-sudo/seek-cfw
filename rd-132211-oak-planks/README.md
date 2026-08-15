# rd-132211 oak planks mod

Personal patch for Minecraft pre-Classic **rd-132211**.

## Changes

1. **Removed height-based revert** — blocks no longer look like grass/stone based on Y.
2. **Oak planks** — left-click place at **one block above the grass layer** (`Y = 43`) places oak planks.
3. Other placements are rock. Legacy saves migrate once on load.

## Download

- [minecraft-rd-132211-client-oakplanks.jar](./minecraft-rd-132211-client-oakplanks.jar)
- SHA1: `e3524029afa856c4a5a17006ee6b23da0703b9f8`

## Install so Prism does NOT revert it

Prism re-downloads libraries when the SHA1 does not match. If you only replace the jar, the next launch restores vanilla — and blocks above grass look like **stone/cobble** again.

1. **Quit Prism completely** (check the tray; it must not be running).
2. Replace this file with the modded jar, **keeping the exact name**:
   ```
   %AppData%\Roaming\PrismLauncher\libraries\com\mojang\minecraft\rd-132211\minecraft-rd-132211-client.jar
   ```
3. In that same folder, create/overwrite `minecraft-rd-132211-client.jar.sha1` with one line:
   ```
   e3524029afa856c4a5a17006ee6b23da0703b9f8
   ```
4. Search under `%AppData%\Roaming\PrismLauncher\meta\` for `rd-132211` / `minecraft-rd-132211-client` and update any `sha1` for that jar to the value above.
5. Mark the jar **read-only** so Prism cannot overwrite it:
   - Right-click jar → Properties → Read-only → OK  
   - Or in PowerShell:
     ```powershell
     attrib +R "$env:APPDATA\Roaming\PrismLauncher\libraries\com\mojang\minecraft\rd-132211\minecraft-rd-132211-client.jar"
     ```
6. Launch the instance (offline is safest the first time).

### Confirm the mod is actually loaded

Before/after launch, the jar SHA1 must stay:

```powershell
Get-FileHash "$env:APPDATA\Roaming\PrismLauncher\libraries\com\mojang\minecraft\rd-132211\minecraft-rd-132211-client.jar" -Algorithm SHA1
```

Expected: `E3524029AFA856C4A5A17006EE6B23DA0703B9F8`

If it changed back, Prism restored vanilla — repeat steps 1–5.

### In-game check

- Place on the **top of grass** (one block up): should be **oak planks** (brown wood), not gray stone.
- Place elsewhere: rock/stone, and it should **stay** that look (no height revert).

## Controls (unchanged)

- Left click: place
- Right click: break
- Enter: save `level.dat`
