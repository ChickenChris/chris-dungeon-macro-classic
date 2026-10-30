#!/bin/bash
# "The map is full" (the game's "Cannot place more than 20 units"): only believed once units are down.
# Ted's log: read at the very start with 0 placed, so every Place step got 0 and the build order ran
# out in one second. The red text reader is faked. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    return m.group(0) if m else (print("FAIL not defined: " + n) or n + '(p*) => ""')
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, fool := true, logs := "", said := "", mapFull := 0, placedUnits := [], stageStart := 1, slotCap := Map(), slotFull := Map()
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
LimitMessage(&txt := "") {
    txt := said
    return said = "" ? "" : "limit"
}
AddLog(t) {
    global logs
    logs .= t "|"
}
CountPlaced(n) => 0
FoolMode() => fool
CapKey(n) => n
FindUnseen(p*) => 0
SaveDebugShot(p*) => 0
Units(n) {
    global placedUnits := []
    loop n
        placedUnits.Push({slot: 1})
}
'''
body += "\n".join(fn(n) for n in ["PlaceRefused"]) + "\n"
body += "global foolOnly := " + ("true" if "!FoolMode() ||" in src else "false") + "\n"
body += r'''
said := "Cannot place more than 20 units! Sell some weaker ones to make room."
Units(0)
Check("nothing down yet: not taken as a full map", !PlaceRefused(1) && !mapFull, mapFull)
Check("what was read is logged once", InStr(logs, "not taken as the map being full"), logs)
Sleep 4100
Units(2)
Check("2 units down: still not", !PlaceRefused(2) && !mapFull, mapFull)
Sleep 4100
Units(19)
if foolOnly {
    Check("Fool's Hunt, 19 units down: the map is full", PlaceRefused(3) && mapFull, mapFull)
    Sleep 4100
    fool := false, mapFull := 0
    Check("a dungeon, 19 units down: not taken as full (only Fool's Hunt has that cap in players' logs)", !PlaceRefused(4) && !mapFull, mapFull)
} else
    Check("Classic (no Fool's Hunt): never taken as a full map, placing goes on", !PlaceRefused(3) && !mapFull, mapFull)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
