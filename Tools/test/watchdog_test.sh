#!/bin/bash
# The watchdog (Chris 9 Nov): no round for 4 minutes -> back to the lobby (the 2nd time in a row: rejoin),
# and a placement wait of 3 minutes in a round explained in the log with a recording. Lib\Engine.ahk
# EngineRun, Chk, Wait, WatchdogCheck, WatchdogStepStuck, WatchdogRecover. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + "(p*) => 0"
def cls(n):
    m = re.search(r"^class " + n + r" extends \w+ \{\s*\}", src, re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return "class " + n + " extends Error {\n}"
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, running := true, paused := false, manualRun := false, cancelManual := false, stageActive := false
global stepNow := "lobby: going to Summer Hunt", stepAt := 0, fakeNow := 1000000, logs := [], calls := [], saves := [], ticks := 0, plan := Map()
global wdRoundAt := 0, wdFires := 0, wdBusy := false, wdStepTold := Map(), wdLastAt := 0, wdInStage := false
global idleSince := 0, slotStops := 0, slotCap := 0, slotOne := 0, slotFull := 0, autoOpenSeen := 0, autoOpenOff := 0, clickOpened := 0, icFloors := 0, icFloor := 0
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
LogHas(t) {
    for m in logs
        if InStr(m, t)
            return true
    return false
}
AddLog(m) => logs.Push(m)
WdNow() => fakeNow
ReleaseKeys() => 0
Step(t) => 0
PausedKeepAlive() => 0
ResumeFront() => 0
Stale() => 0
FoolWaitHook() => 0
Det(k) => false
global lobbyErr := false
BackToLobby() {
    calls.Push("lobby")
    if lobbyErr                                 ; (Roblox closed under it, say)
        throw Error("no Roblox window")
    return true
}
RejoinToLobby() => calls.Push("rejoin")
SendWebhook(t, d, c := 0, p*) => calls.Push("webhook")
DbgSaveSoon(r) => saves.Push(r)
ReadYen() => 19602
SlotCost(n) => n = 6 ? 6600 : 500
SlotReady(n) => false
; each pass of the main loop: a minute of (fake) time in a wait, like a stuck step
Tick() {
    global ticks, fakeNow, running, stageActive
    ticks++
    if ticks = 16                               ; a round between the 2nd and the 3rd time
        stageActive := true
    if ticks = 17
        stageActive := false
    if ticks = 26 || ticks > 60                 ; (a safety stop for the test)
        running := false
    fakeNow += 60000
    Wait(5)
}
''' + cls("MacroStop") + "\n" + cls("MacroRecover") + "\n" + "\n".join(fn(n) for n in ["Chk", "Wait", "EngineRun", "WatchdogCheck", "WatchdogStepStuck", "WatchdogRecover"]) + r'''

; A: no round for 4 minutes, from deep in a wait -> back to the lobby, and the loop goes on; the 2nd
; time in a row -> rejoin; a round in between -> back to the lobby again
EngineRun()
order := ""
for c in calls
    order .= c " "
Check("4 minutes without a round: back to the lobby (with the webhook)", calls.Length >= 2 && calls[1] = "webhook" && calls[2] = "lobby", order)
Check("  logged, with the last step", LogHas("Nothing happened for 4 minutes: no round started (last step: lobby: going to Summer Hunt). Going back to the lobby"), logs.Length ? logs[1] : "")
Check("  the recording saved", saves.Length >= 1 && InStr(saves[1], "no round for 4 minutes"), saves.Length)
Check("  the main loop went on after it (not a stop)", ticks > 6, ticks)
Check("the 2nd time in a row: rejoin", calls.Length >= 4 && calls[4] = "rejoin" && LogHas("Rejoining your server"), order)
acts := ""
for c in calls
    if c != "webhook"
        acts .= c " "
Check("still no round: rejoin again; a round in between: back to the lobby first again", acts = "lobby rejoin rejoin lobby rejoin ", acts)
Check("the macro stopped normally at the end", !running)

; not while paused, in a manual task, while the Find Match number waits for the player, or while recovering
running := true, wdLastAt := 0
for what in ["paused", "manual", "typing", "busy"] {
    wdRoundAt := fakeNow - 600000
    paused := what = "paused", manualRun := what = "manual", wdBusy := what = "busy"
    stepNow := what = "typing" ? "Summer Hunt: Find Match, waiting for you to type the number" : "lobby: going to Summer Hunt"
    fakeNow += 2000, thrown := false
    try WatchdogCheck()
    catch MacroStop
        thrown := true
    Check("no watchdog while " what, !thrown)
}
paused := false, manualRun := false, wdBusy := false

; a 10-minute pause in the lobby: carrying on afterwards isn't "nothing happened for 4 minutes"
stepNow := "lobby: going to Summer Hunt", wdRoundAt := fakeNow, paused := true
fakeNow += 600000
try WatchdogCheck()
paused := false, fakeNow += 2000, thrown := false
try WatchdogCheck()
catch MacroStop
    thrown := true
Check("after a 10-minute pause: no watchdog right away", !thrown)

; the way back to the lobby fails with an error: the macro carries on (not a crash)
ticks := 0, running := true, calls := [], logs := [], wdRoundAt := 0, wdFires := 0, wdLastAt := 0, lobbyErr := true
EngineRun()
Check("going back to the lobby failed: logged and the main loop went on", ticks > 6 && LogHas("no Roblox window"), ticks)
lobbyErr := false, running := true

; B: a placement wait of 3 minutes in a round: explained once, with a recording; the round goes on
logs := [], saves := [], stageActive := true, wdInStage := false
stepNow := "build order: waiting for yen to place slot 6  (19602 / 6600)", stepAt := fakeNow - 180001
fakeNow += 2000
WatchdogCheck()
Check("slot 6 waiting 3 minutes: explained", logs.Length = 1 && logs[1] = "Slot 6: still waiting to place it after 3 minutes (yen 19602, its price 6600, its card looks greyed out)", logs.Length ? logs[1] : "")
Check("  and the recording saved", saves.Length = 1, saves.Length)
fakeNow += 2000
WatchdogCheck()
Check("  only once", logs.Length = 1, logs.Length)
stepNow := "watching the round", stepAt := fakeNow - 600000, fakeNow += 2000
WatchdogCheck()
Check("watching the round for long: nothing (it does that all round)", logs.Length = 1, logs.Length)
stepNow := "build order: waiting for yen to place slot 2", stepAt := fakeNow - 200000, fakeNow += 2000
WatchdogCheck()
Check("another slot's wait: explained too", logs.Length = 2 && InStr(logs[2], "Slot 2: still waiting"), logs.Length)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
