#!/bin/bash
# Roblox's error 273 ("Same account launched experience from different device", Chris 10 Nov: the main
# and an alt took turns kicking each other for 10 minutes). A disconnect is reconnected with the box's own
# Reconnect (same window, same account); a new Roblox only opens after that window is closed; an account
# open in another Roblox (273) is never reconnected. Lib\Engine.ahk CheckConnection, ReconnectHere,
# AltReconnect, SameAccount. The game is faked; run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
src = open(sys.argv[2] + "/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if m:
        # the waits are a minute and 15 s: shorter here (the clock is real)
        return m.group(0).replace("60000", "1500").replace("15000", "400")
    missing.append(n)
    return n + '(p*) => false'
alts = "AltReconnect() {" in src
parts = [fn(n) for n in ["CheckConnection", "ReconnectHere", "StopSameAccount", "SameAccount"] + (["AltReconnect"] if alts else [])]
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, calls := "", logs := [], stageActive := true, RBX := "SameAccountTestWindow", cfg := Map("psLink", "")
global discoText := "", boxes := [], lobbyAfter := 0, lobbyChecks := 0
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
LogHas(t) {
    for m in logs
        if InStr(m, t)
            return true
    return false
}
T273 := "Disconnected Same account launched experience from different device. Reconnect if you prefer to use this device. (Error Code: 273)"
T277 := "Disconnected Lost connection to the game server, please reconnect (Error Code: 277)"
Clk(x, y, *) => Note("Clk " x "," y ";")
Launch(n := 1) {
    Note("Launch;")
    throw Error("stop here")                    ; the launch loop itself is reconnect_test's
}
CloseRoblox() => Note("Close;")
StopMacro() => Note("Stop;")
SendWebhook(p*) => 0
Summary() => ""
AddLog(t) => logs.Push(t)
SaveDebugShot(t) => Note("Shot " t ";")
Wait(ms) => Sleep(10)
Stale() => 0
Chk() => 0
IsDisconnected() {                              ; the box on the main, and what it says
    global discoText := boxes.Length ? boxes[1] : ""
    return boxes.Length > 0
}
AltDisconnected() => DisconnectBoxUp()
DisconnectBoxUp() {                             ; one look at the box: the next one in the list
    global discoText
    if !boxes.Length
        return false
    discoText := boxes.Length > 1 ? boxes.RemoveAt(1) : boxes[1]
    return discoText != "gone"
}
Det(name) {
    global lobbyChecks
    return name = "Lobby" && ++lobbyChecks > lobbyAfter
}
FoolAltBack() => !AltDisconnected() && Det("Lobby")
RelinkRoblox() => 0
FixWindow() => 0
RobloxAppPage() => false
Reset(b*) {
    global calls := "", logs := [], boxes := b, lobbyChecks := 0
}
Run(fn) {
    try return fn()
    catch as e
        return e.Message
}
'''
body += "\n".join(parts) + "\n"
body += r'''
; the box's own text tells error 273 apart
Check("error 273's text", SameAccount(T273))
Check("lost connection (277): not that", !SameAccount(T277))
Check("read with a missing letter or two", SameAccount("Same acc0unt launched experience from different devlce") && SameAccount("(Error Code:273)"))
Check("nothing read: not that", !SameAccount(""))

; the main, error 273: nothing pressed, stopped (the other Roblox isn't kicked)
Reset(T273)
r := Run(CheckConnection)
Check("273 on the main: no Reconnect, no new Roblox, stopped", !InStr(calls, "Clk") && !InStr(calls, "Launch") && InStr(calls, "Stop;"), calls)
Check("  told in the log", LogHas("error 273"), logs.Length ? logs[logs.Length] : "")

; a lost connection: the box's Reconnect, the same window back in the lobby
Reset(T277, "gone"), lobbyAfter := 0
r := Run(CheckConnection)
Check("lost connection: the box's Reconnect (430,384), back in the lobby, no new Roblox", r = true && calls = "Clk 430,384;" && LogHas("Reconnected"), calls)

; Reconnect doesn't bring it back: that window is closed before a new Roblox opens
Reset(T277), lobbyAfter := 999
r := Run(CheckConnection)
Check("not back: Reconnect pressed twice, then that window closed, then a new Roblox", InStr(calls, "Clk 430,384;Clk 430,384;Close;Launch;") && StrSplit(calls, "Clk").Length - 1 = 2, calls)

; Reconnect pressed, and the box comes back with 273 (the account is open elsewhere now): stopped
Reset(T277, T273), lobbyAfter := 999
r := Run(CheckConnection)
Check("273 after the Reconnect: not pressed again, no new Roblox, stopped", calls = "Clk 430,384;Shot same_account;Stop;", calls)
'''
if alts:
    body += r'''
; an alt with 273: nothing pressed (its other Roblox isn't kicked)
Reset(T273)
Check("an alt with 273: not reconnected", !AltReconnect() && !InStr(calls, "Clk"), calls)
Reset(T277, "gone"), lobbyAfter := 0
Check("an alt with a lost connection: its Reconnect", AltReconnect() && calls = "Clk 430,384;", calls)
'''
body += r'''
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
OUT=$(WINEDEBUG=-all timeout 120 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r')
rm -rf "$T"
echo "$OUT"
