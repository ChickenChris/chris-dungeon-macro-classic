#!/bin/bash
# The game's "placed / most" over a held unit's hotbar card (Lib\Engine.ahk HeldCount), with the text
# reader faked: two reads must agree, a count over its limit or no slash is not taken. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" <<'P'
import re, sys
src = open("Lib/Engine.ahk", encoding="utf-8-sig").read()
fn = re.search(r"^HeldCount\(.*?^\}", src, re.S | re.M).group(0)
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
global fails := 0, reads := [], RBX := "x"
Check(name, ok) {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*", "UTF-8"), fails += !ok
}
WinGetClientPos(&x := 0, &y := 0, &w := 0, &h := 0, t := "") => (x := 0, y := 0)
SlotPriceRight(n) => 263 + 64 * (n - 1)
OcrLang() => "en-US"
class OCR {
    static FromRect(p*) {
        global reads
        return {Text: reads.Length ? reads.RemoveAt(1) : ""}
    }
}
Try2(a, b, &most) {
    global reads
    reads := [a, b]
    return HeldCount(1, &most)
}
''' + fn + r'''
Check("1/2 read twice: 1 placed of 2", Try2("1/2", "1/2", &m) = 1 && m = 2)
Check("2/2 at the limit", Try2("2/2", "2 / 2", &m) = 2 && m = 2)
Check("0/2", Try2("0/2", "O/2", &m) = 0 && m = 2)
Check("Bulby's 1/1 read as l/1", Try2("l/1", "1/1", &m) = 1 && m = 1)
Check("the two reads disagree: not taken", Try2("1/2", "2/2", &m) = -1)
Check("over its limit (2/2 read as 5/2): not taken", Try2("5/2", "5/2", &m) = -1)
Check("41/4 (a red 1/1 misread): not taken", Try2("41/4", "41/4", &m) = -1)
Check("no slash: not taken", Try2("12", "12", &m) = -1)
Check("nothing there", Try2("", "", &m) = -1)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 60 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
