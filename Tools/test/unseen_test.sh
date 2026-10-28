#!/bin/bash
# Units placed without their menu showing (Lib\Engine.ahk FindUnseen / TakeUnseen and the game's
# "more than N of this unit" number), run under Wine on their own
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" <<'P'
import re, sys
src = open("Lib/Engine.ahk", encoding="utf-8-sig").read()
fns = [re.search(r"^" + n + r"\(.*?^\}", src, re.S | re.M).group(0) for n in ["NearUnit", "FindUnseen", "TakeUnseen"]]
most = re.search(r'most := RegExMatch\(said, "([^"]+)"', src).group(1)
body = """#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
global placedUnits := [], placeUnsure := Map(), unseenFound := []
fails := 0
Check(name, ok) {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*", "UTF-8"), fails += !ok
}
U(x, y, s) => {x: x, y: y, slot: s, maxed: false, capped: false, dx: 0, dy: -3, misses: 0, lost: false}
""" + "\n".join(fns) + f"""
Most(said) => RegExMatch(said, "{most}", &mm) ? Integer(RegExReplace(mm[1], "[Oo]", "0")) : 0
Check("the game's number read from 'tttan 3'", Most("Wave 2 Current Eff Cannot place more tttan 3 of this unit") = 3)
Check("and from 'than 3'", Most("Cannot place more than 3 of this unit!") = 3)
Check("and 'than 1O'", Most("Cannot place more than 1O units") = 10)
; Skyyylyyyy: two Speedwagons seen, the third went down at a spot where no menu showed
placedUnits.Push(U(100, 100, 5), U(140, 100, 5))
placeUnsure[5] := [{{x: 300, y: 300}}, {{x: 180, y: 100}}]
Check("one unseen unit found", FindUnseen(5, 1) = 1)
Check("at the latest spot without a menu", placedUnits.Length = 3 && placedUnits[3].x = 180)
got := TakeUnseen(5)
Check("handed to the placing step once", got.Length = 1 && got[1].x = 180 && TakeUnseen(5).Length = 0)
; a spot where a counted unit already stands isn't a new unit
placeUnsure[2] := [{{x: 100, y: 100}}]
placedUnits.Push(U(100, 100, 2))
Check("a spot of a counted unit is skipped", FindUnseen(2, 1) = 0 && placedUnits.Length = 4)
Check("no spots, nothing found", FindUnseen(4, 2) = 0)
; other slots' found units stay for their own step
placeUnsure[1] := [{{x: 500, y: 200}}], placeUnsure[3] := [{{x: 600, y: 200}}]
FindUnseen(1, 1), FindUnseen(3, 1)
Check("each slot takes only its own", TakeUnseen(3).Length = 1 && unseenFound.Length = 1 && unseenFound[1].slot = 1)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
"""
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 60 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
