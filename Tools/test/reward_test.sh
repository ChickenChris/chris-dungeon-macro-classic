#!/bin/bash
# Chest rewards (ParseReward in Lib\Engine.ahk): what the reward text reads as. A Secret unit from a
# Rare Chest has no amount, and the coloured rarity under its name ("Secret", "Mythic") was never
# read in players' logs: the unit went unseen (no log line, webhook or Discord showcase). Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => ""'
parts = [fn(n) for n in ["ParseReward", "RewardName", "ChestItems", "NormName", "Levenshtein"]]
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
Show(r) => IsObject(r) ? r.name " x" r.n " [" r.rarity "]" : "(none)"
Rw(txt, name, n, rarity) {
    r := ParseReward(txt)
    return IsObject(r) && r.name = name && r.n = n && r.rarity = rarity
}
'''
body += "\n".join(parts) + "\n"
body += r'''
C := "`n(Click anywhere to continue)"
; as before
t := "Star Remnant (Limited) (x2)`nMythic" C
Check("an item with its rarity", Rw(t, "Star Remnant (Limited)", 2, "Mythic"), Show(ParseReward(t)))
t := "Star Remnant (Limited) (x2)" C
Check("an item, rarity not read (players' logs)", Rw(t, "Star Remnant (Limited)", 2, ""), Show(ParseReward(t)))
t := "Gems (x450)" C
Check("gems", Rw(t, "Gems", 450, ""), Show(ParseReward(t)))
t := "Snow Reaper (War)`nSecret" C
Check("a unit with 'Secret' read", Rw(t, "Snow Reaper (War)", 1, "Secret"), Show(ParseReward(t)))
; the Secret unit when its rarity isn't read: the name above 'Click anywhere to continue'
t := "Snow Reaper (War)" C
Check("a unit, rarity not read: a Secret (only Secret units drop from chests)", Rw(t, "Snow Reaper (War)", 1, "Secret"), Show(ParseReward(t)))
t := "Vengeful Swordsman`nS ecr" C
Check("a unit, its rarity half read: the name above it", Rw(t, "Vengeful Swordsman", 1, "Secret"), Show(ParseReward(t)))
t := "Snow Reaper (War)`nMythlc" C
Check("a misread rarity line isn't taken for the name", ParseReward(t).name = "Snow Reaper (War)", Show(ParseReward(t)))
; never a Secret by mistake (it's posted in Chris's Discord)
for t in ["Gems" C, "Star Remnant (Limited)" C, "Stat Cube" C, "Trait Crystal`nLegendary" C]
    Check("an item whose amount wasn't read isn't a Secret: " StrReplace(t, "`n", " / "), (r := ParseReward(t), !IsObject(r) || r.rarity != "Secret"), Show(r))
for t in ["(Click anywhere to continue)", "Mythic" C, "hts" C, "", "Wave 15`n+450"]
    Check("nothing to read: " StrReplace(t, "`n", " / "), !IsObject(ParseReward(t)), Show(ParseReward(t)))
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
