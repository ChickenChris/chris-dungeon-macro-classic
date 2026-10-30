#!/bin/bash
# Opening a placed unit's menu (OpenUnit in Lib\Engine.ahk): an Abyssal Eel (a summon) swimming over
# the unit opens the eel's menu instead. That isn't the unit gone: it was left for good after 3 such
# visits (Chris: slot 2 'can't find this unit any more' with an eel on top). The game is faked
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => ""'
parts = [fn(n) for n in ["OpenUnit"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, logs := "", mode := "eel", shown := "", clicks := 0
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
; mode: "eel" = every click on the unit opens an eel's shown, "gone" = nothing opens, "unit" = the unit's
Clk(x, y, *) {
    global shown, clicks
    clicks++
    shown := x = 325 && y = 185 ? "" : x = 560 ? "" : mode = "eel" ? "eel" : mode = "unit" ? "unit" : ""
}
WaitUnitMenu(ms) => shown = "unit"
UnitMenuOpen() => shown = "unit"
MaxShown() => shown = "eel"
IsSummonMenu() => shown = "eel"
WaitFor(fn, p*) => fn()
AbilityTick() => 0
Sleep(ms) => 0
SaveDebugShot(t) => 0
AddLog(t) {
    global logs
    logs .= t "|"
}
'''
body += "\n".join(parts) + "\n"
body += r'''
u := {x: 307, y: 334, slot: 2, dx: 0, dy: -3, misses: 0, lost: false}
loop 5
    OpenUnit(u)
Check("an eel over the unit, 5 visits: the unit isn't given up", !u.lost && !InStr(logs, "any more"), logs)
Check("said once that an eel is in the way", StrSplit(logs, "summon").Length - 1 = 1, logs)
Check("the eel's menu is closed again", shown = "", shown)
mode := "unit"
Check("the eel swam off: the unit opens", OpenUnit(u) && !u.lost)
mode := "gone", u2 := {x: 100, y: 100, slot: 3, dx: 0, dy: -3, misses: 0, lost: false}
loop 3
    OpenUnit(u2)
Check("nothing opens at all, 3 visits: left alone as before", u2.lost && InStr(logs, "any more"), logs)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
