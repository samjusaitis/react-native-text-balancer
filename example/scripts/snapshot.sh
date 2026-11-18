#!/usr/bin/env bash
# Records what the library does right now, so a later run can be compared with it exactly:
# - lines/<size>.txt: the test screen's results and every balanced line (text and width), at
#   each Dynamic Type size;
# - shots/<sample id>.png: a screenshot of each sample on its own (`-only <id>`), at the default
#   text size, with the status bar pinned. Screenshots show what's drawn, which onTextLayout
#   doesn't: drawing builds its own text layout.
#
# Usage: example/scripts/snapshot.sh <output dir> [simulator udid, default "booted"]
# Compare two runs with: diff -r <dir a> <dir b>   (PNGs compare byte for byte)
#
# Install a Release build first, as for sweep-text-sizes.sh (it bundles the JS, no Metro needed).
set -euo pipefail

OUT="${1:?usage: snapshot.sh <output dir> [udid]}"
UDID="${2:-booted}"
BUNDLE_ID=$(node -p "require('$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/app.json').expo.ios.bundleIdentifier")
SAMPLES_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/samples.ts"
SIZES=(
  extra-small small medium large extra-large extra-extra-large extra-extra-extra-large
  accessibility-medium accessibility-large accessibility-extra-large
  accessibility-extra-extra-large accessibility-extra-extra-extra-large
)
TIMEOUT=30 # seconds to wait for the screen's summary
SETTLE=3   # seconds without a new summary before reading the latest one

mkdir -p "$OUT/lines" "$OUT/shots"
log=$(mktemp)
log_pid=
original=$(xcrun simctl ui "$UDID" content_size)
cleanup() {
  [[ -n "$log_pid" ]] && kill "$log_pid" 2>/dev/null
  xcrun simctl ui "$UDID" content_size "$original"
  xcrun simctl status_bar "$UDID" clear
  rm -f "$log"
}
trap cleanup EXIT

xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active \
  --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl spawn "$UDID" log stream --level info --style compact \
  --predicate 'process == "TextBalancerExample" AND eventMessage CONTAINS "[test screen]"' \
  >"$log" 2>/dev/null &
log_pid=$!
sleep 2

summaries() { grep -c 'passed$' "$log" || true; }

# Waits for a summary newer than the `$1`th and for the summaries to settle, then writes the
# latest block (summary, per-sample results, lines) to `$2`. Fails if no summary comes.
save_block() {
  local before=$1 file=$2 waited=0 count
  while (( $(summaries) <= before )); do
    if (( waited >= TIMEOUT )); then
      echo "  no summary within ${TIMEOUT}s" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  count=$(summaries)
  while sleep "$SETTLE"; (( $(summaries) != count )); do
    count=$(summaries)
  done
  sed -n 's/.*\[test screen\] //p' "$log" |
    awk '/passed$/ { block = "" } { block = block $0 "\n" } END { printf "%s", block }' >"$file"
  echo "  $(head -n 1 "$file")"
}

relaunch() {
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" >/dev/null
}

echo "Lines at each text size"
xcrun simctl ui "$UDID" content_size "${SIZES[0]}"
before=$(summaries)
relaunch
echo "${SIZES[0]}"
save_block "$before" "$OUT/lines/${SIZES[0]}.txt"
for size in "${SIZES[@]:1}"; do
  before=$(summaries)
  echo "$size"
  xcrun simctl ui "$UDID" content_size "$size"
  save_block "$before" "$OUT/lines/$size.txt"
done

echo "Screenshots, one sample each"
xcrun simctl ui "$UDID" content_size large
for id in $(sed -n "s/^    id: '\([^']*\)',$/\1/p" "$SAMPLES_FILE"); do
  before=$(summaries)
  echo "$id"
  relaunch -only "$id"
  save_block "$before" "$OUT/shots/$id.txt"
  xcrun simctl io "$UDID" screenshot "$OUT/shots/$id.png" >/dev/null 2>&1
done

if grep -l '❌' "$OUT"/lines/*.txt "$OUT"/shots/*.txt; then
  echo "Some checks failed (files above)."
  exit 1
fi
echo "Done: $OUT"
