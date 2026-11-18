#!/usr/bin/env bash
# verify:matrix: which React Native versions the library builds on.
#
# Run it before each release and whenever a new RN minor or RC appears. A full pass gates a release
# and widening the documented RN range.
#
# For each RN version it creates a fresh bare app (@react-native-community/cli init), installs the
# library from this repo as an npm git dependency (git+file://<repo>#<commit>), checks the
# installed package holds exactly what the `files` allowlist ships, runs `pod install`, and runs a
# Debug iOS simulator build. Then it builds the Expo example app (from the working tree, not the
# commit) for iOS and Android. It prints a pass/fail table and exits 1 if any row failed.
#
# Usage: scripts/verify-matrix.sh [options] [version ...]
#   version       an RN minor ("0.86", its latest patch), an exact version ("0.85.2"), or "rc"
#                 (the `next` dist-tag). Default: every RN minor from 0.85 up, plus the RC if newer.
#   --ref REF     the commit or tag the bare apps install (default HEAD). Uncommitted changes
#                 aren't tested by the bare apps.
#   --no-example  skip the Expo example builds.
#   --keep        keep each bare app and its build (default: deleted after its row, ~5 GB each).
#   --list        print the resolved RN versions and exit.
#
# Environment: VERIFY_MATRIX_DIR (work dir, default $TMPDIR/rntb-verify-matrix),
# RN_CLI_VERSION (default latest). The bare apps use the template's defaults, which on RN 0.85+
# means React Native's prebuilt core; export RCT_USE_PREBUILT_RNCORE=0 to build RN from source.
#
# The PEER column says whether the version is inside the library's peerDependencies range. npm
# refuses to install outside it (prereleases included), so the bare apps install with
# --legacy-peer-deps and let the build decide; PEER doesn't affect the result. Below 0.85 the build
# fails with the library's #error, which the NOTE column shows.

# No -e: a failing step fails its row, and the run goes on to the next one.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PKG_NAME=$(node -p "require('$REPO/package.json').name") || exit 1
POD_NAME=ReactNativeTextBalancer
MIN_MINOR=85
WORK="${VERIFY_MATRIX_DIR:-${TMPDIR:-/tmp}/rntb-verify-matrix}"
LOGS="$WORK/logs"
CLI_VERSION="${RN_CLI_VERSION:-latest}"
SEMVER=semver@7.6.3
export LANG=en_US.UTF-8 # CocoaPods refuses to run without it

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

ref=HEAD
example=1
keep=0
list=0
requested=()
while (($#)); do
  case "$1" in
    --ref) [[ $# -ge 2 ]] || { echo "--ref needs a value" >&2; exit 2; }; ref="$2"; shift 2 ;;
    --no-example) example=0; shift ;;
    --keep) keep=1; shift ;;
    --list) list=1; shift ;;
    -h | --help) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) requested+=("$1"); shift ;;
  esac
done

sha=$(git -C "$REPO" rev-parse --verify "$ref^{commit}") || { echo "Not a commit: $ref" >&2; exit 2; }
lib_paths=(ios package.json "$POD_NAME.podspec" react-native.config.js)
if [[ "$ref" == HEAD && -n "$(git -C "$REPO" status --porcelain -- "${lib_paths[@]}")" ]]; then
  echo "warning: uncommitted library changes; the bare apps install ${sha:0:9} without them." >&2
fi

# --- Versions ---------------------------------------------------------------------------------

npm_versions=$(npm view react-native versions dist-tags --json) || { echo "npm view failed" >&2; exit 1; }

# Prints one exact version per line for the requested specs (or the default set).
resolve_versions() {
  NPM_VERSIONS="$npm_versions" node - "$MIN_MINOR" "$@" <<'JS'
const [minMinor, ...specs] = process.argv.slice(2);
const data = JSON.parse(process.env.NPM_VERSIONS);
const stable = data.versions.filter((v) => /^0\.\d+\.\d+$/.test(v));
const parse = (v) => v.split(/[.-]/).slice(0, 3).map(Number);
const latestPatch = (minor) =>
  stable.filter((v) => parse(v)[1] === minor).sort((a, b) => parse(a)[2] - parse(b)[2]).pop();
const rc = data['dist-tags'].next;
const out = [];
if (specs.length === 0) {
  const minors = [...new Set(stable.map((v) => parse(v)[1]))].filter((m) => m >= +minMinor);
  minors.sort((a, b) => a - b).forEach((m) => out.push(latestPatch(m)));
  if (rc && parse(rc)[1] > Math.max(...minors)) out.push(rc);
} else {
  for (const spec of specs) {
    let v;
    if (spec === 'rc') v = rc;
    else if (/^0\.\d+$/.test(spec)) v = latestPatch(+spec.split('.')[1]);
    else if (data.versions.includes(spec)) v = spec;
    if (!v) { console.error(`No react-native version matches "${spec}"`); process.exit(2); }
    out.push(v);
  }
}
console.log(out.join('\n'));
JS
}
versions=$(resolve_versions "${requested[@]+"${requested[@]}"}") || exit 2
((list)) && { echo "$versions"; exit 0; }

mkdir -p "$LOGS"

# --- What the commit ships --------------------------------------------------------------------

# The files npm packs from the commit: its `files` allowlist, plus the package.json, README and
# LICENSE npm always adds.
shipped_files=$(
  git -C "$REPO" show "$sha:package.json" |
    node -e 'for (const f of JSON.parse(require("fs").readFileSync(0)).files) console.log(f)' |
    xargs git -C "$REPO" ls-tree -r --name-only "$sha" --
  git -C "$REPO" ls-tree --name-only "$sha" | grep -E '^(package\.json|README|LICEN[CS]E)'
) || { echo "Can't read the files allowlist at ${sha:0:9}" >&2; exit 1; }
shipped_files=$(sort -u <<<"$shipped_files")
peer_range=$(git -C "$REPO" show "$sha:package.json" | node -p 'JSON.parse(require("fs").readFileSync(0)).peerDependencies["react-native"]')

# --- Helpers ----------------------------------------------------------------------------------

now() { date +%s; }
fmt_time() { printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); }

# Runs a command with its output appended to a log under a "===== <title>" header, so a failure's
# note can be read from its own section. Stdin is closed, so nothing eats the version list.
# Usage: step <log> <title> <command...>
step() {
  local log="$1" title="$2"
  shift 2
  printf '\n===== %s: %s\n' "$title" "$*" >>"$log"
  "$@" >>"$log" 2>&1 </dev/null
}

# The most useful line from the last step's section of a log: the library's #error if present,
# else the first error line, else the section's last line. Paths are cut to the file name.
first_error() {
  local section line
  section=$(awk '/^===== / { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$1")
  line=$(grep -m1 -E "error:.*${PKG_NAME} needs" <<<"$section") ||
    line=$(grep -m1 -E '(^|[^a-z])error:|ERR!|npm error|\[!\]|FAILURE:|What went wrong' <<<"$section") ||
    line=$(tail -n1 <<<"$section")
  sed -E 's#/[^ :]*/([^/ :]+)#\1#g; s/^[[:space:]]+//' <<<"$line" | tr '|' '/' | cut -c1-110
}

# Prints the paths that differ from what the commit ships; returns 1 if there are any.
check_package_files() {
  local installed
  installed=$(cd "$1" && find . -type f | sed 's#^\./##' | sort)
  comm -13 <(echo "$shipped_files") <(echo "$installed") | sed 's/^/unexpected: /'
  comm -23 <(echo "$shipped_files") <(echo "$installed") | sed 's/^/missing: /'
  [[ "$installed" == "$shipped_files" ]]
}

# Whether `pod install` linked the library into the app.
autolinked() { grep -q "^  - $POD_NAME " "$1"; }

# Debug build for any iOS simulator, unsigned. Usage: build_ios <log> <title> <workspace> <scheme>
#   <derived data dir>
build_ios() {
  step "$1" "$2" xcodebuild -workspace "$3" -scheme "$4" -configuration Debug -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$5" CODE_SIGNING_ALLOWED=NO build
}

join_notes() {
  local out="" note
  for note in "$@"; do [[ -n $note ]] && out+="${out:+; }$note"; done
  echo "$out"
}

# Rows of the result table. A row passes when every check it ran passed ("-" = not run).
rows=()
failed=0
# Usage: add_row <target> <install> <package> <pods> <build> <peer> <seconds> <note>
add_row() {
  local result=pass check
  for check in "$2" "$3" "$4" "$5"; do
    [[ $check == pass || $check == - ]] || result=FAIL
  done
  [[ $5 == pass ]] || result=FAIL # every row must get as far as a passing build
  [[ $result == pass ]] || failed=1
  rows+=("$1|$2|$3|$4|$5|$6|$result|$(fmt_time "$7")|$8")
  echo "  $1: $result${8:+: $8}"
}

# --- One bare app per RN version --------------------------------------------------------------

run_rn() {
  local ver="$1" start dir app log install=- package=- pods=- build=- peer notes=()
  start=$(now)
  dir="$WORK/rn-$ver"
  app="$dir/MatrixApp"
  log="$LOGS/rn-$ver.log"
  : >"$log"
  rm -rf "$dir"
  mkdir -p "$dir"
  echo "▶ RN $ver (log: $log)"

  if npx -y "$SEMVER" -r "$peer_range" "$ver" >/dev/null 2>&1; then peer=in; else peer=out; fi

  if step "$log" init npx -y "@react-native-community/cli@$CLI_VERSION" init MatrixApp \
      --version "$ver" --directory "$app" --pm npm --skip-install --skip-git-init \
      --install-pods false &&
    (cd "$app" && step "$log" install npm install --no-audit --no-fund --legacy-peer-deps \
      "$PKG_NAME@git+file://$REPO#$sha"); then
    install=pass
  else
    install=FAIL
    notes+=("$(first_error "$log")")
  fi

  if [[ $install == pass ]]; then
    local pkg_dir="$app/node_modules/$PKG_NAME" diff
    printf '\n===== package files\n' >>"$log"
    (cd "$pkg_dir" && find . -type f | sort) >>"$log"
    if diff=$(check_package_files "$pkg_dir"); then
      package=pass
    else
      package=FAIL
      notes+=("$(tr '\n' ' ' <<<"$diff")")
      printf '%s\n' "$diff" >>"$log"
    fi

    if ! (cd "$app/ios" && step "$log" pods pod install); then
      pods=FAIL
      notes+=("$(first_error "$log")")
    elif ! autolinked "$app/ios/Podfile.lock"; then
      pods=FAIL
      notes+=("$POD_NAME not autolinked")
    else
      pods=pass
      if build_ios "$log" build "$app/ios/MatrixApp.xcworkspace" MatrixApp "$dir/build"; then
        build=pass
      else
        build=FAIL
        notes+=("$(first_error "$log")")
      fi
    fi
  fi

  add_row "RN $ver" "$install" "$package" "$pods" "$build" "$peer" $(($(now) - start)) \
    "$(join_notes "${notes[@]+"${notes[@]}"}")"
  ((keep)) || rm -rf "$dir"
}

# --- The Expo example -------------------------------------------------------------------------

run_example() {
  local example_dir="$REPO/example" start log install_secs
  start=$(now)
  log="$LOGS/example.log"
  : >"$log"
  echo "▶ Expo example (log: $log)"

  # Installing runs `expo prebuild` (and `pod install`) through the example's postinstall.
  if ! (cd "$example_dir" && step "$log" install bun install); then
    local note
    note=$(first_error "$log")
    add_row "example iOS" FAIL - - - - $(($(now) - start)) "$note"
    add_row "example Android" FAIL - - - - 0 "$note"
    return
  fi
  install_secs=$(($(now) - start))

  local ios_start pods=FAIL build=- note=""
  ios_start=$(now)
  if autolinked "$example_dir/ios/Podfile.lock"; then
    pods=pass
    if build_ios "$log" "build iOS" "$example_dir/ios/TextBalancerExample.xcworkspace" \
        TextBalancerExample "$WORK/example-ios-build"; then
      build=pass
    else
      build=FAIL
      note=$(first_error "$log")
    fi
  else
    note="$POD_NAME not autolinked"
  fi
  add_row "example iOS" pass - "$pods" "$build" - $((install_secs + $(now) - ios_start)) "$note"
  ((keep)) || rm -rf "$WORK/example-ios-build"

  # One ABI is enough to compile everything; the library isn't linked on Android at all.
  local android_start build=FAIL note=""
  android_start=$(now)
  if (cd "$example_dir/android" && step "$log" "build Android" ./gradlew assembleDebug \
      -PreactNativeArchitectures=arm64-v8a --console=plain); then
    build=pass
  else
    note=$(first_error "$log")
  fi
  # Both example rows count the shared install time.
  add_row "example Android" pass - - "$build" - $((install_secs + $(now) - android_start)) "$note"
}

# --- Run --------------------------------------------------------------------------------------

echo "verify:matrix: $PKG_NAME at ${sha:0:9}, work dir $WORK"
echo "RN versions: $(tr '\n' ' ' <<<"$versions")"
while IFS= read -r v; do run_rn "$v"; done <<<"$versions"
((example)) && run_example

echo
fmt='%-17s %-8s %-8s %-6s %-6s %-5s %-7s %-7s %s\n'
printf "$fmt" TARGET INSTALL PACKAGE PODS BUILD PEER RESULT TIME NOTE
for row in "${rows[@]}"; do
  IFS='|' read -r target install package pods build peer result time note <<<"$row"
  printf "$fmt" "$target" "$install" "$package" "$pods" "$build" "$peer" "$result" "$time" "$note"
done
echo
((example)) && where=" The example: the working tree." || where=""
echo "Bare apps: ${sha:0:9}.$where Logs: $LOGS"
((failed)) && echo "verify:matrix FAILED" || echo "verify:matrix passed"
exit $failed
