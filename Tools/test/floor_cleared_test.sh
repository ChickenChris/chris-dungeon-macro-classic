#!/bin/bash
# RNG 9 Nov (3.2.120 recording): a dungeon floor won, Next pressed, "Money (Dungeon) x54" over the cleared
# floor. The macro took it for a new round: Tab, teleport, the camera line-up (whose click opened the
# C.E.O.'s upgrade menu in the middle), then "Run finished in 0m 12s". The next room's Enter got "Unable to
# teleport right now" from the game, and the cleared floor behind the room picker was taken as loaded:
# round and round. Lib\Engine.ahk OldRoundScreen, LoadStage, ZoomCameraNow, Tick. Run under Wine
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
    if not m:
        missing.append(n)
        return n + "(p*) => 0"
    return m.group(0)
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, logs := [], stageActive := false, postStage := 0, foolReplayAt := 0, cfg := Map("mode", "Dungeon", "useBuild", 1)
global curMap := "", curDepth := "", mapHow := "", prevDepth := "", lastMapRaw := "", played := false, roomsUp := false, enterUp := false
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
LogHas(t) {
    for m in logs
        if InStr(m, t)
            return true
    return false
}
FoolMode() => cfg["mode"] = "Fool's Hunt"
AddLog(t) => logs.Push(t)
Step(t) => 0
Snap() => 0
Wait(ms) => Sleep(ms)
UpdateMapLabel() => 0
SaneDepth(d) => d
MatchLoadingScreen() => ""
MapFromBanner() => ""
CheckConnection() => false
SaveDebugShot(p*) => 0
BuildSteps() => 0
IsLoaded() => true                       ; the yen and the unit bar show under the room picker too
InStageWorld() => true
Det(k) => k = "Enter" ? enterUp : false
ScanRooms() => roomsUp ? [{kind: "Available"}, {kind: "Available"}] : []
SpecialScreen() => false
PlayStage() {
    global played := true
}
''' + "\n".join(fn(n) for n in ["OldRoundScreen", "LoadStage"]) + r'''

; just after a won dungeon floor: its screen under the reward popups isn't a new round
postStage := A_TickCount - 2000, stageActive := false
Check("dungeon, a floor just won: the screen under the popups is the old round", OldRoundScreen())
stageActive := true
Check("a round playing: not that", !OldRoundScreen())
stageActive := false, postStage := 0
Check("no round ended yet (started mid-round): not that", !OldRoundScreen())
postStage := A_TickCount - 100000
Check("over 90 s after the results: not that any more", !OldRoundScreen())
postStage := A_TickCount - 2000, cfg["mode"] := "Fool's Hunt", foolReplayAt := 0
Check("Summer Hunt before Replay: the old round (as before)", OldRoundScreen())
foolReplayAt := A_TickCount
Check("Summer Hunt after Replay: a new round (as before)", !OldRoundScreen())
cfg["mode"] := "Infinity Castle"
Check("other modes: as before (not held back)", !OldRoundScreen())
cfg["mode"] := "Dungeon", postStage := 0

; the room's Enter pressed, the game says "Unable to teleport right now": the room picker stays up over
; the cleared floor (its yen and units count as loaded). Not taken as the new map: the room again
roomsUp := true, played := false, logs := []
t0 := A_TickCount
LoadStage("Dungeon Throne", 3, false, true)
Check("rooms still showing after Enter: not played as the new map", !played)
Check("  back to picking the room within 10 s", A_TickCount - t0 < 10000, A_TickCount - t0)
Check("  told in the log", LogHas("The room didn't load"), logs.Length ? logs[logs.Length] : "")
roomsUp := false, played := false, logs := []
t0 := A_TickCount
LoadStage("Dungeon Throne", 3, false, true)
Check("the map loaded (no rooms showing): played at once", played && A_TickCount - t0 < 2000, A_TickCount - t0)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
# the main loop holds a new round back on the old round's screen; the camera line-up closes a unit menu its
# click opened (it opened the C.E.O.'s in the middle of the cleared floor)
R=$(python3 - "$(pwd)" <<'P'
import re, sys
s = open(sys.argv[1] + "/Lib/Engine.ahk", encoding="utf-8-sig").read()
t = re.search(r"^Tick\(\) \{.*?^\}", s, re.S | re.M).group(0)
z = re.search(r"^ZoomCameraNow\(.*?^\}", s, re.S | re.M).group(0)
ok1 = re.search(r"if OldRoundScreen\(\) \{\s*\n\s*IdleTick\(\)\s*\n\s*return", t) is not None and t.index("OldRoundScreen()") < t.index("PlayStage()")
ok2 = re.search(r"if NewMenu\(\)\s*\n?\s*Clk\(277, 226\)", z[z.index("WheelDown"):] if "WheelDown" in z else "") is not None
print(("PASS" if ok1 else "FAIL") + " the main loop: the old round's screen waits (popups clicked away), not played")
print(("PASS" if ok2 else "FAIL") + " the camera line-up closes a unit menu its click opened")
P
)
echo "$R"
OUT=$(WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r')
rm -rf "$T"
if echo "$R" | grep -q "^FAIL"; then echo "$OUT" | grep -v "ALL PASSED"; echo "FAILED (static)"; else echo "$OUT"; fi
