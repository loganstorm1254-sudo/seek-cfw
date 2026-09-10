#!/usr/bin/env python3
"""Pack LIFE OS 5.0.0.12d: restore EXIT/TEST/CLEAR + real 4th SONGS button.

10d fault-800 root cause: code-cave passed a raw char* into AppendMenuItem,
which expects a stack std::string. 12d builds the string via the same ctor
Init uses (0x40D08), embeds \"SONGS\" in the cave (does not overwrite CLEAR OUT SOUL),
and restores stock Main labels so TEST/CLEAR work again.
"""
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
STOCK_ANIM = WORK / "vic-anim.bin"
PIGZ = REPO / "ota" / "pigz" / "amd64" / "pigz"
PASS = REPO / "ota" / "ota_test.pass"
OTA_VERSION = "5.0.0.12d"

BOOT_ANIM = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim.raw"
BOOT_ANIM20 = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim_20.raw"
UPDATE_OS = REPO / "seek/overlays/usr/sbin/update-os"
LIFE_SONGS = REPO / "seek/overlays/usr/bin/life-songs"
LIFE_WATCH = REPO / "seek/overlays/usr/bin/life-songs-watch"
ANIM_SVC = REPO / "seek/overlays/lib/systemd/system/vic-anim.service"
WATCH_SVC = REPO / "seek/overlays/lib/systemd/system/life-songs-watch.service"
SONG_DIR = REPO / "seek/overlays/anki/data/life-songs"
SONGS = ("muffin", "survive", "ordinary", "neveralone")

# Labels (VA == file offset) — restore stock range
LABEL_START = 0x30A3B3  # START SELF TEST?
LABEL_END = 0x30A3ED  # past CLEAR OUT SOUL\0

HOOK_AT = 0x5B8C2  # movs r0,#8 ; add r1,sp,#0x250
HOOK_ORIG = bytes.fromhex("082094a9")
HOOK_RETURN = 0x5B8C6
CAVE = 0x365740
GET_SCREEN = 0x63928
APPEND_MENU = 0xA1630
STRING_CTOR = 0x40D08
ITEM2_MOV_R2 = 0x5B85C  # must stay SelfTest(8)


def run(cmd, **kw):
    print("+", " ".join(map(str, cmd)))
    subprocess.check_call(cmd, **kw)


def debugfs_f(script: str) -> str:
    cmdf = WORK / "debugfs12.cmd"
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
    """Thumb B.W (T4) — stays in Thumb. Do NOT use BLX (that caused fault 800)."""
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
    # B T4: hw2 = 10 J1 1 J2 imm11  (NOT 11 J1 0 J2 — that is BLX → ARM)
    hw2 = (0b10 << 14) | (J1 << 13) | (1 << 12) | (J2 << 11) | imm11
    return hw1, hw2


def build_songs_cave() -> bytes:
    """AppendMenuItem(Main, std::string(\"SONGS\"), Network) then resume SelfTest init."""
    code = bytearray()

    def half(h: int) -> None:
        code.extend(struct.pack("<H", h))

    def word(w: int) -> None:
        code.extend(struct.pack("<I", w))

    start = CAVE
    # Mirror Init item-1: GetScreen(Main) + string ctor + AppendMenuItem
    half(0x2004)  # movs r0, #4
    half(0xA994)  # add r1, sp, #0x250
    half(0xF88D)
    half(0x0250)  # strb.w r0, [sp, #0x250]
    half(0x4648)  # mov r0, r9
    bl_gs = len(code)
    half(0)
    half(0)
    half(0x4604)  # mov r4, r0
    half(0xAE94)  # add r6, sp, #0x250
    ldr_pos = len(code)
    half(0)  # ldr r1, [pc, #imm] → &"SONGS"
    half(0x4630)  # mov r0, r6
    bl_ctor = len(code)
    half(0)
    half(0)
    half(0xF104)
    half(0x0010)  # add.w r0, r4, #16
    half(0x4631)  # mov r1, r6
    half(0x220A)  # movs r2, #10  (Network)
    bl_ap = len(code)
    half(0)
    half(0)
    # Resume SelfTest screen setup (instructions we overwrote at the hook)
    half(0x2008)  # movs r0, #8
    half(0xA994)  # add r1, sp, #0x250
    bw_back = len(code)
    half(0)
    half(0)

    while (start + len(code)) % 4:
        half(0xBF00)

    lit_off = len(code)
    str_off = lit_off + 4
    word(0)
    code.extend(b"SONGS\x00")
    struct.pack_into("<I", code, lit_off, start + str_off)

    instr_addr = start + ldr_pos
    pc = (instr_addr + 4) & ~3
    imm8 = (start + lit_off - pc) // 4
    if not (0 <= imm8 <= 255):
        raise SystemExit(f"SONGS literal too far: imm8={imm8}")
    code[ldr_pos : ldr_pos + 2] = struct.pack("<H", 0x4800 | (1 << 8) | imm8)

    h1, h2 = encode_bl(start + bl_gs, GET_SCREEN)
    code[bl_gs : bl_gs + 4] = struct.pack("<HH", h1, h2)
    h1, h2 = encode_bl(start + bl_ctor, STRING_CTOR)
    code[bl_ctor : bl_ctor + 4] = struct.pack("<HH", h1, h2)
    h1, h2 = encode_bl(start + bl_ap, APPEND_MENU)
    code[bl_ap : bl_ap + 4] = struct.pack("<HH", h1, h2)
    h1, h2 = encode_bw(start + bw_back, HOOK_RETURN)
    code[bw_back : bw_back + 4] = struct.pack("<HH", h1, h2)
    return bytes(code)


def patch_vic_anim(anim: bytearray) -> bytearray:
    if not STOCK_ANIM.is_file():
        raise SystemExit(f"missing stock anim {STOCK_ANIM}")
    stock = STOCK_ANIM.read_bytes()

    # Undo prior title rewrite
    if b"PLAY SONGS?     \x00" in anim:
        anim = bytearray(anim.replace(b"PLAY SONGS?     \x00", b"START SELF TEST?\x00", 1))
    if b"SONGS - LIFT OUT\x00" in anim:
        anim = bytearray(anim.replace(b"SONGS - LIFT OUT\x00", b"START SELF TEST?\x00", 1))

    # Restore stock EXIT / TEST / SELF TEST / CLEAR / CLEAR OUT SOUL (+ title)
    anim[LABEL_START:LABEL_END] = stock[LABEL_START:LABEL_END]
    if anim[0x30A3C4 : 0x30A3C4 + 5] != b"EXIT\x00":
        raise SystemExit("EXIT restore failed")
    if anim[0x30A3CE : 0x30A3CE + 10] != b"SELF TEST\x00":
        raise SystemExit("SELF TEST restore failed")
    if anim[0x30A3D8 : 0x30A3D8 + 6] != b"CLEAR\x00":
        raise SystemExit("CLEAR restore failed")
    if not anim[0x30A3DE : 0x30A3DE + 14].startswith(b"CLEAR OUT SOUL"):
        raise SystemExit("CLEAR OUT SOUL restore failed")
    if b"START SELF TEST?\x00" not in anim[LABEL_START : LABEL_START + 20]:
        raise SystemExit("START SELF TEST? restore failed")

    # Keep TEST → SelfTest(8)
    if anim[ITEM2_MOV_R2 : ITEM2_MOV_R2 + 2] != b"\x08\x22":
        anim[ITEM2_MOV_R2 : ITEM2_MOV_R2 + 2] = b"\x08\x22"
        print("restored item2 destination SelfTest(8)")

    cave = build_songs_cave()
    # Allow empty cave or our own prior stub
    existing = bytes(anim[CAVE : CAVE + len(cave)])
    if any(existing) and b"SONGS\x00" not in existing and existing[:2] not in (b"\x04\x20", cave[:2]):
        raise SystemExit("code cave not empty")
    anim[CAVE : CAVE + len(cave)] = cave
    # Clear any leftover from longer 10d cave
    if len(cave) < 128:
        anim[CAVE + len(cave) : CAVE + 128] = bytes(128 - len(cave))

    h1, h2 = encode_bw(HOOK_AT, CAVE)
    hook = struct.pack("<HH", h1, h2)
    if anim[HOOK_AT : HOOK_AT + 4] not in (HOOK_ORIG, hook):
        print(f"hook site was {anim[HOOK_AT:HOOK_AT+4].hex()}, replacing")
    anim[HOOK_AT : HOOK_AT + 4] = hook

    if b"SONGS\x00" not in bytes(anim[CAVE : CAVE + len(cave)]):
        raise SystemExit("SONGS string missing from cave")
    if anim[HOOK_AT : HOOK_AT + 4] != hook:
        raise SystemExit("hook write failed")
    if anim[0x30A3C4 : 0x30A3C4 + 4] != b"EXIT":
        raise SystemExit("EXIT missing after patch")
    if anim[0x30A3CE : 0x30A3CE + 9] != b"SELF TEST":
        raise SystemExit("SELF TEST missing after patch")

    print("vic-anim: stock EXIT/SELF TEST/CLEAR + SONGS cave (std::string ctor)")
    return anim


def main() -> None:
    if not SYS.is_file() or not BOOT_IMG.is_file():
        raise SystemExit("missing /tmp/life-ota/{sys.img,apq8009-robot-boot.img}")
    for p in (BOOT_ANIM, BOOT_ANIM20, UPDATE_OS, LIFE_SONGS, LIFE_WATCH, ANIM_SVC, WATCH_SVC, STOCK_ANIM):
        if not p.is_file():
            raise SystemExit(f"missing {p}")
    if "python" in LIFE_WATCH.read_text().splitlines()[0]:
        raise SystemExit("life-songs-watch must be shell")
    if "SONGS_SCREEN=10" not in LIFE_WATCH.read_text():
        raise SystemExit("watcher must hijack Network (10) for SONGS")

    inj = WORK / "inject12"
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
    (inj / "os-version-code").write_text("12\n")

    run(["debugfs", "-R", f"dump /build.prop {inj / 'build.prop'}", str(SYS)])
    bp = (inj / "build.prop").read_text()
    for a, b in (
        ("5.0.0.11d", OTA_VERSION),
        ("5.0.0.10d", OTA_VERSION),
        ("5.0.0.9d", OTA_VERSION),
        ("5.0.0.8d", OTA_VERSION),
        ("ro.build.version.incremental=11\n", "ro.build.version.incremental=12\n"),
        ("ro.build.version.incremental=10\n", "ro.build.version.incremental=12\n"),
        ("ro.build.version.incremental=9\n", "ro.build.version.incremental=12\n"),
        ("ro.build.version.incremental=8\n", "ro.build.version.incremental=12\n"),
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
    if va[0x30A3C4 : 0x30A3C4 + 4] != b"EXIT":
        raise SystemExit("verify: EXIT missing")
    if va[0x30A3CE : 0x30A3CE + 9] != b"SELF TEST":
        raise SystemExit("verify: SELF TEST missing")
    if va[0x30A3D8 : 0x30A3D8 + 5] != b"CLEAR":
        raise SystemExit("verify: CLEAR missing")
    if not va[0x30A3DE : 0x30A3DE + 14].startswith(b"CLEAR OUT SOUL"):
        raise SystemExit("verify: CLEAR OUT SOUL missing")
    if va[ITEM2_MOV_R2 : ITEM2_MOV_R2 + 2] != b"\x08\x22":
        raise SystemExit("verify: TEST must stay SelfTest(8)")
    if va[HOOK_AT : HOOK_AT + 4] == HOOK_ORIG:
        raise SystemExit("verify: hook not installed")
    # Must be Thumb B.W (hw2 & 0xD000 == 0x9000), not BLX (0xC000) — BLX→ARM = fault 800
    hw2 = int.from_bytes(va[HOOK_AT + 2 : HOOK_AT + 4], "little")
    if (hw2 & 0xD000) != 0x9000:
        raise SystemExit(f"verify: hook is not Thumb B.W (got {va[HOOK_AT:HOOK_AT+4].hex()})")
    if b"SONGS\x00" not in va[CAVE : CAVE + 96]:
        raise SystemExit("verify: SONGS cave string missing")
    from capstone import Cs, CS_ARCH_ARM, CS_MODE_THUMB

    md = Cs(CS_ARCH_ARM, CS_MODE_THUMB)
    hook_insn = next(md.disasm(va[HOOK_AT : HOOK_AT + 4], HOOK_AT))
    if not hook_insn.mnemonic.startswith("b") or "0x365740" not in hook_insn.op_str:
        raise SystemExit(f"verify: bad hook insn {hook_insn.mnemonic} {hook_insn.op_str}")
    cave_insns = list(md.disasm(va[CAVE : CAVE + 64], CAVE))
    bl_ops = [i.op_str for i in cave_insns if i.mnemonic == "bl"]
    if not any("40d08" in x for x in bl_ops):
        raise SystemExit(f"verify: cave missing string ctor BL: {bl_ops}")
    if not any("a1630" in x for x in bl_ops):
        raise SystemExit(f"verify: cave missing AppendMenuItem BL: {bl_ops}")
    if not any(i.mnemonic.startswith("b") and "bl" not in i.mnemonic and "5b8c6" in i.op_str for i in cave_insns):
        raise SystemExit(
            "verify: cave missing Thumb B.W return to SelfTest init: "
            + ", ".join(f"{i.mnemonic} {i.op_str}" for i in cave_insns[-6:])
        )
    run(["debugfs", "-R", f"dump /usr/bin/life-songs-watch {WORK / 'verify-watch'}", str(SYS)])
    vw = (WORK / "verify-watch").read_text()
    if "SONGS_SCREEN=10" not in vw:
        raise SystemExit("watcher must hijack Network screen 10")
    if "SONGS_SCREEN=8" in vw:
        raise SystemExit("do not hijack SelfTest (8)")

    sys_bytes, sys_sha = sha256_file(SYS)
    boot_bytes, boot_sha = sha256_file(BOOT_IMG)
    print("SYSTEM", sys_bytes, sys_sha)
    print("BOOT", boot_bytes, boot_sha)

    run([str(PIGZ), "--best", "--force", "--keep", str(SYS)])
    run(
        [
            "openssl",
            "aes-256-ctr",
            "-pass",
            f"file:{PASS}",
            "-md",
            "md5",
            "-in",
            str(WORK / "sys.img.gz"),
            "-out",
            str(WORK / "out-sys.img.gz"),
        ],
        stderr=subprocess.DEVNULL,
    )
    boot_gz = WORK / "apq8009-robot-boot.img.gz"
    if not boot_gz.is_file():
        run([str(PIGZ), "--best", "--force", "--keep", str(BOOT_IMG)])
    run(
        [
            "openssl",
            "aes-256-ctr",
            "-pass",
            f"file:{PASS}",
            "-md",
            "md5",
            "-in",
            str(boot_gz),
            "-out",
            str(WORK / "out-boot.img.gz"),
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
    outdir = WORK / "tar12"
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
            "tar",
            "-cf",
            str(ota),
            "--mode=0400",
            "--owner=root:0",
            "--group=root:0",
            "-C",
            str(outdir),
            "manifest.ini",
            "apq8009-robot-boot.img.gz",
            "apq8009-robot-sysfs.img.gz",
        ]
    )
    (WORK / "RELEASE-NOTES.md").write_text(
        f"""**LIFE OS {OTA_VERSION}** — restore CCIS buttons + real **SONGS** item.

- Restores stock **EXIT** / **SELF TEST** / **CLEAR** (11d had replaced TEST with SONGS).
- Adds a **4th SONGS** button. Fixes both 10d crash bugs: (1) builds a real `std::string` before `AppendMenuItem`, (2) uses Thumb `B.W` not `BLX` (BLX switched to ARM → fault **800**).
- Confirm **SONGS** → playlist. **SELF TEST** works again. **CLEAR** still wipes.

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v{OTA_VERSION}-life/vicos-{OTA_VERSION}.ota
```

Dev-signed unlocked Vector only. Do not install 5.0.0.2d or 5.0.0.10d.
"""
    )
    print("OTA", ota, ota.stat().st_size)


if __name__ == "__main__":
    main()
