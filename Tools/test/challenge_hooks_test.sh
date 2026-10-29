#!/bin/bash
# Auto challenge's hooks at the end of a round (Lib\Engine.ahk HandleEnd, Lib\Story.ahk LegendReplay):
# a challenge round goes back to the lobby; Legend / Infinite / Infinity Castle leave for a due
# challenge only after counting the round; a dungeon is never left. The game is faked; under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
eng = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
story = open(f"{root}/Lib/Story.ahk", encoding="utf-8-sig").read()
def cut(src, n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M)
    return m.group(0) if m else ""
code = cut(eng, "HandleEnd") + "\n" + cut(story, "LegendReplay") + "\n"
# what the test decides
special = {
    "Det": "Det(n) => false", "FoolMode": "FoolMode() => mode = \"Fool's Hunt\"", "FoolDuo": "FoolDuo() => false",
    "LegendMode": "LegendMode() => mode = \"Legend\"", "InfMode": "InfMode() => mode = \"Infinite\"",
    "ICMode": "ICMode() => mode = \"Infinity Castle\"", "InfBest": "InfBest(p*) => (Note(\"InfBest;\"), 0)",
    "ChallengeLeave": "ChallengeLeave() => (due ? (Note(\"Leave;\"), true) : false)",
    "OcrFindWord": "OcrFindWord(x, y, w, h, re, &cx, &cy) => false", "INF_MAP": "INF_MAP() => \"Shibuya District\"",
    "LEGEND_WORLD": "LEGEND_WORLD() => \"Magic Hills (Elf Invasion)\"", "LEGEND_STAGE": "LEGEND_STAGE() => 1",
    "Summary": "Summary() => \"\"",
}
called = set(re.findall(r"\b([A-Z][A-Za-z_]\w*)\(", code)) - {"HandleEnd", "LegendReplay", "Map", "Max", "Min", "Round", "Abs", "Floor", "Mod", "InStr", "SubStr", "StrLen", "StrLower", "RegExMatch", "RegExReplace", "Integer", "String", "IsInteger", "IsNumber", "FormatTime", "Format", "StrSplit", "StrReplace", "Trim", "Sleep", "WinExist", "Number"}
stubs = [special.get(n, f'{n}(p*) => Note("{n};")') for n in sorted(called)]
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, calls := "", mode := "", due := false, challengeOn := false, lastResult := "win"
global cfg := Map("stopAfterDefeat", 0, "foolMatch", 0, "icHard", 0, "icStopFloors", 0)
global icFloors := 0, icFloor := 0, icUnlocked := 0, icUnlockedTop := 0, infWave := 12, infRuns := 0
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Note(t) {
    global calls
    calls .= t
}
Round_(m, d, c := false, r := "loss") {
    global
    mode := m, due := d, challengeOn := c, calls := "", lastResult := r
    HandleEnd()
    return calls
}
'''
body += "\n".join(stubs) + "\n" + code + ("\nglobal HAS_INF := " + ("1" if "InfMode()" in code else "0") + "\n")
body += r'''
c := Round_("Legend", false, true)
Check("a challenge round's end: back to the lobby its way, no Replay", InStr(c, "ChallengeEnded;") && !InStr(c, "ClickOpenDungeon"), c)
c := Round_("Dungeon", false, true)
Check("a challenge round from Dungeon mode: the same", InStr(c, "ChallengeEnded;") && !InStr(c, "ClickOpenDungeon"), c)
c := Round_("Dungeon", true)
Check("Dungeon: no leaving at a room's end (next room)", InStr(c, "ClickOpenDungeon;") && !InStr(c, "Leave") && !InStr(c, "ChallengeEnded"), c)
c := Round_("Legend", true)
Check("Legend, challenge due: leaves, no Replay", InStr(c, "Leave;") && !InStr(c, "ClickOpenDungeon"), c)
c := Round_("Legend", false)
Check("Legend, nothing due: Replay as before", InStr(c, "ClickOpenDungeon;") && !InStr(c, "Leave"), c)
if HAS_INF {                                     ; Premium only (Classic has no Infinite / Infinity Castle)
c := Round_("Infinite", true)
Check("Infinite, due: the wave counted first, then leaves", InStr(c, "InfBest;") && InStr(c, "Leave;") > InStr(c, "InfBest;") && !InStr(c, "ClickOpenDungeon"), c)
c := Round_("Infinity Castle", true, false, "win")
Check("Infinity Castle, due: the floor counted first, then leaves", icFloors = 1 && InStr(c, "Leave;") && !InStr(c, "ClickOpenDungeon"), c)
}
c := Round_("Fool's Hunt", false)
Check("Fool's Hunt: as before (no challenge)", InStr(c, "ClickOpenDungeon;") && !InStr(c, "Leave"), c)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
