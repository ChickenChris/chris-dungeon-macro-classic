#!/bin/bash
# The map off the minimap (Lib\Engine.ahk MinimapMap and Lib\minimaps.txt), run under Wine on its own:
# a few of the saved shapes are held out of the list and must still be read as their map, and a map
# with no shape in the list must not be read as another one
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d); mkdir "$T/Lib"
python3 - "$T" <<'P'
import re, sys
T = sys.argv[1]
src = open("Lib/Engine.ahk", encoding="utf-8-sig").read()
fns = [re.search(r"^" + n + r"\(.*?^\}", src, re.S | re.M).group(0) for n in ["MinimapMap", "MinimapNear", "MinimapSim", "MinimapRefs", "MinimapOverBanner"]]
lines = open("Lib/minimaps.txt", encoding="ascii").read().splitlines()
held, keep = [], []
# the last shape of these maps is held out; Haunted Academy (Summer) has one shape, so it's then unknown
want = {"Fabled Kingdom": "Fabled Kingdom", "Otherwordly Plane": "Otherwordly Plane", "Assassin Park": "Assassin Park",
        "Cursed Festival": "Cursed Festival", "Shibuya District": "Shibuya District", "Storm Hideout": "Storm Hideout",
        "Sky Island": "Sky Island", "Magic Town": "Magic Town", "Haunted Academy (Summer)": ""}
last = {}
for i, l in enumerate(lines):
    n = l.split("|")[0]
    if n in want: last[n] = i
for i, l in enumerate(lines):
    n = l.split("|")[0]
    (held if last.get(n) == i else keep).append(l)
assert len(held) == len(want), held
open(T + "/Lib/minimaps.txt", "w", newline="\r\n").write("\n".join(keep) + "\n")
checks = "\n".join(f'Held("{l.split("|")[0]}", "{l.split("|")[1]}", "{want[l.split("|")[0]]}")' for l in held)
body = """#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
global testCells := [], curMap := "Unknown", mapHow := "", logged := ""
fails := 0
AddLog(t) {
    global logged
    logged := t
}
UpdateMapLabel() => 0
Check(name, ok) {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*", "UTF-8"), fails += !ok
}
MinimapCells() => testCells
HexCells(h) {
    cells := []
    loop 32 {
        y := A_Index - 1, v := Integer("0x" SubStr(h, y * 8 + 1, 8))
        loop 32
            if (v >> (32 - A_Index)) & 1
                cells.Push(y * 34 + A_Index - 1)
    }
    return cells
}
Held(map, hex, expect) {
    global testCells
    testCells := HexCells(hex)
    got := MinimapMap(&score, &guess)
    Check(map " held out: read as '" got "' (" Round(score * 100) "%, closest " guess "), want '" expect "'", got = expect)
}
""" + "\n".join(fns) + "\n" + checks + """
; the blue name misread as Snowy Town on Otherwordly Plane (Ikyuuko): the minimap wins when sure or backed up
curMap := "Snowy Town"
Check("a 98 % minimap wins over the blue name", MinimapOverBanner("Snowy Town", "Otherwordly Plane", 0.98, "") && curMap = "Otherwordly Plane" && mapHow = "minimap")
curMap := "Snowy Town"
Check("an 85 % minimap wins when the loading screen said the same", MinimapOverBanner("Snowy Town", "Otherwordly Plane", 0.85, "Otherwordly Plane") && curMap = "Otherwordly Plane")
curMap := "Snowy Town"
Check("an 85 % minimap on its own doesn't", !MinimapOverBanner("Snowy Town", "Otherwordly Plane", 0.85, "Snowy Town") && curMap = "Snowy Town")
Check("Planet Greenie (Summer) isn't swapped for Planet Greenie", !MinimapOverBanner("Planet Greenie (Summer)", "Planet Greenie", 0.99, ""))
Check("no minimap, the blue name stays", !MinimapOverBanner("Cursed Festival", "", 0, ""))
testCells := [5, 6, 7]
Check("a few green specks aren't a path", MinimapMap() = "")
testCells := []
Check("no path, no map", MinimapMap() = "")
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
"""
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 60 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
