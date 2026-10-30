#!/bin/bash
# One placing try, kept simple as before 25 Oct (Chris: placing was fluid then): slot key, click, cancel,
# the unit's menu. No red-message read outside Fool's Hunt and no second click on a failed spot once
# the menu is known to open by itself (a player's log: ~40 s per unit on a slower PC). The game is faked
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
m = re.search(r"^TryPlace\([^)\n]*\) \{.*?^\}", src, re.S | re.M)
fn = m.group(0) if m else (print("FAIL not defined: TryPlace") or "TryPlace(p*) => false")
flag = "true" if "refusals := FoolMode()" in fn else "false"
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, reads := 0, clicks := "", menuNext := false, fool := false, placeUnsure := Map()
global autoOpenSeen := true, autoOpenOff := false, clickOpened := 0
global foolChecks := ''' + flag + r'''
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
FoolMode() => fool
PlaceRefused(slot) {
    global reads
    reads++
    return false
}
ClearVote() => 0
VoteOnScreen() => false
ClosePanel() => 0
UnitMenuOpen() => false
Keys(k) => 0
Clk(x, y, p*) {
    global clicks
    clicks .= x "," y ";"
}
WaitUnitMenu(ms) {
    global menuNext
    r := menuNext, menuNext := false
    return r
}
PlaceTimeout() => 900
NearUnit(p*) => false
ReadLevel() => 0
MaxShown() => false
CheckAbility(p*) => 0
SettingsInTheWay() => false
Wait(ms) => 0
AddLog(t) => 0
SaveDebugShot(t) => 0
''' + fn + r'''
; a failed spot in a dungeon: one click, nothing read
clicks := "", reads := 0
ok := TryPlace(300, 300, 1)
Check("a failed spot (dungeon): not placed", !ok)
Check("no red-message read outside Fool's Hunt", reads = 0, reads)
Check("the spot clicked once, not a second time to look for a unit", clicks = "300,300;", clicks)
; a placed unit: the menu opens, closed
clicks := "", menuNext := true
Check("a placed unit: true, its menu closed", TryPlace(340, 300, 1) && InStr(clicks, "325,185;"), clicks)
; the menu doesn't open by itself on this PC: the spot is clicked to look (as before)
autoOpenSeen := false, autoOpenOff := true, clicks := ""
TryPlace(380, 300, 1)
Check("menu never opens by itself: the spot clicked again to look", clicks = "380,300;380,300;", clicks)
autoOpenSeen := true, autoOpenOff := false
if foolChecks {
    fool := true, reads := 0
    TryPlace(420, 300, 1)
    Check("Fool's Hunt: the red message is looked for (its 20-unit cap)", reads >= 1, reads)
}
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
