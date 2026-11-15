#!/bin/bash
# AA's View Player (15 Nov): a click on another player's character opens their profile at the top right
# (Units / Titles, red X at 717,129). The camera zoom's click in the middle hit an alt standing on the
# same spot, and the profile stayed open over the 3rd Summer Hunt card (RNG 15 Nov,
# debug_20261115_133435). PlayerCardUp / ClosePlayerCard, called after the zoom's click and before a
# card vote. Lib\Engine.ahk. Wine
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
def scene(green, red):
    im = Image.new("RGB", (800, 599), (90, 70, 120)); d = ImageDraw.Draw(im)
    if green or red:
        d.rectangle((515, 125, 722, 360), fill=(30, 30, 40))              # the profile's dark box
    if green:
        for x1, x2 in ((525, 585), (589, 650)):                            # Units, Titles
            d.rectangle((x1, 204, x2, 220), fill=(60, 220, 30))
            for x in range(x1 + 8, x2 - 8, 10):
                d.rectangle((x, 208, x + 5, 216), fill=(250, 255, 245))
    if red:
        d.rectangle((706, 116, 730, 142), fill=(230, 20, 25))              # the X
        d.line((711, 121, 725, 137), fill=(255, 255, 255), width=3)
        d.line((725, 121, 711, 137), fill=(255, 255, 255), width=3)
    return im
scene(True, True).save(T + "/card.bmp")
scene(True, False).save(T + "/green.bmp")      # a green ground there (snowy_unit_held: 0.92 green)
scene(False, True).save(T + "/red.bmp")        # red roofs there (hill_striped_roofs: 0.80 red)
scene(False, False).save(T + "/none.bmp")
fx = f"{root}/Tools/test/fixtures"
have = os.path.exists(f"{fx}/player_card_over_cards.bmp")
if have:
    for n in ("player_card_over_cards", "player_card_open", "cards_no_player_card"):
        Image.open(f"{fx}/{n}.bmp").save(f"{T}/{n}.bmp")
W = "Z:" + T.replace("/", "\\")
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
#Include ROOT\Lib\FindText.ahk
global fails := 0, RBX := "", clicks := [], logs := [], cardUp := 0, menuUp := false
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Fresh() => 0
Wait(ms) => 0
AddLog(t) => logs.Push(t)
Step(t) => 0
FocusRoblox() => 0
TurnCamera(w) => 0
Stale() => 0
NewMenu() => menuUp
Clk(x, y) {
    global cardUp
    clicks.Push(x "," y)
    if x = 717 && y = 129 && cardUp > 0
        cardUp -= 1
}
''' + "\n".join(fn(n) for n in ["Pct", "ColorShare", "PlayerCardUp"]) + r'''
Joined(a) {
    s := ""
    for v in a
        s .= (s = "" ? "" : " ") v
    return s
}
Up(pic) {
    FindText().ShowPic("W\" pic, 0)
    return PlayerCardUp()
}
Check("a profile (green Units/Titles + red X): up", Up("card.bmp"))
Check("only green there: not a profile", !Up("green.bmp"))
Check("only red there: not a profile", !Up("red.bmp"))
Check("nothing: not a profile", !Up("none.bmp"))
if HAVE {
    Check("RNG's frame, the profile over the Summer cards: up", Up("player_card_over_cards.bmp"))
    Check("RNG's frame, the profile after the camera zoom: up", Up("player_card_open.bmp"))
    Check("RNG's frame, the cards without a profile: not up", !Up("cards_no_player_card.bmp"))
}

; from here PlayerCardUp is the fake below (the function under test calls it)
PlayerCardUpFake() => cardUp > 0
''' + "\n".join(fn(n).replace("PlayerCardUp()", "PlayerCardUpFake()") for n in ["ClosePlayerCard", "ZoomCameraNow"]) + r'''

cardUp := 1, clicks := [], logs := []
r := ClosePlayerCard()
Check("ClosePlayerCard: its X clicked once, true", r && Joined(clicks) = "717,129", r " / " Joined(clicks))
Check("  logged", logs.Length = 1 && InStr(logs[1], "View Player"), Joined(logs))
cardUp := 0, clicks := [], logs := []
r := ClosePlayerCard()
Check("no profile: nothing clicked, true", r && clicks.Length = 0, r " / " Joined(clicks))
cardUp := 9, clicks := []
r := ClosePlayerCard()
Check("a profile that won't close: tried twice, false", !r && Joined(clicks) = "717,129 717,129", r " / " Joined(clicks))
cardUp := 1, clicks := [], menuUp := false
ZoomCameraNow()
Check("the camera zoom's click opened a profile: closed", Joined(clicks) = "717,129" && cardUp = 0, Joined(clicks))
cardUp := 0, clicks := []
ZoomCameraNow()
Check("the camera zoom without a profile: no extra click", clicks.Length = 0, Joined(clicks))
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
# FoolCards closes it before it reads the cards (the 3rd card is under it): source check (a big function)
fc = re.search(r"^FoolCards\(\) \{.*?^\}", src, re.S | re.M).group(0)
a, b = fc.find("ClosePlayerCard()"), fc.find("for cx in voteNew")
body = body.replace("FileAppend(fails ?", 'Check("FoolCards closes a profile before it reads the cards", ' + ("1" if 0 <= a < b else "0") + ', "' + str(a) + ' vs ' + str(b) + '")\nFileAppend(fails ?', 1)
v = fc[max(0, a - 200):a]
body = body.replace("FileAppend(fails ?", 'Check("  with the vote click let through (voteClick)", ' + ("1" if a > 0 and "voteClick := true" in v else "0") + ')\nFileAppend(fails ?', 1)
# and wherever a click can land on a player (yaymlg / shaaaaark / a 4-alt player's recordings 15 Nov: a placing
# click on an alt opened its profile, then every placement there failed; one open at a round's end covers
# the results' XP Progress title, so Next wasn't pressed): before a placing try, before a unit is clicked,
# and on every pass of the main loop, before the round's end is looked for
def body_of(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M)
    return m.group(0) if m else ""
tp, ou, tk = body_of("TryPlace"), body_of("OpenUnit"), body_of("Tick")
ok_tp = 0 <= tp.find("ClosePlayerCard()") < tp.find("Keys(String(slot))")
ok_ou = 0 <= ou.find("ClosePlayerCard()") < ou.find("for o in tries")
ok_tk = 0 <= tk.find("PlayerCardUp()") < tk.find("EndButtonsSeen(true)")
for name, ok in (("a placing try closes a profile first", ok_tp), ("a unit click closes a profile first", ok_ou), ("the main loop closes a profile before it looks for the round's end", ok_tk)):
    body = body.replace("FileAppend(fails ?", 'Check("' + name + '", ' + ("1" if ok else "0") + ')\nFileAppend(fails ?', 1)
body = body.replace("ROOT", "Z:" + root.replace("/", "\\")).replace("W\\", W + "\\").replace("HAVE", "1" if have else "0")
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
