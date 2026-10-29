#!/bin/bash
# The Story pad (Lib\Story.ahk): the world list matching (Infinite's maps and the Legend worlds),
# the Legend stage reading, and the trade request finder. Run under Wine, no game needed: the
# functions are cut out of Story.ahk / Engine.ahk into one small script
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
import os
srcs = [open(f"{root}/Lib/{f}", encoding="utf-8-sig").read() for f in ("Story.ahk", "Engine.ahk") if os.path.exists(f"{root}/Lib/{f}")]
missing = []
def fn(n):
    for src in srcs:
        m = re.search(r"^" + n + r"\(\) => \[.*?\]$", src, re.S | re.M) or \
            re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or \
            re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
        if m:
            return m.group(0)
    missing.append(n)
    return ""
names = ["INF_MAPS", "LEGEND_WORLDS", "WorldLineIs", "WorldRegex", "FuzzyPick", "FoldOcr", "Levenshtein",
         "LegendStageOf", "LegendPickStage", "LegendBaseMap", "TradePopupAt", "IconPoints", "IconScore", "RedSpotAt"]
parts = [fn(n) for n in names]
if missing:                                      # still to be written: those checks fail, the rest run
    print("FAIL not defined: " + ", ".join(missing))
    parts += [n + '(p*) => "MISSING"' for n in missing]
body = "#Requires AutoHotkey v2.0\n#Warn VarUnset, StdOut\n"
body += 'OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))\n'
body += f'#Include "{"Z:" + root.replace("/", chr(92))}\\Tools\\test\\shot.ahk"\n'
body += "global fails := 0\n" + "\n".join(parts) + "\n"
body += 'Check(name, ok, got := "") {\n    global fails\n    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")\n    fails += !ok\n}\n'
q = lambda s: '"' + s.replace('"', '""') + '"'
# Infinite's maps (the checks inf_map_test.sh had)
for name, line, want in [("Shibuya District", "Shibuya District", 1), ("Shibuya District", "Shibuya Distric†", 1),
        ("Shibuya District", "ShibuyaDistrict", 1), ("Dungeon Throne", "Dungeon Throne", 1),
        ("Planet Namak", "Planet Namak", 1), ("Shibuya District", "Dungeon Throne", 0),
        ("Dungeon Throne", "Levels Cleared: 6/6", 0), ("Ant Kingdom", "Ant Kingdom", 1)]:
    body += f'Check({q(name + " regex vs " + line)}, !!RegExMatch({q(line)}, WorldRegex({q(name)})) = {want})\n'
for line, name, want in [("WaIIed City", "Walled City", 1), ("Wa1led City", "Walled City", 1), ("Shlbuya Distrlct", "Shibuya District", 1),
        ("Shibuya Distric†", "Shibuya District", 1), ("ShibuyaDistrict", "Shibuya District", 1), ("Levels Cleared: 6/6", "Shibuya District", 0),
        ("Infinite Record: N/A", "Walled City", 0), ("Snowy Kingdorn", "Snowy Kingdom", 1), ("Snowy Kingdorn", "Snowy Town", 0),
        ("Snowy Town", "Snowy Kingdom", 0), ("Wailed Ciity", "Walled City", 1), ("Ruined City", "Walled City", 0), ("Fiend City", "Walled City", 0),
        ("Magic Hills (Elf Invasion)", "Magic Hills", 0)]:
    body += f'Check({q(line + " is " + name + ": " + str(want))}, !!WorldLineIs({q(line)}, {q(name)}, INF_MAPS()) = {want})\n'
# the Legend worlds: brackets, misread letters, never a different world
for line, name, want in [("Magic Hills (Elf Invasion)", "Magic Hills (Elf Invasion)", 1), ("Ruined Clty (Midnlght)", "Ruined City (Midnight)", 1),
        ("Ruined City (Midnight)", "Fabled Kingdom (Generals)", 0), ("Magic Hills", "Magic Hills (Elf Invasion)", 0),
        ("Virtual Dungeon (Bosses)", "Virtual Dungeon (Bosses)", 1), ("Fabled Klngdom (Generals)", "Fabled Kingdom (Generals)", 1),
        ("Spirit lnvasion", "Spirit Invasion", 1), ("Space Center", "Spirit Invasion", 0), ("Dungeon Throne", "Rain Village", 0),
        ("Legend Stages", "Dungeon Throne", 0), ("Main Stages", "Space Center", 0)]:
    body += f'Check({q("legend: " + line + " is " + name + ": " + str(want))}, !!WorldLineIs({q(line)}, {q(name)}, LEGEND_WORLDS()) = {want})\n'
body += 'Check("brackets are plain text in a world regex", !!RegExMatch("Virtual Dungeon (Bosses)", WorldRegex("Virtual Dungeon (Bosses)")))\n'
body += 'Check("8 Legend worlds, Magic Hills (Elf Invasion) first", LEGEND_WORLDS().Length = 8 && LEGEND_WORLDS()[1] = "Magic Hills (Elf Invasion)")\n'
# the Legend stage column
for line, want in [("Legend Stage 3", 3), ("LegendStage 1", 1), ("LegendStage3", 3), ("Legend Stage l", 1), ("Legend Stage З", 3),
        ("Legend Stage 6", 6), ("Legend Stages", 0), ("Legend Stage 11", 0), ("Legend Stage 13", 0), ("Main Stages", 0), ("Legend Stage", 0)]:
    body += f'Check({q("stage of " + line + " = " + str(want))}, (g := LegendStageOf({q(line)})) = {want}, g)\n'
for want, seen, exp in [(5, "[1, 2, 3]", 3), (2, "[1, 2, 3]", 2), (4, "[]", 0), (1, "[2, 3]", 0), (6, "[4, 5, 6]", 6), (2, "[3, 4, 5, 6]", 0)]:
    body += f'Check({q(f"stage {want} of {seen} = {exp}")}, (g := LegendPickStage({want}, {seen})) = {exp}, g)\n'
for world, exp in [("Ruined City (Midnight)", "Ruined City"), ("Spirit Invasion", "Spirit World"), ("Dungeon Throne", "Dungeon Throne"),
        ("Magic Hills (Elf Invasion)", "Magic Hills"), ("Virtual Dungeon (Bosses)", "Virtual Dungeon")]:
    body += f'Check({q("base map of " + world)}, (g := LegendBaseMap({q(world)})) = {q(exp)}, g)\n'
# a trade request over the screen: found, and where its Decline button is (screenshots: game 8 px in, 31 down)
import os
if os.path.exists(f"{root}/Tools/test/fixtures/trade_request.bmp"):    # the pictures are Premium-only (Classic is public)
    fx = "Z:" + root.replace("/", chr(92)) + "\\Tools\\test\\fixtures\\"
    body += f'tr := Shot("{fx}trade_request.bmp"), pop := Shot("{fx}popup_exploding.bmp")\n'
    body += 'Check("trade request found", TradePopupAt(tr, 8, 31, 0, 0, 780, 560, &dx, &dy) && Abs(dx - 721) <= 3 && Abs(dy - 312) <= 3, (dx ?? "") "," (dy ?? ""))\n'
    body += 't := A_TickCount\nCheck("no trade request on a curse popup", !TradePopupAt(pop, 8, 31, 0, 0, 780, 560, &dx, &dy))\n'
    body += 'Check("looking for one is quick", A_TickCount - t < 1500, A_TickCount - t " ms")\n'
# the Tournament popup's red X: the middle of the red spot, not an orange or a tiny one
body += """class Fake {
    __New(sq) => this.sq := sq
    GetColor(x, y, *) {
        for s in this.sq
            if x >= s[1] && x < s[1] + s[3] && y >= s[2] && y < s[2] + s[3]
                return s[4]
        return 0x202020
    }
}
"""
body += 'Check("red X found at its middle", RedSpotAt(Fake([[500, 100, 16, 0xE02020], [430, 130, 30, 0x20C040]]), 0, 0, 400, 60, 640, 160, &cx, &cy) && Abs(cx - 507) <= 2 && Abs(cy - 107) <= 2, (cx ?? "") "," (cy ?? ""))\n'
body += 'Check("red X across two cells found at its middle", RedSpotAt(Fake([[470, 115, 16, 0xE02020]]), 0, 0, 400, 60, 640, 160, &cx, &cy) && Abs(cx - 477) <= 2 && Abs(cy - 122) <= 2, (cx ?? "") "," (cy ?? ""))\n'
body += 'Check("orange isn\'t red", !RedSpotAt(Fake([[500, 100, 16, 0xFF8040]]), 0, 0, 400, 60, 640, 160))\n'
body += 'Check("a red dot isn\'t an X", !RedSpotAt(Fake([[500, 100, 2, 0xE02020]]), 0, 0, 400, 60, 640, 160))\n'
body += 'Check("the game offset counts", RedSpotAt(Fake([[508, 131, 16, 0xE02020]]), 8, 31, 400, 60, 640, 160, &cx, &cy) && Abs(cx - 507) <= 2 && Abs(cy - 107) <= 2, (cx ?? "") "," (cy ?? ""))\n'
body += 'FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")\nExitApp fails ? 1 : 0\n'
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
if [ -s "$T/t.ahk" ]; then
    WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
fi
rm -rf "$T"
