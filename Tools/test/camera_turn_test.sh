#!/bin/bash
# The camera turned back (Chris 9 Nov: Future City in other weather, like Inferno, "has the camera 180°
# turned"). Zoomed in (first person) a sideways mouse move turns the camera; the macro turns it in
# steps until your arrow on the minimap points the way the map's walk was made with. The arrow only
# tells 4 directions, so the turn is measured: it changes at 45° and at 135°. A fake camera here:
# each nudge turns it a set number of degrees. Lib\Engine.ahk TurnCamera, WalkFace, GoToSpot. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if not m:
        missing.append(n)
        return n + "(p*) => -1"
    return m.group(0)
alts = "global altDepth" in src
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, logs := [], yaw := 0.0, perNudge := 7.0, nudges := 0, altDepth := 0, walkFaces := Map()
global cfg := Map("walks", Map("Future City", "face:0,w+0,w-900,end@900", "Old Map", "w+0,w-500", "Clicked", "click:400,300"))
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
AddLog(t) => logs.Push(t)
WalkKey(m) => m
PlaceKey(m) => m
CamNudge(dir, px := 15) {                        ; the fake camera: a 15 px nudge turns it perNudge degrees
    global yaw, nudges
    yaw := Mod(yaw + dir * perNudge * px / 15 + 720, 360), nudges++
}
MiniFacing() => Mod(Round(yaw / 90) * 90, 360)   ; like the arrow: 4 directions, changing at 45°
Off(a, b) => Abs(Mod(a - b + 540, 360) - 180)
''' + "\n".join(fn(n) for n in ["TurnCamera", "FaceName", "RouteFace", "WalkFace"]) + r'''

for step in [3.0, 7.0, 11.0] {
    for t in [[0, 180], [180, 0], [0, 90], [0, 270], [270, 90]] {
        yaw := t[1] + 0.0, perNudge := step, nudges := 0, logs := []
        ok := TurnCamera(t[2])
        Check("facing " FaceName(t[1]) ", wanted " FaceName(t[2]) " (" step "° a nudge): turned to within " Round(step) "°", ok && Off(yaw, t[2]) <= step, Round(yaw) "° after " nudges " nudges")
    }
}
yaw := 190.0, perNudge := 5.0, logs := []
Check("not quite straight (190°), wanted up: lands on up", TurnCamera(0) && Off(yaw, 0) <= 5, Round(yaw))
Check("  told in the log", logs.Length && InStr(logs[logs.Length], "the camera faced down") && InStr(logs[logs.Length], "turned it round"), logs.Length ? logs[logs.Length] : "")
yaw := 180.0, perNudge := 0.0, nudges := 0, logs := []
Check("the camera doesn't turn (no first person): gives up", !TurnCamera(0) && nudges <= 75, nudges)
Check("  told in the log", logs.Length && InStr(logs[logs.Length], "couldn't turn the camera"), logs.Length ? logs[logs.Length] : "")
; an account whose camera turns slowly (Roblox's Camera Sensitivity is per account: RNG 10 Nov, his alt 2
; nudged for 18 s and its picture barely moved): bigger nudges after 25 without the arrow changing
for slow in [0.3, 0.8, 1.5] {
    for t in [[180, 0], [0, 90]] {
        yaw := t[1] + 0.0, perNudge := slow, nudges := 0, logs := []
        ok := TurnCamera(t[2])
        Check("a slow camera (" slow "° a nudge), " FaceName(t[1]) " to " FaceName(t[2]) ": turned, within " Round(slow * 16, 1) "°", ok && Off(yaw, t[2]) <= slow * 16, Round(yaw) "° after " nudges " nudges")
    }
}
Check("  the log says it turned slowly", logs.Length && InStr(logs[logs.Length], "turned slowly"), logs.Length ? logs[logs.Length] : "")
yaw := 180.0, perNudge := 7.0, nudges := 0, logs := []
TurnCamera(0)
Check("a normal camera: no word about it", logs.Length && !InStr(logs[logs.Length], "slowly"), logs.Length ? logs[logs.Length] : "")
yaw := 0.0, perNudge := 7.0, nudges := 0
Check("already the right way: not touched", TurnCamera(0) && !nudges, nudges)
Check("no direction wanted: not touched", !TurnCamera(-1) && !nudges, nudges)

; which way each map's camera should face: its walk's mark
Check("a marked walk: its direction", WalkFace("Future City") = 0, WalkFace("Future City"))
Check("an older walk without a mark: made the normal way (-2: up when the game flipped it)", WalkFace("Old Map") = -2, WalkFace("Old Map"))
Check("a Click to Move walk: none", WalkFace("Clicked") = -1, WalkFace("Clicked"))
Check("no walk (the spots still count): the normal way too", WalkFace("Nowhere") = -2, WalkFace("Nowhere"))
yaw := 180.0, perNudge := 7.0, logs := []
Check("normal way wanted, the camera flipped (down): turned up", TurnCamera(-2) && Off(yaw, 0) <= 7, Round(yaw))
yaw := 0.0, nudges := 0
Check("normal way wanted, it is: not touched", TurnCamera(-2) && !nudges, nudges)
yaw := 90.0, nudges := 0
TurnCamera(-2)
Check("normal way wanted, facing right (not the game's flip): not touched", !nudges && Off(yaw, 90) = 0, nudges)
if HASALTS {
    walkFaces["Old Map"] := 180, altDepth := 1
    Check("an alt, an older walk: the main's camera this stage", WalkFace("Old Map") = 180, WalkFace("Old Map"))
    altDepth := 0
    Check("the main, an older walk: the normal way", WalkFace("Old Map") = -2, WalkFace("Old Map"))
}
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
body = body.replace("HASALTS", "true" if alts else "false")
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
# the camera line-up turns it to the walk's direction before the walk
R=$(python3 - "$(pwd)" <<'P'
import re, sys
s = open(sys.argv[1] + "/Lib/Engine.ahk", encoding="utf-8-sig").read()
g = re.search(r"^GoToSpot\(.*?^\}", s, re.S | re.M); z = re.search(r"^ZoomCameraNow\(.*?^\}", s, re.S | re.M)
ok1 = bool(g) and "WalkFace(mapName)" in g.group(0) and "ZoomCamera(want)" in g.group(0)
ok2 = bool(z) and re.search(r"Click\s*\n\s*if want >= 0 \|\| want = -2\b[^\n]*\n\s*TurnCamera\(want\)", z.group(0)) is not None
print(("PASS" if ok1 else "FAIL") + " GoToSpot: the walk's direction to the camera line-up")
print(("PASS" if ok2 else "FAIL") + " the line-up turns the camera while zoomed in (before tilting down), walks without a mark too")
P
)
echo "$R"
OUT=$(# the nudge itself: a relative mouse move (what Roblox turns the camera by in first person), Pause respected
python3 - "$(pwd)" <<'P2'
import re, sys
e = open(sys.argv[1] + "/Lib/Engine.ahk", encoding="utf-8-sig").read()
f = re.search(r"^CamNudge\(dir, px := 15\) \{.*?^\}", e, re.S | re.M)
b = f.group(0) if f else ""
print(("PASS" if 'DllCall("mouse_event", "UInt", 0x0001, "Int", dir * px' in b and "MouseMove" not in b else "FAIL") + " the nudge is a relative mouse move, not MouseMove to a place")
print(("PASS" if "Chk()" in b else "FAIL") + " the nudge holds on Pause and stops on Stop")
P2
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r')
rm -rf "$T"
if echo "$R" | grep -q "^FAIL"; then echo "$OUT" | grep -v "ALL PASSED"; echo "FAILED (static)"; else echo "$OUT"; fi
