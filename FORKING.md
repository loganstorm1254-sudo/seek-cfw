# Forking 1.6-rebuild (manual — cloud agent cannot create GitHub forks)

This tree is a **1:1 remake** of [Victor-Rebuild/vicos-oelinux-1.6-rebuild-2](https://github.com/Victor-Rebuild/vicos-oelinux-1.6-rebuild-2) with only error-prevention changes under `poky/victor/meta-anki/recipes/update-os/` and `seek/flash/`.

The GitHub token for this agent **cannot** create forks or new repos. Do this once in a browser while logged into `loganstorm1254-sudo`:

## Fork these (recommended names)

| Upstream | Fork as |
| --- | --- |
| https://github.com/Victor-Rebuild/vicos-oelinux-1.6-rebuild-2 | already mirrored here as `seek-cfw` |
| https://github.com/Victor-Rebuild/victor-1.6-rebuild-2 | `seek-cfw-victor` (or `storm-os-victor` retargeted) |
| https://github.com/Victor-Rebuild/victor-1.6-rebuild-externals | `seek-cfw-externals` |
| https://github.com/Victor-Rebuild/wire_d-1.6-rebuild-2 | `seek-cfw-wired` |
| https://github.com/Victor-Rebuild/vic-cloudswitch (branch `1.6-rebuild`) | optional |
| https://github.com/Victor-Rebuild/vic-verbose | optional |

## After forking, retarget submodules

```bash
cd seek-cfw
git submodule set-url anki/victor-1.6 https://github.com/loganstorm1254-sudo/seek-cfw-victor
git submodule set-url anki/wired https://github.com/loganstorm1254-sudo/seek-cfw-wired
# then in the victor fork:
cd anki/victor-1.6
git submodule set-url EXTERNALS https://github.com/loganstorm1254-sudo/seek-cfw-externals
```

Until you fork, builds still work against the **Victor-Rebuild** upstream URLs already in `.gitmodules`.

## Credit

1.6-rebuild is by Switch-modder / Emily / Raj-jyot (Victor-Rebuild). Keep upstream attribution.
