#!/bin/bash
# Summer Hunt on Snowy Kingdom: the results' Replay is green, not yellow (Chris 10 Nov 21:30, log__37 and
# debug_20261110_205602: the main never pressed it, took the results for a new round and sat there an
# hour; 9 Nov both alts "couldn't find its Replay button" there). Lib\Engine.ahk FindOpenDungeon. Wine
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
    missing.append(n)
    return n + "(p*) => false"
def scene(right, bar=False, one=False):
    # the results' two buttons as measured on Chris's frame: 228-394 and 406-568, rows 100-139
    im = Image.new("RGB", (800, 599), (40, 100, 190)); d = ImageDraw.Draw(im)
    if bar:
        d.rectangle((158, 74, 642, 86), fill=(30, 230, 20))         # a full green health bar
    d.rectangle((226, 98, 396, 141), fill=(0, 0, 0)); d.rectangle((228, 100, 394, 139), fill=(19, 255, 0))
    if not one:
        d.rectangle((404, 98, 570, 141), fill=(0, 0, 0)); d.rectangle((406, 100, 568, 139), fill=right)
    for x in range(250, 380, 18):                                    # white letters across both
        d.rectangle((x, 112, x + 9, 128), fill=(255, 255, 255))
    for x in range(440, 540, 18):
        d.rectangle((x, 112, x + 9, 128), fill=(255, 255, 255))
    return im
scene((79, 230, 0)).save(T + "/green.bmp")
scene((255, 190, 0)).save(T + "/yellow.bmp")
scene((79, 230, 0), one=True).save(T + "/one.bmp")
im = Image.new("RGB", (800, 599), (40, 100, 190)); d = ImageDraw.Draw(im)
d.rectangle((158, 74, 642, 86), fill=(30, 230, 20)); d.rectangle((330, 160, 470, 175), fill=(40, 220, 30))
im.save(T + "/bar.bmp")                                              # a full green bar, "Wave Completed!"-wide green text
im = Image.new("RGB", (800, 599), (40, 100, 190)); d = ImageDraw.Draw(im)
d.rectangle((158, 70, 500, 90), fill=(30, 230, 20))                  # a health bar 70% full (342 px, like both buttons)
im.save(T + "/bar70.bmp")
real = f"{root}/Tools/test/fixtures/fool_win_green_replay.bmp"
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
''' + "\n".join(fn(n) for n in ["MiddleOf", "FindOpenDungeon"]) + r'''

TryPic(pic, &x, &y) {
    FindText().ShowPic("W\" pic, 0)
    x := 0, y := 0
    return FindOpenDungeon(&x, &y)
}
ok := TryPic("green.bmp", &x, &y)
Check("green Return to lobby + green Replay (Snowy Kingdom): found", ok)
Check("  on the Replay (406-568 x 100-139), not on Return to lobby", ok && x >= 430 && x <= 545 && y >= 100 && y <= 139, x "," y)
ok := TryPic("yellow.bmp", &x, &y)
Check("green + yellow (the other maps): still found, on the Replay", ok && x >= 430 && x <= 545, ok " " x "," y)
Check("one green button alone: not taken for the Replay", !TryPic("one.bmp", &x, &y))
Check("a green health bar and green text: not taken for the buttons", !TryPic("bar.bmp", &x, &y))
Check("a health bar as wide as both buttons (starts at 158, not 228): not taken for them", !TryPic("bar70.bmp", &x, &y))
if HAVE {
    ok := TryPic("real.bmp", &x, &y)
    Check("Chris's frame (Snowy Kingdom, Wave 50, Waiting for Players 0/3): found", ok)
    Check("  on its Replay (403-572 x 100-139)", ok && x >= 430 && x <= 545 && y >= 100 && y <= 139, x "," y)
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
