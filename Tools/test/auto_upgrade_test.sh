#!/bin/bash
# The game's Auto Upgrade (UPD 21.5) as a build order choice (Premium 3.2.165; Classic too, Chris 25 Nov: "also make
# auto upgrade feature for free version aswell". Chris 23 Nov: "place slot 1 auto upgrade"). A Place / Upgrade step's "upgrade" choice -2 =
# Auto: each unit gets the game's Auto switched on in its upgrade panel ("Auto: Off" grey / "Auto: On" purple
# at about 175,348) instead of the macro pressing Upgrade. Lib\Engine.ahk AutoUpgradeState, AutoUpgradeOn,
# UpgradeGroup, StepText; the main script's step loading. The On/Off pictures are Chris's
# clip (23 Nov). Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys, os
T, root = sys.argv[1], sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
main = open(f"{root}/Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n, s=src):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", s, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) =>.*?(?=\n\S)", s, re.S | re.M)
    if m:
        return m.group(0).replace("WinGetClientPos &ox, &oy, , , RBX", "ox := 0, oy := 0")
    missing.append(n)
    return n + "(p*) => \"\""
fx = f"{root}/Tools/test/fixtures"
W = "Z:" + fx.replace("/", "\\")
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
#Include ROOT\Lib\FindText.ahk
global fails := 0, RBX := "ahk_id 1", lg := "", clicks := 0, closes := 0, usePic := true, st := Map(), opens := Map()
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Fresh() => 0
Wait(ms) => 0
StageOver() => false
SaveDebugShot(p*) => 0
AddLog(t) {
    global lg
    lg .= t "|"
}
global cur := ""
OpenUnit(u) {
    global cur
    cur := u
    return opens.Get(u.slot, true)
}
CloseMenuClick() {
    global closes, cur
    closes++, cur := ""
}
Clk(x, y, *) {
    global clicks
    if x = 175 && y = 348 && IsObject(cur) {
        clicks++
        st[cur.slot] := st.Get(cur.slot, "off") = "on" ? "off" : "on"     ; it switches each click
    }
}
PairStep(st) => false
PairName(st) => ""
PairTimes(st) => ""
''' + "\n".join([fn("ColorShare"), fn("AutoUpgradeState").replace("AutoUpgradeState(", "RealAutoState("), fn("AutoUpgradeOn"), fn("StepText")]) + r'''
AutoUpgradeState() => usePic ? RealAutoState() : IsObject(cur) ? st.Get(cur.slot, "off") : ""

FindText().ShowPic("W\auto_upgrade_off.bmp", 0)
Check("Chris's clip, the panel with Auto: Off: off", AutoUpgradeState() = "off", AutoUpgradeState())
FindText().ShowPic("W\auto_upgrade_on.bmp", 0)
Check("  with Auto: On (purple): on", AutoUpgradeState() = "on", AutoUpgradeState())
for f in ["auto_upgrade_none.bmp"] {
    FindText().ShowPic("W\" f, 0)
    Check("  " f " (no panel): neither", AutoUpgradeState() = "", AutoUpgradeState())
}
usePic := false
u1 := {slot: 1}, u2 := {slot: 1}, u3 := {slot: 2}
st := Map(1, "off", 2, "on"), clicks := 0, closes := 0, lg := ""
n := AutoUpgradeOn([u1, u3])
Check("a unit with Auto off: clicked once, on; one already on: not clicked", n = 2 && clicks = 1 && st[1] = "on" && st[2] = "on", n " on, " clicks " clicks")
Check("  each panel closed after", closes = 2, closes)
opens := Map(3, false), st := Map(3, "off"), clicks := 0, lg := ""
n := AutoUpgradeOn([{slot: 3}])
Check("a unit whose panel doesn't open: skipped, logged", n = 0 && clicks = 0 && InStr(lg, "didn't open"), lg)
Check("the step text: Place slot 1 x3, auto upgrade", InStr(StepText({kind: "place", slot: 1, count: 3, up: -2, hill: 0}), "Place slot 1 x3, auto upgrade") = 1, StepText({kind: "place", slot: 1, count: 3, up: -2, hill: 0}))
Check("  Upgrade slot 2 with auto", InStr(StepText({kind: "upgrade", slot: 2, count: 1, up: -2, units: 0}), "auto upgrade"), StepText({kind: "upgrade", slot: 2, count: 1, up: -2, units: 0}))
Check("  to max still says to max", InStr(StepText({kind: "place", slot: 1, count: 1, up: -1, hill: 0}), "to max"))
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
body = body.replace("ROOT", "Z:" + root.replace("/", "\\")).replace('"W\\', '"' + W + "\\")
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
# static: UpgradeGroup turns -2 into Auto; the step loaders keep -2; the choice exists
ug = re.search(r"^UpgradeGroup\(units, times\) \{.*?^\}", src, re.S | re.M); ug = ug.group(0) if ug else ""
print(("PASS" if re.search(r"if times = -2[^\n]*\n\s*return[^\n]*AutoUpgradeOn\(units\)", ug) else "FAIL") + " UpgradeGroup with -2: the game's Auto (every step goes through it)")
ok = main.count("ClampInt(f[4], -2, 10, 0)") == 1 and main.count("ClampInt(up, -2, 10, 0)") >= 1
print(("PASS" if ok else "FAIL") + " saved and sent steps keep -2 (place / upgrade)")
print(("PASS" if re.search(r'UP_NAMES := \[.*"auto upgrade[^"]*"\]', main, re.S) and re.search(r"UP_VALUES := \[[^\]]*-2\]", main) else "FAIL") + " the step editor offers auto upgrade (-2)")
app = open(f"{root}/UI/app.js", encoding="utf-8").read()
print(("PASS" if 'st.up == -2' in app and '"auto"' in app and "u(max|auto|" in app else "FAIL") + " the window: its step text, the build code (ua) both ways")

# the build code both ways in the window's own code: place, upgrade and Erwin steps with auto come back as auto
import subprocess, json
js = re.search(r"^function buildCode\(list\) \{.*?^\}", app, re.S | re.M).group(0) + "\n" + re.search(r"^function parseBuildCode\(text\) \{.*?^\}", app, re.S | re.M).group(0)
pg = re.search(r"^const pairGap = .*$", app, re.M)
code = "const S = {maxCount: 6}; const isPair = (st) => st.kind === 'erwin' || st.kind === 'wenda';\n" + (pg.group(0) if pg else "") + "\n" + js + r"""
const list = [{kind: "place", slot: 1, count: 3, up: -2, hill: 0}, {kind: "upgrade", slot: 2, count: 1, up: -2, units: 0}, {kind: "erwin", slot: 3, count: 4, up: -2, secs: 30, gap: 4}];
const back = parseBuildCode(buildCode(list));
console.log(JSON.stringify({code: buildCode(list), ups: back.map((s) => s.up)}));"""
try:
    r = json.loads(subprocess.run(["node", "-e", code], capture_output=True, text=True, timeout=30).stdout)
    print(("PASS" if r["ups"] == [-2, -2, -2] else "FAIL") + " the build code keeps auto both ways (place, upgrade, Erwin): " + r["code"] + " -> " + str(r["ups"]))
except Exception as e:
    print("FAIL the build code round trip didn't run: " + str(e)[:200])
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
