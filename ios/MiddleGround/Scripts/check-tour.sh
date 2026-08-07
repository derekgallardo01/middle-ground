#!/bin/bash
#
# Samples a recorded tour into frames, so what the video shows can be checked
# rather than assumed.
#
# Four takes were declared finished on the strength of the recorder exiting 0.
# One was nine minutes of a home screen, one swiped the same screen repeatedly,
# and two showed the couple where the group was meant to be. In every case the
# script had succeeded. Looking at the frames is the only step that has ever
# caught any of it.
#
#   Scripts/check-tour.sh /tmp/mg-tour5/nearby-tour.mp4 [count]
#
# Writes numbered PNGs beside the video, each stamped with its timestamp.

set -euo pipefail

VIDEO="${1:?usage: check-tour.sh <video.mp4> [frame count]}"
COUNT="${2:-24}"
OUT="$(dirname "$VIDEO")/frames"

[[ -s "$VIDEO" ]] || { echo "no video at $VIDEO" >&2; exit 1; }

DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO")
DURATION=${DURATION%.*}
[[ "$DURATION" -gt 0 ]] || { echo "video has no duration" >&2; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT"

echo "$VIDEO — ${DURATION}s, sampling $COUNT frames"
for i in $(seq 0 $((COUNT - 1))); do
    second=$((DURATION * i / COUNT))
    printf -v name "%s/%02d-at-%03ds.png" "$OUT" "$i" "$second"
    ffmpeg -loglevel error -ss "$second" -i "$VIDEO" -frames:v 1 \
        -vf "scale=390:-1" -y "$name"
done

echo "$OUT"
ls "$OUT"
