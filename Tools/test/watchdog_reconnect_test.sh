#!/bin/bash
# The 4-minute watchdog in the middle of a reconnect (mmanimals 15-17 Nov, 3 times): disconnected 40 s after
# a round, the box's Reconnect didn't bring it back, Roblox was opened again, and 2 minutes into that the
# watchdog ("no round for 4 minutes", counted from the round's end) threw the macro out of the reconnect and
# opened Roblox once more on top of the one still loading: none of the next 5 opens came back, and the macro
# stopped. The watchdog now holds off while a reconnect runs, and counts its 4 minutes from the reconnect's end.
# Lib\Engine.ahk CheckConnection / WatchdogCheck. Wine
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
parts = [fn(n) for n in ["CheckConnection", "WatchdogCheck"]]
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
class MacroRecover extends Error {
}
global fails := 0, lg := "", RBX := "WatchdogReconnectTestWindow", cfg := Map("psLink", "")
global running := true, paused := false, manualRun := false, stageActive := false, stepNow := "back to the lobby for the next dungeon", stepAt := 0
global wdRoundAt := 0, wdFires := 0, wdBusy := false, wdStepTold := Map(), wdLastAt := 0, wdInStage := false
global clock := 10000000, backAt := 0, launches := 0
g := Gui(, RBX), g.Show("x0 y0 w800 h600 NA")
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
WdNow() => clock
Chk() => WatchdogCheck()
Wait(ms) {                                       ; the macro's waits: time passes, and Chk runs as in the macro
    global clock
    clock += ms
    Chk()
}
AddLog(t) {
    global lg
    lg .= t "|"
}
ReconnectHere() {                                ; the box's Reconnect: a minute, not back
    global clock
    loop 30
        Wait(2000)
    return false
}
Launch(n := 1) {                                 ; Roblox opened again: back in the lobby 2:10 later
    global launches, backAt
    launches++
    if !backAt
        backAt := clock + 130000
}
Det(name) => name = "Lobby" && backAt && clock >= backAt
IsDisconnected() => true
WatchdogGame(now) => 0                           ; (the in-round check: no round in this test)
SameAccount(t) => false
StopSameAccount() => 0
SendWebhook(p*) => 0
Summary() => ""
CloseRoblox() => 0
StopMacro() => 0
SaveDebugShot(t) => 0
RelinkRoblox() => 0
FixWindow() => 0
RobloxAppPage() => false
Clk(p*) => 0
Stale() => 0
WatchdogStepStuck(st) => 0
WdStops() => false                               ; (Premium: with alts it stops instead)
global discoText := "Lost connection to the game server (Error Code: 277)"
'''
body += "\n".join(parts) + "\n"
body += r'''
; the round ended 3 min 20 s ago (Victory 01:54:35, disconnected 01:55:20, the reconnect from then on)
wdRoundAt := clock - 200000, wdLastAt := 0
thrown := ""
try ok := CheckConnection()
catch MacroRecover as e
    thrown := e.Message, ok := false
Check("the watchdog doesn't break into the reconnect", thrown = "", thrown)
Check("  Roblox opened once and the macro is back (Reconnected)", ok && launches = 1 && InStr(lg, "Reconnected"), ok " " launches " " lg)
Check("  the 4 minutes count from the reconnect's end", wdRoundAt = clock && !wdBusy, (clock - wdRoundAt) " " wdBusy)
; and it still watches afterwards: 4 more minutes with no round
clock += 241000, wdLastAt := 0
thrown := ""
try WatchdogCheck()
catch MacroRecover as e
    thrown := e.Message
Check("4 minutes after the reconnect with no round: the watchdog fires again", InStr(thrown, "Nothing happened for 4 minutes"), thrown)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
