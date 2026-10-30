#!/bin/bash
# Old configs: walks the macro has replaced (defaults.ini [OldWalks]) are swapped for the new ones at
# start and after an import too (an import brought them back for that session: Cr1es's old Snowy Town
# walk, then not one unit placed). The walks of a player's real old config. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d); mkdir -p "$T/Lib"; cp Lib/defaults.ini "$T/Lib/"
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read()
m = re.search(r"^UpgradeOldWalks\(\) \{.*?^\}", src, re.S | re.M)
fn = m.group(0) if m else (print("FAIL not defined: UpgradeOldWalks") or "UpgradeOldWalks() => 0")
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, cfg := Map("walks", Map())
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
''' + fn + r'''
f := A_ScriptDir "\Lib\defaults.ini"
w := cfg["walks"]
; from the player's old config (Chris_s_Dungeon_Premium (2).ini)
w["Snowy Town"] := "d+0,w+1266,d-1282,d+2094,w-2125,w+3282,d-3313,d+3891,w-3907,d-4579"
w["Air Craft"] := "s+0,a+828,s-969,s+1282,s-1516,s+1625,s-1922,s+3078,s-3141,w+4375,w-4610,w+4719,w-4766,w+4860,a-5500,d+6391,d-6875,d+7578,d-7641,a+8063,w-8344,w+9000,a-9641,d+10657,d-10828,d+10922,w-11563,w+12203,d-12203,w-12266,w+12407,w-12485,d+12532,d-12563,d+12657,d-12719"
w["Mountain Temple"] := "w+0,w-235,d+438,d-1422,w+1719,w-1813,d+2031,d-2125,w+2360,w-2422,w+2922,w-2985"
w["Spirit World"] := "w+0,w-63,w+360,w-407"
w["Cursed Festival"] := "d+0,d-1437,s+1640,s-1781"
w["Navy Bay"] := "w+0,d+999,w-2000"                       ; their own recording: kept
n := UpgradeOldWalks()
Check("the 4 old walks in that config are swapped", n = 4, n)
for name in ["Snowy Town", "Air Craft", "Mountain Temple", "Spirit World"]
    Check(name ": the walk the macro ships now", w[name] == IniRead(f, "Walks", name), w[name])
Check("a walk that's already the current one stays", w["Cursed Festival"] == "d+0,d-1437,s+1640,s-1781")
Check("their own recording stays", w["Navy Bay"] == "w+0,d+999,w-2000")
Check("run again: nothing more to swap", UpgradeOldWalks() = 0)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
