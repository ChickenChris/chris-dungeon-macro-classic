#!/bin/bash
# Summer Hunt, Play Here after a Replay: no loading screen, so the green title names the map. It was read as
# the round loaded, under the "Vote start" panel, and not again: a player's log 11 Nov, "Couldn't read the
# map's name in the round ... Last text read: wave o" on Future City (5 times on 10 Nov). Read again after
# the start countdown. Lib\Engine.ahk SummerRoundMap. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
f = re.search(r"^SummerRoundMap\(\) \{.*?^\}", src, re.S | re.M).group(0)
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, curMap := "Unknown", mapHow := "", lastMapRaw := "", logs := [], cfg := Map(), titleReads := 0, titleAfter := 2
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
AddLog(t) => logs.Push(t)
Step(t) => 0
Wait(ms) => 0
UpdateMapLabel() => 0
MinimapNote(p*) => ""
MinimapOverBanner(p*) => false
SameMap(a, b) => a = b
MapFromBanner() => (lastMapRaw := "wave o", "")
MinimapMap(&s := 0) => (s := 0.46, "")            ; Windy Future City: no match
; the green title: under the Vote start panel at first (nothing read), there from the 2nd read on
SummerTitleMap(timeout) {
    global titleReads
    titleReads++
    return titleReads >= titleAfter ? "Future City" : ""
}
''' + f + r'''

SummerRoundMap()
Check("Play Here after a Replay: the title read again after the countdown", curMap = "Future City", curMap)
Check("  the log says so", logs.Length && InStr(logs[logs.Length], "Map: Future City") && InStr(logs[logs.Length], "green title"), logs.Length ? logs[logs.Length] : "")
; Find Match: the title is the hour's map, not this round's: not trusted, as before
global curMap := "Unknown", titleReads := 0, logs := []
cfg["foolMatch"] := 1
SummerRoundMap()
Check("Find Match: the title isn't used (it names the hour's map)", curMap = "Unknown", curMap)
cfg["foolMatch"] := 0
; the title never shows: Unknown (the auto pattern), as before
global curMap := "Unknown", titleReads := 0, titleAfter := 99
SummerRoundMap()
Check("no title at all: still Unknown", curMap = "Unknown", curMap)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 120 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
