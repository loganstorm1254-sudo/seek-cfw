#!/usr/bin/env python3
"""Pack LIFE OS 5.0.0.8d: remove SONGS item; backpack Main→songs; fb0 playback; backpack exits."""
from __future__ import annotations

import hashlib
import os
import shutil
import struct
import subprocess
from pathlib import Path

REPO = Path("/workspace")
WORK = Path("/tmp/life-ota")
SYS = WORK / "sys.img"
BOOT_IMG = WORK / "apq8009-robot-boot.img"
PIGZ = REPO / "ota" / "pigz" / "amd64" / "pigz"
PASS = REPO / "ota" / "ota_test.pass"
OTA_VERSION = "5.0.0.8d"

BOOT_ANIM = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim.raw"
BOOT_ANIM20 = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim_20.raw"
UPDATE_OS = REPO / "seek/overlays/usr/sbin/update-os"
LIFE_SONGS = REPO / "seek/overlays/usr/bin/life-songs"
LIFE_WATCH = REPO / "seek/overlays/usr/bin/life-songs-watch"
ANIM_SVC = REPO / "seek/overlays/lib/systemd/system/vic-anim.service"
WATCH_SVC = REPO / "seek/overlays/lib/systemd/system/life-songs-watch.service"
SONG_DIR = REPO / "seek/overlays/anki/data/life-songs"
SONGS = ("muffin", "survive", "ordinary", "neveralone")


def run(cmd, **kw):
    print("+", " ".join(map(str, cmd)))
    subprocess.check_call(cmd, **kw)


def debugfs_f(script: str) -> str:
    cmdf = WORK / "debugfs8.cmd"
    cmdf.write_text(script if script.endswith("\n") else script + "\n")
    r = subprocess.run(
        ["debugfs", "-w", "-f", str(cmdf), str(SYS)],
        capture_output=True,
        text=True,
    )
    out = (r.stdout or "") + (r.stderr or "")
    print(out[-3000:])
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
    n = 0
    with path.open("rb") as f:
        while True:
            b = f.read(8 * 1024 * 1024)
            if not b:
                break
            h.update(b)
            n += len(b)
    return n, h.hexdigest()


def patch_vic_anim(anim: bytearray) -> bytearray:
    """Restore SELF TEST labels; keep short CLEAR; ease debug unlock for backpack."""
    # Restore SelfTest confirm title if previously patched to SONGS - LIFT OUT
    old_title = b"SONGS - LIFT OUT\x00"
    new_title = b"START SELF TEST?\x00"
    if len(old_title) != len(new_title):
        raise SystemExit("title length mismatch")
    if old_title in anim:
        anim = anim.replace(old_title, new_title, 1)

    # Restore menu label SONGS → SELF TEST (same padded width as original patch)
    if b"SONGS\x00\x00\x00\x00\x00" in anim:
        anim = anim.replace(b"SONGS\x00\x00\x00\x00\x00", b"SELF TEST\x00", 1)
    elif b"SELF TEST\x00" not in anim and b"SONGS\x00" in anim:
        # Unexpected layout — try exact 5-char replace with padding
        raise SystemExit("SONGS label layout unexpected; cannot restore SELF TEST")

    if b"SELF TEST\x00" not in anim:
        raise SystemExit("SELF TEST label missing after restore")
    if b"SONGS\x00" in anim and b"SONGS - LIFT" not in anim:
        # leftover SONGS menu token
        if anim.count(b"SONGS\x00") > 0 and b"SELF TEST\x00" in anim:
            # allow only if somehow both exist from other strings — reject menu SONGS
            pass
    if b"EXIT\x00" not in anim:
        raise SystemExit("EXIT label missing")

    # Keep CLEAR short if CLEAR OUT SOUL menu item still present
    if b"CLEAR OUT SOUL\x00" in anim:
        # Only replace the menu item form (14 chars + nul), not "CLEAR OUT SOUL?"
        # CLEAR OUT SOUL\x00 is 14+1; CLEAR\x00 + 9 pad = 15
        menu_soul = b"CLEAR OUT SOUL\x00"
        # Avoid replacing CLEAR OUT SOUL?
        idx = 0
        while True:
            j = anim.find(menu_soul, idx)
            if j < 0:
                break
            # Skip confirm prompt that continues with '?'
            if j + len(menu_soul) <= len(anim) and anim[j + len(b"CLEAR OUT SOUL")] == ord("?"):
                idx = j + 1
                continue
            anim[j : j + len(menu_soul)] = b"CLEAR\x00" + bytes(9)
            break

    # Ease debug-screen unlock: kMenuHeadRange_rad DEG_TO_RAD(55) → ~0.001 rad
    # so a tiny head move on Main unlocks backpack→Network (songs).
    old_f = struct.pack("<f", 55 * 3.141592653589793 / 180.0)
    new_f = struct.pack("<f", 0.001)
    if anim.count(old_f) != 1:
        # Already patched on a prior 8d attempt, or image differs
        if anim.count(new_f) >= 1:
            print("head-range already eased")
        else:
            raise SystemExit(f"expected one 55deg float, found {anim.count(old_f)}")
    else:
        anim = anim.replace(old_f, new_f, 1)
        print("patched head unlock threshold → 0.001 rad")

    if b"START SELF TEST?\x00" not in anim:
        raise SystemExit("START SELF TEST? missing")
    if b"SONGS - LIFT OUT\x00" in anim:
        raise SystemExit("SONGS title still present")
    return anim


def main() -> None:
    if not SYS.is_file() or not BOOT_IMG.is_file():
        raise SystemExit("missing /tmp/life-ota/{sys.img,apq8009-robot-boot.img}")
    for p in (BOOT_ANIM, BOOT_ANIM20, UPDATE_OS, LIFE_SONGS, LIFE_WATCH, ANIM_SVC, WATCH_SVC):
        if not p.is_file():
            raise SystemExit(f"missing {p}")
    for name in SONGS:
        if not (SONG_DIR / f"{name}.raw").is_file() or not (SONG_DIR / f"{name}.wav").is_file():
            raise SystemExit(f"missing song media for {name}")
    if LIFE_WATCH.read_text().startswith("#!") and "python" in LIFE_WATCH.read_text().splitlines()[0]:
        raise SystemExit("life-songs-watch must be shell")

    inj = WORK / "inject8"
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

    (inj / "os-version").write_text("5.0.0.8d\n")
    (inj / "os-version-code").write_text("8\n")

    run(["debugfs", "-R", f"dump /build.prop {inj / 'build.prop'}", str(SYS)])
    bp = (inj / "build.prop").read_text()
    for a, b in (
        ("5.0.0.7d", "5.0.0.8d"),
        ("5.0.0.6d", "5.0.0.8d"),
        ("5.0.0.5d", "5.0.0.8d"),
        ("5.0.0.4d", "5.0.0.8d"),
        ("5.0.0.3d", "5.0.0.8d"),
        ("5.0.0.2d", "5.0.0.8d"),
        ("5.0.0.1d", "5.0.0.8d"),
        ("ro.build.version.incremental=7\n", "ro.build.version.incremental=8\n"),
        ("ro.build.version.incremental=6\n", "ro.build.version.incremental=8\n"),
        ("ro.build.version.incremental=5\n", "ro.build.version.incremental=8\n"),
        ("ro.build.version.incremental=4\n", "ro.build.version.incremental=8\n"),
        ("ro.build.version.incremental=3\n", "ro.build.version.incremental=8\n"),
        ("ro.build.version.incremental=2\n", "ro.build.version.incremental=8\n"),
        ("ro.build.version.incremental=1\n", "ro.build.version.incremental=8\n"),
    ):
        bp = bp.replace(a, b)
    if "5.0.0.8d" not in bp:
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
        "rm /lib/systemd/system/anki-robot.target.wants/life-boot-music.service",
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
    for name in SONGS:
        sif(f"{songs_path}/{name}.raw", "mode", "0100444")
        sif(f"{songs_path}/{name}.wav", "mode", "0100444")

    # Verify
    run(["debugfs", "-R", f"dump /usr/sbin/update-os {WORK / 'verify-update-os'}", str(SYS)])
    vupd = (WORK / "verify-update-os").read_text()
    if "rm -f /usr/bin/curl" not in vupd or "curl.anki" not in vupd:
        raise SystemExit("update-os ETXTBSY fix not injected")
    run(["debugfs", "-R", f"dump /usr/bin/life-songs-watch {WORK / 'verify-watch'}", str(SYS)])
    vw = (WORK / "verify-watch").read_text()
    if "NETWORK_SCREEN=10" not in vw or "python" in vw.splitlines()[0]:
        raise SystemExit("watcher not injected correctly")
    run(["debugfs", "-R", f"dump /usr/bin/life-songs {WORK / 'verify-songs'}", str(SYS)])
    vs = (WORK / "verify-songs").read_text()
    if "/dev/fb0" not in vs:
        raise SystemExit("life-songs fb0 path missing")
    run(["debugfs", "-R", f"dump /anki/bin/vic-anim {WORK / 'verify-vic-anim'}", str(SYS)])
    va = (WORK / "verify-vic-anim").read_bytes()
    if b"EXIT\x00" not in va:
        raise SystemExit("vic-anim EXIT missing")
    if b"SELF TEST\x00" not in va:
        raise SystemExit("vic-anim SELF TEST missing")
    if b"SONGS\x00\x00\x00\x00\x00" in va:
        raise SystemExit("SONGS menu label still present")
    if b"START SELF TEST?\x00" not in va:
        raise SystemExit("SelfTest title missing")
    if b"SONGS - LIFT OUT\x00" in va:
        raise SystemExit("SONGS title still present")
    if va.count(struct.pack("<f", 0.001)) < 1:
        raise SystemExit("head unlock float not patched")
    run(["debugfs", "-R", f"dump {boot_path} {WORK / 'verify-boot.raw'}", str(SYS)])
    if (WORK / "verify-boot.raw").stat().st_size != BOOT_ANIM.stat().st_size:
        raise SystemExit("boot_anim size mismatch")
    run(["debugfs", "-R", f"dump {songs_path}/muffin.wav {WORK / 'verify-muffin.wav'}", str(SYS)])
    if (WORK / "verify-muffin.wav").read_bytes()[36:40] != b"data":
        raise SystemExit("muffin.wav not canonical")

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
    outdir = WORK / "tar8"
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
        f"""**LIFE OS {OTA_VERSION}** — backpack songs (no SONGS menu item).

- Removed the broken **SONGS** CCIS item (SELF TEST restored).
- On CCIS **Main**, backpack opens the song playlist (face video via `/dev/fb0` + audio).
- Backpack again while playing exits.
- Starfield boot unchanged. `update-os` ETXTBSY curl fix included.

Do not install 5.0.0.2d (bootloop).

## SSH

```bash
curl -L -o robot_sshkey https://github.com/kercre123/unlocking-vector/raw/refs/heads/main/ssh_root_key
chmod 600 robot_sshkey
ssh -i robot_sshkey root@VECTOR_IP
```

## Install

If update-os still fails on an older build with Text file busy:

```bash
mount -o remount,rw /
cp -L /usr/bin/curl /usr/bin/curl.anki && chmod 755 /usr/bin/curl.anki
rm -f /usr/bin/curl
cat > /usr/bin/curl << 'EOF'
#!/bin/sh
exec /usr/bin/curl.anki -k -L --http1.1 -4 --connect-timeout 30 "$@"
EOF
chmod 755 /usr/bin/curl
```

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v{OTA_VERSION}-life/vicos-{OTA_VERSION}.ota
```

Recovery: `ota-start` with the same URL. Dev-signed unlocked Vector only.
"""
    )
    print("OTA", ota, ota.stat().st_size)
    print(manifest)


if __name__ == "__main__":
    main()
