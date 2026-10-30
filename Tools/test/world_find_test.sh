#!/bin/bash
# The Story pad's Select World list (WorldFind in Lib\Story.ahk): read a notch at a time down to the
# bottom, then back up (a player's Shibuya District was never matched on the way down, only the
# bottom of the list was in the log). The list and the reader are faked. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Story.ahk", encoding="utf-8-sig").read() + "\n" + open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => ""'
parts = [fn(n) for n in ["WorldFind", "WorldRead", "WorldLineIs", "WorldRegex", "FoldOcr", "Levenshtein", "FuzzyPick"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, worldLastRead := "", RBX := "WorldFindTestWindow", pos := 0, lastDir := 0, blurDown := false, scrolls := 0
g := Gui(, RBX), g.Show("x0 y0 w800 h600 NA")
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
; the list: 3 worlds show at a time; a notch moves it one world
LIST := ["Planet Greenie", "Walled City", "Snowy Town", "Sand Village", "Navy Bay", "Fiend City", "Spirit World", "Ant Kingdom",
    "Magic Town", "Haunted Academy", "Space Center", "Alien Spaceship", "Fabled Kingdom", "Ruined City", "Puppet Island",
    "Virtual Dungeon", "Snowy Kingdom", "Shibuya District", "Dungeon Throne", "Mountain Temple"]
ScrollAt(x, y, n) {
    global pos, lastDir, scrolls
    scrolls++, lastDir := n > 0 ? 1 : -1
    pos := Max(0, Min(LIST.Length - 3, pos + n))
}
class OCR {
    static FromRect(*) {
        lines := []
        loop 3 {
            t := LIST[pos + A_Index]
            if blurDown && lastDir = 1 && t = "Shibuya District"      ; still sliding on the way down
                t := "Sh!b~ya D!s"
            lines.Push({Text: t, x: 10, y: A_Index * 90, w: 120, h: 16})
        }
        return {Lines: lines}
    }
}
OcrLang() => "en"
ClosePopups() => false
DeclineTrade() => false
INF_MAPS() => LIST
Wait(ms) => 0
'''
body += "\n".join(parts) + "\n"
body += r'''
x := 0, y := 0
pos := 0, blurDown := false
Check("read clearly on the way down: found", WorldFind("Shibuya District", INF_MAPS(), &x, &y) && x = 685, x)
pos := 0, blurDown := true
Check("passed on the way down (still sliding): found on the way back up", WorldFind("Shibuya District", INF_MAPS(), &x, &y))
pos := 0, blurDown := false, scrolls := 0
Check("a world that isn't there: not found, and it stops (no endless scrolling)", !WorldFind("Nowhere Land", INF_MAPS(), &x, &y) && scrolls < 80, scrolls)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
