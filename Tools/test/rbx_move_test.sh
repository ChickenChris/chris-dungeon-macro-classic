#!/bin/bash
# The mouse blocked by Windows (Chris 25 Nov: Legend Stage, Summer Hunt and Artifact all did nothing; the log
# only said "The mouse only moved with SetCursorPos (the normal way was blocked)"). The macro moves the mouse
# the normal way, then with SendEvent, then with SetCursorPos, which only puts the cursor there: when that's
# the only one that works, Windows is blocking the macro's input to Roblox (Roblox or Bloxstrap opened as
# administrator), so its clicks and keys don't reach the game either (Play was clicked, nothing opened).
# That has to be said like a mouse that doesn't move at all. Lib\Engine.ahk RbxMove. Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys
T, root = sys.argv[1], sys.argv[2]
eng = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
m = re.search(r"^RbxMove\(x, y\) \{.*?^\}", eng, re.S | re.M)
fn = m.group(0) if m else "RbxMove(p*) => 0"
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, lg := "", note := "", cur := [0, 0], works := "normal", RBX := "ahk_id 1"
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
AddLog(t) {
    global lg
    lg .= t "|"
}
Notify(t, p*) {
    global note
    note := t
}
; Windows, faked: which way of moving the mouse gets through ("normal", "event", "setcursor" or "none")
WinGetClientPos(&x := 0, &y := 0, &w := 0, &h := 0, p*) {
    x := 100, y := 50
}
CoordMode(p*) => 0
WinGetProcessName(p*) => "RobloxPlayerBeta.exe"
MouseMove(x, y, p*) {
    global cur
    if works = "normal"
        cur := [x, y]
}
SendEvent(s) {
    global cur
    if works = "event" && RegExMatch(s, "Click (\d+) (\d+)", &m)
        cur := [Integer(m[1]), Integer(m[2])]
}
DllCall(name, p*) {
    global cur
    if name = "SetCursorPos" && works = "setcursor"
        cur := [p[2], p[4]]
}
MouseGetPos(&mx := 0, &my := 0, p*) {
    mx := cur[1], my := cur[2]
}
''' + fn + r'''

RbxMove(400, 300)
Check("the mouse moves the normal way: nothing said", lg = "" && note = "", lg)
works := "event", lg := ""
RbxMove(200, 150)
Check("only with SendEvent (the macro's clicks are SendEvent too): said, no alarm", InStr(lg, "only moved with SendEvent") && !InStr(lg, "blocking") && note = "", lg)
works := "setcursor", lg := ""
RbxMove(600, 400)
Check("only with SetCursorPos: said that Windows is blocking the macro's clicks", InStr(lg, "blocking the macro's clicks"), lg)
Check("  with what's in front (Roblox)", InStr(lg, "RobloxPlayerBeta.exe"), lg)
Check("  and what to do: Roblox (or Bloxstrap) opened normally, or the macro as administrator", A_IsAdmin || InStr(lg, "administrator"), lg)
Check("  a message on screen too", InStr(note, "blocking"), note)
lg := "", note := ""
RbxMove(300, 250)
Check("  not again straight away (once every 2 minutes)", !InStr(lg, "blocking") && note = "", lg)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'; [ "${PIPESTATUS[0]}" = 124 ] && echo "FAILED (timed out)"
rm -rf "$T"
