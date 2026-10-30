#!/bin/bash
# Legend stage buttons (Lib\Story.ahk): the stage wanted isn't read but its neighbours are (a player's
# log, Magic Hills: "Legend Stage 2", "Legen d Stage 3" read, Stage 1 never, the top button is
# coloured differently). Its button is where the others' spacing puts it. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Story.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => ""'
parts = [fn(n) for n in ["LegendGuessRow"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
'''
body += "\n".join(parts) + "\n"
body += r'''
gx := 0, gy := 0
rows := Map(2, [290, 250], 3, [290, 300])
Check("stage 1 above stage 2 by their spacing", LegendGuessRow(rows, 1, &gx, &gy) && gx = 290 && gy = 200, gx "," gy)
Check("stage 4 when only 2 and 3 show: no guess (a world with fewer stages plays its highest)", !LegendGuessRow(rows, 4, &gx, &gy))
rows := Map(1, [290, 200], 3, [290, 300])
Check("stage 2 between 1 and 3", LegendGuessRow(rows, 2, &gx, &gy) && gy = 250, gy)
Check("one button read (Stage 3 only, 'Legend Stoge 2' misread): the usual 35 px a row", LegendGuessRow(Map(3, [290, 310]), 1, &gx, &gy) && gy = 240, gy)
Check("nothing read: no guess", !LegendGuessRow(Map(), 1, &gx, &gy))
Check("off the list (stage 6 far below): no guess", !LegendGuessRow(Map(1, [290, 200], 2, [290, 250]), 6, &gx, &gy) || gy <= 450, gy)
Check("odd spacing (a misread line): no guess", !LegendGuessRow(Map(2, [290, 250], 3, [290, 255]), 1, &gx, &gy))
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
