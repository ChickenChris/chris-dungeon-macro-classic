#!/bin/bash
# A unit's menu left open over the room picker (the round ended mid-upgrade) covered the room's
# Enter button: "its panel didn't open" / "No Enter button" round and round (a player's video).
# It's closed before the rooms are picked; the room's own panel (a red X too) is left alone. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
m = re.search(r"^CloseUnitPanel\(\) \{.*?^\}", src, re.S | re.M)
part = m.group(0) if m else 'CloseUnitPanel() => FileAppend("FAIL CloseUnitPanel not defined`n", "*")'
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, menuOpen := false, redX := false, clicks := 0, logs := ""
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Stale() => 0
Wait(ms) => 0
AddLog(t) {
    global logs
    logs .= t "|"
}
Det(name, &x := 0, &y := 0) {
    x := 330, y := 230
    return name = "UnitExit" && (menuOpen || redX)
}
MaxShown() => menuOpen
ReadLevel() => menuOpen ? 8 : -1
MenuButtons() => menuOpen
Clk(x, y) {
    global clicks, menuOpen
    clicks++, menuOpen := false
}
'''
body += part + "\n"
body += r'''
menuOpen := true
CloseUnitPanel()
Check("a unit's menu over the picker: closed with one click, and said", !menuOpen && clicks = 1 && InStr(logs, "closing it"), clicks " " logs)
clicks := 0, logs := "", redX := true
CloseUnitPanel()
Check("only a red X (the room's own panel): left alone", clicks = 0 && logs = "", clicks)
redX := false
CloseUnitPanel()
Check("nothing open: nothing clicked", clicks = 0)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
