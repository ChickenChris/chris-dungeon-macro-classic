#!/bin/bash
# The room's small font: an 8 read as a 0 (Alex: "every room 18 it thinks it's room 10"). Rooms go
# up one at a time, so a number that doesn't fit but does with a 0/3/6/9 <-> 8 swap is taken as that.
# Room 1 (a new dungeon) and numbers that fit are never changed. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
m = re.search(r"^SaneDepth\([^)\n]*\) \{.*?^\}", src, re.S | re.M)
part = m.group(0) if m else 'SaneDepth(d) => (FileAppend("FAIL SaneDepth not defined`n", "*"), d)'
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, logs := "", prevDepth := "", curDepth := ""
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
AddLog(t) {
    global logs
    logs .= t "|"
}
; a new stage, as LoadStage does it: the room before is kept, this room's number read
Room(read) {
    global prevDepth := curDepth, curDepth := SaneDepth(read)
    return curDepth
}
'''
body += part + "\n"
body += r'''
Room(16), Room(17)
Check("room 18 read as 10: 18, and says so", (r := Room("10")) = 18 && InStr(logs, "read as 10, taken as 18"), r " " logs)
Check("the same room again after a loss, misread again: 18", (r := Room("10")) = 18, r)
Check("read right: 19", (r := Room("19")) = 19, r)
Check("a new dungeon's room 1 is never changed", (r := Room("1")) = 1, r)
Check("room 3 read as 8: 3", (Room("2"), r := Room("8")) = 3, r)
Check("room 8 read as 6: 8", (Room("4"), Room("5"), Room("6"), Room("7"), r := Room("6")) = 8, r)
Check("a number that fits is kept: 10 after 9", (Room("9"), r := Room("10")) = 10, r)
Check("nothing fits: kept as read", (r := Room("14")) = 14, r)
Check("no room before: kept as read", (curDepth := "", r := Room("10")) = 10, r)
Check("no number: stays empty", (r := Room("")) = "", r)
Check("banner read again later in the same room: kept", (curDepth := 18, prevDepth := 17, SaneDepth("10")) = 18)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
