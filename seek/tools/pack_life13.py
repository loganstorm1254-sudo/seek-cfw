#!/usr/bin/env python3
"""Pack LIFE OS 5.0.0.13d: stop fault-800 — remove SONGS code-cave entirely.

12d still crashed vic-anim (fault 800) despite std::string + Thumb B.W fixes.
13d restores stock Init (no hook/cave) and stock EXIT / SELF TEST / CLEAR.
SONGS is opened from CCIS Main via backpack → Network(10) hijack (no 4th AppendMenuItem).
"""
from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
from pathlib import Path

REPO = Path("/workspace")
WORK = Path("/tmp/life-ota")
SYS = WORK / "sys.img"
BOOT_IMG = WORK / "apq8009-robot-boot.img"
STOCK_ANIM = WORK / "vic-anim.bin"
PIGZ = REPO / "ota" / "pigz" / "amd64" / "pigz"
PASS = REPO / "ota" / "ota_test.pass"
OTA_VERSION = "5.0.0.13d"

BOOT_ANIM = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim.raw"
BOOT_ANIM20 = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim_20.raw"
UPDATE_OS = REPO / "seek/overlays/usr/sbin/update-os"
LIFE_SONGS = REPO / "seek/overlays/usr/bin/life-songs"
LIFE_WATCH = REPO / "seek/overlays/usr/bin/life-songs-watch"
ANIM_SVC = REPO / "seek/overlays/lib/systemd/system/vic-anim.service"
WATCH_SVC = REPO / "seek/overlays/lib/systemd/system/life-songs-watch.service"
SONG_DIR = REPO / "seek/overlays/anki/data/life-songs"
SONGS = ("muffin", "survive", "ordinary", "neveralone")

LABEL_START = 0x30A3B3
LABEL_END = 0x30A3ED
HOOK_AT = 0x5B8C2
HOOK_ORIG = bytes.fromhex("082094a9")
CAVE = 0x365740
ITEM2_MOV_R2 = 0x5B85C


def run(cmd, **kw):
    print("+", " ".join(map(str, cmd)))
    subprocess.check_call(cmd, **kw)


def debugfs_f(script: str) -> str:
    cmdf = WORK / "debugfs13.cmd"
    cmdf.write_text(script if script.endswith("\n") else script + "\n")
    r = subprocess.run(
        ["debugfs", "-w", "-f", str(cmdf), str(SYS)],
        capture_output=True,
        text=True,
    )
    out = (r.stdout or "") + (r.stderr or "")
    print(out[-2000:])
    if r.returncode != 0:
        raise SystemExit(f"debugfs failed: {r.returncode}")
    return out


def sif(path, field, value):
    subprocess.run(
        ["debugfs", "-w", str(SYS)],
        input=f"sif {path} {field} {value}\nquit\n",
        text=True,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def sha256_file(path: Path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(8 * 1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return path.stat().st_size, h.hexdigest()


def patch_vic_anim(anim: bytearray) -> bytearray:
    if not STOCK_ANIM.is_file():
        raise SystemExit(f"missing stock anim {STOCK_ANIM}")
    stock = STOCK_ANIM.read_bytes()

    # Restore any rewritten titles
    for old, new in (
        (b"PLAY SONGS?     \x00", b"START SELF TEST?\x00"),
        (b"SONGS - LIFT OUT\x00", b"START SELF TEST?\x00"),
    ):
        if old in anim:
            anim = bytearray(anim.replace(old, new, 1))

    # Full stock labels: EXIT / TEST / SELF TEST / CLEAR / CLEAR OUT SOUL
    anim[LABEL_START:LABEL_END] = stock[LABEL_START:LABEL_END]

    # Undo 10d/12d hook
    if anim[HOOK_AT : HOOK_AT + 4] != HOOK_ORIG:
        print(f"restoring Init hook {anim[HOOK_AT:HOOK_AT+4].hex()} → {HOOK_ORIG.hex()}")
        anim[HOOK_AT : HOOK_AT + 4] = HOOK_ORIG

    # Wipe any code cave
    if any(anim[CAVE : CAVE + 128]):
        print("clearing SONGS code cave")
        anim[CAVE : CAVE + 256] = bytes(256)

    # TEST → SelfTest(8)
    if anim[ITEM2_MOV_R2 : ITEM2_MOV_R2 + 2] != b"\x08\x22":
        anim[ITEM2_MOV_R2 : ITEM2_MOV_R2 + 2] = b"\x08\x22"
        print("restored item2 destination SelfTest(8)")

    if anim[HOOK_AT : HOOK_AT + 4] != HOOK_ORIG:
        raise SystemExit("hook restore failed")
    if any(anim[CAVE : CAVE + 64]):
        raise SystemExit("cave not cleared")
    if anim[0x30A3C4 : 0x30A3C4 + 4] != b"EXIT":
        raise SystemExit("EXIT missing")
    if anim[0x30A3CE : 0x30A3CE + 9] != b"SELF TEST":
        raise SystemExit("SELF TEST missing")
    if anim[0x30A3D8 : 0x30A3D8 + 5] != b"CLEAR":
        raise SystemExit("CLEAR missing")
    if not anim[0x30A3DE : 0x30A3DE + 14].startswith(b"CLEAR OUT SOUL"):
        raise SystemExit("CLEAR OUT SOUL missing")
    if b"START SELF TEST?\x00" not in anim[LABEL_START : LABEL_START + 20]:
        raise SystemExit("START SELF TEST? missing")

    print("vic-anim: stock menu only (no SONGS cave) — fault-800 safe")
    return anim


def main() -> None:
    if not SYS.is_file() or not BOOT_IMG.is_file():
        raise SystemExit("missing /tmp/life-ota/{sys.img,apq8009-robot-boot.img}")
    for p in (BOOT_ANIM, BOOT_ANIM20, UPDATE_OS, LIFE_SONGS, LIFE_WATCH, ANIM_SVC, WATCH_SVC, STOCK_ANIM):
        if not p.is_file():
            raise SystemExit(f"missing {p}")
    watch = LIFE_WATCH.read_text()
    if "python" in watch.splitlines()[0]:
        raise SystemExit("life-songs-watch must be shell")
    if "SONGS_SCREEN=10" not in watch:
        raise SystemExit("watcher must hijack Network (10) for backpack songs")

    inj = WORK / "inject13"
    if inj.exists():
        shutil.rmtree(inj)
    inj.mkdir()
    (inj / "menu").mkdir()

    shutil.copy2(BOOT_ANIM, inj / "boot_anim.raw")
    shutil.copy2(BOOT_ANIM20, inj / "boot_anim_20.raw")
    shutil.copy2(UPDATE_OS, inj / "update-os")
    os.chmod(inj / "update-os", 0o755)
    shutil.copy2(LIFE_SONGS, inj / "life-songs")
    os.chmod(inj / "life-songs", 0o755)
    shutil.copy2(LIFE_WATCH, inj / "life-songs-watch")
    os.chmod(inj / "life-songs-watch", 0o755)
    shutil.copy2(ANIM_SVC, inj / "vic-anim.service")
    shutil.copy2(WATCH_SVC, inj / "life-songs-watch.service")
    for name in SONGS:
        shutil.copy2(SONG_DIR / f"{name}.raw", inj / f"{name}.raw")
        shutil.copy2(SONG_DIR / f"{name}.wav", inj / f"{name}.wav")
        shutil.copy2(SONG_DIR / "menu" / f"{name}.raw", inj / "menu" / f"{name}.raw")
        play = SONG_DIR / "menu" / f"playing-{name}.raw"
        if play.is_file():
            shutil.copy2(play, inj / "menu" / f"playing-{name}.raw")
    for extra in ("title.raw", "exit.raw"):
        src = SONG_DIR / "menu" / extra
        if src.is_file():
            shutil.copy2(src, inj / "menu" / extra)

    (inj / "os-version").write_text(f"{OTA_VERSION}\n")
    (inj / "os-version-code").write_text("13\n")

    run(["debugfs", "-R", f"dump /build.prop {inj / 'build.prop'}", str(SYS)])
    bp = (inj / "build.prop").read_text()
    for a, b in (
        ("5.0.0.12d", OTA_VERSION),
        ("5.0.0.11d", OTA_VERSION),
        ("5.0.0.10d", OTA_VERSION),
        ("5.0.0.9d", OTA_VERSION),
        ("ro.build.version.incremental=12\n", "ro.build.version.incremental=13\n"),
        ("ro.build.version.incremental=11\n", "ro.build.version.incremental=13\n"),
        ("ro.build.version.incremental=10\n", "ro.build.version.incremental=13\n"),
        ("ro.build.version.incremental=9\n", "ro.build.version.incremental=13\n"),
    ):
        bp = bp.replace(a, b)
    if OTA_VERSION not in bp:
        raise SystemExit("build.prop version bump failed:\n" + bp)
    (inj / "build.prop").write_text(bp)

    run(["debugfs", "-R", f"dump /anki/bin/vic-anim {inj / 'vic-anim'}", str(SYS)])
    anim = patch_vic_anim(bytearray((inj / "vic-anim").read_bytes()))
    (inj / "vic-anim").write_bytes(anim)

    boot_path = "/anki/data/assets/cozmo_resources/config/engine/animations/boot_anim.raw"
    boot20_path = "/anki/data/assets/cozmo_resources/config/engine/animations/boot_anim_20.raw"
    songs_path = "/anki/data/assets/life-songs"

    lines = [
        f"rm {boot_path}",
        f"write {inj / 'boot_anim.raw'} {boot_path}",
        f"rm {boot20_path}",
        f"write {inj / 'boot_anim_20.raw'} {boot20_path}",
        "rm /usr/sbin/update-os",
        f"write {inj / 'update-os'} /usr/sbin/update-os",
        "rm /usr/bin/life-songs",
        f"write {inj / 'life-songs'} /usr/bin/life-songs",
        "rm /usr/bin/life-songs-watch",
        f"write {inj / 'life-songs-watch'} /usr/bin/life-songs-watch",
        "rm /lib/systemd/system/vic-anim.service",
        f"write {inj / 'vic-anim.service'} /lib/systemd/system/vic-anim.service",
        "rm /lib/systemd/system/life-songs-watch.service",
        f"write {inj / 'life-songs-watch.service'} /lib/systemd/system/life-songs-watch.service",
        "rm /anki/bin/vic-anim",
        f"write {inj / 'vic-anim'} /anki/bin/vic-anim",
        "rm /etc/os-version",
        f"write {inj / 'os-version'} /etc/os-version",
        "rm /etc/os-version-code",
        f"write {inj / 'os-version-code'} /etc/os-version-code",
        "rm /build.prop",
        f"write {inj / 'build.prop'} /build.prop",
        "mkdir /anki/data/assets/life-songs",
        "mkdir /anki/data/assets/life-songs/menu",
    ]
    for name in SONGS:
        lines += [
            f"rm {songs_path}/{name}.raw",
            f"write {inj / (name + '.raw')} {songs_path}/{name}.raw",
            f"rm {songs_path}/{name}.wav",
            f"write {inj / (name + '.wav')} {songs_path}/{name}.wav",
            f"rm {songs_path}/menu/{name}.raw",
            f"write {inj / 'menu' / (name + '.raw')} {songs_path}/menu/{name}.raw",
        ]
        play = inj / "menu" / f"playing-{name}.raw"
        if play.is_file():
            lines += [
                f"rm {songs_path}/menu/playing-{name}.raw",
                f"write {play} {songs_path}/menu/playing-{name}.raw",
            ]
    for extra in ("title.raw", "exit.raw"):
        p = inj / "menu" / extra
        if p.is_file():
            lines += [
                f"rm {songs_path}/menu/{extra}",
                f"write {p} {songs_path}/menu/{extra}",
            ]
    lines += [
        "mkdir /lib/systemd/system/anki-robot.target.wants",
        "rm /lib/systemd/system/anki-robot.target.wants/life-songs-watch.service",
        "symlink /lib/systemd/system/life-songs-watch.service /lib/systemd/system/anki-robot.target.wants/life-songs-watch.service",
    ]
    debugfs_f("\n".join(lines))

    sif("/usr/sbin/update-os", "mode", "0100755")
    sif("/usr/bin/life-songs", "mode", "0100755")
    sif("/usr/bin/life-songs-watch", "mode", "0100755")
    sif("/lib/systemd/system/vic-anim.service", "mode", "0100644")
    sif("/lib/systemd/system/life-songs-watch.service", "mode", "0100644")
    sif("/anki/bin/vic-anim", "mode", "0100500")
    sif("/anki/bin/vic-anim", "uid", "2903")
    sif("/anki/bin/vic-anim", "gid", "2901")
    sif("/etc/os-version", "mode", "0100444")
    sif("/etc/os-version-code", "mode", "0100444")
    sif(boot_path, "mode", "0100444")
    sif(boot20_path, "mode", "0100444")

    run(["debugfs", "-R", f"dump /anki/bin/vic-anim {WORK / 'verify-vic-anim'}", str(SYS)])
    va = (WORK / "verify-vic-anim").read_bytes()
    if va[HOOK_AT : HOOK_AT + 4] != HOOK_ORIG:
        raise SystemExit("hook not restored — still bootloop risk")
    if any(va[CAVE : CAVE + 64]):
        raise SystemExit("cave still dirty")
    if va[0x30A3C4 : 0x30A3C4 + 4] != b"EXIT":
        raise SystemExit("EXIT missing")
    if va[0x30A3CE : 0x30A3CE + 9] != b"SELF TEST":
        raise SystemExit("SELF TEST missing")
    if va[ITEM2_MOV_R2 : ITEM2_MOV_R2 + 2] != b"\x08\x22":
        raise SystemExit("item2 must stay SelfTest(8)")
    run(["debugfs", "-R", f"dump /usr/bin/life-songs-watch {WORK / 'verify-watch'}", str(SYS)])
    vw = (WORK / "verify-watch").read_text()
    if "SONGS_SCREEN=10" not in vw:
        raise SystemExit("watcher must hijack Network (10)")
    if "MAIN_SCREEN=4" not in vw:
        raise SystemExit("watcher must arm on Main")

    sys_bytes, sys_sha = sha256_file(SYS)
    boot_bytes, boot_sha = sha256_file(BOOT_IMG)
    print("SYSTEM", sys_bytes, sys_sha)
    print("BOOT", boot_bytes, boot_sha)

    run([str(PIGZ), "--best", "--force", "--keep", str(SYS)])
    run(
        [
            "openssl", "aes-256-ctr",
            "-pass", f"file:{PASS}", "-md", "md5",
            "-in", str(WORK / "sys.img.gz"),
            "-out", str(WORK / "out-sys.img.gz"),
        ],
        stderr=subprocess.DEVNULL,
    )
    boot_gz = WORK / "apq8009-robot-boot.img.gz"
    if not boot_gz.is_file():
        run([str(PIGZ), "--best", "--force", "--keep", str(BOOT_IMG)])
    run(
        [
            "openssl", "aes-256-ctr",
            "-pass", f"file:{PASS}", "-md", "md5",
            "-in", str(boot_gz),
            "-out", str(WORK / "out-boot.img.gz"),
        ],
        stderr=subprocess.DEVNULL,
    )

    manifest = f"""[META]
manifest_version=1.0.0
update_version={OTA_VERSION}
ankidev=1
num_images=2
reboot_after_install=0
[BOOT]
encryption=1
delta=0
compression=gz
wbits=31
bytes={boot_bytes}
sha256={boot_sha}
[SYSTEM]
encryption=1
delta=0
compression=gz
wbits=31
bytes={sys_bytes}
sha256={sys_sha}
"""
    outdir = WORK / "tar13"
    if outdir.exists():
        shutil.rmtree(outdir)
    outdir.mkdir()
    (outdir / "manifest.ini").write_text(manifest)
    shutil.copy2(WORK / "out-boot.img.gz", outdir / "apq8009-robot-boot.img.gz")
    shutil.copy2(WORK / "out-sys.img.gz", outdir / "apq8009-robot-sysfs.img.gz")
    ota = WORK / f"vicos-{OTA_VERSION}.ota"
    if ota.exists():
        ota.unlink()
    run(
        [
            "tar", "-cf", str(ota),
            "--mode=0400", "--owner=root:0", "--group=root:0",
            "-C", str(outdir),
            "manifest.ini",
            "apq8009-robot-boot.img.gz",
            "apq8009-robot-sysfs.img.gz",
        ]
    )
    (WORK / "RELEASE-NOTES.md").write_text(
        f"""**LIFE OS {OTA_VERSION}** — stop fault **800** spam from 12d/10d.

- Removes the `vic-anim` SONGS code-cave again (binary 4th menu item still crashes anim).
- Restores stock CCIS: **EXIT** / **SELF TEST** / **CLEAR**.
- **SONGS**: on CCIS Main, press the **backpack** button (opens Network → playlist).

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v{OTA_VERSION}-life/vicos-{OTA_VERSION}.ota
```

If stuck in 800 and `update-os` will not run, use recovery / `ota-start` with the same URL.

Dev-signed unlocked Vector only. Do not install 5.0.0.10d or 5.0.0.12d.
"""
    )
    print("OTA", ota, ota.stat().st_size)


if __name__ == "__main__":
    main()
