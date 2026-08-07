#!/usr/bin/env python3
"""
Finds where a screen recording stops being idle, and prints that second.

`test-without-building` still has to install the app on the simulator, and from this shared volume
that took seven and a half minutes against a tour of under two. Recording cannot start any later
without missing the launch, so the dead head is cut afterwards instead: the first raw tour was 554
seconds, of which 445 were a motionless home screen.

Compares small greyscale frames five seconds apart and reports ten seconds before the first real
change, so the launch itself stays in shot.

    python3 Scripts/trim-tour.py video.mp4
"""

import os
import subprocess
import sys

FRAME = "/tmp/.tourframe.raw"
STEP_SECONDS = 5
LEAD_IN_SECONDS = 10
# Mean per-pixel difference. A still screen sits near zero; a launch is far above this.
MOTION_THRESHOLD = 5


def grey_frame(video: str, second: int) -> bytes | None:
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-ss", str(second), "-i", video,
         "-frames:v", "1", "-vf", "scale=80:-1", "-f", "rawvideo",
         "-pix_fmt", "gray", "-y", FRAME],
        check=False,
    )
    if not os.path.exists(FRAME) or os.path.getsize(FRAME) == 0:
        return None
    return open(FRAME, "rb").read()


def first_motion(video: str, limit_seconds: int = 1800) -> int:
    previous = None
    for second in range(0, limit_seconds, STEP_SECONDS):
        frame = grey_frame(video, second)
        if frame is None:
            break
        if previous is not None and len(frame) == len(previous):
            change = sum(abs(a - b) for a, b in zip(frame, previous)) / len(frame)
            if change > MOTION_THRESHOLD:
                return max(0, second - LEAD_IN_SECONDS)
        previous = frame
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit("usage: trim-tour.py <video.mp4>")
    print(first_motion(sys.argv[1]))
