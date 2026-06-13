#!/usr/bin/env bash
# Record a uniform 16 kHz mono test clip from the mic into ~/vad_real/<name>.wav
# so we can validate the Silero speech gate on real voice.
#
#   scripts/record_clip.sh --list                 # show audio input devices
#   scripts/record_clip.sh speech_fr 6 [MIC_IDX]  # record 6s named speech_fr
#
# MIC_IDX defaults to 0 (first audio device from --list). First run will ask the
# terminal for Microphone permission — grant it once.
set -euo pipefail
OUT="${HOME}/vad_real"; mkdir -p "$OUT"

if [ "${1:-}" = "--list" ]; then
  echo "Audio input devices (use the [n] index for AVFoundation):"
  ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1 | sed -n '/AVFoundation audio devices/,$p'
  exit 0
fi

name="${1:?usage: record_clip.sh NAME SECONDS [MIC_IDX]   (or --list)}"
secs="${2:?usage: record_clip.sh NAME SECONDS [MIC_IDX]   (or --list)}"
idx="${3:-0}"

echo "Recording '${name}' for ${secs}s from audio device :${idx}"
for n in 3 2 1; do printf "  %s...\n" "$n"; sleep 1; done
echo "  >>> GO (speak / do the action now) <<<"
ffmpeg -hide_banner -loglevel error -f avfoundation -i ":${idx}" \
       -t "${secs}" -ar 16000 -ac 1 -y "${OUT}/${name}.wav"
echo "Saved ${OUT}/${name}.wav"
