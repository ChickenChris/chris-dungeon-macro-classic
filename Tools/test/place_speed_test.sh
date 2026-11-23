#!/bin/bash
# Failed placing tries were slow (Chris 23 Nov: "so much unnecessary waiting time ... its so slow"): ~6 s each
# on his debug_20261123_094046 (2.6 s for the unit's menu, then 3.4 s more: the red message read again after Q
# though it was read twice in the wait). The wait for the menu now follows how fast this game shows it: the
# slowest of the last menus seen + 0.5 s (never under 0.8 s, never over the old wait); a late menu makes the
# next waits longer again. The red text isn't read again after Q when the wait read it under 0.9 s before.
# Lib\Engine.ahk MenuWaitMs / MenuSeen, TryPlace. Wine
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
    return n + "(p*) => 0"
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, menuTimes := []
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
''' + "\n".join([fn("MenuWaitMs"), fn("MenuSeen")]) + r'''

Check("no menu seen yet this round: the old wait (2 s)", MenuWaitMs(2000) = 2000, MenuWaitMs(2000))
MenuSeen(400)
Check("  one seen: still the old wait (one quick menu could be luck)", MenuWaitMs(2000) = 2000, MenuWaitMs(2000))
MenuSeen(500)
Check("menus at 0.4 and 0.5 s: the wait 1.0 s (the slowest + 0.5 s)", MenuWaitMs(2000) = 1000, MenuWaitMs(2000))
MenuSeen(150), MenuSeen(200), MenuSeen(150), MenuSeen(100), MenuSeen(120)
Check("  very quick menus: never under 0.8 s", MenuWaitMs(2000) = 800, MenuWaitMs(2000))
MenuSeen(1900)
Check("a late menu (1.9 s): the old wait again", MenuWaitMs(2000) = 2000, MenuWaitMs(2000))
Check("  never over the old wait (Placement speed 4 s)", MenuWaitMs(4000) = 2400, MenuWaitMs(4000))
loop 5
    MenuSeen(300)
Check("only the last 5 count: quick again after the late one", MenuWaitMs(2000) = 800, MenuWaitMs(2000))
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body)
tp = re.search(r"^TryPlace\(x, y, slot\) \{.*?^\}", eng, re.S | re.M); tp = tp.group(0) if tp else ""
print(("PASS" if re.search(r"lookMs := autoOpenOff \|\| turbo \? 1000 : MenuWaitMs\(Max\(2000, PlaceTimeout\(\)\)\)", tp) else "FAIL") + " TryPlace waits for the menu by MenuWaitMs")
print(("PASS" if tp.count("MenuSeen(") >= 2 else "FAIL") + "   and records every menu it sees (quick and late)")
print(("PASS" if re.search(r"A_TickCount - readAt >= 900 && PlaceRefused\(slot\)", tp) else "FAIL") + " the red text not read again after Q when the wait just read it")
st = re.search(r"^StartStage\(\)|menuTimes := \[\]", eng, re.M)
print(("PASS" if re.search(r"menuTimes := \[\]", eng.split("^MenuWaitMs")[0]) or "menuTimes := []" in eng else "FAIL") + " the menu times start over each round")
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
