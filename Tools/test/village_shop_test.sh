#!/bin/bash
# UPD 21.5's "Village Shop!" (Scarlet Ore defenses) pops up over a Misty Village round's VICTORY: the title
# under it couldn't be read, the round's end wasn't seen and the macro went on upgrading units on the results
# until Chris paused it (debug_20261123_101915). Seen by its title (OCR "Village Shop", only when the results'
# green Next and XP Progress show), closed with its X (582,210), then the results are read as always.
# Lib\Engine.ahk EndByColour / VillageShopOver. Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys
T, root = sys.argv[1], sys.argv[2]
eng = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n, s=eng):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", s, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) =>.*?(?=\n\S)", s, re.S | re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + "(p*) => false"
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, lg := "", clicks := "", shopUp := true, nextUp := true, cfg := Map("mode", "Misty Village")
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
AddLog(t) {
    global lg
    lg .= t "|"
}
Wait(ms) => 0
Stale() => 0
VoteOnScreen() => false
XpPanelUp() => true
PeopleListOver() => false
TitleColour(&tx := 0) => shopUp ? "" : "gold"    ; VICTORY under the shop can't be read
ColorShare(x1, y1, x2, y2, test) => nextUp && x1 = 280 && y1 = 384 ? 0.9 : 0
OcrFindWord(x, y, w, h, re, &cx, &cy) => shopUp && y >= 170 && y <= 200 && RegExMatch("Village", re) ? (cx := 340, cy := 200, true) : false
Clk(x, y, *) {
    global clicks, shopUp
    clicks .= x "," y ";"
    if x = 582 && y = 210
        shopUp := false                         ; its X: the results show again
}
''' + "\n".join([fn("EndByColour"), fn("VillageShopOver")]) + r'''

Check("the shop over the results: the round's end is seen", EndByColour(), clicks)
Check("  the shop closed with its X (582,210)", InStr(clicks, "582,210;"), clicks)
Check("  said in the log", InStr(lg, "Village Shop"), lg)
clicks := "", lg := ""
Check("then the results are read as always", EndByColour() && clicks = "", clicks)
shopUp := false, nextUp := false, clicks := ""
Check("mid-round (no green Next): nothing read, nothing clicked", !EndByColour() && clicks = "", clicks)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
