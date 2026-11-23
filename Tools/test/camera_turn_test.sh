#!/bin/bash
# The camera turned back (Chris 9 Nov: Future City in other weather, like Inferno, "has the camera 180°
# turned"). Zoomed in (first person) a sideways mouse move turns the camera; the macro turns it in
# steps until your arrow on the minimap points the way the map's walk was made with. The arrow only
# tells 4 directions, so the turn is measured: it changes at 45° and at 135°. A fake camera here:
# each nudge turns it a set number of degrees. Chris 20 Nov: "if it points any way but up it will zoom in
# and then use arrow keys left or right to adjust the camera so it points upwards", "or mouse": the arrow
# keys first, the mouse when they don't turn it.
# A player 23 Nov (Classic, Ant Kingdom, debug_20261123_181647): "it walked off the wrong side of the map". The
# camera faced right, a quarter turn to up was logged, but the view was left at an angle: on a busy PC the screen
# shows the camera 0.1-0.2 s late, so the arrow changes were seen late and the key was let go late (15-30° off
# at this speed, still "up" on the arrow), and Ryn's walk went off sideways. Now it goes on through the wanted
# direction, back until it's seen there again (that way back measures how late the screen is), then half a
# quarter turn less that. The fake screen here can be behind by lagMs.
# Lib\Engine.ahk TurnCamera, KeyTurn, CamTurn, GoToSpot. Run under Wine
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
global fails := 0, logs := [], yaw := 0.0, perNudge := 7.0, nudges := 0, altDepth := 0
global keySpeed := 0.0, keyRev := false, keyDown := "", downAt := 0, keyHolds := 0, camKeySign := 1, camKeysWork := -1
global lagMs := 0, past := [], base := 0.0, stageStart := 1, shots := 0
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
    past.Push({t: A_TickCount, y: yaw, key: ""})
}
; what the camera faced at time t (for a screen lagMs behind): the last key or nudge before t, and since
YawAt(t) {
    y := base, k := "", at := 0
    for e in past
        if e.t <= t
            y := e.y, k := e.key, at := e.t
    return Mod(y + (k = "" ? 0 : (t - at) / 1000 * keySpeed * (k = "Right" ? 1 : -1) * (keyRev ? -1 : 1)) + 720, 360)
}
Stale() => 0
SaveDebugShot(p*) {
    global shots
    shots++
}
; the arrow keys: held, the fake camera turns keySpeed degrees a second (keyRev: the other way)
KeyYaw() => keyDown = "" ? 0 : (A_TickCount - downAt) / 1000 * keySpeed * (keyDown = "Right" ? 1 : -1) * (keyRev ? -1 : 1)
SendKeys(k) {
    global yaw, keyDown, downAt, keyHolds
    if RegExMatch(k, "^\{(Left|Right) down\}$", &m)
        yaw := Mod(yaw + KeyYaw() + 720, 360), keyDown := m[1], downAt := A_TickCount, keyHolds++
    else if RegExMatch(k, "^\{(Left|Right) up\}$")
        yaw := Mod(yaw + KeyYaw() + 720, 360), keyDown := ""
    past.Push({t: A_TickCount, y: yaw, key: keyDown})
}
Chk() => 0
MiniFacing() => Mod(Round((lagMs ? YawAt(A_TickCount - lagMs) : Mod(yaw + KeyYaw() + 720, 360)) / 90) * 90, 360)   ; like the arrow: 4 directions, changing at 45°
Off(a, b) => Abs(Mod(a - b + 540, 360) - 180)
''' + "\n".join(fn(n) for n in ["TurnCamera", "KeyTurn", "CamTurn", "FaceName", "RouteFace", "MiniFacingRead", "CamUnseen"]) + r'''

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

; the arrow keys HELD (Chris 20 Nov "use arrow keys"; 21 Nov "it's super slow": tapped, a turn took about
; 10 s before the Start vote). Chris's clip: a full circle in about 2.5 s held
for t in [[180, 0], [90, 0], [270, 0], [0, 90]] {
    yaw := t[1] + 0.0, keySpeed := 144.0, keyRev := false, camKeysWork := -1, perNudge := 7.0, nudges := 0, logs := []
    t0 := A_TickCount
    ok := TurnCamera(t[2]), took := A_TickCount - t0
    Check("arrow keys held, " FaceName(t[1]) " to " FaceName(t[2]) ": within 10°, under 3 s, no mouse", ok && Off(yaw, t[2]) <= 10 && took < 3000 && !nudges, Round(yaw) "° " took " ms " nudges " nudges")
}
Check("  told in the log", logs.Length && InStr(logs[logs.Length], "faced up") && InStr(logs[logs.Length], "a quarter right") && !InStr(logs[logs.Length], "mouse"), logs.Length ? logs[logs.Length] : "")
yaw := 90.0, keySpeed := 144.0, keyRev := true, camKeysWork := -1, nudges := 0, camKeySign := 1
ok := TurnCamera(0)
Check("arrow keys that turn it the other way on this account: still up", ok && Off(yaw, 0) <= 10 && !nudges, Round(yaw) "° " nudges)
Check("  and remembered for the next turns", camKeySign = -1, camKeySign)
keyRev := false, camKeySign := 1
yaw := 180.0, keySpeed := 0.0, camKeysWork := -1, perNudge := 7.0, nudges := 0, logs := []
t0 := A_TickCount
ok := TurnCamera(0), took1 := A_TickCount - t0
Check("the arrow keys don't turn it: the mouse does, the keys given up within 4.5 s", ok && Off(yaw, 0) <= 7 && nudges && took1 < 4500, Round(yaw) "° " took1 " ms " nudges " nudges")
Check("  told in the log", logs.Length && InStr(logs[1], "mouse"), logs.Length ? logs[1] : "")
yaw := 180.0, nudges := 0, keyHolds := 0
t0 := A_TickCount
ok := TurnCamera(0), took2 := A_TickCount - t0
Check("  the next turn goes straight to the mouse (the keys not tried again)", ok && took2 < 1000 && nudges && !keyHolds, took2 " ms, " keyHolds " key holds")
; the screen behind the camera (a busy PC): the arrow keys still land within 10°
for lag in [120, 200] {
    for t in [[90, 0], [270, 0], [180, 0], [0, 90]] {
        yaw := t[1] + 0.0, base := yaw, past := [], lagMs := lag, keySpeed := 144.0, keyRev := false, camKeySign := 1, camKeysWork := -1, nudges := 0, logs := []
        ok := TurnCamera(t[2])
        Sleep lag + 50
        Check("the screen " lag " ms behind (a busy PC), " FaceName(t[1]) " to " FaceName(t[2]) ": within 10°, keys only", ok && Off(yaw, t[2]) <= 10 && !nudges, Round(yaw) "° " nudges " nudges")
    }
}
yaw := 180.0, base := yaw, past := [], lagMs := 150, keyRev := true, camKeySign := 1, camKeysWork := -1, nudges := 0
ok := TurnCamera(0)
Check("  keys turning the other way on this account, a half turn, the screen 150 ms behind: within 10°", ok && Off(yaw, 0) <= 10 && !nudges, Round(yaw) "° " nudges)
keyRev := false, lagMs := 0
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
ok1 = bool(g) and "ZoomCamera(want)" in g.group(0) and "WalkFace" not in g.group(0)
ok2 = bool(z) and re.search(r"Click\s*\n(?:[^\n]*\n){0,6}?\s*if want >= 0\s*(?:;[^\n]*)?\n\s*TurnCamera\(want\)[^\n]*\n\s*MouseMove 400, 400", z.group(0)) is not None
print(("PASS" if ok1 else "FAIL") + " GoToSpot: the camera line-up (always up)")
print(("PASS" if ok2 else "FAIL") + " the line-up turns the camera while zoomed in (before tilting down), up for every walk")
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
k = re.search(r"^KeyTurn\([^)\n]*\) \{.*?^\}", e, re.S | re.M)
kb = k.group(0) if k else ""
print(("PASS" if '"{" key " down}"' in kb and "finally SendKeys(\"{\" key \" up}\")" in kb and '"Right"' in kb and '"Left"' in kb and "Chk()" in kb else "FAIL") + " the arrow key held: Left or Right, always let go (finally), Pause respected")
P2
WINEDEBUG=-all timeout 150 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'; [ "${PIPESTATUS[0]}" = 124 ] && echo "FAILED (timed out)")
rm -rf "$T"
if echo "$R" | grep -q "^FAIL"; then echo "$OUT" | grep -v "ALL PASSED"; echo "FAILED (static)"; else echo "$OUT"; fi
