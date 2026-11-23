#!/bin/bash
# The camera always faces up before the walk and the Start vote (Chris 20 Nov: "make it so the cameras
# always have to point upwards before clicking start to the round? and then it start moving", "if it
# points any way but up it will zoom in and then use arrow keys left or right"). Lunoc 19 Nov (log 60):
# the camera faced down, the turn fell short at left, and the walk's keys were turned to match: the spots
# were off. Now every map and walk is lined up facing up; the line-up is done again (3 tries in all) while
# the camera doesn't face up; the key turn is only what's left after that. The walk recorder lines it up
# facing up too, so new walks are made facing up. Lib\Engine.ahk GoToSpot. Wine
# Chris 23 Nov (laptop, Haunted Mansion, debug_20261123_132421): the camera faced left, nothing was turned and
# nothing said. The zoom's click opened an alt's profile (it stood on the same spot) lower than where it was
# looked for, so it stayed open through the line-up; and the arrow read once, not seen, ended it silently. Now
# the arrow is read again for a moment when it isn't seen, the profile is closed wherever it opened, and a
# camera left the wrong way (or an arrow never seen) is said in the log with a screenshot (Logs\camera_....bmp).
# Lib\Engine.ahk MiniFacingRead, CamUnseen, TurnCamera, ZoomCameraNow
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
src = open(sys.argv[2] + "/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) =>.*$", src, re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + "(p*) => 0"
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, logs := [], foolVotes := 0, altDepth := 0
global cfg := Map("tpSpawn", 1, "zoom", 1, "walks", Map("Up Map", "face:0,w+0,w-500", "Side Map", "face:90,w+0,w-500", "Old Map", "w+0,w-500"))
global face := 0, turnsTo := Map(), zooms := [], walkedFacing := -9, reads := [], shots := [], stageStart := 1, RBX := "main"
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
AddLog(t) => logs.Push(t)
LogHas(t) {
    for l in logs
        if InStr(l, t)
            return true
    return false
}
TeleportToSpawn() => 0
ClearVote() => 0
VoteOnScreen() => false
WalkKey(m) => m
PlaceKey(m) => m
MiniFacing() => reads.Length ? reads.RemoveAt(1) : face   ; (reads: what the next reads see first)
Stale() => 0
SaveDebugShot(t) => shots.Push(t)
CamKeys() => {work: 1, sign: 1}
KeyTurn(p*) => ""
CamTurn(p*) => ""
CamNudge(p*) => 0
AltName(p*) => "Alt"
ZoomCamera(want := -1) {                         ; each line-up turns the camera to where this try leaves it
    global face
    zooms.Push(want)
    if want >= 0 && turnsTo.Has(zooms.Length)
        face := turnsTo[zooms.Length]
}
WalkRoute(m) {
    global walkedFacing := face
}
''' + "\n".join(fn(n) for n in ["GoToSpot", "RouteFace", "FaceName", "MiniFacingRead", "CamUnseen", "TurnCamera"]) + r'''
Reset(f, tt) {
    global
    face := f, turnsTo := tt, zooms := [], logs := [], walkedFacing := -9, reads := [], shots := []
}
Wanted() {
    s := ""
    for z in zooms
        s .= z " "
    return Trim(s)
}
; Lunoc: down, the first turn stops at left, the second gets it up
Reset(180, Map(1, 270, 2, 0))
GoToSpot("Up Map")
Check("the turn fell short (left): lined up again, facing up before the walk", zooms.Length = 2 && walkedFacing = 0, Wanted() " walked " walkedFacing)
Check("  told in the log", LogHas("still faces left") && LogHas("lining it up again"), logs.Length ? logs[1] : "")
Reset(180, Map(1, 0))
GoToSpot("Up Map")
Check("up after the first line-up: once", zooms.Length = 1 && walkedFacing = 0 && !LogHas("again"), Wanted())
Reset(180, Map())
GoToSpot("Up Map")
Check("a camera that doesn't turn at all: 3 tries, then the walk (its keys turned)", zooms.Length = 3 && walkedFacing = 180, Wanted() " walked " walkedFacing)
Reset(-1, Map())
GoToSpot("Up Map")
Check("the arrow not seen: once, as before", zooms.Length = 1 && walkedFacing = -1, Wanted())
; up for every walk and map
Reset(90, Map(1, 0))
GoToSpot("Old Map")
Check("a walk without a mark, the camera facing right: turned up (it was left alone)", Wanted() = "0" && walkedFacing = 0, Wanted())
Reset(270, Map(1, 0))
GoToSpot("No Walk Map")
Check("a map with no walk (placing from spawn): turned up too", Wanted() = "0", Wanted())
Reset(90, Map(1, 0))
GoToSpot("Side Map")
Check("a walk made facing right: turned up too (Chris 20 Nov: always up, its keys turned)", Wanted() = "0", Wanted())
Reset(90, Map(1, 0))
GoToSpot("Side Map", false, true)
Check("the walk recorder: lined up facing up, so the new walk is made facing up", Wanted() = "0", Wanted())
cfg["tpSpawn"] := 0, Reset(90, Map(1, 0))
GoToSpot("Up Map")
Check("no teleport to spawn: turned up all the same", Wanted() = "0", Wanted())
cfg["tpSpawn"] := 1
; ---- Chris 23 Nov, the laptop: an arrow not seen for a moment, a camera left the wrong way, said
Reset(90, Map())
reads := [-1, -1]
GoToSpot("Up Map")
Check("the arrow unseen for 2 reads, then right: still lined up again (not given up)", zooms.Length = 3, Wanted())
Check("  still right after 3 tries: said in the log, with a screenshot", LogHas("after 3 tries") && shots.Length = 1 && InStr(shots[1], "camera"), (logs.Length ? logs[logs.Length] : "") " | " shots.Length)
Reset(0, Map())
GoToSpot("Up Map")
Check("  facing up: nothing said, no screenshot", !LogHas("after 3 tries") && !shots.Length)
; TurnCamera's own read (zoomed in): read again for a moment, then said once per round with a screenshot
Reset(-1, Map())
ok := TurnCamera(0)
Check("TurnCamera: the arrow never seen: not turned, said once, a screenshot", !ok && LogHas("arrow on the minimap") && shots.Length = 1, logs.Length " " shots.Length)
TurnCamera(0)
Check("  not said again this round", logs.Length = 1 && shots.Length = 1, logs.Length)
global stageStart := 2
TurnCamera(0)
Check("  said again the next round", logs.Length = 2, logs.Length)
Reset(0, Map())
reads := [-1, -1, -1]
Check("  seen on the 4th read (up): fine, nothing said", TurnCamera(0) && !logs.Length, logs.Length)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
z = re.search(r"^ZoomCameraNow\([^)\n]*\) \{.*?^\}", src, re.S | re.M); z = z.group(0) if z else ""
i, j = z.find("ClosePlayerCard()"), z.find("TurnCamera(want)")
print(("PASS" if 0 <= i < j and "if PlayerCardUp()\n        ClosePlayerCard()" not in z else "FAIL") + " the zoom's click opened a profile: closed wherever it opened, before the turn (it was only looked for at the top right)")
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
