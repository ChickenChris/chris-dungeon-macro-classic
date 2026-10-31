#!/bin/bash
# Placing without the yen: the try fails, and each failed try marked a good spot as bad, until there
# was "no place left to place the units" (Soru). Now a try that fails while the yen is under the
# unit's price waits for the yen and leaves the spot alone. The game is faked. Run under Wine
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
parts = [fn(n) for n in ["PlaceSlot", "EnoughYen"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, yen := 0, now := 0, tries := 0, placedUnits := [], goodSpots := Map(), slotStops := Map()
global slotCap := Map(), walkedHere := false, curMap := "Test", barShown := false, cost := 600, rate := 100
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
SlotRoom(n, need) => need
; the unit bar not seen (the case that tried without the yen): ready by the yen against the price
SlotReady(n) => barShown ? true : EnoughYen(n)   ; barShown: the card looks ready whatever the yen (the case Soru hit)
SlotCost(n) => cost
ReadYen() => yen
CountPlaced(n) => placedUnits.Length
CapKey(n) => n
NextToUnit(x, y) => false
StageOver() => now > 600000
Step(t) => 0
AddLog(t) => 0
LearnSpot(n, p) => 0
TakeUnseen(n) => []
UpgradePass(p*) => 0
GoToSpot(p*) => 0
BuffTick() => 0
Wait(ms) {
    global now, yen
    now += ms, yen += rate * ms // 1000
}
; a try: placed when the yen is there (and pays for it), otherwise fails
TryPlace(x, y, n) {
    global yen, tries
    tries++
    if yen < cost
        return false
    yen -= cost
    return true
}
'''
body += "\n".join(parts) + "\n"
body += r'''
pts := []
loop 6
    pts.Push({x: A_Index * 40, y: 300})
NewCtx() => {lv: [6, 3, 6], pts: pts, used: Map(), fails: Map(), cursor: 1, build: true, over: false}
ctx := NewCtx()
got := PlaceSlot(ctx, 1, 4)
Check("waits for the yen and places all 4", got.Length = 4, got.Length)
bad := 0
for k, v in ctx.fails
    bad += v
Check("no spot was marked bad for want of yen", bad = 0, bad)
Check("didn't try spot after spot without the yen", tries <= 8, tries)
; the card looks ready but the yen isn't there: the try fails, it waits, the spots stay good
yen := 0, now := 0, tries := 0, placedUnits := [], barShown := true
ctx := NewCtx()
got := PlaceSlot(ctx, 1, 4)
bad := 0
for k, v in ctx.fails
    bad += v
Check("card looks ready without the yen: still places all 4, no spot marked bad", got.Length = 4 && bad = 0, got.Length " placed, " bad " bad")
barShown := false
; the yen can't be read: tries as before
yen := 0, now := 0, tries := 0, placedUnits := [], cost := -1
ctx := NewCtx()
Check("price or yen unreadable: tries like before (no waiting)", (PlaceSlot(ctx, 1, 1), tries) >= 1 && now < 60000, tries " " now)
; the unit bar not seen and not enough yen: SlotReady says wait
cost := 600, yen := 100
Check("bar not seen, 100 of 600 yen: not ready", !SlotReady(1))
yen := 700
Check("bar not seen, 700 of 600 yen: ready", SlotReady(1))
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
