# Victor DVT2 (Seek CFW)

Reference: [Victor DVT2 on Vector Documentation](https://randym32.github.io/Anki.Vector.Documentation/historical-bots/Victor%20DVT2.html)

## What DVT2 is

Second Design Validation Test batch. **Embedded Linux** (not Android DVT1). Old **body board** with different electrical behavior; **head board** matches production Vector.

## What Seek does for DVT2

| Area | Behavior |
|------|----------|
| **ESN / serial** | Birth certificate ESN `0` → read `androidboot.serialno` from cmdline (8-char hex, e.g. `1f19f8b7`) |
| **CCIS Main** | Shows `HW: DVT2` when fake birth cert detected |
| **HAL body** | DVT2 touch + proximity paths when `ro.build.target=5`, syscon `DevBuild`, fake ESN, or `/data/seek/dvt2_body` |
| **Wi‑Fi boot** | `seek-wifi-boot` scans for legacy **AnkiRobits** SSID after normal autoconnect fails |
| **Boot splash** | Anki DVT proprietary rampost splash |
| **Pairing name** | `Victor-XXXX` display (Vector→Victor) |

## Legacy Wi‑Fi (AnkiRobits)

Many DVT2 units were provisioned for:

- **SSID:** `AnkiRobits`
- **Password:** `KlaatuBaradaNikto!`

Create a router or phone hotspot with those credentials so the robot can autoconnect (or use ADB over TCP on that LAN).

Disable DVT2 fallback scan: `touch /data/seek/skip-dvt2-wifi`

Force DVT2 body HAL quirks on a modern body: `touch /data/seek/dvt2_body` (only if you know you need old-board touch/prox handling).

## Modern firmware on DVT2 hardware

- A/B boot slots work (`bootctl-anki`, `update-os`).
- Shell / motors / laser are compatible with production Vector parts.
- Body board DFU is old; full body swap to modern boards is not viable — heads can be upgraded via QDL.

## DVT1 note

DVT1 units sometimes used **AnkiTest2** / `password` — not auto-scanned by Seek; provision via app or dash.
