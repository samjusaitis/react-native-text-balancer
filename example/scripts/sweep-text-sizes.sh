#!/usr/bin/env bash
# Steps an iOS simulator through every Dynamic Type size while the example app's test screen runs,
# and prints the screen's summary at each size, with any failing checks.
#
# Usage: example/scripts/sweep-text-sizes.sh [simulator udid, default "booted"]
#
# The example app must already be installed on a booted simulator. A Release build bundles the
# current JS and needs no Metro:
#   cd example/ios && xcodebuild -workspace TextBalancerExample.xcworkspace \
#     -scheme TextBalancerExample -configuration Release -sdk iphonesimulator \
#     -derivedDataPath build build
#   xcrun simctl install booted build/Build/Products/Release-iphonesimulator/TextBalancerExample.app
#
# The script relaunches the app, steps the text size from the smallest to the largest
# accessibility size (so balanced text has to rebalance after each change), then puts the
# simulator's text size back. Exits 1 if any size had a failing check.
set -euo pipefail

UDID="${1:-booted}"
BUNDLE_ID=com.codefish.textbalancerexample
SIZES=(
  extra-small small medium large extra-large extra-extra-large extra-extra-extra-large
  accessibility-medium accessibility-large accessibility-extra-large
  accessibility-extra-extra-large accessibility-extra-extra-extra-large
)
TIMEOUT=30 # seconds to wait for the screen's summary after a change
SETTLE=3   # seconds without a new summary before reading the latest one

log=$(mktemp)
log_pid=
original=$(xcrun simctl ui "$UDID" content_size)
cleanup() {
  [[ -n "$log_pid" ]] && kill "$log_pid" 2>/dev/null
  xcrun simctl ui "$UDID" content_size "$original"
  rm -f "$log"
}
trap cleanup EXIT

# The screen logs a summary line ("... passed"), then one line per sample.
xcrun simctl spawn "$UDID" log stream --level info --style compact \
  --predicate 'process == "TextBalancerExample" AND eventMessage CONTAINS "[test screen]"' \
  >"$log" 2>/dev/null &
log_pid=$!
sleep 2

summaries() { grep -c 'passed$' "$log" || true; }

# Waits for a summary newer than the `$1`th, then for the summaries to settle. Prints the latest
# summary and its failing sample lines, and returns 1 if any check failed.
read_summary() {
  local before=$1 waited=0 count
  while (( $(summaries) <= before )); do
    if (( waited >= TIMEOUT )); then
      echo "  no summary within ${TIMEOUT}s"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  count=$(summaries)
  while sleep "$SETTLE"; (( $(summaries) != count )); do
    count=$(summaries)
  done
  # The latest block: from the last summary line to the end.
  local block
  block=$(sed -n 's/.*\[test screen\] //p' "$log" | awk '/passed$/ { block = "" } { block = block $0 "\n" } END { printf "%s", block }')
  echo "  $(head -n 1 <<<"$block")"
  if grep -q '❌' <<<"$block"; then
    grep '❌' <<<"$block" | sed 's/^/    /'
    return 1
  fi
}

failed=()
echo "Launching at $original"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
read_summary 0 || failed+=("$original")

current=$original
for size in "${SIZES[@]}"; do
  [[ "$size" == "$current" ]] && continue
  before=$(summaries)
  echo "$size"
  xcrun simctl ui "$UDID" content_size "$size"
  current=$size
  read_summary "$before" || failed+=("$size")
done

if (( ${#failed[@]} )); then
  echo "Failing at: ${failed[*]}"
  exit 1
fi
echo "All sizes pass."
