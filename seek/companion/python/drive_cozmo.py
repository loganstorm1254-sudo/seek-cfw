#!/usr/bin/env python3
"""Minimal Cozmo-styled Vector drive pad (keyboard).

Requires Vector SDK credentials (same as official SDK / Wire DDL pair).
"""

from __future__ import annotations

import argparse
import sys
import time

try:
    import anki_vector
    from anki_vector.connection import ControlPriorityLevel
    from anki_vector.util import degrees
except ImportError:
    sys.stderr.write(
        "Install the Vector SDK first:\n"
        "  pip3 install -e <repo>/anki/victor/tools/sdk/vector-python-sdk-private/sdk\n"
    )
    raise SystemExit(1)


def handle(robot: anki_vector.Robot, ch: str) -> bool:
    if ch in ("q", "\x03"):
        robot.motors.set_wheel_motors(0, 0)
        return False
    if ch in (" ", "x"):
        robot.motors.set_wheel_motors(0, 0)
    elif ch == "w":
        robot.motors.set_wheel_motors(80, 80)
    elif ch == "s":
        robot.motors.set_wheel_motors(-60, -60)
    elif ch == "a":
        robot.motors.set_wheel_motors(-50, 50)
    elif ch == "d":
        robot.motors.set_wheel_motors(50, -50)
    elif ch == "g":
        robot.motors.set_wheel_motors(0, 0)
        try:
            robot.anim.play_animation_trigger("GreetAfterLongTime")
        except Exception as exc:
            print("anim failed:", exc)
        time.sleep(0.2)
    return True


def loop(robot: anki_vector.Robot) -> None:
    while True:
        ch = sys.stdin.read(1).lower()
        if ch == "\x1b":
            sys.stdin.read(1)
            ch = {"A": "w", "B": "s", "C": "d", "D": "a"}.get(sys.stdin.read(1), "")
        if not handle(robot, ch):
            break


def main() -> int:
    p = argparse.ArgumentParser(description="Drive Vector with a Cozmo-mode buddy script")
    p.add_argument("--ip", required=True, help="Vector IP from CCIS Main screen")
    p.add_argument("--serial", default=None, help="ESN / serial (optional if in SDK config)")
    args = p.parse_args()

    kwargs = {
        "ip": args.ip,
        "behavior_control_level": ControlPriorityLevel.OVERRIDE_BEHAVIORS_PRIORITY,
    }
    if args.serial:
        kwargs["serial"] = args.serial

    print("Connecting to Vector at", args.ip)
    print("Keys: WASD/arrows drive | space stop | g greet | q quit")

    with anki_vector.Robot(**kwargs) as robot:
        robot.behavior.set_head_angle(degrees(20.0))
        robot.behavior.set_lift_height(0.0)
        try:
            import termios
            import tty

            fd = sys.stdin.fileno()
            old = termios.tcgetattr(fd)
            tty.setcbreak(fd)
            try:
                loop(robot)
            finally:
                termios.tcsetattr(fd, termios.TCSADRAIN, old)
        except Exception:
            print("No raw keyboard — type commands: w a s d x g q")
            while True:
                cmd = sys.stdin.readline().strip().lower()
                if not handle(robot, cmd[:1] if cmd else ""):
                    break
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
