#!/bin/bash
# Everyone's walks and spots reset to Chris's own (Lib\defaults.ini [Reset] Walks=N, Chris 3 Nov): once
# per reset number, later recordings kept; an import can't bring other walks back for Chris's maps
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d); mkdir -p "$T/Lib"; cp Lib/defaults.ini "$T/Lib/"
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read()
fns = []
for n in ["UpgradeOldWalks", "LoadShippedWalks"]:
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M)
    fns.append(m.group(0) if m else (print("FAIL not defined: " + n) or n + "(p*) => 0"))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, saves := 0, cfg := Map("walks", Map(), "spots", Map(), "walksReset", "")
SaveConfig(*) {
    global saves
    saves++
}
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
''' + "\n".join(fns) + r'''
f := A_ScriptDir "\Lib\defaults.ini"
cfg["walks"]["Navy Bay"] := "w+0,d+999,w-2000"               ; a player's own recordings
cfg["walks"]["Some Map"] := "w+0,w-500"
cfg["spots"]["Navy Bay"] := [{x: 1, y: 2}]
LoadShippedWalks()
Check("reset: Chris's Navy Bay walk replaces the player's", cfg["walks"]["Navy Bay"] == IniRead(f, "Walks", "Navy Bay"))
Check("reset: a map Chris has no walk for loses the player's", !cfg["walks"].Has("Some Map"))
Check("reset: the player's spots are gone, Chris's are there", !cfg["spots"].Has("Navy Bay") && cfg["spots"].Has("Snowy Town"))
Check("reset: saved, with its number", saves = 1 && cfg["walksReset"] = IniRead(f, "Reset", "Walks"), saves)
Check("Chris's Adventurer Town (Fool's Hunt) walk is shipped", cfg["walks"].Has("Adventurer Town (Fool's Hunt)"))
cfg["walks"]["Navy Bay"] := "w+0,d+111"                      ; recorded again after the reset
LoadShippedWalks()
Check("next start: no second reset, a new recording stays", cfg["walks"]["Navy Bay"] == "w+0,d+111" && saves = 1, cfg["walks"]["Navy Bay"])
LoadShippedWalks(true)                                         ; after an import
Check("after an import: Chris's walk wins again", cfg["walks"]["Navy Bay"] == IniRead(f, "Walks", "Navy Bay"))
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
