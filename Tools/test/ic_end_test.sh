#!/bin/bash
# Infinity Castle's round end (free in Classic since 3.0.100, the same code as Premium): a win counts
# its floors (Hard: 2, or the "Room N unlocked" lines read), goes to the next floor, stops after the
# floors set; a loss tries the floor again. The game is faked. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    return m.group(0) if m else (print("FAIL not defined: " + n) or n + '(p*) => ""')
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, logs := "", res := "win", lastResult := "", challengeOn := false, stopped := 0, loads := 0, nexts := 0
global icFloors := 0, icFloor := 0, icUnlocked := 0, icUnlockedTop := 0
global cfg := Map("mode", "Infinity Castle", "icHard", 0, "icStopFloors", 0, "stopAfterDefeat", 0)
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
ReadResult() {
    global lastResult := res
}
FinishStage() => 0
ChallengeEnded() => 0
ChallengeLeave() => false
LegendMode() => false
PortalMode() => false
LegendReplay() => 0
PortalReplay() => 0
FoolReplayAll() => 0
FoolEndToLobby() => 0
BackToLobby() => 0
FoolStartRound() => 0
InfBest(p*) => 0
SaveConfig() => 0
INF_MAP() => ""
global infWave := 0, infRuns := 0
InfMode() => false
FoolMode() => false
FoolDuo() => false
Det(p*) => false
ClickDet(p*) => 0
ClickOpenDungeon() {
    global nexts
    nexts++
}
LoadStage(p*) {
    global loads
    loads++
}
StopMacro() {
    global stopped
    stopped++
}
Chk() => 0
SendWebhook(p*) => 0
Summary() => ""
UpdateMapLabel() => 0
UpdateStats() => 0
Stale() => 0
Step(t) => 0
Wait(ms) => 0
AddLog(t) {
    global logs
    logs .= t "|"
}
End(r) {
    global res := r, logs := "", nexts := 0, loads := 0
    HandleEnd()
}
'''
body += "\n".join(fn(n) for n in ["HandleEnd", "ICMode"]) + "\n"
body += r'''
End("win")
Check("a win on Normal: 1 floor, then the next floor", icFloors = 1 && nexts = 1 && loads = 1 && InStr(logs, "floor cleared"), icFloors " " logs)
cfg["icHard"] := 1
End("win")
Check("a win on Hard: 2 floors", icFloors = 3, icFloors)
icUnlocked := 3, icUnlockedTop := 45
End("win")
Check("the 'Room N unlocked' lines read: their count, and the floor", icFloors = 6 && icFloor = 45 && InStr(logs, "room 45 unlocked"), icFloors " " icFloor)
End("loss")
Check("a loss: no floor, the floor again", icFloors = 6 && nexts = 1 && loads = 1, icFloors)
cfg["icStopFloors"] := 8
End("win")
Check("Stop after 8 floors: stops", icFloors = 8 && stopped = 1 && InStr(logs, "stopping"), icFloors " " stopped)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
