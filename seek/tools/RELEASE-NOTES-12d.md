**LIFE OS 5.0.0.12d** — restore CCIS buttons + real **SONGS** item.

- Restores stock **EXIT** / **SELF TEST** / **CLEAR** (11d had replaced TEST with SONGS).
- Adds a **4th SONGS** button. Fixes both 10d crash bugs: (1) builds a real `std::string` before `AppendMenuItem`, (2) uses Thumb `B.W` not `BLX` (BLX switched to ARM → fault **800**).
- Confirm **SONGS** → playlist. **SELF TEST** works again. **CLEAR** still wipes.

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v5.0.0.12d-life/vicos-5.0.0.12d.ota
```

Dev-signed unlocked Vector only. Do not install 5.0.0.2d or 5.0.0.10d.
