#!/bin/bash
# A cursed room always holds a rare chest (150 of 150 in a player's log). Lib\Engine.ahk CursedRare:
# the room counts a rare chest even when its picture wasn't matched (Lunoc: a 4-thing room's small
# rare chest was read as a plain "Chest", and a Shop + Shrine room won). Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(root + "/Lib/Engine.ahk", encoding="utf-8-sig").read() + "\n" + open(root + "/Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => 0'
parts = [fn(n) for n in ["CursedRare", "ThingValue", "IndexOf", "RoomChests", "LabelCount"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, roomRare := Map()
; Lunoc-like room list: Rare chest first, then Shop, Shrine, Hoard, Chest, Boss
global cfg := Map("route", ["Rare_Chest", "Shop", "Shrine", "Hoard", "Chest", "Boss"])
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
MakePk(i, has*) {
    s := 0
    for t in has
        s += ThingValue(t)
    return {r: {i: i}, has: has, score: s, chests: 1}
}
Kinds(a) {
    s := ""
    for t in a
        s .= t "+"
    return s
}
Has(pk) {
    s := ""
    for t in pk.has
        s .= t "+"
    return s
}
'''
body += "\n".join(parts) + "\nglobal HAS_RR := " + ("1" if "roomRare" in parts[0] else "0") + "\n"
body += r'''
; Lunoc's room: Curse + Shop + Hoard + Chest, the chest really the rare one
pk := MakePk(1, "Shop", "Hoard", "Chest")
CursedRare(pk)
Check("a cursed room's Chest is its rare chest", Has(pk) = "Shop+Hoard+Rare_Chest+", Has(pk))
Check("scored as a rare chest (double), not a chest", pk.score = 5 + 3 + 12, pk.score)
if HAS_RR                                         ; Premium: a rare-chest room owes the cat a chest
    Check("counted as a rare-chest room (Cat Tower)", roomRare.Get(1, false))
; Lunoc's numbers: Shop + Shrine scored 12 against this room; now the cursed room is worth more
Check("Lunoc's case: the Regen room now beats Shop + Shrine", pk.score > 5 + 4, pk.score)
; no chest read at all: the rare chest is still there
pk := MakePk(2, "Shop")
CursedRare(pk)
Check("a cursed room with no chest read gets its rare chest", Has(pk) = "Shop+Rare_Chest+" && pk.score = 5 + 12, Has(pk) " " pk.score)
; the rare chest already read: nothing changes
pk := MakePk(3, "Rare_Chest", "Hoard")
CursedRare(pk)
Check("a rare chest already read: unchanged", Has(pk) = "Rare_Chest+Hoard+" && pk.score = 12 + 3, Has(pk) " " pk.score)
; two CHEST labels in a cursed room: one rare (always there), one normal (Lunoc)
pk := MakePk(4, "Shop", "Chest"), pk.chests := 2
CursedRare(pk)
Check("cursed room with 2 chests: a rare one and a normal one", Has(pk) = "Shop+Chest+Rare_Chest+" && pk.score = 5 + 2 + 12, Has(pk) " " pk.score)
; what the room's chest pictures and CHEST labels say it holds
Check("rare picture + 2 CHEST labels: rare and normal", Kinds(RoomChests(true, 2)) = "Rare_Chest+Chest+", Kinds(RoomChests(true, 2)))
Check("rare picture + 1 label: just the rare one", Kinds(RoomChests(true, 1)) = "Rare_Chest+", Kinds(RoomChests(true, 1)))
Check("rare picture, label not read: the rare one", Kinds(RoomChests(true, 0)) = "Rare_Chest+", Kinds(RoomChests(true, 0)))
Check("no rare picture + 1 label: a chest", Kinds(RoomChests(false, 1)) = "Chest+", Kinds(RoomChests(false, 1)))
Check("nothing: nothing", Kinds(RoomChests(false, 0)) = "", Kinds(RoomChests(false, 0)))
Check("one label found at 3 spots next to each other: 1", LabelCount([{x: 300, y: 400}, {x: 301, y: 400}, {x: 300, y: 401}]) = 1)
Check("two labels side by side: 2", LabelCount([{x: 270, y: 430}, {x: 320, y: 430}]) = 2)
Check("two labels stacked: 2", LabelCount([{x: 300, y: 380}, {x: 300, y: 430}]) = 2)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
