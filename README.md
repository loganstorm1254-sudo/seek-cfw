# Seek CFW — 1.6-rebuild (error-safe)

**1:1 remake** of [Victor-Rebuild 1.6-rebuild](https://github.com/Victor-Rebuild/vicos-oelinux-1.6-rebuild-2).

No Seek branding, boot splash, CCIS, or head-only changes. The only deltas are **error prevention** for OTA install:

| Problem | Fix |
| --- | --- |
| GitHub / SSL download fails (`CERTIFICATE_VERIFY_FAILED`, broken `curl.anki`) | `update-os` uses real `curl -k` → `/ota/v.ota` |
| Truncated OTA bricks flash | Reject OTA &lt; 200MB |
| Recovery flash marked wrong slot unbootable | Lock **other** slot only; `set_bootable` on target |
| Fault **920** `NO_GATEWAY_CERT` after OS switch | Auto-create `gateway.cert` before reboot |

Upstream personality lives in submodule `anki/victor-1.6` → [victor-1.6-rebuild-2](https://github.com/Victor-Rebuild/victor-1.6-rebuild-2).

See [FORKING.md](FORKING.md) to fork submodule repos under your account (agent cannot create GitHub forks).

## Install on robot now (no rebuild)

**Preferred (Windows CMD):** download the OTA on your PC, then upload + flash. Vector does **not** download from GitHub.

```cmd
curl -L -o %TEMP%\flash-16-from-pc.cmd https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/16-rebuild-errorsafe-7a4a/seek/flash/flash-16-from-pc.cmd
%TEMP%\flash-16-from-pc.cmd 192.168.42.111
```

Stay on charger. Takes several minutes (PC download + scp + flash), then Vector reboots.

That installs public **1.6-rebuild** `vicos-1.6.1.80d.ota (error-safe)` (~172MB, unlocked/dev).

Optional — flash from the robot itself (slower / flaky Wi‑Fi):

```sh
update-os latest
```

OSKR / locked-prod: pick the matching asset from [historical releases](https://github.com/Victor-Rebuild/1.6-rebuild-historical-releases/releases/tag/1.6.1.007X) and pass the URL:

```sh
update-os https://github.com/Victor-Rebuild/1.6-rebuild-historical-releases/releases/download/v1.6.1.80d-errorsafe/vicos-1.6.1.80doskr.ota
```

Fault 920 only:

```sh
sh /usr/sbin/fix-error-920
# or
curl -k -L -o /data/fix-920.sh https://raw.githubusercontent.com/loganstorm1254-sudo/seek-cfw/cursor/16-rebuild-errorsafe-7a4a/seek/flash/fix-error-920.sh
sh /data/fix-920.sh
```

After install, set up with the 1.6-rebuild server: https://anki2.ca/1.6/

## Build your own OTA (optional)

Same as upstream 1.6-rebuild:

```bash
git clone https://github.com/loganstorm1254-sudo/seek-cfw --recurse-submodules -b cursor/16-rebuild-errorsafe-7a4a
cd seek-cfw
./build/build.sh -bt dev -v 1
# output: ./_build/1.6.1.1.ota  (version scheme follows ANKI_VERSION=1.6.1)
```

## Upstream

- OS: [vicos-oelinux-1.6-rebuild-2](https://github.com/Victor-Rebuild/vicos-oelinux-1.6-rebuild-2)
- Personality: [victor-1.6-rebuild-2](https://github.com/Victor-Rebuild/victor-1.6-rebuild-2)
- Docs / install: https://anki2.ca/1.6-rebuild
