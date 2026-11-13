#!/bin/bash
# "Back to Lobby?" (Kaguya 13 Nov, video: a private server joined with its code): after Return to lobby
# the game asks Public Server or "@<owner>'s Server", and the macro kept pressing Return to lobby under it
# until the watchdog fired. Its own private server is picked (the right button). Lib\Engine.ahk
# BackToLobby, BackLobbyPick, Lib\Challenge.ahk ChallengeEnded. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
import os
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read() + "\n" + open(f"{root}/Lib/Challenge.ahk", encoding="utf-8-sig").read()
fxdir = root + "/Tools/test/fixtures/"
real = os.path.exists(fxdir + "back_to_lobby_choice.bmp")      # (Premium's recorded frames)
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if not m:
        missing.append(n)
        return n + "(p*) => 0"
    return m.group(0)
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, realLook := false, clicks := [], logs := [], popup := false, lobby := false, challengeOn := true, lastResult := "win"
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Step(t) => 0
Stale() => 0
Wait(ms) => 0
AddLog(t) => logs.Push(t)
SaveDebugShot(t) => 0
ClickAway() => 0
FindOpenDungeon(&x, &y) => false
OcrFindWord(x, y, w, h, re, &lx, &ly) => (lx := 400, ly := 121, !popup && !lobby)
Det(n) => n = "Lobby" ? lobby : n = "EndScreen" ? !lobby : false
BackLobbyUp() => realLook ? BackLobbyUpReal() : popup
ClickDet(n, dx, dy, p*) => Clk("ret", "")
Clk(x, y, *) {                                  ; Return to lobby: the question; the right button: the lobby
    global popup, lobby
    clicks.Push(x "," y)
    if x = "ret" || x = 400
        popup := true
    else if x = 465 && y = 323 && popup
        popup := false, lobby := true
}
WaitFor(fn, timeout, step := 100) {
    loop 20
        if fn()
            return true
    return false
}
''' + "\n".join(fn(n) for n in ["BackToLobby", "BackLobbyPick", "ChallengeEnded", "LobbyWordRe"]) + r'''

r := BackToLobby()
Check("Return to lobby, the question: its own server picked, in the lobby", r && lobby && clicks.Length = 2 && clicks[2] = "465,323", clicks.Length ? clicks[clicks.Length] : "none")
Check("  logged once", logs.Length && InStr(logs[1], "private server"), logs.Length ? logs[1] : "")
popup := false, lobby := false, clicks := [], logs := []
ChallengeEnded()
Check("after a challenge (Kaguya's case): the same", lobby && !challengeOn && IndexOf(clicks, "465,323"), clicks.Length)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
IndexOf(arr, v) {
    for i, x in arr
        if x = v
            return i
    return 0
}
'''
if not real:
    body = body.replace("BackLobbyUp() => realLook ? BackLobbyUpReal() : popup", "BackLobbyUp() => popup")
if real:
    body = body.replace("ExitApp fails ? 1 : 0", "#Include " + "Z:" + (root + "/Lib/FindText.ahk").replace("/", "\\") + "\n" + fn("ColorShare").replace("WinGetClientPos &ox, &oy, , , RBX", "ox := 0, oy := 0") + "\n" + fn("BackLobbyUp").replace("BackLobbyUp(", "BackLobbyUpReal(", 1) + "\nFresh() => 0\nglobal RBX := \"\"\n" + r'''
; the real thing, on RNG's 7 Nov recording: "Back to Lobby?" with Public Server and "@ThePowerOfRNG's Server"
realLook := true
FindText().ShowPic("FXback_to_lobby_choice.bmp", 0)
Check("RNG's frame: 'Back to Lobby?' seen", BackLobbyUpReal())
for f in ["fool_waiting_players", "party_alt_waiting_host", "vote_orange_lobby", "settings_over_vote_check", "adaptation_choice"] {
    FindText().ShowPic("FX" f ".bmp", 0)
    Check("not on " f, !BackLobbyUpReal())
}
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''.replace('"FX', '"' + "Z:" + fxdir.replace("/", "\\")), 1)
    body = body.replace('FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")\n#Include', "#Include", 1)
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 120 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
