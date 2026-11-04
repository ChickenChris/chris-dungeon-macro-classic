#!/bin/bash
# The captcha's slashed zero read as 8 (Lib\Engine.ahk CaptchaZeros): the digits are cut out of the
# picture and each 8 / 0 is told apart by its middle. Fixtures: the number from Chris's recording
# (13097, typed as 13897) and the same with a real 8 drawn in. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
cp Tools/test/fixtures/captcha_13097.txt Tools/test/fixtures/captcha_13897.txt "$T/"
python3 - "$T/t.ahk" <<'P'
import re, sys
src = open("Lib/Engine.ahk", encoding="utf-8-sig").read()
fn = re.search(r"^CaptchaZeros\(.*?^\}", src, re.S | re.M).group(0)
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
global fails := 0, pic := Map(), RBX := "x"
Check(name, ok) {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*", "UTF-8"), fails += !ok
}
Load(f) {
    global pic
    pic := Map()
    lines := StrSplit(Trim(FileRead(A_ScriptDir "\" f), "`r`n"), "`n", "`r")
    loop lines.Length - 1 {
        y := A_Index - 1, row := lines[A_Index + 1]
        loop StrLen(row) // 6
            pic[(y + 262) * 1000 + A_Index - 1 + 244] := Integer("0x" SubStr(row, (A_Index - 1) * 6 + 1, 6))
    }
}
WinGetClientPos(&x := 0, &y := 0, &w := 0, &h := 0, t := "") => (x := 0, y := 0)
Fresh() => 0
class FakeShot {
    GetColor(x, y, m := 0) => pic.Get(y * 1000 + x, 0)
}
FindText() => FakeShot()
''' + fn + r'''
Load("captcha_13097.txt")
Check("the slashed zero read as 8 becomes 0 (13897 -> " CaptchaZeros("13897") ")", CaptchaZeros("13897") = "13097")
Check("a 0 read right stays 0", CaptchaZeros("13097") = "13097")
Check("a wrong digit count: left as read", CaptchaZeros("1389") = "1389")
Load("captcha_13897.txt")
Check("a real 8 stays 8 (" CaptchaZeros("13897") ")", CaptchaZeros("13897") = "13897")
Check("a real 8 read as 0 becomes 8", CaptchaZeros("13097") = "13897")
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
