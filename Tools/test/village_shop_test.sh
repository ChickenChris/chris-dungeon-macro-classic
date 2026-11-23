#!/bin/bash
# UPD 21.5's "Village Shop!" (Scarlet Ore defenses) pops up at a Misty Village round's VICTORY, before Next (and
# sometimes over the Replay screen after it). The results under it couldn't be read: the round's end wasn't seen
# and the macro went on upgrading units on the results until Chris paused it (debug_20261123_101915, 094046). Its
# Next under the shop is a duller green than the old check took. Looked for (OCR "Village Shop") whenever the
# results' XP Progress panel shows; closed with its X (582,210), then "LEAVE THE SHOP?" Leave (Chris's
# screenshot); then the results are read as always. Lib\Engine.ahk VillageShopOver / VillageShopClose, StageOver,
# Lib\Misty.ahk MistyReplay / TowerNext. Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys, os
T, root = sys.argv[1], sys.argv[2]
eng = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
mis = open(f"{root}/Lib/Misty.ahk", encoding="utf-8-sig").read() if os.path.exists(f"{root}/Lib/Misty.ahk") else ""
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
global fails := 0, lg := "", clicks := "", shopUp := true, leaveUp := false, xpUp := true
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
XpPanelUp() => xpUp
WaitFor(f, ms, step := 100) {
    loop Max(1, ms // 500)
        if f()
            return true
    return f()
}
OcrFindWord(x, y, w, h, re, &cx, &cy) {
    if shopUp && !leaveUp && y >= 160 && y <= 200 && RegExMatch("Village", re)
        return (cx := 340, cy := 200, true)
    if leaveUp && y >= 300 && y <= 340 && RegExMatch("Leave", re)
        return (cx := 318, cy := 343, true)
    return false
}
Clk(x, y, *) {
    global clicks, shopUp, leaveUp
    clicks .= x "," y ";"
    if x = 582 && y = 210 && shopUp
        leaveUp := true                         ; its X: "LEAVE THE SHOP?" Leave / Stay
    if x = 318 && y = 343 && leaveUp
        leaveUp := false, shopUp := false       ; Leave: the results show again
}
''' + "\n".join([fn("VillageShopUp"), fn("VillageShopClose"), fn("VillageShopOver")]) + r'''

Check("the shop at the results (XP Progress up): seen and closed", VillageShopOver(), clicks)
Check("  its X (582,210), then LEAVE THE SHOP? Leave", InStr(clicks, "582,210;318,343;") && !shopUp && !leaveUp, clicks)
Check("  said in the log", InStr(lg, "Village Shop"), lg)
shopUp := false, clicks := "", lg := ""
Check("no shop: nothing clicked", !VillageShopClose() && clicks = "", clicks)
shopUp := true, xpUp := false, clicks := ""
Check("mid-round (no XP Progress panel): not even read", !VillageShopOver() && clicks = "", clicks)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
so = re.search(r"^StageOver\(\) \{.*?^\}", eng, re.S | re.M); so = so.group(0) if so else ""
print(("PASS" if "VillageShopOver()" in so else "FAIL") + " checked every time the round's end is looked for (StageOver)")
for f in ["MistyReplay", "TowerNext"]:
    b = re.search(r"^" + f + r"\(\) \{.*?^\}", mis, re.S | re.M)
    if b or f == "TowerNext":
        b = b.group(0) if b else ""
        print(("PASS" if re.search(r"\{\n(?:\s*(?:global|static|duo :=|won :=)[^\n]*\n)*\s*VillageShopClose\(\)", b) else "FAIL") + " " + f + ": the shop closed first (it can show over the Replay screen too)")
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
