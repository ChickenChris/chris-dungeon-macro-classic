#!/bin/bash
# A map lost after walking to its spot: the walk went somewhere the enemies never pass (Magic Hills
# in the dungeon: all 14 units placed, 5 defeats in a row at depth 3, players: "it puts units
# behind the spawn"). The next time on that map it places from spawn instead; a loss from spawn
# too goes back to the walk; a win keeps whatever won. The game is faked. Run under Wine
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
parts = [fn(n) for n in ["GoToSpot", "WalkLearn"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, walks := 0, logs := "", walkedHere := false, lastResult := "", curMap := "Magic Hills"
global walkLost := Map(), cfg := Map("tpSpawn", true, "zoom", false, "walks", Map())
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
TeleportToSpawn() => 0
ZoomCamera() => 0
ClearVote() => 0
VoteOnScreen() => false
global foolVotes := 0
WalkKey(m) => m  ; (Premium only)
HasBuiltInWalk(m) => m = "Magic Hills"
WalkRoute(m) {
    global walks, walkedHere
    if !(cfg["walks"].Has(m) || HasBuiltInWalk(m))
        return
    walks++, walkedHere := true
}
AddLog(t) {
    global logs
    logs .= t "|"
}
; one stage on the map: the start (walkedHere off), going to the spot, then the result
Stage(result) {
    global walks, walkedHere, lastResult, logs
    walks := 0, walkedHere := false, logs := ""
    GoToSpot(curMap)
    lastResult := result
    WalkLearn()
    return walks
}
'''
body += "\n".join(parts) + "\n"
body += r'''
Check("first time: walks", Stage("loss") = 1)
Check("lost after the walk: from spawn next time, and says why", Stage("loss") = 0 && InStr(logs, "from spawn"), logs)
Check("lost from spawn too: the walk again", Stage("win") = 1)
Check("won after the walk: keeps walking", Stage("win") = 1)
Stage("loss")
Check("lost again: spawn", Stage("win") = 0)
Check("won from spawn: stays at spawn", Stage("win") = 0)
Check("the Spots page's Test walk still walks", (walks := 0, GoToSpot(curMap, true, true), walks) = 1)
Check("other maps keep their walk", (curMap := "Snowy Town", walks := 0, cfg["walks"]["Snowy Town"] := "d+0", Stage("loss")) = 1)
curMap := "Puppet Island"
Check("a map with no walk: nothing changes, nothing said", (Stage("loss"), Stage("loss")) = 0 && !InStr(logs, "spawn"), logs)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
