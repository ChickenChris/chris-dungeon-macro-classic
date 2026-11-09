#!/bin/bash
# Walks turned to the camera (Chris 9 Nov, Dungeon Throne: the main and the alt played the same walk and
# ended in opposite places; on the minimap the main's arrow pointed down, the alt's up). A walk is
# W A S D, which go where the camera faces: it's played with its keys turned to match the camera it
# was made with. Lib\Engine.ahk MiniFacing, FacingOf, TurnRoute, RouteFace, WalkRoute. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys, os
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if not m:
        missing.append(n)
        return n + "(p*) => -1"
    return m.group(0).replace("WinGetClientPos &ox, &oy, , , RBX", "ox := 0, oy := 0")
fxdir = root + "/Tools/test/fixtures/"
fx = "Z:" + fxdir.replace("/", "\\")
haveFx = os.path.exists(fxdir + "facing_down_dungeon_throne.bmp")   # (Premium: players' frames stay out of Classic)
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
#Include ROOT\Lib\FindText.ahk
global fails := 0, RBX := "", logs := [], played := "", fakeFace := -1, altDepth := 0, walkFaces := Map(), walkedHere := false
global cfg := Map("walks", Map("Dungeon Throne", "face:180,w+0,d+0,w-700,s+900,s-1000,d-1200,Space+1300,Space-1400,end@1500", "Planet Greenie", "a+0,w+0,a-2200,w-2200,end@2200"))
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
Fresh() => 0
Step(t) => 0
AddLog(t) => logs.Push(t)
WalkKey(m) => m
PlaceKey(m) => m
BuiltInWalk(m) => ""
ClickWalk(p*) => 0
PlayRoute(r) {
    global played := r
}
''' + "\n".join(fn(n) for n in ["FacingOf", "TurnRoute", "RouteFace", "FaceName", "WalkRoute"]) + "\n" + fn("MiniFacing").replace("MiniFacing(", "MiniFacingReal(", 1) + r'''
MiniFacing() => fakeFace >= -1 ? fakeFace : MiniFacingReal()

; the arrow on the minimap, from your recordings
Facing(name, want) {
    global fails
    FindText().ShowPic("FX" name ".bmp", 0)
    got := MiniFacingReal()
    FileAppend((got = want ? "PASS " : "FAIL ") "arrow on " name ": " got (got = want ? "" : " (want " want ")") "`n", "*", "UTF-8")
    fails += got != want
}
if HAVEFX {
    Facing("facing_down_dungeon_throne", 180)
    Facing("facing_up_dungeon_throne_alt", 0)
    Facing("facing_up_tilted_planet_greenie", 0)
    Facing("facing_up_snowy_kingdom", 0)
    Facing("facing_left_turned", 270)
    Facing("facing_right_turned", 90)
}
; drawn arrows (6 x 4, like the game's): the open end is where the pixels spread
Arrow(rows) {
    m := Map()
    for y, r in rows
        loop parse r
            if A_LoopField = "#"
                m[(700 + A_Index) * 1000 + 500 + y] := 1
    return m
}
Check("drawn arrow v: down", FacingOf(Arrow(["#....#", "##.##.", ".###..", "..#..."])) = 180, FacingOf(Arrow(["#....#", "##.##.", ".###..", "..#..."])))
Check("drawn arrow ^: up", FacingOf(Arrow(["..##..", ".####.", "##..##", "#....#"])) = 0)
Check("drawn arrow <: left", FacingOf(Arrow(["...#", "..##", ".##.", "##..", ".##.", "..##", "...#"])) = 270)
Check("drawn arrow >: right", FacingOf(Arrow(["#...", "##..", ".##.", "..##", ".##.", "##..", "#..."])) = 90)
heart := Arrow(["..#....#.", "#########", "#########", "#########", "#########", ".#######.", "..#####..", "...###..."])
Check("the base's white heart isn't an arrow", FacingOf(heart) = -1, FacingOf(heart))
both := Arrow(["#....#", "##.##.", ".###..", "..#..."])
for k in Arrow(["..##..", ".####.", "##..##", "#....#"])
    both[k + 40000] := 1                                ; another white arrow 40 px to the right
Check("two white arrows: can't tell, nothing turned", FacingOf(both) = -1, FacingOf(both))

; the keys turned: the camera turned half way round = W<->S, A<->D; a quarter clockwise: W->A, D->W, S->D, A->S
Check("a walk's direction mark", RouteFace("face:180,w+0,w-500") = 180 && RouteFace("w+0,w-500") = -1 && RouteFace("click:400,300") = -1)
Check("turned half way", TurnRoute("face:180,w+0,d+0,w-700,Space+5,end@900", 180) = "face:180,s+0,a+0,s-700,Space+5,end@900", TurnRoute("face:180,w+0,d+0,w-700,Space+5,end@900", 180))
Check("turned a quarter clockwise", TurnRoute("w+0,d+10,s+20,a+30", 90) = "a+0,w+10,d+20,s+30", TurnRoute("w+0,d+10,s+20,a+30", 90))
Check("turned a quarter the other way", TurnRoute("w+0,d+10,s+20,a+30", 270) = "d+0,s+10,a+20,w+30", TurnRoute("w+0,d+10,s+20,a+30", 270))

; the walk itself: made facing down (Chris's main on Dungeon Throne)
fakeFace := 180, played := "", logs := []
WalkRoute("Dungeon Throne")
Check("camera faces down like the walk: played as it is", played = cfg["walks"]["Dungeon Throne"] && !LogHas("turned"), played)
fakeFace := 0, played := "", logs := []
WalkRoute("Dungeon Throne")
Check("camera faces up (the alt): W<->S and A<->D", played = "face:180,s+0,a+0,s-700,w+900,w-1000,a-1200,Space+1300,Space-1400,end@1500", played)
Check("  told in the log", LogHas("camera faces up, the walk was made facing down: its keys turned to match"), logs.Length ? logs[1] : "")
fakeFace := -1, played := ""
WalkRoute("Dungeon Throne")
Check("arrow not seen: played as it is", played = cfg["walks"]["Dungeon Throne"], played)
; no mark (older walks): played as it is; with alts (Premium), they turn to the main's camera of the stage
fakeFace := 0, played := "", altDepth := 0
WalkRoute("Planet Greenie")
Check("no mark, the main: played as it is", played = "a+0,w+0,a-2200,w-2200,end@2200", played)
if HASALTS {
    fakeFace := 180, played := "", altDepth := 1
    WalkRoute("Planet Greenie")
    Check("no mark, an alt facing the other way than the main: turned to the main's", played = "d+0,s+0,d-2200,s-2200,end@2200", played)
    fakeFace := 0, played := ""
    WalkRoute("Planet Greenie")
    Check("no mark, an alt facing like the main: as it is", played = "a+0,w+0,a-2200,w-2200,end@2200", played)
    altDepth := 0
}
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
body = body.replace("HAVEFX", "true" if haveFx else "false").replace("HASALTS", "true" if "global altDepth" in src else "false").replace("ROOT", "Z:" + root.replace("/", "\\")).replace("FX", fx)
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
# recording a walk keeps the camera's direction; Chris's Dungeon Throne walk is marked facing down
R=$(python3 - "$(pwd)" <<'P'
import sys, re
root = sys.argv[1]
main = open(f"{root}/Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read()
m = re.search(r"^RecordWalk\(name\) \{.*?^\}", main, re.S | re.M)
ok1 = bool(m) and "MiniFacing()" in m.group(0) and '"face:"' in m.group(0)
ini = open(f"{root}/Lib/defaults.ini", encoding="utf-16").read()
walks = ini.split("[Walks]")[1].split("\n[")[0] if "[Walks]" in ini else ""
old = ini.split("[OldWalks]")[1].split("\n[")[0] if "[OldWalks]" in ini else ""
dt = re.search(r"^Dungeon Throne=(.*)$", walks, re.M)
ok2 = bool(dt) and dt.group(1).startswith("face:180,w+0,d+0,w-703,")
ok3 = bool(re.search(r"^Dungeon Throne=w\+0,d\+0,w-703,", old, re.M)) if "Dungeon Throne" in walks else False
print(("PASS" if ok1 else "FAIL") + " recording a walk keeps which way the camera faced")
print(("PASS" if ok2 else "FAIL") + " Chris's Dungeon Throne walk marked: made facing down")
print(("PASS" if ok3 else "FAIL") + " the unmarked one in [OldWalks] (players who have it get the marked one)")
fc = re.search(r"^Future City \(Fool's Hunt\)=(.*)$", walks, re.M)
dc = re.search(r"^Future City=(.*)$", walks, re.M)
ok4 = bool(fc) and fc.group(1).startswith("face:180,a+0,s+1688,") and bool(dc) and not dc.group(1).startswith("face:")
print(("PASS" if ok4 else "FAIL") + " Chris's Summer Hunt walk for Future City shipped, made facing down (Inferno turns it round); the dungeon's unmarked")
P
)
echo "$R"
OUT=$(WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r')
rm -rf "$T"
if echo "$R" | grep -q "^FAIL"; then echo "$OUT" | grep -v "ALL PASSED"; echo "FAILED (static)"; else echo "$OUT"; fi
