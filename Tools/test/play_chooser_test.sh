#!/bin/bash
# UPD 21.5.0 (Chris 23 Nov, "new interference when you click on play"): the lobby's Play opens "Where do you
# want to Play?" (Summer Event / Misty Village / Regular Stages) instead of teleporting. The macro clicked Play
# and waited for a teleport that never came. Now (Lib\Engine.ahk PlayTo, PlayChooserUp): after Play, that
# window's card: Summer Event for Summer Hunt, Regular Stages for the Story pads (Lib\Story.ahk PadWalk), and
# no S walk "back to the normal play area" after Regular Stages. The window is known by its dark panel, the
# Summer Event card's green border and the Regular Stages card's blue one (Chris's screenshot). Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys, os, glob
T, root = sys.argv[1], sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
story = open(f"{root}/Lib/Story.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n, s=src):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", s, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) =>.*?(?=\n\S)", s, re.S | re.M)
    if m:
        return m.group(0).replace("WinGetClientPos &ox, &oy, , , RBX", "ox := 0, oy := 0")
    missing.append(n)
    return n + "(p*) => false"
fx = f"{root}/Tools/test/fixtures"
have = os.path.exists(f"{fx}/play_chooser_upd215.bmp")
others = [os.path.basename(f) for f in sorted(glob.glob(f"{fx}/*.bmp")) if not f.endswith("play_chooser_upd215.bmp")]
W = "Z:" + fx.replace("/", "\\")
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
#Include ROOT\Lib\FindText.ahk
global fails := 0, RBX := "ahk_id 1", clicks := "", chooser := false, usePic := true, opens := true
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Fresh() => 0
Wait(ms) => Sleep(Min(ms, 20))
Clk(x, y, *) {
    global clicks, chooser
    clicks .= x "," y ";"
    if x = 270 || x = 529
        chooser := false                        ; a card clicked: the window closes
    if x = 85 && y = 295 && !usePic && opens
        chooser := true                         ; Play opens it (UPD 21.5)
}
SceneSig() => [100]
SigLight(a) => 100
''' + "\n".join([fn("ColorShare"), fn("RowsWith"), fn("PlayChooserUp").replace("PlayChooserUp(", "RealChooserUp("), fn("PlayTo")]) + r'''
PlayChooserUp() => usePic ? RealChooserUp() : chooser

if HAVE {
    FindText().ShowPic("W\play_chooser_upd215.bmp", 0)
    Check("Chris's screenshot: Where do you want to Play? is seen", PlayChooserUp())
}
others := OTHERS
for f in others {
    FindText().ShowPic("W\" f, 0)
    Check("  " f ": not that window", !PlayChooserUp())
}
usePic := false
clicks := "", chooser := false
ok := PlayTo("summer")
Check("Summer Hunt: Play, then the Summer Event card", ok && clicks = "85,295;270,323;", clicks)
clicks := "", chooser := false
ok := PlayTo("regular")
Check("Story pads: Play, then the Regular Stages card", ok && clicks = "85,295;529,323;", clicks)
opens := false                                  ; Play doesn't open it (an older game)
clicks := "", chooser := false
ok := PlayTo("summer")
Check("no such window (an older game): just Play, nothing else clicked", !ok && clicks = "85,295;", clicks)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
body = body.replace("HAVE", "true" if have else "false").replace("OTHERS", "[" + ", ".join('"' + o + '"' for o in others) + "]").replace("ROOT", "Z:" + root.replace("/", "\\")).replace('"W\\', '"' + W + "\\")
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
# PadWalk (static): Play through PlayTo("regular"), and the S walk to the normal area only without that window
m = re.search(r"^PadWalk\(\) \{.*?^\}", story, re.S | re.M); b = m.group(0) if m else ""
ok = re.search(r'(\w+) := PlayTo\("regular"\).*?if !\1\b[^\n]*\n\s*ToNormalArea\(\)', b, re.S) is not None and "Clk(85, 295)" not in b
print(("PASS" if ok else "FAIL") + " the Story pads: Regular Stages, and no walk back to the normal area after it")
for where, n in [("Summer Hunt (the main and each alt)", 2)]:
    pt = re.search(r"^PlayTo\(where\) \{.*?^\}", src, re.S | re.M); rest = src.replace(pt.group(0), "") if pt else src
    c = len(re.findall(r'PlayTo\("summer"\)', rest)); raw = len(re.findall(r"Clk\(85, 295\)", rest))   # (PlayTo's own Play aside)
    print(("PASS" if c >= 1 and raw == 0 else "FAIL") + f" {where}: Play through PlayTo(\"summer\") ({c} of them), no bare Play click left ({raw})")
P
WINEDEBUG=-all timeout 120 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
