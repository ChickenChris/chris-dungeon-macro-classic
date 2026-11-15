#!/bin/bash
# Units the game says are down but whose menu wasn't seen (Lib\Engine.ahk UnitHereIs, used by FindUnseen):
# each spot is clicked and the unit's menu waited for as long as placing waits (the Placement speed), not
# 0.7 s. On a PC where the menu was too slow to be seen while placing, 0.7 s never found it either
# (Apocalypse 15 Nov: "2 of them got placed without the macro seeing it", none found, slot 3 never
# upgraded). Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" <<'P'
import re, sys
src = open("Lib/Engine.ahk", encoding="utf-8-sig").read()
fns = [re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M).group(0) for n in ["UnitHereIs", "PlaceTimeout"]]
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
global fails := 0, cfg := Map("placeSpeed", 3), waited := [], menuAfter := 0, slotMenuName := Map(3, "Elyssia")
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8"), fails += !ok
}
ClearVote() => 0
UnitMenuOpen() => false
CloseMenuClick() => 0
Wait(ms) => 0
Clk(x, y) => 0
WaitUnitMenu(ms) => (waited.Push(ms), menuAfter && ms >= menuAfter)   ; the menu shows after menuAfter ms
NewMenu() => true
IsSummonMenu() => false
MenuUnitName() => "Elyssia"
NameAlike(a, b) => a = b
OtherSlotName(n, s) => false
''' + "\n".join(fns) + r'''
cfg["placeSpeed"] := 3, waited := [], menuAfter := 1500
Check("Placement speed 2 s: the menu waited up to 2 s (it showed after 1.5 s: found)", UnitHereIs(3, 300, 250) && waited.Length && waited[1] >= 2000, waited.Length ? waited[1] : "")
cfg["placeSpeed"] := 6, waited := [], menuAfter := 3500
Check("Placement speed 4 s (slower): up to 4 s", UnitHereIs(3, 300, 250) && waited[1] >= 4000, waited.Length ? waited[1] : "")
cfg["placeSpeed"] := 1, waited := [], menuAfter := 600
Check("Placement speed 1 s: never under 0.7 s", UnitHereIs(3, 300, 250) && waited[1] >= 700, waited.Length ? waited[1] : "")
menuAfter := 0, waited := []
Check("no unit there: not taken", !UnitHereIs(3, 300, 250))
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
