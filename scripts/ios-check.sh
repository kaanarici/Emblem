#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../ios"

journeys=false ratchet=false
for arg in "$@"; do
  case $arg in
    --journeys) journeys=true ;;
    --ratchet) ratchet=true ;;
    *) echo "unknown option $arg" >&2; exit 2 ;;
  esac
done

started=$SECONDS
step() { print -P "%F{cyan}── $1%f ($(( SECONDS - started ))s)"; }

MAX_LINES=600
baseline=file-length-baseline.txt
swift_files=("${(@f)$(find . -name '*.swift' -not -path './build*' -not -path '*/.build/*' -not -path './Emblem.xcodeproj/*' -not -path './tools/*' | sort)}")

step "swift-format rules (swift-format.json)"
findings=$(xcrun swift-format lint --parallel --configuration swift-format.json "${swift_files[@]}" 2>&1 \
  | grep -E "\[($(grep ': true' swift-format.json | grep -oE '"[A-Z][A-Za-z]+"' | tr -d '"' | paste -sd '|' -))\]" || true)
if [[ -n $findings ]]; then print -r -- "$findings"; exit 1; fi

step "file length (max $MAX_LINES code lines; $baseline only shrinks, keyed by file name so moves keep their limit)"
sizes=$(for file in "${swift_files[@]}"; do
  print "$(grep -cvE '^[[:space:]]*(//.*)?$' "$file") ${file:t}"
done)
over=$(awk -v max=$MAX_LINES -v base="$baseline" '
  BEGIN { while ((getline line < base) > 0) { split(line, f, " "); allowed[f[2]] = f[1] } }
  { limit = ($2 in allowed) ? allowed[$2] : max; if ($1 > limit) print $2 " has " $1 " lines (limit " limit ")" }' <<< "$sizes")
if $ratchet; then
  awk -v max=$MAX_LINES -v base="$baseline" '
    BEGIN { while ((getline line < base) > 0) { split(line, f, " "); allowed[f[2]] = f[1] } }
    ($2 in allowed) { n = ($1 < allowed[$2]) ? $1 : allowed[$2]; if (n > max) print n " " $2 }' <<< "$sizes" > "$baseline.next"
  mv "$baseline.next" "$baseline"
  echo "$baseline: $(wc -l < "$baseline" | tr -d ' ') files over $MAX_LINES."
fi
loose=$(awk 'NR == FNR { size[$2] = $1; next } !($2 in size) || size[$2] < $1 { print $2 }' <(print -r -- "$sizes") "$baseline")
if [[ -n $over ]]; then print -r -- "$over"; echo "Split the file; never raise the baseline."; exit 1; fi
if [[ -n $loose ]]; then print -r -- "$loose"; echo "These files shrank. Run scripts/ios-check.sh --ratchet."; exit 1; fi

step "xcodegen"
./generate-project.sh > /dev/null

simulator=${EMBLEM_SIMULATOR:-Emblem Check}
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["name"] == name and "iOS" in runtime: print(device["udid"]); raise SystemExit' "$simulator")
if [[ -z $udid ]]; then
  runtime=$(xcrun simctl list runtimes available -j | python3 -c 'import json,sys; print([r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS"][-1])')
  device_type=$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; print([d["identifier"] for d in json.load(sys.stdin)["devicetypes"] if d["name"].startswith("iPhone") and "Pro" in d["name"] and "Max" not in d["name"]][-1])')
  udid=$(xcrun simctl create "$simulator" "$device_type" "$runtime")
fi
destination="platform=iOS Simulator,id=$udid"
build=(-derivedDataPath build/DerivedData -quiet)
test=(test "${build[@]}" -collect-test-diagnostics never)

step "build Emblem for $simulator"
xcodebuild build -scheme Emblem -destination "$destination" "${build[@]}"

step "EmblemGenerationTests and contracts/fixtures (macOS)"
xcodebuild "${test[@]}" -scheme EmblemGenerationTests -destination platform=macOS

step "EmblemRecordingTests (Simulator)"
xcodebuild "${test[@]}" -scheme EmblemRecordingTests -destination "$destination"

if $journeys; then
  step "EmblemUITests journeys (Simulator)"
  xcodebuild "${test[@]}" -scheme EmblemUITests -destination "$destination"
fi

step "ios-check passed"
