#!/bin/bash
# Summer Hunt card vote: which card is picked. Chris 11 Nov: "it selected 100% magic resist instead of
# 50%": Resistant Enemies II over Resistant Enemies I, the same card twice and the higher level taken,
# which is right for your own buffs (Range II over Range I) and wrong for an enemy card.
# Limits per run (RNG / The Grinch 23 Nov: "it managed to find 800% worth of health cards", "if 400% never take hp
# again for that run, add hard limits for each card"): a max on each enemy card (Enemy Health max 400%), the
# number read off each card (+50% Enemy Health; Whiteout's +50% counts too), what this round took added up, and a
# card past its max picked last. Cards that weaken your units ("the fat -15% range that accompanies the card":
# Whiteout's big red line) picked last too, in every mode (Chris: "Always avoid them").
# The Grinch 23 Nov: "i set the max health to 400% and its currently at 450%" (his log: the macro counted 330%):
# only a card's own kind was counted, and a weather card's other enemy effects ("+50% Enemy Health" on a card of
# another kind) weren't. Every "+N Enemy Health / Shield / Regen / Speed" on a card counts now, and a card that
# would take any of them past its max is skipped.
# Lib\Engine.ahk FoolCards, CardAmount, CardAmounts, CardWeakens, CardOverMax, the screen faked. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
eng = open(root + "/Lib/Engine.ahk", encoding="utf-8-sig").read()
main = open(root + "/Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read()
missing = []
def fn(src, n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if not m:
        missing.append(n)
        return n + "(p*) => 0"
    return m.group(0)
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, RBX := "", voteNew := true, voteClick := false, foolVotes := 0, logs := [], voted := 0
global names := Map(), pearlsAt := Map(), greenAt := Map(), effAt := Map(), cfg := Map(), foolTaken := Map()
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
FoolVoteDy() => 0
Step(t) => 0
Wait(ms) => 0
Stale() => 0
NewMenu() => false
CloseMenuClick() => 0
SaveDebugShot(t) => 0
AddLog(t) => logs.Push(t)
FoolVoteUp() => false
OcrLang() => "en-US"
CardPearls(cx) => pearlsAt.Get(cx, -1)
CardGreen(cx) => greenAt.Get(cx, false)
CardEffect(cx) => effAt.Get(cx, "")
PlayerCardUp() => false
ClosePlayerCard() => 0
FoolVoteAt(x, dy) {
    global voted
    voted := x
    return true
}
class OCR {                                     ; the card names, by where they're read
    static FromRect(x, y, w, h, p*) => {Text: names.Get(x + 75, "")}
}
''' + "\n".join([fn(eng, "FoolCards").replace("A_TickCount - votedAt < 25000", "false").replace("A_TickCount - firstSeen < 1500", "false").replace("WinGetClientPos &ox, &oy, , , RBX", "ox := 0, oy := 0"), fn(main, "IndexOf"), fn(main, "FOOL_CARDS"), fn(eng, "CardAmount"), fn(eng, "CardAmounts"), fn(eng, "CardWeakens"), fn(eng, "CardOverMax"), fn(eng, "CardMaxOf"), fn(eng, "CardUnits"), fn(eng, "CardName"), fn(eng, "CARD_PCT")]) + r'''

Pick(a, b, c, pa := -1, pb := -1, pc := -1, ea := "", eb := "", ec := "", gc := false) {
    global names, pearlsAt, effAt, greenAt, voted
    names := Map(223, a, 401, b, 578, c), pearlsAt := Map(223, pa, 401, pb, 578, pc), voted := 0
    effAt := Map(223, ea, 401, eb, 578, ec), greenAt := Map(578, gc)
    FoolCards()
    return voted = 223 ? a : voted = 401 ? b : voted = 578 ? c : "none"
}
cfg["foolCards"] := FOOL_CARDS(), cfg["foolCoins"] := 0, cfg["foolSafe"] := 0
; Chris's vote: Resistant Enemies I (+50 physical and magic resist, +30% pearls) and II (+100, +70%)
got := Pick("+ Resistant Enemies Il", "+ Plated Enemies Ill", "+ Resistant Enemies 1", 70, 150, 30)
Check("Resistant Enemies I and II: the milder one (I)", got = "+ Resistant Enemies 1", got)
got := Pick("+ Resistant Enemies 1", "+ Plated Enemies Ill", "+ Resistant Enemies Il", 30, 150, 70)
Check("  the other way round too", got = "+ Resistant Enemies 1", got)
got := Pick("+ Resistant Enemies Il", "+ Plated Enemies Ill", "+ Resistant Enemies", -1, -1, -1)
Check("  its SummerPearls unread: by the I / II in its name", got = "+ Resistant Enemies", got)
; your own buff twice: the stronger one, as before
got := Pick("+ Range Il", "+ Boss Damage", "+ Range", -1, 30, -1)
Check("Range I and Range II (your buff): Range II", got = "+ Range Il", got)
; "Most SummerPearls" on: the one with the most pearls, on purpose
cfg["foolCoins"] := 1
got := Pick("+ Resistant Enemies 1", "+ Attack", "+ Resistant Enemies Il", 30, -1, 70)
Check("'Most SummerPearls' on: Resistant Enemies II (more pearls)", got = "+ Resistant Enemies Il", got)
cfg["foolCoins"] := 0
; the list still decides between different cards
got := Pick("+ Boss Damage", "+ Plated Enemies", "+ Enemy Shield Il", 30, 30, 70)
Check("different cards: your list's order (Enemy Shield first)", got = "+ Enemy Shield Il", got)

; ---- what a card adds, read off it (else its level times the level I amount)
Check("amount: +50% Enemy Health", CardAmount("health", "+30% SummerPearls +50% Enemy Health", 1) = 50, CardAmount("health", "+30% SummerPearls +50% Enemy Health", 1))
Check("  Whiteout's: +50% Enemy Health (not its +100% SummerPearls, not -15% Range)", CardAmount("health", "+100% SummerPearls +50% Enemy Health -15% Range Blizzard Card", 1) = 50)
Check("  +3 Enemy Shield", CardAmount("shield", "+50% SummerPearls +3 Enemy Shield Blizzard Card", 1) = 3)
Check("  +0.5% Enemy Regen", CardAmount("regen", "+30% SummerPearls +0.5% Enemy Regen", 1) = 0.5)
Check("  +25% Enemy Speed", CardAmount("speed", "+30% SummerPearls +25% Enemy Speed", 1) = 25)
Check("  nothing read: level II Enemy Health counts 100% (2 x 50%)", CardAmount("health", "", 2) = 100, CardAmount("health", "", 2))
; ---- cards that weaken your units
Check("Whiteout's -15% Range weakens your units", CardWeakens("+100% SummerPearls +50% Enemy Health -15% Range Blizzard Card", false))
Check("  its minus not read, on a red card: still", CardWeakens("+100% SummerPearls +50% Enemy Health 15% Range Blizzard Card", false))
Check("  -10% Attack too", CardWeakens("+70% SummerPearls -10% Attack", false))
Check("  not your own Cooldown buff (-5% Attack Cooldown, green)", !CardWeakens("-5% Attack Cooldown for your units", true))
Check("  not Explosive Deaths' +6 range (the blast's)", !CardWeakens("+30% SummerPearls Enemies explode when they die +6 Range", false))
Check("  not Bonfire (+75% Fire Damage Taken, green)", !CardWeakens("+75% Fire Damage Taken Blizzard Card", true))
; Chris's vote 23 Nov (debug_20261123_121515, 12:27:46): Permafrost, Whiteout, Bonfire. Most SummerPearls on
; took Whiteout (+100%) with its -15% Range: now the next most, Permafrost
cfg["foolCoins"] := 1
got := Pick("Permafrost", "Whiteout", "Bonfire", 50, 100, 0, "+50% SummerPearls +3 Enemy Shield Blizzard Card",
    "+100% SummerPearls +50% Enemy Health -15% Range Blizzard Card", "+75% Fire Damage Taken Blizzard Card", true)
Check("Most SummerPearls on: not Whiteout (-15% Range): Permafrost", got = "Permafrost", got)
Check("  the log says why", InStr(logs[logs.Length], "Whiteout") && InStr(logs[logs.Length], "Range"), logs[logs.Length])
cfg["foolCoins"] := 0
got := Pick("Whiteout", "+ Enemy Speed Il", "+ Plated Enemies", 100, 70, 30, "+100% SummerPearls +50% Enemy Health -15% Range Blizzard Card",
    "+70% SummerPearls +50% Enemy Speed -10% Attack", "+30% SummerPearls +75 Enemy Physical Resist")
Check("your list: Whiteout (health, #3) and Speed II (#4) weaken your units: Plated Enemies (#14)", got = "+ Plated Enemies", got)
got := Pick("Whiteout", "+ Enemy Speed Il", "Whiteout", 100, 70, 100, "+100% SummerPearls +50% Enemy Health -15% Range Blizzard Card",
    "+70% SummerPearls +50% Enemy Speed -10% Attack", "+100% SummerPearls +50% Enemy Health -15% Range Blizzard Card")
Check("  all three weaken them: one is still picked (no vote = a random card)", got != "none", got)
; ---- a max per run: Enemy Health max 400%
cfg["foolMax"] := Map("health", 400), foolTaken := Map("health", 350)
got := Pick("+ Enemy Health", "+ Boss Damage", "+ Plated Enemies", 30, 30, 30, "+30% SummerPearls +50% Enemy Health", "", "+30% SummerPearls +75 Enemy Physical Resist")
Check("Enemy Health at 350% of max 400%: +50% still fits, picked", got = "+ Enemy Health", got)
Check("  this round's Enemy Health now 400%", foolTaken.Get("health", 0) = 400, foolTaken.Get("health", 0))
got := Pick("+ Enemy Health", "+ Boss Damage", "+ Plated Enemies", 30, 30, 30, "+30% SummerPearls +50% Enemy Health", "", "+30% SummerPearls +75 Enemy Physical Resist")
Check("  at 400%: never again this round, the next on your list (Plated Enemies)", got = "+ Plated Enemies", got)
Check("  the log says why", InStr(logs[logs.Length], "Enemy Health") && InStr(logs[logs.Length], "400"), logs[logs.Length])
foolTaken := Map("health", 300)
got := Pick("+ Enemy Health Ill", "+ Boss Damage", "+ Plated Enemies", 150, 30, 30, "+150% SummerPearls +150% Enemy Health", "", "+30% SummerPearls +75 Enemy Physical Resist")
Check("  at 300%, Enemy Health III (+150%) would go past 400%: Plated Enemies", got = "+ Plated Enemies", got)
foolTaken := Map("health", 375)
got := Pick("Whiteout", "+ Boss Damage", "+ Plated Enemies", 100, 30, 30, "+100% SummerPearls +50% Enemy Health Blizzard Card", "", "+30% SummerPearls +75 Enemy Physical Resist")
Check("  a weather card's +50% Enemy Health counts too", got = "+ Plated Enemies", got)
; ---- every enemy effect on a card counts (The Grinch 23 Nov: the game at 450%, the macro had 330%)
a := CardAmounts("yen", "+50% Yen +50% Enemy Health Sandstorm Card", 1)
Check("a card of another kind with +50% Enemy Health: counts 50% health", a.Has("health") && a["health"] = 50 && a.Count = 1, a.Count)
a := CardAmounts("health", "+30% SummerPearls +50% Enemy Health +25% Enemy Speed", 1)
Check("  health and speed on one card: both", a.Get("health", 0) = 50 && a.Get("speed", 0) = 25, a.Get("speed", 0))
a := CardAmounts("slow", "-30% Enemy Speed for 10 s", 1)
Check("  your own slow card (-30% Enemy Speed): not enemy speed", !a.Count, a.Count)
a := CardAmounts("shield", "+50% SummerPearls +3 Enemy Shield Blizzard Card", 1)
Check("  a card's own kind as before (+3 Enemy Shield)", a.Get("shield", 0) = 3 && a.Count = 1, a.Count)
cfg["foolMax"] := Map("health", 400), foolTaken := Map("health", 380)
got := Pick("* Attack", "+ Plated Enemies", "Buried Treasure", 0, 30, 0, "+10% Attack", "+30% SummerPearls +75 Enemy Physical Resist", "+50% Yen +50% Enemy Health Sandstorm Card", true)
Check("Enemy Health at 380% of max 400%: a weather card with +50% Enemy Health is skipped too", got != "Buried Treasure", got)
foolTaken := Map("health", 100)
cfg["foolCards"] := ["yen", "attack", "plated", "shield", "regen", "health", "speed", "range", "cooldown", "grounded", "slow", "explosive", "resistant", "spellproof", "gale", "updraft", "boss"]
got := Pick("* Attack", "+ Plated Enemies", "Buried Treasure", 0, 30, 0, "+10% Attack", "+30% SummerPearls +75 Enemy Physical Resist", "+50% Yen +50% Enemy Health Sandstorm Card", true)
Check("  under the max: picked, and its +50% Enemy Health counted (100% -> 150%)", foolTaken.Get("health", 0) = 150, got " " foolTaken.Get("health", 0))
cfg["foolCards"] := FOOL_CARDS()
cfg["foolMax"] := Map("health", 0), foolTaken := Map("health", 2000)
got := Pick("+ Enemy Health", "+ Boss Damage", "+ Plated Enemies", 30, 30, 30, "+30% SummerPearls +50% Enemy Health", "", "")
Check("no max (0): as before", got = "+ Enemy Health", got)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
st = re.search(r"global waveNow := 0, abilFired := Map\(\)[^\n]*\n(?:[^\n]*\n){0,3}", eng)
print(("PASS" if re.search(r"global foolTaken := Map\(\)", eng[eng.find("stageActive := true"):eng.find("stageActive := true") + 1500]) else "FAIL") + " the cards taken start over every round")
# the max per round: a setting (Map of card -> max), kept in the settings file, sent to the window, set from it,
# (Classic: no settings import)
print(("PASS" if '"foolCards", FOOL_CARDS(), "foolMax", Map()' in main else "FAIL") + " foolMax has a default (no max)")
ui = re.search(r"^UiState\(\) \{.*?^\}", main, re.S | re.M); ui = ui.group(0) if ui else ""
print(("PASS" if 'c["foolMax"] := cfg["foolMax"]' in ui else "FAIL") + "   sent to the window")
print(("PASS" if re.search(r'case "foolMax":[^\n]*\n(?:[^\n]*\n){0,6}?[^\n]*cfg\["foolMax"\]\[k\] := [^\n]*SaveConfig\(\)', main) else "FAIL") + "   set from the window (an enemy card, a number, 0 = none)")
lc = re.search(r"^LoadConfig\(\) \{.*?^\}", main, re.S | re.M); lc = lc.group(0) if lc else ""
print(("PASS" if 'IniRead(cfgFile, "Fool", "Max_" k, "")' in lc else "FAIL") + "   read from the settings file ([Fool] Max_health=400)")
print(("PASS" if re.search(r'for k, v in cfg\["foolMax"\]\n\s*if v > 0\n\s*ini\.Set\("Fool", "Max_" k, v\)', main) else "FAIL") + "   and saved there")
P
WINEDEBUG=-all timeout 120 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
