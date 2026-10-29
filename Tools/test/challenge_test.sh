#!/bin/bash
# Auto challenge (Lib\Challenge.ahk) with the game faked: the half hour, when it's due, the trip to
# the pad and the end of a challenge round. Every click and key is written down. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys, os
root = sys.argv[2]
src = open(f"{root}/Lib/Challenge.ahk", encoding="utf-8-sig").read() if os.path.exists(f"{root}/Lib/Challenge.ahk") else ""
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => "MISSING"'
parts = [fn(n) for n in ["ChallengeSlot", "ChallengeDue", "StartChallenge", "ChallengeWalk", "ChallengeFail", "ChallengeEnded", "ChallengeLeave", "ChallengeLobby", "LobbyWordRe", "ChallengeStepOff"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, calls := "", challengeOn := false, lastResult := "win", cfg := Map()
global padOk := true, backOk := true, alreadyCleared := false, joinAt := 0, joinN := 0, wordAt := 0, wordN := 0, lobbyAfterWord := true, lobbyNow := false, shots := ""
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Note(t) {
    global calls
    calls .= t
}
Clk(x, y, *) => Note("Clk " x "," y ";")
ClickDet(name, p*) => Note("ClickDet " name ";")
SendKeys(k) => Note("Keys " k ";")
PadStart(label, sel := true) => (Note("PadStart " label " " sel ";"), padOk)
LoadStage(p*) => Note("LoadStage;")
BackToLobby() => (Note("BackToLobby;"), backOk)
SaveConfig() => Note("Save;")
SaveDebugShot(t) {
    global shots
    shots .= t ";"
}
CloseChat() => 0
AddLog(t) => 0
Step(t) => 0
Wait(ms) => 0
Stale() => 0
FocusRoblox() => 0
SceneSig() => [1]
SigDiff(a, b) => 50
WaitAreaTeleport(b) => true
FoolJoinUp() {                                   ; "Join Matchmaking?" shows from the joinAt-th look
    global joinN
    return joinAt && ++joinN >= joinAt
}
Det(name) {
    global lobbyNow
    return name = "Lobby" && lobbyNow
}
OcrFindWord(x, y, w, h, re, &cx, &cy) {          ; the top "Return to lobby" from the wordAt-th look
    global wordN, lobbyNow
    if InStr(re, "already")                      ; "You have already cleared this challenge!"
        return alreadyCleared ? (cx := 400, cy := 446, true) : false
    if !(wordAt && ++wordN >= wordAt)
        return false
    cx := 451, cy := 121
    if lobbyAfterWord
        lobbyNow := true                         ; clicking it gets you to the lobby
    return true
}
Reset(mode := "Legend") {
    global
    calls := "", challengeOn := false, padOk := true, backOk := true, alreadyCleared := false, joinAt := 0, joinN := 0, wordAt := 0, wordN := 0, lobbyAfterWord := true, lobbyNow := false, shots := ""
    cfg := Map("autoChallenge", 1, "challengeSlot", 0, "mode", mode)
}
Count(s, part) => StrSplit(s, part).Length - 1
'''
body += "\n".join(parts) + "\n"
body += r'''
; --- the half hour
; a new half hour counts from 2 minutes past (a PC clock a little ahead, or a game a little late,
; still showed the old, already cleared challenge and the new one was skipped)
Check("14:01:59 and 14:02:00 are different half hours", ChallengeSlot("20261029140159") != ChallengeSlot("20261029140200"))
Check("14:00:30 is still the 13:30 one", ChallengeSlot("20261029140030") = ChallengeSlot("20261029133500"))
Check("14:02 and 14:31:59 are the same half hour", ChallengeSlot("20261029140200") = ChallengeSlot("20261029143159"))
Check("14:32 is the next one", ChallengeSlot("20261029143200") = ChallengeSlot("20261029140200") + 1)

; --- due
Reset(), cfg["autoChallenge"] := 0
Check("switch off: not due", !ChallengeDue())
Reset("Fool's Hunt")
Check("Fool's Hunt: never due", !ChallengeDue())
Reset()
Check("Legend, a new half hour: due", ChallengeDue())
Reset("Dungeon")
Check("Dungeon, a new half hour: due (from the lobby)", ChallengeDue())
Reset(), cfg["challengeSlot"] := ChallengeSlot()
Check("already played this half hour: not due", !ChallengeDue())
Reset(), challengeOn := true
Check("while playing one: not due", !ChallengeDue())

; --- to the pad
Reset(), joinAt := 3
StartChallenge()
Check("Areas, then Challenges", InStr(calls, "Clk 764,475;Clk 302,413;"), calls)
Check("walks with A, and lets go of it", InStr(calls, "Keys {a down};") && InStr(calls, "Keys {a up};") > InStr(calls, "Keys {a down};"), calls)
Check("Play Here, then Start without Select", InStr(calls, "Clk 330,325;") && InStr(calls, "PadStart Challenge 0;") > InStr(calls, "Clk 330,325;"), calls)
Check("playing it", challengeOn && InStr(calls, "LoadStage;"), calls)
Check("the half hour is saved as played", cfg["challengeSlot"] = ChallengeSlot() && InStr(calls, "Save;"), calls)

Reset()
StartChallenge()
Check("pad never reached: not playing, no Start", !challengeOn && !InStr(calls, "PadStart"), calls)
Check("pad never reached: the half hour still counts as played", cfg["challengeSlot"] = ChallengeSlot())
Check("pad never reached: one screenshot", shots = "challenge_entry;", shots)
Check("pad never reached: tried twice, A let go each time", Count(calls, "Clk 764,475;") = 2 && Count(calls, "Keys {a down};") = Count(calls, "Keys {a up};"), calls)
Check("pad never reached: not due any more (no retry loop)", !ChallengeDue())

Reset(), joinAt := 3, alreadyCleared := true
StartChallenge()
Check("already cleared: Cancel, back to farming, nothing played", InStr(calls, "Clk 330,325;") && InStr(calls, "Clk 401,525;") && !InStr(calls, "PadStart") && !challengeOn, calls)
Check("already cleared: no screenshot (nothing went wrong)", shots = "", shots)
Check("already cleared: steps off the door after Cancel", InStr(calls, "Keys {d down};") > InStr(calls, "Clk 401,525;") && InStr(calls, "Keys {d up};") > InStr(calls, "Keys {d down};"), calls)
Reset(), joinAt := 3, padOk := false
StartChallenge()
Check("the round didn't start: steps off the door, not playing", InStr(calls, "Keys {d down};") > InStr(calls, "PadStart") && InStr(calls, "Keys {d up};") && !challengeOn, calls)

; --- the end of a challenge round: rewards tapped away, then the top Return to lobby
Reset(), challengeOn := true, wordAt := 3
ChallengeEnded()
Check("rewards tapped, then Return to lobby clicked", InStr(calls, "Clk 560,560;Clk 560,560;Clk 451,121;"), calls)
Check("back in the lobby: not playing a challenge any more", !challengeOn)
Check("no back-to-lobby needed", !InStr(calls, "BackToLobby"), calls)
Reset(), challengeOn := true
ChallengeEnded()
Check("Return to lobby never seen: the usual back-to-lobby", InStr(calls, "BackToLobby;") && !challengeOn, calls)
Reset(), challengeOn := true, backOk := false
ChallengeEnded()
Check("not back in the lobby yet: still a challenge (the lobby clears it)", challengeOn)

; --- the lobby ends any challenge (a disconnect, a manual exit, a Stop/Start mid-challenge left it
; set, and the next farming round was taken for the challenge's end: a dungeon was thrown away)
Reset(), challengeOn := true
Check("lobby with a challenge left set: cleared, and a new half hour is due", ChallengeLobby() && !challengeOn)
Reset(), challengeOn := true, cfg["challengeSlot"] := ChallengeSlot()
Check("lobby, this half hour played: cleared, not due", !ChallengeLobby() && !challengeOn)

; --- the top "Return to lobby" read with the usual mistakes
for w in ["lobby", "Lobby", "Iobby", "1obby", "lobby.", "|obby", "Return", "lobbv"]
    Check("the button's word: " w, RegExMatch(w, LobbyWordRe()))
for w in ["to", "Replay", "Next", "lobbyist", ""]
    Check("not the button's word: " w, !RegExMatch(w, LobbyWordRe()))

; --- leaving for it after a round
Reset()
Check("due: back to the lobby", ChallengeLeave() && calls = "BackToLobby;", calls)
Reset(), cfg["challengeSlot"] := ChallengeSlot()
Check("not due: nothing", !ChallengeLeave() && calls = "", calls)

FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
