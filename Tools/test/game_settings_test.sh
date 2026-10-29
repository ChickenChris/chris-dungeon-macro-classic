#!/bin/bash
# The game's own Settings window (Quick Summon, Graphics...) left open over the map: placing
# clicked into it for the rest of the stage (a player's clip, Alien Spaceship). It's told by its
# words, closed after Teleport to Spawn only when it's really gone, and closed when placing fails
# while it's up. The game is faked. Run under Wine
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
    return n + '(p*) => ""'
parts = [fn(n) for n in ["IsSettingsText", "CloseSettings", "SettingsInTheWay"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, open := false, clicks := 0, closesNeeded := 1, spawnShown := false, logs := ""
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Clk(x, y, *) {
    global clicks, open, closesNeeded
    if x = 583 && y = 147 {
        clicks++
        if clicks >= closesNeeded
            open := false
    }
}
GameSettingsOpen() => open
Det(name, p*) => name = "Spawn" && open && spawnShown
Wait(ms) => 0
WaitFor(fn, p*) => fn()
AddLog(t) {
    global logs
    logs .= t "|"
}
SaveDebugShot(t) => 0
'''
body += "\n".join(parts) + "\n"
body += r'''
; its words
for t in ["Settings`nQuick Summon`nGraphics`nSmooth Lighting", "Settings`nDisable Textures`nDepth-Of-Field", "Settings`nTeleport to Spawn"]
    Check("the game's Settings window: " StrReplace(t, "`n", " / "), IsSettingsText(t))
for t in ["Settings", "Graphics", "Wave 15`n81120/81120", "Upgrade`nSell`nSettings? no", ""]
    Check("not it: " StrReplace(t, "`n", " / "), !IsSettingsText(t))
; closing after Teleport to Spawn: the list scrolled to the top (no Spawn row on show) counted as
; closed after one click, even when the click didn't take
open := true, spawnShown := false, clicks := 0, closesNeeded := 2
ok := CloseSettings()
Check("closed only once it's really gone (a second click)", ok && !open && clicks = 2, clicks)
open := true, closesNeeded := 99, clicks := 0
Check("it won't close: says so", !CloseSettings() && open)
; placing: a failed spot with the window up closes it
open := true, closesNeeded := 1, clicks := 0, logs := ""
Check("placing failed with the window up: closed", SettingsInTheWay() && !open && InStr(logs, "Settings"), logs)
open := false, clicks := 0
Check("not up: nothing clicked", !SettingsInTheWay() && clicks = 0)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
