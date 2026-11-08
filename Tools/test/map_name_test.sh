#!/bin/bash
# Map names read off the room panel / loading screen (Lib\Engine.ahk: MatchMapName). Cases are real
# text from players' logs. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if not m:
        sys.exit("not found: " + n)
    return m.group(0)
names = ["MatchMapName", "MatchMapStrict", "MatchMapLoose", "FoldLoose", "ScoreMapName", "FoldOcr", "NormName", "Levenshtein", "LoadingScreens", "WordSim", "LcsLen"]
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0
Check(txt, want) {
    global fails
    got := MatchMapName(txt)
    ok := got = want
    FileAppend((ok ? "PASS " : "FAIL ") "[" txt "] -> " (got = "" ? "(none)" : got) (ok ? "" : " (want " (want = "" ? "(none)" : want) ")") "`n", "*", "UTF-8")
    fails += !ok
}
''' + "\n".join(fn(n) for n in names) + r'''

; Chris 8 Nov: a Future City room whose map line wasn't read was taken as Dungeon Throne
; (the panel's own "DUNGEON DEPTH" title before "Dungeon Room"): no map is better than a wrong one
Check("DUNGEON DEPTH: 2/20 Dungeon Room Deptf:fi DIFFICULT V:", "")
Check("DUNGEON DEPTH: 2/20 Dungeon Room Deptff:fi DIFFICULT V:", "")
Check("DUNGEON DEPTH : Dungeon Room Deptf:fi DIFFICULT V:", "")
; still read as before
Check("DUNGEON DEPTH : Dungeon Room St range Toun DIFFICUL T V : CUEBT", "Strange Town")
Check("DUNGEON DEPTH: 2/20 Dungeon Room Future City Depth: 2 DIFFICULTY:", "Future City")
Check("DUNGEON DEPTH: 5/20 Dungeon Room Dungeon Throne Depth: 5", "Dungeon Throne")
Check("Dungeon Throne Dungeon Room", "Dungeon Throne")
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
[ -n "$KEEP" ] && echo "$T" || rm -rf "$T"
