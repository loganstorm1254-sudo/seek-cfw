**LIFE OS 5.0.0.11d** — fixes fault **800** bootloop from 5.0.0.10d.

- **10d** injected a 4th CCIS menu item into `vic-anim` and crashed anim on boot (800).
- **11d** removes that code-cave. Menu is safe again: **EX** / **SONGS** / **CLR**.
- Confirm **SONGS** (lift) → playlist (face `/dev/fb0` + audio).
- **CLR** still wipes. Self-test is not on the main list in this recovery build.

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v5.0.0.11d-life/vicos-5.0.0.11d.ota
```

If stuck in 800 bootloop and `update-os` will not run, use recovery / `ota-start` with the same URL.

Dev-signed unlocked Vector only. Do not install 5.0.0.2d or 5.0.0.10d.
