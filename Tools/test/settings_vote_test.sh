#!/bin/bash
# The game's Settings, opened by the macro for Teleport to Spawn, isn't the card vote (RNG 10 Nov,
# debug_20261110_230809: "cards up", a card "voted" inside Settings, the Teleport click held back, no
# teleport). Lib\Engine.ahk FoolVoteDy, TeleportToSpawn, SettingsInTheWay. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys, os
from PIL import Image
T, root = sys.argv[1], sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M)
    if m:
        return m.group(0).replace("WinGetClientPos &ox, &oy, , , RBX", "ox := 0, oy := 0")
    missing.append(n)
    return n + "(p*) => false"
real = f"{root}/Tools/test/fixtures/settings_over_vote_check.bmp"
have = os.path.exists(real)
if have:
    Image.open(real).save(T + "/settings.bmp")
W = "Z:" + T.replace("/", "\\")
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
#Include ROOT\Lib\FindText.ahk
global fails := 0, RBX := "", voteNew := false, dbgVote := "", stageActive := true, settingsBusy := false
global seen := [], logs := [], spawnAt := 0
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Fresh() => 0
FoolMode() => true
CardUnderMouse() => 0
SaveDebugShot(t) => 0
AddLog(t) => logs.Push(t)
Step(t) => 0
Wait(ms) => seen.Push(settingsBusy)        ; every wait in the Settings visit: is the flag on?
LoadingScreenUp() => false
Clk(x, y, *) => (x = 26 && y = 570 ? seen.Push("gear:" settingsBusy) : 0)
SpawnFound(&fx, &fy, p*) => (fx := 300, fy := 250, true)
CloseSettings() => (seen.Push("close:" settingsBusy), true)
GameSettingsOpen() => true
Keys(k) => 0
MenuSig() => 1
WaitFor(f, ms, p*) => true
''' + "\n".join(fn(n) for n in ["ColorShare", "FoolVoteDy", "TeleportToSpawn", "SettingsInTheWay"]) + r'''

if HAVE {
    FindText().ShowPic("W\settings.bmp", 0)
    settingsBusy := false
    Check("RNG's frame (Settings open) on its own still looks like a vote to the colours (why the flag)", FoolVoteDy() != "", dbgVote)
    settingsBusy := true
    Check("  while the macro has Settings open: no vote", FoolVoteDy() = "", dbgVote)
    settingsBusy := false
}
seen := []
TeleportToSpawn()
gear := "", close := "", allOn := true
for v in seen
    if InStr(v, "gear:")
        gear := v
    else if InStr(v, "close:")
        close := v
    else
        allOn := allOn && v
Check("Teleport to Spawn: the flag is on from the gear click", gear = "gear:1", gear)
Check("  through every wait in Settings", allOn)
Check("  and while Settings is closed", close = "close:1", close)
Check("  off afterwards", !settingsBusy, settingsBusy)
seen := []
SettingsInTheWay()
Check("Settings in the way: the flag on while it's closed, off after", seen.Length && seen[seen.Length] = "close:1" && !settingsBusy)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
body = body.replace("ROOT", "Z:" + root.replace("/", "\\")).replace("W\\", W + "\\").replace("HAVE", "1" if have else "0")
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
