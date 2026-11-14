#!/bin/bash
# The game's red "Cannot place more than 2 of this unit!" now shows just above the yen and the hotbar
# (Alphonse 14 Nov, Future City raid, Elysia: the half-screen read garbled it over a busy map, the closer
# read only looked under the wave counter, and slot 3 was tried again every 4 s). The screen and the text
# reader are faked: the message is only readable by a close read of the strip it's in. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    return m.group(0) if m else (print("FAIL not defined: " + n) or n + '(p*) => ""')
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, UniquePopup := "", msgAt := 0, msg := "", bigSays := "", reads := []
g := Gui(), g.Show("x0 y0 w800 h600")
global RBX := "ahk_id " g.Hwnd
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
FT(p*) => false
Stale() => 0
Fresh() => 0
OcrLang() => "en"
class RedScreen {                                ; a map with red on it (Future City's road and buildings)
    GetColor(x, y, p*) => 0xFF2020
}
FindText(p*) => RedScreen()
; the text reader: a close read (a strip up to 120 px tall) that takes in the whole message reads it;
; the half-screen read gets what bigSays says (the message garbled away over a busy map, or read)
class OCR {
    static FromRect(x, y, w, h, lang, opts) {
        WinGetClientPos &ox, &oy, , , RBX
        y -= oy
        reads.Push(y "+" h)
        if h > 120
            return {Text: bigSays}
        return {Text: msg != "" && y <= msgAt && y + h >= msgAt + 17 ? msg : "Tyrant Force Minion"}
    }
}
'''
body += "\n".join(fn(n) for n in ["LimitMessage"]) + "\n"
body += r'''
msg := "Cannot place more than 2 of this unit!", msgAt := 455, bigSays := "Tyrant Force Minion Minion Wave 8 +69 7005"
r := LimitMessage(&said)
Check("the message just above the yen (y 455-472), garbled in the big read: read, the unit's limit", r = "limit" && InStr(said, "more than 2"), r " / " said)
reads := [], msgAt := 120
r := LimitMessage(&said)
Check("the message under the wave counter (where it was): still read", r = "limit", r " / " said)
reads := [], msg := ""
r := LimitMessage(&said)
Check("no message on a red map: nothing", r = "", r " / " said)
reads := [], bigSays := "Cannot place more than 2 of this unit!"
r := LimitMessage(&said)
Check("read in the big read already: no closer reads (each read costs time)", r = "limit" && reads.Length = 1, reads.Length)
g.Destroy()
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
