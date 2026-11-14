#!/bin/bash
# Hill units (Lib\Engine.ahk HillPoints): the view before and while the unit is held, faked; cells that
# are pure green while it is held are hills (green text is not), spots in the biggest hill first, a hill's middle first. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" <<'P'
import re, sys
src = open("Lib/Engine.ahk", encoding="utf-8-sig").read()
fn = re.search(r"^HillPoints\(.*?^\}", src, re.S | re.M).group(0) + "\n" + re.search(r"^HillGreen\(.*$", src, re.M).group(0)
m = re.search(r"^HillComps\(.*?^\}", src, re.S | re.M)
fn += "\n" + (m.group(0) if m else "")
srt = re.search(r"^SortByDistance\(.*?^\}", src, re.S | re.M).group(0) + "\n" + re.search(r"^IndexOf\(.*?^\}", open("Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read(), re.S | re.M).group(0)
real = re.search(r"^HillGrid\(.*?^\}", src, re.S | re.M).group(0).replace("HillGrid(", "HillGridReal(", 1).replace("WinGetClientPos &ox, &oy, , , RBX", "ox := 0, oy := 0")
import os
root = os.getcwd()
fx = "Z:" + (root + "/Tools/test/fixtures/hill_snowy_held.bmp").replace("/", "\\")
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
#Include ROOT\Lib\FindText.ahk
global fails := 0, grids := [], logs := "", stageStart := 1, RBX := ""
Snap() => 0
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok || got = "" ? "" : " (got " got ")") "`n", "*", "UTF-8"), fails += !ok
}
global did := ""
Keys(k) {
    global did
    did .= "key " k ";"
}
ClearVote() => 0
CardsPause() => 0
Stale() => 0
SaveDebugShot(t) {
    global did
    did .= "shot " t ";"
}
AddLog(t) {
    global logs
    logs .= t "|"
}
HillGrid(step) {                                ; the views in turn, the last one stays
    global grids
    g := grids.Length > 1 ? grids.RemoveAt(1) : grids[1]
    return g = "real" ? HillGridReal(step) : g
}
global hillCol := [0, 200, 0]
; a grey view; `hills`: boxes [x1, y1, x2, y2] that turn green while held, the rest turns red
View(hills, held) {
    g := Map(), y := 96
    while y <= 500 {
        x := 30
        while x <= 760 {
            hill := false
            for h in hills
                hill := hill || (x >= h[1] && x <= h[3] && y >= h[2] && y <= h[4])
            g[x * 10000 + y] := !held ? [90, 90, 90] : hill ? hillCol : (y > 450 ? [95, 255, 71] : [160, 60, 60])
            x += 12
        }
        y += 12
    }
    return g
}
''' + srt + "\n" + fn + "\n" + real + r'''
small := [400, 300, 440, 330], big := [100, 150, 220, 250]
grids := [View([small, big], true)]
pts := HillPoints(4)
inBox(p, b) => p.x >= b[1] && p.x <= b[3] && p.y >= b[2] && p.y <= b[4]
Check("spots found (" pts.Length ")", pts.Length >= 6)
Check("the biggest hill first", inBox(pts[1], big))
Check("its middle first (" pts[1].x "," pts[1].y ")", Abs(pts[1].x - 160) <= 12 && Abs(pts[1].y - 200) <= 12)
ok := true
for p in pts
    ok := ok && (inBox(p, big) || inBox(p, small))
Check("every spot on a hill", ok)
Check("the small hill too", inBox(pts[pts.Length], small))
; RNG 13 Nov: "placing multiple hill units ... tries to place it almost at the same spot, but fails due to
; the hitbox". A hill's spots 12 px apart all sat inside the first unit: now at least 30 px apart
near := 99999
loop 4 {
    i := A_Index
    loop 4
        if A_Index > i
            near := Min(near, Sqrt((pts[i].x - pts[A_Index].x) ** 2 + (pts[i].y - pts[A_Index].y) ** 2))
}
Check("a hill's first 4 spots at least 30 px apart (" Round(near) ")", near >= 30)
Check("says it saw 2 hills", InStr(logs, "2 hills seen"))
stageStart := 2, logs := ""
grids := [View([], true)]
did := ""
Check("no green: no spots, and it says so", HillPoints(4).Length = 0 && InStr(logs, "no hills seen"))
; RNG 13 Nov: green hills not seen on Mountain Temple / a snowy map ("might be lighting"). The picture was
; taken after the unit was put back (no green on it): now while it's still held, to see the real colours
Check("  its picture taken while the unit is still held", RegExMatch(did, "shot hill;.*key q;"), did)

; a player's Snowy Kingdom (8 Nov): the map's blue light makes the hills (20-60, 240, 110-160), not pure
; green, and they lit up a moment after the unit was picked up (looked once at 0.45 s: none, then 15
; ground spots tried, "Cannot place unit here!")
stageStart := 3, logs := "", hillCol := [40, 240, 140]
grids := [View([big], true)]
Check("Snowy Kingdom's blue-green hills are hills", HillPoints(4).Length >= 6)
stageStart := 4, logs := "", hillCol := [0, 200, 0]
grids := [View([], true), View([], true), View([big], true)]
pts := HillPoints(4)
Check("the hills light up late: looked again, found", pts.Length >= 6 && inBox(pts[1], big))
; RNG 14 Nov (Alt 2, Spirit Town): picked up and put back 0.48 s later, "no hills seen": 3 scattered green
; points (text) ended the look before the roofs lit up. It looks until it sees a hill, not 3 green points
stageStart := 6, logs := ""
Scatter() {
    g := View([], true)
    for k in [42 * 10000 + 108, 306 * 10000 + 204, 498 * 10000 + 396]
        g.Has(k) ? g[k] := [0, 200, 0] : 0
    return g
}
grids := [Scatter(), Scatter(), View([big], true)]
pts := HillPoints(4)
Check("3 green points but no hill yet: looked again until the hill lit up", pts.Length >= 6 && inBox(pts[1], big), pts.Length)
; RNG 14 Nov: Summer Hunt's Level Modifiers list runs down to y 425 on the right; its green "Magic
; Resistance: -60" was a hill at 702,420. The grid leaves the right-hand panel out down to the minimap
g := HillGridReal(12), inPanel := 0
for k in g
    inPanel += k // 10000 >= 630 && Mod(k, 10000) >= 160 && Mod(k, 10000) < 440
Check("the grid leaves out the info panel down to the minimap (y 160-440 on the right)", inPanel = 0, inPanel)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
body = body.replace("ROOT", "Z:" + root.replace("/", "\\\\")).replace("FX", fx)
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 60 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
