#!/usr/bin/env python3
"""Pack LIFE OS 5.0.0.10d: CCIS EX/TEST/CLR + SONGS menu (fb0 playlist)."""
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
OTA_VERSION = "5.0.0.10d"

BOOT_ANIM = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim.raw"
BOOT_ANIM20 = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim_20.raw"
UPDATE_OS = REPO / "seek/overlays/usr/sbin/update-os"
LIFE_SONGS = REPO / "seek/overlays/usr/bin/life-songs"
LIFE_WATCH = REPO / "seek/overlays/usr/bin/life-songs-watch"
ANIM_SVC = REPO / "seek/overlays/lib/systemd/system/vic-anim.service"
WATCH_SVC = REPO / "seek/overlays/lib/systemd/system/life-songs-watch.service"
SONG_DIR = REPO / "seek/overlays/anki/data/life-songs"
SONGS = ("muffin", "survive", "ordinary", "neveralone")

# Known addresses in current WireOS-based vic-anim (VA == file offset)
ADDR_EXIT = 0x30A3C4
ADDR_SELFTEST = 0x30A3CE  # 10-byte slot
ADDR_CLEAR = 0x30A3D8  # 6-byte slot
ADDR_SONGS = 0x30A3DE  # second CLEAR / padding
HOOK_AT = 0x5B8C2  # movs r0,#8 ; add r1,sp,#0x250 before SelfTest menu setup
HOOK_RETURN = 0x5B8C6
CAVE = 0x365740
GET_SCREEN = 0x63928
APPEND_MENU = 0xA1630


def run(cmd, **kw):
    print("+", " ".join(map(str, cmd)))
    subprocess.check_call(cmd, **kw)


def debugfs_f(script: str) -> str:
    cmdf = WORK / "debugfs10.cmd"
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
    with path.open("rb") as f:
        while True:
            b = f.read(8 * 1024 * 1024)
            if not b:
                break
            h.update(b)
    return path.stat().st_size, h.hexdigest()


def encode_bl(from_addr: int, to_addr: int) -> tuple[int, int]:
    pc = from_addr + 4
    imm25 = (to_addr - pc) & 0x1FFFFFF
    S = (imm25 >> 24) & 1
    imm10 = (imm25 >> 12) & 0x3FF
    imm11 = (imm25 >> 1) & 0x7FF
    I1 = (imm25 >> 23) & 1
    I2 = (imm25 >> 22) & 1
    J1 = ~(I1 ^ S) & 1
    J2 = ~(I2 ^ S) & 1
    hw1 = 0xF000 | (S << 10) | imm10
    hw2 = (0b11 << 14) | (J1 << 13) | (1 << 12) | (J2 << 11) | imm11
    return hw1, hw2


def encode_bw(from_addr: int, to_addr: int) -> tuple[int, int]:
    pc = from_addr + 4
    imm25 = (to_addr - pc) & 0x1FFFFFF
    S = (imm25 >> 24) & 1
    imm10 = (imm25 >> 12) & 0x3FF
    imm11 = (imm25 >> 1) & 0x7FF
    I1 = (imm25 >> 23) & 1
    I2 = (imm25 >> 22) & 1
    J1 = ~(I1 ^ S) & 1
    J2 = ~(I2 ^ S) & 1
    hw1 = 0xF000 | (S << 10) | imm10
    hw2 = (0b11 << 14) | (J1 << 13) | (0 << 12) | (J2 << 11) | imm11
    return hw1, hw2


def build_songs_cave() -> bytes:
    """Thumb stub: AppendMenuItem(Main, \"SONGS\", Network) then resume SelfTest menu init."""
    code = bytearray()

    def half(h: int) -> None:
        code.extend(struct.pack("<H", h))

    def word(w: int) -> None:
        code.extend(struct.pack("<I", w))

    start = CAVE
    # movs r0, #4
    half(0x2004)
    # add r1, sp, #0x250
    half(0xA994)
    # strb r0, [sp, #0x250]
    half(0xF88D)
    half(0x0250)
    # mov r0, r9
    half(0x4648)
    bl_gs = len(code)
    half(0)
    half(0)
    # mov r4, r0
    half(0x4604)
    ldr_pos = len(code)
    half(0)  # ldr r6, [pc, #imm]
    # add.w r0, r4, #16
    half(0xF104)
    half(0x0010)
    # mov r1, r6
    half(0x4631)
    # movs r2, #10  (Network)
    half(0x220A)
    bl_ap = len(code)
    half(0)
    half(0)
    # movs r0, #8
    half(0x2008)
    # add r1, sp, #0x250
    half(0xA994)
    bw_back = len(code)
    half(0)
    half(0)
    while (start + len(code)) % 4:
        half(0xBF00)
    lit_off = len(code)
    word(ADDR_SONGS)

    instr_addr = start + ldr_pos
    pc = (instr_addr + 4) & ~3
    lit_addr = start + lit_off
    imm8 = (lit_addr - pc) // 4
    if not (0 <= imm8 <= 255):
        raise SystemExit(f"SONGS literal too far: imm8={imm8}")
    code[ldr_pos : ldr_pos + 2] = struct.pack("<H", 0x4800 | (6 << 8) | imm8)

    h1, h2 = encode_bl(start + bl_gs, GET_SCREEN)
    code[bl_gs : bl_gs + 4] = struct.pack("<HH", h1, h2)
    h1, h2 = encode_bl(start + bl_ap, APPEND_MENU)
    code[bl_ap : bl_ap + 4] = struct.pack("<HH", h1, h2)
    h1, h2 = encode_bw(start + bw_back, HOOK_RETURN)
    code[bw_back : bw_back + 4] = struct.pack("<HH", h1, h2)
    return bytes(code)


def patch_vic_anim(anim: bytearray) -> bytearray:
    # Restore SelfTest title if still SONGS-titled from older packs
    if b"SONGS - LIFT OUT\x00" in anim:
        anim = anim.replace(b"SONGS - LIFT OUT\x00", b"START SELF TEST?\x00", 1)

    # Stable-address label shrinks + SONGS string
    # EXIT (5) → EX + pad (pointer stays at ADDR_EXIT)
    if anim[ADDR_EXIT : ADDR_EXIT + 5] in (b"EXIT\x00", b"EX\x00\x00\x00"):
        anim[ADDR_EXIT : ADDR_EXIT + 5] = b"EX\x00" + bytes(2)
    else:
        raise SystemExit(f"EXIT label unexpected: {anim[ADDR_EXIT:ADDR_EXIT+8]!r}")

    # SELF TEST (10) → TEST + pad (still 10 bytes) — keeps pointer stable
    slot = anim[ADDR_SELFTEST : ADDR_SELFTEST + 10]
    if slot.startswith(b"SELF TEST\x00") or slot.startswith(b"SONGS\x00") or slot.startswith(b"TEST\x00"):
        anim[ADDR_SELFTEST : ADDR_SELFTEST + 10] = b"TEST\x00" + bytes(5)
    else:
        raise SystemExit(f"SELF TEST slot unexpected: {slot!r}")

    # CLEAR (6) → CLR + pad
    cslot = anim[ADDR_CLEAR : ADDR_CLEAR + 6]
    if cslot.startswith(b"CLEAR\x00") or cslot.startswith(b"CLR\x00"):
        anim[ADDR_CLEAR : ADDR_CLEAR + 6] = b"CLR\x00" + bytes(2)
    else:
        raise SystemExit(f"CLEAR slot unexpected: {cslot!r}")

    # SONGS string for 4th item
    anim[ADDR_SONGS : ADDR_SONGS + 6] = b"SONGS\x00"

    # Inject AppendMenuItem(Main, SONGS, Network) before SelfTest menu init
    cave = build_songs_cave()
    if any(anim[CAVE : CAVE + len(cave)]):
        # Allow re-pack over our own stub (detect SONGS literal at end)
        if anim[CAVE : CAVE + 2] != b"\x04\x20" and b"\xde\xa3\x30\x00" not in bytes(
            anim[CAVE : CAVE + 64]
        ):
            # Check if already our stub
            if anim[CAVE : CAVE + 4] != cave[:4]:
                raise SystemExit("code cave not empty")
    anim[CAVE : CAVE + len(cave)] = cave

    h1, h2 = encode_bw(HOOK_AT, CAVE)
    # Must replace movs r0,#8 ; add r1,sp,#0x250
    if anim[HOOK_AT : HOOK_AT + 4] not in (
        b"\x08\x20\x94\xa9",
        struct.pack("<HH", h1, h2),
    ):
        # Already hooked with different encoding, or unexpected
        cur = bytes(anim[HOOK_AT : HOOK_AT + 4])
        if cur != b"\x08\x20\x94\xa9":
            # allow if already a B.W into our cave range
            print("hook site", cur.hex(), "patching anyway")
    anim[HOOK_AT : HOOK_AT + 4] = struct.pack("<HH", h1, h2)

    # Ease head unlock if still stock 55deg
    old_f = struct.pack("<f", 55 * 3.141592653589793 / 180.0)
    new_f = struct.pack("<f", 0.001)
    if anim.count(old_f) == 1:
        anim = bytearray(anim.replace(old_f, new_f, 1))
        print("patched head unlock threshold")
    else:
        print("head-range already eased or absent")

    if b"EX\x00" not in anim[ADDR_EXIT : ADDR_EXIT + 3]:
        raise SystemExit("EX label missing")
    if b"TEST\x00" not in anim[ADDR_SELFTEST : ADDR_SELFTEST + 5]:
        raise SystemExit("TEST label missing")
    if b"CLR\x00" not in anim[ADDR_CLEAR : ADDR_CLEAR + 4]:
        raise SystemExit("CLR label missing")
    if b"SONGS\x00" not in anim[ADDR_SONGS : ADDR_SONGS + 6]:
        raise SystemExit("SONGS label missing")
    if b"START SELF TEST?\x00" not in anim:
        raise SystemExit("START SELF TEST? missing")
    return anim


def main() -> None:
    if not SYS.is_file() or not BOOT_IMG.is_file():
        raise SystemExit("missing /tmp/life-ota/{sys.img,apq8009-robot-boot.img}")
    for p in (BOOT_ANIM, BOOT_ANIM20, UPDATE_OS, LIFE_SONGS, LIFE_WATCH, ANIM_SVC, WATCH_SVC):
        if not p.is_file():
            raise SystemExit(f"missing {p}")
    if "python" in LIFE_WATCH.read_text().splitlines()[0]:
        raise SystemExit("life-songs-watch must be shell")

    inj = WORK / "inject10"
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
    (inj / "os-version-code").write_text("10\n")

    run(["debugfs", "-R", f"dump /build.prop {inj / 'build.prop'}", str(SYS)])
    bp = (inj / "build.prop").read_text()
    for a, b in (
        ("5.0.0.9d", OTA_VERSION),
        ("5.0.0.8d", OTA_VERSION),
        ("5.0.0.7d", OTA_VERSION),
        ("5.0.0.6d", OTA_VERSION),
        ("5.0.0.5d", OTA_VERSION),
        ("ro.build.version.incremental=9\n", "ro.build.version.incremental=10\n"),
        ("ro.build.version.incremental=8\n", "ro.build.version.incremental=10\n"),
        ("ro.build.version.incremental=7\n", "ro.build.version.incremental=10\n"),
        ("ro.build.version.incremental=6\n", "ro.build.version.incremental=10\n"),
        ("ro.build.version.incremental=5\n", "ro.build.version.incremental=10\n"),
    ):
        bp = bp.replace(a, b)
    if OTA_VERSION not in bp:
        raise SystemExit("build.prop version bump failed:\n" + bp)
    (inj / "build.prop").write_text(bp)

    run(["debugfs", "-R", f"dump /anki/bin/vic-anim {inj / 'vic-anim'}", str(SYS)])
    anim = patch_vic_anim(bytearray((inj / "vic-anim").read_bytes()))
    (inj / "vic-anim").write_bytes(anim)
    print("vic-anim patched: EX/TEST/CLR + SONGS menu item")

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

    run(["debugfs", "-R", f"dump /usr/bin/life-songs-watch {WORK / 'verify-watch'}", str(SYS)])
    vw = (WORK / "verify-watch").read_text()
    if "SONGS_SCREEN=10" not in vw or "python" in vw.splitlines()[0]:
        raise SystemExit("watcher not injected")
    run(["debugfs", "-R", f"dump /anki/bin/vic-anim {WORK / 'verify-vic-anim'}", str(SYS)])
    va = (WORK / "verify-vic-anim").read_bytes()
    if va[ADDR_EXIT : ADDR_EXIT + 2] != b"EX":
        raise SystemExit("EX label not in vic-anim")
    if va[ADDR_SELFTEST : ADDR_SELFTEST + 4] != b"TEST":
        raise SystemExit("TEST label not in vic-anim")
    if va[ADDR_CLEAR : ADDR_CLEAR + 3] != b"CLR":
        raise SystemExit("CLR label not in vic-anim")
    if va[ADDR_SONGS : ADDR_SONGS + 5] != b"SONGS":
        raise SystemExit("SONGS label not in vic-anim")
    if va[HOOK_AT : HOOK_AT + 2] == b"\x08\x20":
        raise SystemExit("SONGS hook not installed")
    if va[CAVE : CAVE + 2] != b"\x04\x20":
        raise SystemExit("SONGS cave missing")

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
    outdir = WORK / "tar10"
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
        f"""**LIFE OS {OTA_VERSION}** — CCIS SONGS menu (others kept, shortened).

- CCIS Main: **EXIT** / **TEST** / **CLR** / **SONGS**
- **TEST** still opens self-test. **CLR** still clears. **SONGS** plays the face playlist.
- Face video via `/dev/fb0` + audio. Starfield boot + `update-os` curl fix included.

Do not install 5.0.0.2d (bootloop).

## Install

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v{OTA_VERSION}-life/vicos-{OTA_VERSION}.ota
```

Dev-signed unlocked Vector only.
"""
    )
    print("OTA", ota, ota.stat().st_size)


if __name__ == "__main__":
    main()
