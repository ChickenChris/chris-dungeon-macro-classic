#!/bin/bash
# The Misty Tower mode (Lib\Misty.ahk TowerFloorIn, StartTower, TowerNext). Chris 23 Nov: it climbs floor by
# floor. The tower window opens on the highest open floor already (its panel: "Misty Tower: Floor 21"); no floor
# is clicked (a player 23 Nov, 20 cleared: Floor 21 was misread and Floor 20 clicked, "Chose the wrong floor"),
# its number is only read for the log. Start (401,438: the window sits as the other pads' do, Chris's
# screenshot 23 Nov; the clip's frame caught it still sliding in, 57 px higher),
# Play Here (PadStart) or Find Match, LoadStage("Misty Village"). A win: "Next Floor" at the top of the end
# screen (488,121, his clip), the next floor loads. A loss: Replay / Retry if the game shows one, else the
# lobby (the same floor is picked again). Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys, os
T, root = sys.argv[1], sys.argv[2]
mis = open(f"{root}/Lib/Misty.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n, s=mis):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", s, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) =>.*?(?=\n\S)", s, re.S | re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + "(p*) => false"
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, lg := "", clicks := "", cfg := Map("mode", "Misty Tower", "towerMatch", 0), towerFloor := 0
global joinUp := false, matchOk := true, loaded := "", started := "", lobby := 0, lastResult := "win"
global shown := Map(), works := true, endUp := true, words := []
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
AddLog(t) {
    global lg
    lg .= t "|"
}
Step(t) => 0
Stale() => 0
Wait(ms) => 0
CloseChat() => 0
SaveDebugShot(p*) => 0
ChallengeLeave() => false
VillageShopClose() => false
global foolAlts := [], foolAltMissed := Map(), portalRegroup := false, portalAltWait := 20000   ; (no alts here)
AltsReconnectAll() => false
FoolDuo() => false
PartyOn() => false
PartyEnsure() => false
PortalAltsIn(p*) => 0
PlayHere() => 0
OpenPortalRow() => 0
OpenPortalFriends() => 0
FoolAltsToLobby() => 0
MistyToTower() => true
FoolJoinUp() => joinUp
FoolMatchTries(f, what) => matchOk
RaidWaitMatch(what := "") => true
FindOpenDungeon(&x, &y) => false
TowerTitle() => title
PadStart(label, select := true) {
    global started
    started := label
    return true
}
LoadStage(m := "", p*) {
    global loaded
    loaded := m
}
BackToLobby() {
    global lobby
    lobby++
    return true
}
WaitFor(f, ms, step := 100) {
    loop Max(1, ms // 500)
        if f()
            return true
    return f()
}
Det(n) => n = "EndScreen" && endUp
MistyEndAt(re, &x, &y) {
    for w, xy in shown
        if RegExMatch(w, re)
            return (x := xy[1], y := xy[2], true)
    return false
}
Clk(x, y, *) {
    global clicks, endUp, shown
    clicks .= x "," y ";"
    if y = 121 && works
        endUp := false, shown := Map()          ; the end screen goes, the next floor loads
}
''' + "\n".join([fn("TowerMatchOn"), fn("TowerFloorIn"), fn("TowerFloorRead"), fn("StartTower"), fn("TowerToMatch"), fn("TowerNext")]) + r'''

; the panel's title as the player's recording shows it (20 floors cleared, the window opened on Floor 21)
Check("the floor the window opened on: Misty Tower: Floor 21 -> 21", TowerFloorIn("Misty Tower: Floor 21") = 21)
Check("  glued / misread: MistyTower:Floor21, Floor 3, F1oor 7", TowerFloorIn("MistyTower:Floor21") = 21 && TowerFloorIn("Floor 3") = 3 && TowerFloorIn("Misty Tower: F1oor 7") = 7)
Check("  nothing read: 0", TowerFloorIn("") = 0 && TowerFloorIn("Misty Village") = 0)
global title := "Misty Tower: Floor 21"
clicks := "", lg := ""
StartTower()
Check("the tower: no floor clicked (it's on the highest already), Start, Play Here's start, the map", InStr(clicks, "400,390;401,438;") && !InStr(clicks, "290,") && started = "Misty Tower" && loaded = "Misty Village", clicks " / " started)
Check("  the log names the floor", InStr(lg, "Floor 21") && towerFloor = 21, lg)
cfg["towerMatch"] := 1, joinUp := true, clicks := "", started := "", loaded := ""
StartTower()
Check("Find Match: the match, no Play Here start", InStr(clicks, "401,438;") && started = "" && loaded = "Misty Village", clicks " / " started)
cfg["towerMatch"] := 0, joinUp := false
; after a floor
towerFloor := 3, lastResult := "win", shown := Map("Next", [470, 121], "Floor", [520, 121]), works := true, endUp := true, clicks := "", loaded := "", lobby := 0, lg := ""
TowerNext()
Check("a win: Next Floor at the top, the next floor loads", InStr(clicks, ",121;") && loaded = "Misty Village" && !lobby, clicks " / lobby " lobby)
Check("  floor 4 now, said in the log", towerFloor = 4 && InStr(lg, "Floor 3 cleared"), towerFloor " | " lg)
lastResult := "loss", shown := Map("Retry", [488, 121]), endUp := true, clicks := "", loaded := "", lobby := 0
TowerNext()
Check("a loss with Retry: that floor again", InStr(clicks, "488,121;") && loaded = "Misty Village" && towerFloor = 4, clicks)
lastResult := "loss", shown := Map("Return", [312, 121]), endUp := true, clicks := "", lobby := 0
TowerNext()
Check("a loss without Replay / Retry: the lobby (the same floor next)", lobby = 1 && !InStr(clicks, "312,121"), clicks " / lobby " lobby)
lastResult := "win", shown := Map("Next", [470, 121]), works := false, endUp := true, clicks := "", loaded := "", lobby := 0
TowerNext()
Check("Next Floor pressed but nothing happened: the lobby", lobby = 1 && loaded = "", clicks)
cfg["towerMatch"] := 1, works := true, shown := Map("Next", [470, 121]), endUp := true, clicks := "", lobby := 0
TowerNext()
Check("Find Match: the lobby for a new match", lobby = 1 && !InStr(clicks, "470,121"), clicks)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
tw = re.search(r"^TowerWindowUp\(\) =>.*$", mis, re.M); tw = tw.group(0) if tw else ""
print(("PASS" if "OcrFindWord(160, 172, 330, 30," in tw and "^misty$" not in tw else "FAIL") + " the tower window's title read where it sits (y 172-202), not Misty Village's window by 'Misty'")
tl = re.search(r"^TowerTitle\(\) \{.*?^\}", mis, re.S | re.M); tl = tl.group(0) if tl else ""
print(("PASS" if "OCR.FromRect(ox + 355, oy + 212, 200, 32," in tl else "FAIL") + " the panel's title read where it sits (Misty Tower: Floor N, x 355-555, y 212-244)")
print(("PASS" if not re.search(r"^(TowerWords|TowerFloorsIn|TowerFloorPick)\(", mis, re.M) else "FAIL") + " no floor clicked from the list any more")
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
