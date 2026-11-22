#!/bin/bash
# A new round with its Vote start up isn't the old round (Lib\Engine.ahk OldRoundScreen). For 90 s after a
# round ends, a round screen counts as the old round under reward popups (its popups get clicked away, so a
# cleared floor isn't played again). A player 22 Nov (debug_20261122_070208, Ant Kingdom depth 19): the room's
# loading was taken as "didn't load" after 8 s, and when the new room showed, its Vote start sat there while
# the macro clicked "reward popups" for a minute; the vote ran out, the round started without it: Defeat,
# and "Stop after a defeat" stopped the macro. A Vote start is only ever on a new round: played at once.
# (The detector sees that player's vote in the game: at 07:28:14 the same recording pressed its Yes.) Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys
T, root = sys.argv[1], sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
m = re.search(r"^OldRoundScreen\(\) \{.*?^\}", src, re.S | re.M)
fn = m.group(0) if m else "OldRoundScreen() => true"
art = bool(m) and '"Artifact"' in m.group(0)       # (Classic has no Artifact mode)
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, cfg := Map("mode", "Dungeon"), stageActive := false, postStage := 0, foolReplayAt := 0
global voteUp := false, fool := false
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
FoolMode() => fool
Det(name, &x := "", &y := "") => name = "VoteStart" && voteUp
''' + fn + r'''

for m in ["Dungeon", "Raid", "Legend"] (ART ? ["Artifact"] : []) {
}
modes := ["Dungeon", "Raid", "Legend"]
if ART
    modes.Push("Artifact")
for m in modes {
    cfg["mode"] := m, fool := false, stageActive := false, postStage := A_TickCount - 30000
    voteUp := true
    Check(m ": 30 s after a round, a round screen WITH its Vote start: a new round (played)", !OldRoundScreen())
    voteUp := false
    Check("  without a vote: still the old round (its popups clicked away)", OldRoundScreen())
}
cfg["mode"] := "Summer Hunt", fool := true, foolReplayAt := 0, postStage := A_TickCount - 30000
voteUp := true
Check("Summer Hunt, Replay not pressed yet but a Vote start up: a new round", !OldRoundScreen())
voteUp := false
Check("  without a vote: the old round, as before", OldRoundScreen())
cfg["mode"] := "Dungeon", fool := false, postStage := A_TickCount - 95000
Check("over 90 s after: never the old round (as before)", !OldRoundScreen())
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
body = body.replace('for m in ["Dungeon", "Raid", "Legend"] (ART ? ["Artifact"] : []) {\n}\n', "").replace("ART", "true" if art else "false")
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
