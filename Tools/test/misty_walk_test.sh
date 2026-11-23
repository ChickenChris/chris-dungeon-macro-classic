#!/bin/bash
# Getting to the Misty Tower (Classic; UPD 21.5, Chris's clips 23 Nov). Play -> "Where do you want to Play?" ->
# Misty Village (the middle card, 400,323); from where it lands W to Flutter ("[E] Flutter"), E, her "[View
# Event Tower]" (the Misty Tower window). Not there: a fresh Play, then Roblox rejoined and once more.
# Lib\Misty.ahk FlutterLookIn, MistyToTower, MistyHold; Lib\Engine.ahk PlayTo. Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys, os
T, root = sys.argv[1], sys.argv[2]
eng = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
mis = open(f"{root}/Lib/Misty.ahk", encoding="utf-8-sig").read() if os.path.exists(f"{root}/Lib/Misty.ahk") else ""
missing = []
def fn(n, s):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", s, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) =>.*?(?=\n\S)", s, re.S | re.M)
    if m:
        return m.group(0).replace("WinGetClientPos &ox, &oy, , , RBX", "ox := 0, oy := 0")
    missing.append(n)
    return n + "(p*) => false"
fx = f"{root}/Tools/test/fixtures"; W = "Z:" + fx.replace("/", "\\")
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, RBX := "ahk_id 1", lg := "", held := Map(), heldMs := Map(), plays := 0, keysE := 0, clicks := ""
global vclock := 0, since := 0, frozenMs := 0, stuck := false, rejoins := 0, herReach := 999999, missWalking := false
global usePic := true, ringAfter := 1500, flutterAfter := 2000, ringOpen := false, atFlutter := false, flaky := false, looks := 0, talking := false, towerUp := false, reachable := true, t0s := Map()
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Fresh() => 0
Step(t) => 0
Stale() => 0
FocusRoblox() => 0
SaveDebugShot(p*) => 0
SceneSig() => [100 + Min(heldMs.Get("w", 0) + heldMs.Get("s", 0), 3000)]     ; walking changes the picture
TickNow() => vclock
AddLog(t) {
    global lg
    lg .= t "|"
}
Wait(ms) {                                      ; time passes: what's held walks
    global
    Sleep(Min(ms, 30))
    vclock += ms, since += ms
    if since <= frozenMs || stuck               ; frozen after the teleport / controls stuck: what's held doesn't walk
        return
    for k, on in held
        if on
            heldMs[k] := heldMs.Get(k, 0) + ms
    if reachable && held.Get("s", 0) && held.Get("d", 0) && heldMs.Get("s", 0) >= ringAfter
        ringOpen := true
    if reachable && held.Get("w", 0) && heldMs.Get("w", 0) >= flutterAfter
        atFlutter := heldMs.Get("w", 0) < flutterAfter + herReach     ; by her: her prompt stays; walked past: gone
}
SendKeys(k) {
    global held
    if RegExMatch(k, "^\{(\w+) (down|up)\}$", &m)
        held[m[1]] := m[2] = "down"
}
Keys(k) {
    global keysE, talking
    if k = "e" && atFlutter                     ; E by her opens her dialogue
        keysE++, talking := true
}
WaitFor(f, ms, step := 100) {
    t := A_TickCount
    while A_TickCount - t < ms {
        if f()
            return true
        Wait(step)
    }
    return f()
}
Clk(x, y, *) {
    global clicks, towerUp
    clicks .= x "," y ";"
    if x = 204 && y = 472 && talking
        towerUp := true
}
PlayTo(where) {
    global plays, held, heldMs, ringOpen, atFlutter, since
    plays++, heldMs := Map(), ringOpen := false, atFlutter := false, since := 0
    return where = "misty"
}
WaitAreaTeleport(before, needDark := false) => true
RejoinToLobby() {                               ; a fresh join: the controls work again
    global rejoins, stuck
    rejoins++, stuck := false
}
FlutterLook() {                                 ; flaky: her prompt read once, then missed (Chris 23 Nov, 04:35)
    global looks
    if !(reachable && atFlutter) || missWalking && held.Get("w", 0)   ; read while walking: missed (Chris 05:10)
        return false
    looks++                                     ; (reads by her: the 1st sees it, the next ones miss)
    return !flaky || looks <= 1 || looks >= 6
}
FlutterTowerAt(&x, &y) => talking ? (x := 204, y := 472, true) : false
TowerWindowUp() => towerUp
''' + "\n".join([fn("SigDiff", eng), fn("MistyHold", mis), fn("MistyRejoin", mis), fn("MistyGo", mis), fn("FlutterLookIn", mis), fn("MistyToTower", mis)]) + r'''

reachable := false, plays := 0, lg := "", rejoins := 0
ok := MistyToTower()
Check("Flutter not reached: a fresh Play, then Roblox rejoined and once more, then it says so", !ok && plays = 3 && rejoins = 1 && InStr(lg, "Flutter wasn't reached"), plays " plays, " rejoins " rejoins | " lg)
Check("  no key left held", !held.Get("w", 0))
reachable := true, held := Map(), plays := 0, keysE := 0, clicks := "", talking := false, towerUp := false
ok := MistyToTower()
Check("W to Flutter, E, her [View Event Tower]: the tower window", ok && plays = 1 && keysE = 1 && InStr(clicks, "204,472;"), plays " plays, E " keysE ", " clicks)
Check("  W let go", !held.Get("w", 0))
; Chris 23 Nov 04:35: the walk stopped at her prompt, a second read missed it and E was never pressed
reachable := true, held := Map(), plays := 0, keysE := 0, clicks := "", talking := false, towerUp := false, flaky := true, looks := 0
global keysAny := 0
ok := MistyToTower()
Check("her prompt seen once, then missed: E pressed anyway, the tower window", ok && plays = 1 && InStr(clicks, "204,472;"), plays " plays, " clicks)
flaky := false
; Chris 23 Nov 04:47-04:49 (debug_044742, 044850, his clip): at night the character stood still for 5-13 s after
; the teleport with W held, then walked; the 6 s were over before he moved ("now you are just not walking")
reachable := true, held := Map(), plays := 0, keysE := 0, clicks := "", talking := false, towerUp := false, frozenMs := 10000, lg := ""
ok := MistyToTower()
Check("frozen 10 s after the teleport: W stays held until he walks, Flutter reached on the first Play", ok && plays = 1 && InStr(clicks, "204,472;"), plays " plays, " clicks " | " lg)
held := Map(), plays := 0, keysE := 0, clicks := "", talking := false, towerUp := false, frozenMs := 999999, lg := "", rejoins := 0
ok := MistyToTower()
Check("  never moving: a fresh Play, a rejoin and once more, then it says he didn't move", !ok && plays = 3 && rejoins = 1 && InStr(lg, "didn't move"), plays " plays, " rejoins " rejoins | " lg)
Check("  W let go", !held.Get("w", 0))
frozenMs := 0
; Chris 23 Nov 04:47-05:03: the very first walk worked; after the tower window was left open (04:42) W never moved
; him again, day or night, after every Play (05:03 clip: standing still with W held). A fresh join fixes the game's
; controls: Roblox rejoined for the last try
held := Map(), plays := 0, keysE := 0, clicks := "", talking := false, towerUp := false, stuck := true, rejoins := 0, lg := ""
ok := MistyToTower()
Check("controls stuck: Roblox rejoined, then W to Flutter and the tower window", ok && rejoins = 1 && InStr(clicks, "204,472;") && InStr(lg, "rejoin"), plays " plays, " rejoins " rejoins, " clicks " | " lg)
stuck := false
; Chris 23 Nov 05:10 (debug_051004): "[E] Flutter" showed for about a second as he walked by her, the looks while
; walking missed it and he walked on into the curtains: "now you dont click E". By her, it's looked for standing
; still (short steps, as for the Elf Mage)
held := Map(), plays := 0, keysE := 0, clicks := "", talking := false, towerUp := false, rejoins := 0, lg := "", herReach := 1000, missWalking := true
ok := MistyToTower()
Check("her prompt only read standing still, gone a step past her: E by her, the tower window on the first Play", ok && plays = 1 && keysE = 1 && InStr(clicks, "204,472;"), plays " plays, E " keysE ", " clicks " | " lg)
Check("  W let go", !held.Get("w", 0))
herReach := 999999, missWalking := false
Check("her prompt: [E] Flutter, also read as E] Flutter / (E) Flutter / [El Flutter", FlutterLookIn("[E] Flutter") && FlutterLookIn("Lvl 245`n[E] Flutte") && FlutterLookIn("E] Flutter") && FlutterLookIn("(E) Flutter") && FlutterLookIn("[El Flutter") && !FlutterLookIn("Flutter, Demon Girl and Lovey") && !FlutterLookIn("[E] Elf Mage"))
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
body = body.replace("ROOT", "Z:" + root.replace("/", "\\")).replace('"W\\', '"' + W + "\\")
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
pt = re.search(r"^PlayTo\(where\) \{.*?^\}", eng, re.S | re.M)
print(("PASS" if pt and re.search(r'"misty" \? 400', pt.group(0)) else "FAIL") + " PlayTo(\"misty\"): the Misty Village card (400,323)")
print(("PASS" if re.search(r'"Misty Village", \[\]', eng) else "FAIL") + " Misty Village is a map (spots, walks and build order for it)")
print(("PASS" if mis and not re.search(r"MistyToStages|StartMisty|PortalAltsIn|PartyEnsure|FoolAltsToLobby", mis) else "FAIL") + " Classic: the tower only, no Misty Village stages, no alts")
P
WINEDEBUG=-all timeout 120 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
