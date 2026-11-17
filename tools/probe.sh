#!/bin/bash
# Headless UI probe on a real device. The test runner synthesizes touches on the
# phone itself, so nothing on the Mac (mouse, keyboard, windows) is touched.
#
#   tools/probe.sh build                         build app + probe once
#   tools/probe.sh run 'launch <bundle>; shot x'  run a script, export attachments
#
# Output lands in /tmp/lune-probe/<run>/ as PNG screenshots and .txt trees.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${PROBE_DEVICE:-00008160-0019388904C14036}"
DERIVED="${PROBE_DERIVED:-/tmp/lune-probe-build}"
OUT_ROOT="/tmp/lune-probe"

case "${1:-}" in
build)
    xcodebuild build-for-testing \
        -project "$ROOT/lune/lune.xcodeproj" -scheme lune \
        -destination "platform=iOS,id=$DEVICE" \
        -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
        2>&1 | grep -E "error:|BUILD|TEST" || true
    ;;
run)
    script="${2:?script required}"
    stamp="$(date +%H%M%S)"
    result="$OUT_ROOT/$stamp.xcresult"
    out="$OUT_ROOT/$stamp"
    mkdir -p "$OUT_ROOT"
    xctestrun="$(ls "$DERIVED"/Build/Products/*.xctestrun | head -1)"
    TEST_RUNNER_PROBE_SCRIPT="$script" xcodebuild test-without-building \
        -xctestrun "$xctestrun" \
        -destination "platform=iOS,id=$DEVICE" \
        -resultBundlePath "$result" \
        2>&1 | grep -E "error|failed|Executed|TEST (SUCCEEDED|FAILED)" || true
    xcrun xcresulttool export attachments --path "$result" --output-path "$out" >/dev/null
    python3 - "$out" <<'PY'
import json, os, sys
out = sys.argv[1]
manifest = json.load(open(os.path.join(out, "manifest.json")))
for test in manifest:
    for att in test.get("attachments", []):
        src = os.path.join(out, att["exportedFileName"])
        name = att.get("suggestedHumanReadableName", att["exportedFileName"])
        base, ext = os.path.splitext(att["exportedFileName"])
        label = name.split("_")[0] if "_" in name else name
        dst = os.path.join(out, label + ext)
        os.rename(src, dst)
        print(dst)
PY
    ;;
*)
    echo "usage: $0 build | run '<script>'"
    exit 1
    ;;
esac
