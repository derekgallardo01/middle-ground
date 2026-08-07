#!/usr/bin/env python3
"""
Finds where a screen recording stops being idle, and prints that second.

`test-without-building` still has to install the app on the simulator, and from this shared volume
that took seven and a half minutes against a tour of under two. Recording cannot start any later
without missing the launch, so the dead head is cut afterwards instead: the first raw tour was 554
seconds, of which 445 were a motionless home screen.

Compares small greyscale frames a few seconds apart and reports shortly before the first real
change, so the launch itself stays in shot.

Takes an optional floor: the second before which nothing can possibly be the app. The recorder
works this out from the wall clock in xcodebuild's log, and it matters because the simulator
obliges with "motion" long before the app appears — waking the display counts. On its own this
detector once left a quarter of the film sitting on a home screen.

    python3 Scripts/trim-tour.py video.mp4 [search-from-second] [--end]

With `--end` it reports where the action stops instead, so the trailing minutes of teardown can be
cut too.
"""

from typing import Optional

import os
import subprocess
import sys

FRAME = "/tmp/.tourframe.raw"
STEP_SECONDS = 2
LEAD_IN_SECONDS = 3
# Mean per-pixel difference. A still screen sits near zero; a launch is far above this.
MOTION_THRESHOLD = 5


def grey_frame(video: str, second: int) -> Optional[bytes]:
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-ss", str(second), "-i", video,
         "-frames:v", "1", "-vf", "scale=80:-1", "-f", "rawvideo",
         "-pix_fmt", "gray", "-y", FRAME],
        check=False,
    )
    if not os.path.exists(FRAME) or os.path.getsize(FRAME) == 0:
        return None
    return open(FRAME, "rb").read()


def first_motion(video: str, floor_seconds: int = 0, limit_seconds: int = 1800) -> int:
    previous = None
    for second in range(floor_seconds, limit_seconds, STEP_SECONDS):
        frame = grey_frame(video, second)
        if frame is None:
            break
        if previous is not None and len(frame) == len(previous):
            change = sum(abs(a - b) for a, b in zip(frame, previous)) / len(frame)
            if change > MOTION_THRESHOLD:
                return max(floor_seconds, second - LEAD_IN_SECONDS)
        previous = frame
    return floor_seconds


def last_motion(video: str, floor_seconds: int = 0, limit_seconds: int = 3600) -> int:
    """The second after which nothing moves again.

    The tour terminates the app and xcodebuild then spends a minute or two tearing down, all of it
    recorded. Trimming only the head left a film that stopped after two minutes and sat on a home
    screen for the rest — which reads as a broken video, not as a finished tour.
    """
    previous = None
    last = floor_seconds
    for second in range(floor_seconds, limit_seconds, STEP_SECONDS):
        frame = grey_frame(video, second)
        if frame is None:
            break
        if previous is not None and len(frame) == len(previous):
            change = sum(abs(a - b) for a, b in zip(frame, previous)) / len(frame)
            if change > MOTION_THRESHOLD:
                last = second
        previous = frame
    # A breath after the last thing that happened, rather than a hard cut on it.
    return last + LEAD_IN_SECONDS


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: trim-tour.py <video.mp4> [search-from-second]")
    floor = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    if "--end" in sys.argv:
        print(last_motion(sys.argv[1], floor_seconds=floor))
    else:
        print(first_motion(sys.argv[1], floor_seconds=floor))
