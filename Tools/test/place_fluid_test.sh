#!/bin/bash
# Spots that adapt (Chris 9 Nov, Dungeon Throne): the camera sat close, Elyssia covered the middle and
# the game's red "can't place here" covered most of it; the next spots were all tried there, 6 s each.
# Red under a spot: skipped without a try (not a miss); a try that fails next to a unit: spots that
# close to units are skipped from then on. Lib\Engine.ahk PlaceSlotAt, NextToUnit. Run under Wine
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
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => ""'
parts = [fn(n) for n in ["PlaceSlot", "PlaceSlotAt", "EnoughYen", "NextToUnit", "PatternPoints", "SortByDistance"]]
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, now := 0, tries := 0, redSkips := 0, logs := [], placeRedSkip := false
global placedUnits := [], goodSpots := Map(), slotStops := Map(), slotCap := Map(), walkedHere := false, curMap := "Dungeon Throne"
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
HillSlot(n) => false
HillPoints(n) => []
SlotRoom(n, need) => need
SlotReady(n) => true
SlotCost(n) => 2000
ReadYen() => 7401
CountPlaced(n) => placedUnits.Length
CapKey(n) => n
StageOver() => now > 600000
Step(t) => 0
AddLog(t) => logs.Push(t)
LearnSpot(n, p) => 0
TakeUnseen(n) => []
UpgradePass(p*) => 0
GoToSpot(p*) => 0
BuffTick() => 0
Wait(ms) {
    global now
    now += ms
}
; the recording: red over the middle-left (the 3 of 5 spots tried there were mostly red), Elyssia's
; body over the rest of the middle (her own spot and 83 px from it failed)
IsRed(x, y) => x < 400 && !(x = 358 && y = 332)
TryPlace(x, y, n) {
    global tries, redSkips, placeRedSkip, now
    placeRedSkip := false
    if IsRed(x, y) {                            ; (what the real one does: red under it, no click)
        placeRedSkip := true, redSkips++, now += 400
        return false
    }
    tries++, now += 6000
    for u in placedUnits
        if (u.x - x) ** 2 + (u.y - y) ** 2 < 88 ** 2
            return false
    return true
}
'''
body += "\n".join(parts) + "\n"
body += r'''
placedUnits := [{x: 435, y: 300, slot: 1, maxed: false, capped: false, dx: 0, dy: -3, misses: 0, lost: false}]
ctx := {lv: [6, 2, 5], pts: PatternPoints("Circle"), used: Map("435,300", true), fails: Map(), cursor: 1, build: true, over: false}
got := PlaceSlot(ctx, 1, 1)
spot := got.Length ? got[1].x "," got[1].y : "none"
Check("the 2nd Elyssia placed", got.Length = 1, got.Length)
Check("  away from the first (not on her body): " spot, got.Length && (got[1].x - 435) ** 2 + (got[1].y - 300) ** 2 >= 88 ** 2)
Check("  few real tries (red spots skipped, her body skipped after it failed twice): " tries, tries <= 3, tries)
Check("  in well under a minute", now < 40000, now)
stopped := false
for m in logs
    stopped := stopped || InStr(m, "stopped at")
Check("  the red skips didn't end the step", !stopped)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
