#!/bin/bash
# "Save chests for after the boss" (HandleChests in Lib\Engine.ahk): a boss beaten in an earlier
# dungeon (or before a Stop) must not open the next dungeon's chests straight away (Apocalipse's
# chests were opened from the first rooms with the switch on). The game is faked. Run under Wine
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
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => ""'
parts = [fn(n) for n in ["HandleChests", "OpenDungeonFromLobby"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, opened := 0, bossDone := false, chestsDone := false, curDepth := 3, dungeonTotal := 20
global cfg := Map("saveChests", 1), stat := {chests: 0}, roomAhead := ""
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
OpenChestSlot(x, y) {
    global opened
    opened++
    return 1
}
AddLog(t) => 0
Step(t) => 0
Clk(p*) => 0
CloseChat() => 0
Det(p*) => false
WaitDet(p*) => false
ClickDet(p*) => 0
WaitFor(p*) => true
ScanRooms(p*) => []
SpecialScreen(p*) => false
EnterDungeonByColour(p*) => false
ClickDungeonContinue() => 0
LeavePopupUp() => false
PetChests(n) => 0
UpdateStats() => 0
'''
body += "\n".join(parts) + "\n"
body += r'''
opened := 0, bossDone := false, curDepth := 3
HandleChests()
Check("room 3, switch on: saved", opened = 0, opened)
bossDone := true                                ; the boss of the last dungeon (or one before a Stop)
OpenDungeonFromLobby()
opened := 0, curDepth := 2
HandleChests()
Check("a new dungeon from the lobby: its chests are saved again", opened = 0 && !bossDone, opened)
chestsDone := true
OpenDungeonFromLobby()
Check("a new dungeon: its chests aren't opened yet", !chestsDone)
opened := 0, curDepth := 20
HandleChests()
Check("its last room (depth 20 of 20): opened", opened > 0, opened)
cfg["saveChests"] := 0, bossDone := false, opened := 0, curDepth := 4
HandleChests()
Check("switch off: opened right away", opened > 0, opened)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
