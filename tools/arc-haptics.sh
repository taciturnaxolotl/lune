#!/bin/bash
# Log every haptic Arc Search plays, live, by attaching lldb to it on this Mac.
#
# Needs: Arc Search installed from the Mac App Store (iPhone & iPad Apps), and SIP with
# debugging restrictions disabled (atalanta's custom config has this).
#
#   tools/arc-haptics.sh            attach to a running Arc Search and log until Ctrl-C
#
# Output: one line per call with the generator class, style/intensity and the Arc frames
# that triggered it, also appended to /tmp/arc-haptics.log.
set -euo pipefail

pid="$(pgrep -f 'ArcMobile2|Arc Search' | head -1 || true)"
if [ -z "$pid" ]; then
    echo "Arc Search is not running. Open it on this Mac first." >&2
    exit 1
fi

script="$(mktemp -t arc-haptics).py"
cat > "$script" <<'PY'
import lldb

STYLES = {0: "light", 1: "medium", 2: "heavy", 3: "soft", 4: "rigid"}
NOTIFY = {0: "success", 1: "warning", 2: "error"}
LOG = open("/tmp/arc-haptics.log", "a", buffering=1)

def caller(frame):
    thread = frame.GetThread()
    names = []
    for i in range(1, min(thread.GetNumFrames(), 14)):
        f = thread.GetFrameAtIndex(i)
        module = f.GetModule().GetFileSpec().GetFilename() or ""
        name = f.GetFunctionName() or ""
        if "Arc" in module or "arc" in module.lower():
            names.append(name)
        if len(names) >= 3:
            break
    return " <- ".join(names) or "(no Arc frame)"

def report(frame, text):
    line = f"{text}   {caller(frame)}"
    print(line)
    LOG.write(line + "\n")

def on_init(frame, bp_loc, extra, internal):
    style = frame.FindRegister("x2").GetValueAsUnsigned()
    report(frame, f"init impact style={STYLES.get(style, style)}")
    return False

def on_impact(frame, bp_loc, extra, internal):
    obj = frame.FindRegister("x0").GetValueAsUnsigned()
    intensity = frame.FindRegister("d0").GetValue()
    style = frame.EvaluateExpression(f"(long)[(id){obj} _style]").GetValueAsSigned()
    report(frame, f"impact style={STYLES.get(style, style)} intensity={intensity}")
    return False

def on_impact_plain(frame, bp_loc, extra, internal):
    obj = frame.FindRegister("x0").GetValueAsUnsigned()
    style = frame.EvaluateExpression(f"(long)[(id){obj} _style]").GetValueAsSigned()
    report(frame, f"impact style={STYLES.get(style, style)} intensity=default")
    return False

def on_selection(frame, bp_loc, extra, internal):
    report(frame, "selection changed")
    return False

def on_notify(frame, bp_loc, extra, internal):
    kind = frame.FindRegister("x2").GetValueAsUnsigned()
    report(frame, f"notification {NOTIFY.get(kind, kind)}")
    return False

def on_chhaptic(frame, bp_loc, extra, internal):
    report(frame, f"CoreHaptics {frame.GetFunctionName()}")
    return False

def __lldb_init_module(debugger, internal_dict):
    target = debugger.GetSelectedTarget()
    hooks = [
        ("-[UIImpactFeedbackGenerator initWithStyle:]", "on_init"),
        ("-[UIImpactFeedbackGenerator impactOccurredWithIntensity:]", "on_impact"),
        ("-[UIImpactFeedbackGenerator impactOccurredWithIntensity:atLocation:]", "on_impact"),
        ("-[UIImpactFeedbackGenerator impactOccurred]", "on_impact_plain"),
        ("-[UISelectionFeedbackGenerator selectionChanged]", "on_selection"),
        ("-[UISelectionFeedbackGenerator selectionChangedAtLocation:]", "on_selection"),
        ("-[UINotificationFeedbackGenerator notificationOccurred:]", "on_notify"),
        ("-[CHHapticEngine startWithCompletionHandler:]", "on_chhaptic"),
        ("-[CHHapticPatternPlayer startAtTime:error:]", "on_chhaptic"),
    ]
    for symbol, handler in hooks:
        bp = target.BreakpointCreateByName(symbol)
        bp.SetScriptCallbackFunction(f"{__name__}.{handler}")
        bp.SetAutoContinue(True)
        print(f"hooked {symbol}: {bp.GetNumLocations()} location(s)")
    print("Tap around Arc. Ctrl-C to stop.")
PY

echo "Attaching to Arc Search (pid $pid). Log: /tmp/arc-haptics.log"
exec lldb -p "$pid" \
    -o "command script import $script" \
    -o "process continue"
