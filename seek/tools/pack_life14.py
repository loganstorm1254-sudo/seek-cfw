#!/usr/bin/env python3
"""Pack LIFE OS 5.0.0.14d: meme boot anim + suppress 800/890/899. No songs."""
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
OTA_VERSION = "5.0.0.14d"

BOOT_ANIM = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim.raw"
BOOT_ANIM20 = REPO / "seek/overlays/anki/victor/resources/config/engine/animations/boot_anim_20.raw"
UPDATE_OS = REPO / "seek/overlays/usr/sbin/update-os"
FAULT = REPO / "seek/overlays/anki/fault-code/fault-code-handler"
ANIM_SVC = REPO / "seek/overlays/lib/systemd/system/vic-anim.service"

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
    cmdf = WORK / "debugfs14.cmd"
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
    """Ensure stock menu / no leftover SONGS cave from 10d–12d."""
    if not STOCK_ANIM.is_file():
        raise SystemExit(f"missing stock anim {STOCK_ANIM}")
    stock = STOCK_ANIM.read_bytes()
    for old, new in (
        (b"PLAY SONGS?     \x00", b"START SELF TEST?\x00"),
        (b"SONGS - LIFT OUT\x00", b"START SELF TEST?\x00"),
    ):
        if old in anim:
            anim = bytearray(anim.replace(old, new, 1))
    anim[LABEL_START:LABEL_END] = stock[LABEL_START:LABEL_END]
    if anim[HOOK_AT : HOOK_AT + 4] != HOOK_ORIG:
        print(f"restoring Init hook {anim[HOOK_AT:HOOK_AT+4].hex()}")
        anim[HOOK_AT : HOOK_AT + 4] = HOOK_ORIG
    if any(anim[CAVE : CAVE + 64]):
        print("clearing leftover code cave")
        anim[CAVE : CAVE + 256] = bytes(256)
    if anim[ITEM2_MOV_R2 : ITEM2_MOV_R2 + 2] != b"\x08\x22":
        anim[ITEM2_MOV_R2 : ITEM2_MOV_R2 + 2] = b"\x08\x22"
    if anim[HOOK_AT : HOOK_AT + 4] != HOOK_ORIG:
        raise SystemExit("hook restore failed")
    if any(anim[CAVE : CAVE + 64]):
        raise SystemExit("cave not cleared")
    print("vic-anim: stock (no songs cave)")
    return anim


def main() -> None:
    if not SYS.is_file() or not BOOT_IMG.is_file():
        raise SystemExit("missing /tmp/life-ota/{sys.img,apq8009-robot-boot.img}")
    for p in (BOOT_ANIM, BOOT_ANIM20, UPDATE_OS, FAULT, ANIM_SVC, STOCK_ANIM):
        if not p.is_file():
            raise SystemExit(f"missing {p}")
    fault_txt = FAULT.read_text()
    if "-eq 800" not in fault_txt or "-eq 890" not in fault_txt or "-eq 899" not in fault_txt:
        raise SystemExit("fault-code-handler must suppress 800/890/899")

    n = len(BOOT_ANIM.read_bytes()) // (184 * 96 * 2)
    n20 = len(BOOT_ANIM20.read_bytes()) // (160 * 80 * 2)
    if n < 8 or n != n20:
        raise SystemExit(f"boot anim frame mismatch {n} vs {n20}")

    inj = WORK / "inject14"
    if inj.exists():
        shutil.rmtree(inj)
    inj.mkdir()

    shutil.copy2(BOOT_ANIM, inj / "boot_anim.raw")
    shutil.copy2(BOOT_ANIM20, inj / "boot_anim_20.raw")
    shutil.copy2(UPDATE_OS, inj / "update-os")
    os.chmod(inj / "update-os", 0o755)
    shutil.copy2(FAULT, inj / "fault-code-handler")
    os.chmod(inj / "fault-code-handler", 0o755)
    shutil.copy2(ANIM_SVC, inj / "vic-anim.service")

    (inj / "os-version").write_text(f"{OTA_VERSION}\n")
    (inj / "os-version-code").write_text("14\n")

    run(["debugfs", "-R", f"dump /build.prop {inj / 'build.prop'}", str(SYS)])
    bp = (inj / "build.prop").read_text()
    for a, b in (
        ("5.0.0.13d", OTA_VERSION),
        ("5.0.0.12d", OTA_VERSION),
        ("5.0.0.11d", OTA_VERSION),
        ("5.0.0.10d", OTA_VERSION),
        ("ro.build.version.incremental=13\n", "ro.build.version.incremental=14\n"),
        ("ro.build.version.incremental=12\n", "ro.build.version.incremental=14\n"),
        ("ro.build.version.incremental=11\n", "ro.build.version.incremental=14\n"),
        ("ro.build.version.incremental=10\n", "ro.build.version.incremental=14\n"),
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

    lines = [
        f"rm {boot_path}",
        f"write {inj / 'boot_anim.raw'} {boot_path}",
        f"rm {boot20_path}",
        f"write {inj / 'boot_anim_20.raw'} {boot20_path}",
        "rm /usr/sbin/update-os",
        f"write {inj / 'update-os'} /usr/sbin/update-os",
        "rm /usr/bin/fault-code-handler",
        f"write {inj / 'fault-code-handler'} /usr/bin/fault-code-handler",
        "rm /lib/systemd/system/vic-anim.service",
        f"write {inj / 'vic-anim.service'} /lib/systemd/system/vic-anim.service",
        "rm /anki/bin/vic-anim",
        f"write {inj / 'vic-anim'} /anki/bin/vic-anim",
        "rm /etc/os-version",
        f"write {inj / 'os-version'} /etc/os-version",
        "rm /etc/os-version-code",
        f"write {inj / 'os-version-code'} /etc/os-version-code",
        "rm /build.prop",
        f"write {inj / 'build.prop'} /build.prop",
        # Drop songs plumbing from earlier builds
        "rm /usr/bin/life-songs",
        "rm /usr/bin/life-songs-watch",
        "rm /lib/systemd/system/life-songs-watch.service",
        "rm /lib/systemd/system/anki-robot.target.wants/life-songs-watch.service",
        "rm /lib/systemd/system/life-boot-music.service",
        "rm /lib/systemd/system/anki-robot.target.wants/life-boot-music.service",
    ]
    debugfs_f("\n".join(lines))

    sif("/usr/sbin/update-os", "mode", "0100755")
    sif("/usr/bin/fault-code-handler", "mode", "0100755")
    sif("/lib/systemd/system/vic-anim.service", "mode", "0100644")
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
        raise SystemExit("hook not stock")
    if any(va[CAVE : CAVE + 64]):
        raise SystemExit("cave dirty")
    run(["debugfs", "-R", f"dump /usr/bin/fault-code-handler {WORK / 'verify-fault'}", str(SYS)])
    vf = (WORK / "verify-fault").read_text()
    if "-eq 800" not in vf or "-eq 890" not in vf or "-eq 899" not in vf:
        raise SystemExit("fault handler missing 800/890/899 suppress")
    run(["debugfs", "-R", f"dump {boot_path} {WORK / 'verify-boot.raw'}", str(SYS)])
    if len((WORK / "verify-boot.raw").read_bytes()) != len(BOOT_ANIM.read_bytes()):
        raise SystemExit("boot_anim size mismatch on image")

    sys_bytes, sys_sha = sha256_file(SYS)
    boot_bytes, boot_sha = sha256_file(BOOT_IMG)
    print("SYSTEM", sys_bytes, sys_sha)
    print("BOOT", boot_bytes, boot_sha)
    print("boot frames", n)

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
    outdir = WORK / "tar14"
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
        f"""**LIFE OS {OTA_VERSION}** — boot only + fault suppress.

- Moving boot is the new animated clip (70 frames). Static portrait splash unchanged.
- Suppress faults **800**, **890**, **899** (never show).
- Songs / SONGS menu / `vic-anim` cave removed. Stock CCIS: EXIT / SELF TEST / CLEAR.

```bash
update-os https://github.com/loganstorm1254-sudo/seek-cfw/releases/download/v{OTA_VERSION}-life/vicos-{OTA_VERSION}.ota
```

Dev-signed unlocked Vector only. Do not install 5.0.0.10d or 5.0.0.12d.
"""
    )
    print("OTA", ota, ota.stat().st_size)


if __name__ == "__main__":
    main()
