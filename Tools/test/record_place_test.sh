#!/bin/bash
# "Record my placing" (from another macro's "Record a run: smart placement learns where your units stand", Chris
# 24 Nov: "you choose"; Zak 23 Nov: the walk's spot on Space Center had nowhere to place). Like Record walk: it
# teleports, lines up the camera and walks the map's walk, then you place your units by hand and each one placed
# is saved as a spot, in order (F6 when done, F3 cancels). Placed = a unit picked first (1-6, or its card on the
# hotbar), then a click in the game, then its menu opens (a click on a unit already there, or a refused spot,
# isn't one). The map's spots are replaced by these and Use my spots goes on.
# Chris's Dungeon Macro.ahk RecordPlacing, PlaceInput. Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys
T, root = sys.argv[1], sys.argv[2]
main = open(f"{root}/Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read()
html = open(f"{root}/UI/index.html", encoding="utf-8").read()
missing = []
def fn(n, s=main):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", s, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) =>.*?(?=\n\S)", s, re.S | re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + "(p*) => false"
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, lg := "", note := "", cfg := Map("spots", Map("Space Center", [{x: 1, y: 1}]), "useSpots", 0)
global running := false, manualRun := false, cancelManual := false, RBX := "ahk_id 100", walkWho := 0, events := [], menus := [], walked := ""
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
AddLog(t) {
    global lg
    lg .= t "|"
}
Notify(t, p*) {
    global note
    note := t
}
WinExist(w) => true
ToolTip(p*) => 0
FocusRoblox() => 0
ReleaseKeys() => 0
SaveConfig() => 0
SendSpots(p*) => 0
WalkBusy() => Notify("busy")
GoToSpot(m, walk := true, force := false) {
    global walked
    walked := m " walk " walk " force " force
}
PlaceKey(n) => n
AltSpotsKey(n, who) => n " alt " who
; the player's actions, one per look: "arm" "cancel" "click x y" "done" "quit"
PlaceInput(&x, &y) {
    if !events.Length
        return "done"
    e := StrSplit(events.RemoveAt(1), " ")
    if e[1] = "click"
        x := Integer(e[2]), y := Integer(e[3])
    return e[1]
}
WaitUnitMenu(ms) => menus.Length ? menus.RemoveAt(1) : false
''' + "\n".join([fn("SpotsOf"), fn("RecordPlacing")]) + r'''

Spots() {
    s := ""
    for p in cfg["spots"]["Space Center"]
        s .= p.x "," p.y " "
    return Trim(s)
}
; 1 picked, placed (menu); a click on a unit already there (not picked); the hotbar card, a refused spot (no
; menu); 2 picked, Q (put back), a click; 3 picked, placed; F6
events := ["arm", "click 300 250", "click 400 260", "arm", "click 420 300", "arm", "cancel", "click 500 300", "arm", "click 450 330", "done"]
menus := [true, false, true]
RecordPlacing("Space Center")
Check("it goes to where the macro places from: teleport, camera, the map's walk", walked = "Space Center walk 1 force 1", walked)
Check("the two units placed are saved as the map's spots, in order (the old one replaced)", Spots() = "300,250 450,330", Spots())
Check("  a click on a unit already there, a refused spot, a unit put back (Q): not spots", !InStr(Spots(), "400,260") && !InStr(Spots(), "420,300") && !InStr(Spots(), "500,300"), Spots())
Check("  Use my spots switched on", cfg["useSpots"] = 1)
Check("  said: how many", InStr(note, "2 spots") && InStr(lg, "2 spots"), note " | " lg)
Check("  the macro free again afterwards", !manualRun)
cfg["spots"]["Space Center"] := [{x: 1, y: 1}], events := ["arm", "click 300 250", "quit"], menus := [true], note := ""
RecordPlacing("Space Center")
Check("cancelled (F3): nothing saved, the old spots kept", Spots() = "1,1", Spots())
events := ["click 300 250", "done"], menus := [true], note := ""
RecordPlacing("Space Center")
Check("done without placing anything: nothing saved, said", Spots() = "1,1" && InStr(note, "No units"), note)
running := true, note := "", events := ["arm", "click 1 2", "done"]
RecordPlacing("Space Center")
Check("the macro running: not started", note = "busy", note)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
pi = re.search(r"^PlaceInput\(&x, &y\) \{.*?^\}", main, re.S | re.M); pi = pi.group(0) if pi else ""
print(("PASS" if '"F6"' in pi and '"F3"' in pi and "vk3" in pi and '"RButton"' in pi and "LButton" in pi and re.search(r"y >= 500 \? \"arm\" : \"click\"", pi) else "FAIL")
      + " PlaceInput: F6 done, F3 quit, 1-6 or a hotbar card picks a unit, Q / right click puts it back, a click in the game")
print(("PASS" if re.search(r'case "recordPlacing": RecordPlacing\(mp\)', main) else "FAIL") + " the window's button starts it")
print(("PASS" if 'data-cmd="recordPlacing"' in html else "FAIL") + "   a Record my placing button on the Spots page")
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'; [ "${PIPESTATUS[0]}" = 124 ] && echo "FAILED (timed out)"
rm -rf "$T"
