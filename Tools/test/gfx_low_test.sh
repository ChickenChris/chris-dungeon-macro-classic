#!/bin/bash
# "Lower Roblox's graphics while macroing" (from another macro's "Optimisation while macroing", Chris 24 Nov:
# "you choose"): a busy PC shows the game late (the camera turns of 23 Nov) and misses clicks. On, every Roblox
# the macro plays (the main and each alt) is put on graphics level 1 the first time the macro brings it to the
# front: Roblox's own keys, Shift+F10 lowers it a level (10 of them reach 1 from anywhere). Roblox keeps the
# level after the macro stops: F10 turns it back up, said in the log. Lib\Engine.ahk GraphicsDown,
# FocusRoblox, the setting and the window. Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys
T, root = sys.argv[1], sys.argv[2]
eng = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
main = open(f"{root}/Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read()
html = open(f"{root}/UI/index.html", encoding="utf-8").read()
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
global fails := 0, lg := "", sent := "", cfg := Map("lowGfx", 1), RBX := "ahk_id 100", running := true
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
AddLog(t) {
    global lg
    lg .= t "|"
}
SendKeys(k) {
    global sent
    sent .= k
}
WinExist(w) => w != ""
WinActive(w) => w != ""
''' + "\n".join([fn("GraphicsDown")]) + r'''

GraphicsDown()
n := StrLen(sent) - StrLen(StrReplace(sent, "+{F10}"))
Check("on, the main brought to the front: Shift+F10 ten times (level 1 from anywhere)", n = 10 * 6, sent)
Check("  said in the log, with how to turn it back up (F10)", InStr(lg, "level 1") && InStr(lg, "F10"), lg)
sent := "", lg := ""
GraphicsDown()
Check("  the same Roblox again: not again", sent = "", sent)
RBX := "ahk_id 200"
GraphicsDown()
Check("an alt's Roblox in front: its graphics too", StrLen(sent) = 10 * 6, sent)
Check("  said once a session, not for every window", lg = "", lg)
sent := "", running := false, RBX := "ahk_id 400"
GraphicsDown()
Check("the macro not running (Snap Roblox, picking a spot): nothing pressed", sent = "", sent)
sent := "", running := true, cfg["lowGfx"] := 0, RBX := "ahk_id 300"
GraphicsDown()
Check("off: nothing pressed", sent = "", sent)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
fr = re.search(r"^FocusRoblox\(\) \{.*?^\}", eng, re.S | re.M); fr = fr.group(0) if fr else ""
print(("PASS" if fr.count("GraphicsDown()") >= 2 else "FAIL") + " FocusRoblox lowers it once Roblox is in front (already there, or just brought there)")
sk = re.search(r"^ScalarKeys\(\) => .*?(?=\n\n)", main, re.S | re.M); sk = sk.group(0) if sk else ""
print(("PASS" if '"lowGfx"' in sk and re.search(r'"lowGfx", 0[,)]', main) else "FAIL") + " the setting: saved, off by default")
t = re.search(r'<label class="toggle" data-key="lowGfx"[^>]*>.*?</label>', html, re.S); t = t.group(0) if t else ""
print(("PASS" if t and "F10" in t else "FAIL") + " the window: a switch in Settings, saying F10 turns it back up")
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'; [ "${PIPESTATUS[0]}" = 124 ] && echo "FAILED (timed out)"
rm -rf "$T"
