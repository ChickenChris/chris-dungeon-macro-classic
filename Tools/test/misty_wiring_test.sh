#!/bin/bash
# The Misty Tower wired into Classic (Chris 23 Nov: "Make towers for classic too but not bring alt and multi
# account"): a Classic mode (the settings, the Order list), towerMatch saved, the lobby starting it, "Open
# Portal? / Join Matchmaking?" left open answered, the floor's end (Next Floor), the old-round guard, the
# window's mode row with its Play Here / Find Match, and no alts. Static, and app.js must still parse
cd "$(dirname "$0")/../.."
python3 - "$(pwd)" <<'P'
import re, sys, subprocess
root = sys.argv[1]
main = open(f"{root}/Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read()
eng = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
story = open(f"{root}/Lib/Story.ahk", encoding="utf-8-sig").read()
app = open(f"{root}/UI/app.js", encoding="utf-8").read()
html = open(f"{root}/UI/index.html", encoding="utf-8").read()
fails = 0
def check(name, ok):
    global fails
    print(("PASS " if ok else "FAIL ") + name); fails += not ok
lists = re.findall(r'\["Dungeon", "Legend", "Raid", "Infinity Castle", "Fool\'s Hunt"((?:, "[^"]+")*)\]', main)
check("a Classic mode: in every list of Classic's modes (settings, copied settings, the Order list)", len(lists) == 4 and all('"Misty Tower"' in x for x in lists))
check("towerMatch has a default", re.search(r'"towerMatch", 0', main) is not None)
sv = [l for l in main.splitlines() if '"raidMatch"' in l and '"bgOpacity"' in l]
check("  and is saved", bool(sv) and '"towerMatch"' in sv[0])
check("Lib\\Misty.ahk included", "#Include %A_ScriptDir%\\Lib\\Misty.ahk" in main)
lob = re.search(r"    if Det\(\"Lobby\"\) \{.*?\n    \}", eng, re.S); lob = lob.group(0) if lob else ""
check("the lobby starts it", "else if TowerMode()\n            StartTower()" in lob)
left = re.findall(r"if \(ICMode\(\) \|\| LegendMode\(\) \|\| RaidMode\(\)((?: \|\| \w+\(\))*)\)", eng)
check("Open Portal? / Join Matchmaking? left open: answered for it too", len(left) == 2 and all("TowerMode()" in x for x in left))
he = re.search(r"^HandleEnd\(\) \{.*?^\}", eng, re.S | re.M); he = he.group(0) if he else ""
check("the floor's end: TowerNext", "if TowerMode() {\n        TowerNext()\n        return\n    }" in he)
ors = re.search(r"^OldRoundScreen\(\) \{.*?^\}", eng, re.S | re.M); ors = ors.group(0) if ors else ""
check("the old-round guard knows it", '"Misty Tower"' in ors)
check("RaidWaitMatch names what it waits for (the tower's Find Match)", re.search(r'^RaidWaitMatch\(what := "raid"\)', story, re.M) is not None)
mo = re.search(r"^const MODES = \[(.*)\];", app, re.M)
fm = re.search(r"^const FREE_MODES = \[(.*?)\];", app, re.M)
check("the window's modes: the Misty Tower, free in Classic", bool(mo) and '"Misty Tower"' in mo.group(1) and bool(fm) and '"Misty Tower"' in fm.group(1))
css = open(f"{root}/UI/app.css", encoding="utf-8").read()
check("  eight modes: two rows of four (one row cut the Misty Tower off)", "#segModeHome { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr));" in css)
check("  its Play Here / Find Match", 'id="towerSub"' in html and 'id="segTowerJoin"' in html and 'setVal("towerMatch", i)' in app
      and '$("#towerSub").classList.toggle("open", isTower())' in app)
ts = re.search(r'<div class="mode-sub" id="towerSub">.*?</div></div>', html, re.S); ts = ts.group(0) if ts else ""
check("  no alts or Multi Roblox there", bool(ts) and "foolOwnTeam" not in ts and "multiRoblox" not in ts)
r = subprocess.run(["node", "-e", "new Function(require('fs').readFileSync(process.argv[1],'utf8'))", f"{root}/UI/app.js"], capture_output=True, text=True)
check("app.js parses", r.returncode == 0)
print("ALL PASSED" if not fails else "FAILED %d" % fails)
sys.exit(1 if fails else 0)
P
