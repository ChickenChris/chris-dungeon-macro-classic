#!/bin/bash
# Reconnecting (Lib\Engine.ahk CheckConnection): when Roblox opens its own app page instead of the
# game, nothing is clicked there (a click opened another game) and Anime Adventures is opened again.
# The game is faked; run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
src = open(sys.argv[2] + "/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => false'
parts = [fn(n) for n in ["CheckConnection", "IsAppNav"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, calls := "", stageActive := true, appPage := true, RBX := "ReconnectTestWindow", cfg := Map("psLink", "")
g := Gui(, RBX), g.Show("x0 y0 w800 h600 NA")
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Note(t) {
    global calls
    calls .= t
}
Clk(x, y, *) {                                  ; a click here ends the test (the old code waits minutes)
    Check("on Roblox's app page nothing is clicked", false, "Clk " x "," y)
    FileAppend("FAILED`n", "*", "UTF-8")
    ExitApp 1
}
Launch(n := 1) => Note("Launch;")
CloseRoblox() => Note("Close;")
StopMacro() => Note("Stop;")
RobloxAppPage() => appPage
IsDisconnected() => true
SendWebhook(p*) => 0
Summary() => ""
AddLog(t) => 0
SaveDebugShot(t) => 0
Wait(ms) => 0
RelinkRoblox() => 0
FixWindow() => 0
Det(name) => false
Chk() => 0
'''
body += "\n".join(parts) + "\n"
body += r'''
CheckConnection()
Check("on Roblox's app page nothing is clicked", !InStr(calls, "Clk"), calls)
Check("the game is opened again each time (5 tries)", StrSplit(calls, "Launch;").Length - 1 = 5, calls)
Check("the app page is closed before opening it again", StrSplit(calls, "Close;").Length - 1 = 4, calls)
; the app's left bar (Home, Moments, Chat, Me), read with mistakes; the game's own buttons aren't it
for t, want in Map("Home`nMoments`nChat`nMe", 1, "Hame`nMoments`nChat", 1, "Home`nChat", 1, "Home", 0, "", 0,
        "Play`nAreas`nUnits`nSummon`nItems", 0, "Chat with friends", 0)
    Check("app bar: " StrReplace(t, "`n", " ") " = " want, !!IsAppNav(t) = want)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
