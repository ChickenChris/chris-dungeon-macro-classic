#!/bin/bash
# Summer Hunt card vote: which card is picked. Chris 11 Nov: "it selected 100% magic resist instead of
# 50%": Resistant Enemies II over Resistant Enemies I, the same card twice and the higher level taken,
# which is right for your own buffs (Range II over Range I) and wrong for an enemy card.
# Lib\Engine.ahk FoolCards, the screen faked (its waits taken out). Run under Wine
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
global names := Map(), pearlsAt := Map(), greenAt := Map(), cfg := Map()
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
CardEffect(cx) => ""
FoolVoteAt(x, dy) {
    global voted
    voted := x
    return true
}
class OCR {                                     ; the card names, by where they're read
    static FromRect(x, y, w, h, p*) => {Text: names.Get(x + 75, "")}
}
''' + "\n".join([fn(eng, "FoolCards").replace("A_TickCount - votedAt < 25000", "false").replace("A_TickCount - firstSeen < 1500", "false").replace("WinGetClientPos &ox, &oy, , , RBX", "ox := 0, oy := 0"), fn(main, "IndexOf"), fn(main, "FOOL_CARDS")]) + r'''

Pick(a, b, c, pa := -1, pb := -1, pc := -1) {
    global names, pearlsAt, voted
    names := Map(223, a, 401, b, 578, c), pearlsAt := Map(223, pa, 401, pb, 578, pc), voted := 0
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
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 120 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
