#!/bin/bash
# A hill unit only goes on a hill (RNG 14 Nov): with no hill seen it tried the usual ground spots, then
# "Nothing could be placed... Back to spawn" twice, and gave up after 10 minutes. Now: no hill seen, the
# step is skipped; hills seen but nothing more fits, it moves on after a minute and never goes back to
# spawn ("skip the step and move on", "I need it nearby the main units for buffs"). The game is faked.
# Run under Wine
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
parts = [fn(n) for n in ["PlaceSlot", "PlaceSlotAt", "EnoughYen"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, yen := 99999, now := 0, tries := [], placedUnits := [], goodSpots := Map(), slotStops := Map()
global slotCap := Map(), walkedHere := true, curMap := "Mountain Temple", logs := "", respawns := 0
global hillOn := true, hillPts := [], fits := 0
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
HillSlot(n) => hillOn
HillPoints(n) => hillPts
TickNow() => now
SlotRoom(n, need) => need
SlotReady(n) => true
SlotCost(n) => 500
ReadYen() => yen
CountPlaced(n) => placedUnits.Length
CapKey(n) => n
NextToUnit(x, y) => false
StageOver() => now > 900000
Step(t) => 0
AddLog(t) {
    global logs
    logs .= t "|"
}
LearnSpot(n, p) => 0
TakeUnseen(n) => []
global upgradeMs := 0
UpgradePass(p*) {                                ; the upgrades done between tries take time
    global now
    now += upgradeMs
}
GoToSpot(p*) {
    global respawns
    respawns++
}
BuffTick() => 0
Wait(ms) {
    global now
    now += ms
}
; a try takes about 3 s; the first `fits` tries land, the rest don't (no room left on the hills)
TryPlace(x, y, n) {
    global now, tries, fits
    now += 3000, tries.Push(x "," y)
    if fits > 0 {
        fits--
        return true
    }
    return false
}
'''
body += "\n".join(parts) + "\n"
body += r'''
ground := []
loop 8
    ground.Push({x: 300 + A_Index * 20, y: 300})
NewCtx() => {lv: [6, 3, 6], pts: ground, used: Map(), fails: Map(), cursor: 1, build: true, over: false}

; no hill seen while holding it (Spirit Town, Navy Bay: no hills at all)
hillPts := [], tries := [], now := 0
got := PlaceSlot(NewCtx(), 5, 3)
Check("no hill seen: nothing placed, no ground spot tried", got.Length = 0 && tries.Length = 0, tries.Length " tries")
Check("  and no trip back to spawn", respawns = 0, respawns)

; hills seen, nothing fits on them (Mountain Temple, nothing of this alt down yet)
hillPts := [{x: 100, y: 120}, {x: 140, y: 120}, {x: 500, y: 110}], tries := [], now := 0, logs := "", fits := 0, respawns := 0
got := PlaceSlot(NewCtx(), 4, 4)
Check("nothing fits on the hills: moves on within about a minute", got.Length = 0 && now <= 80000, now)
Check("  never back to spawn", respawns = 0 && !InStr(logs, "Back to spawn"), logs)
Check("  never a ground spot", !InStr(StrJoin(tries), "300"), StrJoin(tries))
Check("  and says it's moving on", InStr(logs, "moving on"), logs)

; long rounds (upgrades between tries, RNG's log: "stopped at 2/4" after 2.5 minutes): the minute ends it
tries := [], now := 0, logs := "", fits := 0, placedUnits := [], respawns := 0, upgradeMs := 20000
ctx := NewCtx(), ctx.build := false
got := PlaceSlot(ctx, 4, 4)
Check("long rounds: still moves on after about a minute", got.Length = 0 && now <= 100000, now)
Check("  saying it's the hills", InStr(logs, "(hill unit): no more fit on the hills for a minute, moving on (0/4)"), logs)
upgradeMs := 0

; 2 fit, then no room: the 2 are kept, it moves on after a minute
tries := [], now := 0, logs := "", fits := 2, placedUnits := []
got := PlaceSlot(NewCtx(), 4, 4)
Check("2 of 4 fit: kept, moves on within about a minute of the last one", got.Length = 2 && now <= 100000, got.Length " placed, " now)

; a ground unit that fits nowhere after the walk: still back to spawn once, as before
hillOn := false, tries := [], now := 0, logs := "", fits := 0, placedUnits := [], respawns := 0
PlaceSlot(NewCtx(), 2, 1)
Check("a ground unit that fits nowhere after the walk: back to spawn as before", respawns >= 1, respawns)
StrJoin(a) {
    s := ""
    for v in a
        s .= v ";"
    return s
}
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 120 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
