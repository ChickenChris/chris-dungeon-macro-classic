#!/bin/bash
# The Order list (Lib\Order.ahk): modes one after another, each for its time, the top again with Repeat,
# a stop at the end without it. The clock and the macro around it are faked. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" <<'P'
import sys
src = open("Lib/Order.ahk", encoding="utf-8-sig").read().replace("A_TickCount", "Clock()")
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
global fails := 0, now := 0, logs := "", stopped := false, refreshed := 0
global cfg := Map("mode", "Dungeon", "orderOn", 1, "orderRepeat", 1, "order", [{mode: "Dungeon", mins: 120}, {mode: "Fool's Hunt", mins: 60}])
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8"), fails += !ok
}
Clock() => now
UpdateMapLabel() => 0
SaveConfig() => 0
global cfgFile := ""
SetCfg(k, v) => cfg[k] := v
UI(p*) {
    global refreshed
    refreshed++
}
UiState() => 0
AddLog(t) {
    global logs
    logs .= t "|"
}
StopMacro() {
    global stopped
    stopped := true
}
IndexOf(arr, v) {
    for i, x in arr
        if x = v
            return i
    return 0
}
ClampInt(v, lo, hi, d) => IsInteger(v) ? Max(lo, Min(hi, Integer(v))) : d
''' + src + r'''
cfg["mode"] := "Legend"
OrderStart()
Check("start: the first mode, from the top", cfg["mode"] = "Dungeon" && orderIdx = 1 && InStr(logs, "Order list 1/2: Dungeon for 2 h"), logs)
now := 119 * 60000
Check("before its time: nothing", !OrderDue() && !OrderNext() && cfg["mode"] = "Dungeon")
now := 121 * 60000
Check("its time's up: due (a round is finished first)", OrderDue())
Check("in the lobby: the next mode", OrderNext() && cfg["mode"] = "Fool's Hunt" && InStr(logs, "Order list 2/2: Summer Hunt for 1 h"), logs)
now += 61 * 60000
Check("Repeat on: back to the top after the last", OrderNext() && cfg["mode"] = "Dungeon" && orderIdx = 1)
cfg["orderRepeat"] := 0
now += 121 * 60000
OrderNext()
now += 61 * 60000
Check("Repeat off: stops after the last", OrderNext() && stopped && InStr(logs, "Order list done (3 h)"), logs)
cfg["orderOn"] := 0, stopped := false
OrderStart()
now += 999 * 60000
Check("switched off: never due", !OrderDue() && !OrderNext() && !stopped)
Check("times shown: 90 min as 1.5 h, 45 min", OrderTime(90) = "1.5 h" && OrderTime(45) = "45 min")
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 60 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
