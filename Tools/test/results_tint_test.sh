#!/bin/bash
# Summer Hunt VICTORY under the Sandstorm weather: the game's warm tint makes the results' "XP Progress"
# title cream (255,244,211), not white, so the results by colour were refused and the macro clicked
# around (325,185 + the corner) instead of pressing Next (Clone 15 Nov, debug_20261114_171937, Spirit
# World). Lib\Engine.ahk XpPanelUp / EndButtonsSeen. Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys, os
from PIL import Image, ImageDraw
T, root = sys.argv[1], sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M)
    if m:
        return m.group(0).replace("WinGetClientPos &ox, &oy, , , RBX", "ox := 0, oy := 0")
    m = re.search(r"^" + n + r"\([^)\n]*\) =>.*$", src, re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + "(p*) => false"
def scene(header):
    # the results as on Clone's frame: gold VICTORY (title middle ~334), the dark box, the green Next
    # (319,385), and the XP Progress panel on the right with its title at 592-700 x 136-150
    im = Image.new("RGB", (800, 599), (205, 110, 45)); d = ImageDraw.Draw(im)
    d.rectangle((175, 160, 495, 420), fill=(22, 16, 12))
    for x in range(200, 470, 34):                                    # VICTORY's letters
        d.rectangle((x, 168, x + 26, 205), fill=(255, 190, 40))
    d.rectangle((270, 373, 370, 398), fill=(40, 205, 30))            # Next
    for x in range(296, 345, 14):
        d.rectangle((x, 380, x + 7, 391), fill=(255, 255, 255))
    d.rectangle((520, 120, 790, 560), fill=(20, 15, 12))             # XP Progress panel
    if header:
        for x in range(592, 700, 9):                                 # its title's letters
            d.rectangle((x, 136, x + 6, 150), fill=header)
    return im
scene((240, 213, 172)).save(T + "/cream.bmp")    # the Sandstorm tint
scene((255, 255, 255)).save(T + "/white.bmp")    # no weather
scene(None).save(T + "/noheader.bmp")            # no XP panel title: a card vote's colours
scene((255, 170, 40)).save(T + "/orange.bmp")    # orange lava / fire where the title would be
real = f"{root}/Tools/test/fixtures/fool_win_sandstorm.bmp"
have = os.path.exists(real)
if have:
    Image.open(real).save(T + "/real.bmp")
W = "Z:" + T.replace("/", "\\")
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
#Include ROOT\Lib\FindText.ahk
global fails := 0, RBX := ""
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Fresh() => 0
Det(n) => false
VoteOnScreen() => false
PeopleListOver() => false
FindOpenDungeon(&x, &y) => false
''' + "\n".join(fn(n) for n in ["MiddleOf", "Pct", "ColorShare", "TitleColour", "NextByColour", "XpPanelUp", "EndButtonsSeen"]) + r'''

Seen(pic) {
    FindText().ShowPic("W\" pic, 0)
    return EndButtonsSeen(true)
}
Check("VICTORY with a cream XP Progress title (Sandstorm tint): the results", Seen("cream.bmp"))
Check("VICTORY with a white XP Progress title: still the results", Seen("white.bmp"))
Check("no XP Progress title: not the results (a card vote's colours)", !Seen("noheader.bmp"))
Check("orange where the title would be: not the results", !Seen("orange.bmp"))
if HAVE {
    Check("Clone's frame (Spirit World VICTORY, Sandstorm): the results", Seen("real.bmp"))
    FindText().ShowPic("W\real.bmp", 0)
    ok := NextByColour(&x, &y)
    Check("  its Next found (about 319,385)", ok && Abs(x - 319) <= 30 && Abs(y - 385) <= 15, ok " " x "," y)
}
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
body = body.replace("ROOT", "Z:" + root.replace("/", "\\")).replace("W\\", W + "\\").replace("HAVE", "1" if have else "0")
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
