#!/bin/bash
# Raids (Lib\Story.ahk StartRaid, RaidWalk, RaidReplay; Chris's recording 10 Nov, UPD 21): Areas > Raids,
# a short walk to the raid pad, the world in "Select World", the raid's button on the left (35 px apart),
# then the pad's Select / Play Here / Start. The game faked: every click and key is written down.
# Run under Wine, no game needed
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(root + "/Lib/Story.ahk", encoding="utf-8-sig").read()
eng = open(root + "/Lib/Engine.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n, src=src):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*(?:\n[ \t]+.*)*", src, re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => "MISSING"'
parts = [fn(n) for n in ["RAID_WORLDS", "RaidMode", "RAID_WORLD", "RAID_ACT", "RaidBaseMap", "RaidWalk", "StartRaid", "RaidFail", "RaidTitle", "RaidReplay", "WorldRegex", "WorldLineIs",
    "RaidMatchOn", "RaidToPad", "RaidToMatch", "RaidWaitMatch"]] + [fn("FoolMatchTries", eng)]
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, calls := "", logs := [], words := Map(), lastResult := "", RBX := "RaidFlowTestWindow"
global cfg := Map("mode", "Raid"), padAfter := 99, padChecks := 0, worldOk := true, padStartOk := true, worldLastRead := "", title := ""
global joinUp := true, matchRes := [], gearLeft := 0
g := Gui(, RBX), g.Show("x0 y0 w800 h600 NA")
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
Note(t) {
    global calls
    calls .= t
}
Clk(x, y, *) => Note("Clk " x "," y ";")
SendKeys(k) => Note("Key " k ";")
ClickOpenDungeon() => Note("OpenDungeon;")
BackToLobby() => Note("Lobby;")
LoadStage(map := "") => Note("LoadStage " map ";")
PadStart(label, select := true) => (Note("PadStart " label (select ? "" : " no select") ";"), padStartOk)
FoolJoinUp() => joinUp                           ; "Join Matchmaking?"
FoolGear() {                                     ; the settings gear: there for `gearLeft` more looks (-1: always)
    global gearLeft
    return gearLeft < 0 || gearLeft-- > 0
}
CaptchaUp() => false
CaptchaWindowUp() => false
CaptchaClose() => Note("CaptchaClose;")
FoolToPad() => (Note("FoolToPad;"), true)
FoolFindMatch(last := true, what := "") {        ; Find Match and the number: what `matchRes` says
    Note("FindMatch " what ";")
    return matchRes.Length ? matchRes.RemoveAt(1) : false
}
ClosePopups() => false
CloseChat() => 0
AddLog(t) => logs.Push(t)
SaveDebugShot(t) => Note("Shot " t ";")
Step(t) => 0
Wait(ms) => 0
Stale() => 0
FocusRoblox() => 0
SceneSig() => 0
WaitAreaTeleport(*) => Note("Teleport;")
OcrLang() => "en"
ChallengeLeave() => false
Det(name) => false
IndexOf(a, v) {
    for i, x in a
        if x = v
            return i
    return 0
}
FuzzyPick(line, names) => ""
PadCancelUp() {                                  ; the pad's Cancel shows after `padAfter` looks (-1: never)
    global padChecks
    return padAfter >= 0 && ++padChecks > padAfter
}
WorldFind(name, names, &x, &y) {
    Note("Find " name ";")
    return worldOk ? (x := 700, y := 280, true) : false
}
OcrFindWord(x, y, w, h, re, &cx, &cy) {
    for r, p in words
        if r = re
            return (cx := p[1], cy := p[2], true)
    return false
}
class OCR {
    static FromRect(*) => {Text: title, Lines: [], Words: []}
}
Reset() {
    global calls := "", logs := [], words := Map(), padChecks := 0, joinUp := true, matchRes := [], gearLeft := 0
}
LogHas(t) {
    for m in logs
        if InStr(m, t)
            return true
    return false
}
'''
body += "\n".join(parts) + "\n"
body += r'''
; --- the settings
cfg["raidWorld"] := "Cursed Festival", cfg["raidAct"] := "3"
Check("the world and raid from the settings", RAID_WORLD() = "Cursed Festival" && RAID_ACT() = 3)
cfg["raidWorld"] := "Nowhere", cfg["raidAct"] := 9
Check("an unknown world: Sacred Planet (the first one open); a raid past 5: 5", RAID_WORLD() = "Sacred Planet" && RAID_ACT() = 5)
cfg["raidAct"] := "x"
Check("no number: raid 1", RAID_ACT() = 1)
Check("the map of a world with a bracket (walks and spots)", RaidBaseMap("Ant Kingdom (Midnight)") = "Ant Kingdom" && RaidBaseMap("Ruined City (The Menace)") = "Ruined City" && RaidBaseMap("Sacred Planet") = "Sacred Planet")
Check("Raid mode", RaidMode() && (cfg["mode"] := "Legend", !RaidMode()))
cfg["mode"] := "Raid"

; --- the world list's lines (what the reader gives on the pad, Chris's recording)
Check("Sacred Planet's line", WorldLineIs("Sacred Planet", "Sacred Planet", RAID_WORLDS()))
Check("a locked world, its name half under the lock: Ant Kingdo (Midnight)", WorldLineIs("Ant Kingdo (Midnight)", "Ant Kingdom (Midnight)", RAID_WORLDS()))
Check("Future City (Tyrant) isn't Future City", !WorldLineIs("Future City (Tyrant)", "Future City", RAID_WORLDS()))

; --- lobby -> pad -> world -> raid -> Start
Reset(), cfg["raidWorld"] := "Strange Town", cfg["raidAct"] := 3, padAfter := 2, worldOk := true, padStartOk := true, title := "Raid: The Evil Monk"
StartRaid()
want := "Clk 400,340;Clk 400,390;Clk 765,475;Clk 495,410;Teleport;Key {a down};Key {a up};Key {w down};Key {w up};Find Strange Town;Clk 700,288;Clk 289,310;PadStart Raid;LoadStage Strange Town;"
Check("Areas, Raids, left then ahead to the pad, the world, raid 3's button (y 310), Start, its map", calls = want, calls)
Check("  the log says which raid started (a locked one can't be picked)", LogHas("Strange Town raid 3 (Raid: The Evil Monk) started"), logs.Length ? logs[logs.Length] : "")
Reset(), padAfter := 0, title := ""
StartRaid()
Check("already standing on the pad: no teleport, no walk", !InStr(calls, "Teleport") && InStr(calls, "Find Strange Town;") && InStr(calls, "LoadStage Strange Town;"), calls)
Reset(), padAfter := -1
StartRaid()
Check("the pad never reached: 3 teleports, then a picture and no world clicked", StrSplit(calls, "Teleport").Length - 1 = 3 && InStr(calls, "Shot raid_entry;") && !InStr(calls, "Find"), calls)
Reset(), padAfter := 0, worldOk := false
StartRaid()
Check("the world not in the list: Cancel (401,525) and a picture", InStr(calls, "Shot raid_world;Clk 401,525;") && !InStr(calls, "PadStart") && LogHas("couldn't find Strange Town in the raid list"), calls)
Reset(), worldOk := true, padStartOk := false
StartRaid()
Check("Start didn't take: not played", !InStr(calls, "LoadStage"), calls)
padStartOk := true

; --- Find Match (og-73 "ADD MATCHMAKING TO RAIDS"; Chris: the same Join Matchmaking? as every mode)
Check("Find Match is off at first", !RaidMatchOn())
cfg["raidMatch"] := 1
Reset(), padAfter := 0, matchRes := [true], title := ""
StartRaid()
Check("Find Match: the world, the raid, Select, Find Match (the number), then the match's round on the raid's map",
    calls = "Clk 400,340;Clk 400,390;Find Strange Town;Clk 700,288;Clk 289,310;Clk 401,438;FindMatch Raid;LoadStage Strange Town;", calls)
Reset(), padAfter := 0, matchRes := ["retry", true]
StartRaid()
Check("  a number that didn't go through: Find Match again", StrSplit(calls, "FindMatch Raid;").Length - 1 = 2 && InStr(calls, "LoadStage Strange Town;") && !InStr(calls, "FoolToPad"), calls)
Reset(), padAfter := 0, matchRes := ["nowin"]
StartRaid()
Check("  not matched: Play Here and Start as without it (Select pressed already)", InStr(calls, "FindMatch Raid;PadStart Raid no select;LoadStage Strange Town;"), calls)
Reset(), padAfter := 0, joinUp := false
StartRaid()
Check("  no Join Matchmaking? after Select: the pad's Start, no Find Match", !InStr(calls, "FindMatch") && InStr(calls, "Clk 401,438;PadStart Raid no select;"), calls)
Reset(), padAfter := 0, matchRes := [true], gearLeft := -1
StartRaid()
Check("  matched but no round came: not played, a picture (the lobby tries again)", !InStr(calls, "LoadStage") && InStr(calls, "Shot raid_queue;"), calls)
Reset(), joinUp := true
Check("back to Find Match: Join Matchmaking? still up, nothing to do", RaidToMatch() && calls = "", calls)
Reset(), joinUp := false, padAfter := 0
r := RaidToMatch()
Check("back to Find Match: gone, so the pad, the world, the raid and Select again", calls = "Find Strange Town;Clk 700,288;Clk 289,310;Clk 401,438;", calls)
Check("  false when Join Matchmaking? still doesn't show", !r)
Reset(), matchRes := ["retry", "retry", "retry"], joinUp := false
Check("3 numbers that didn't go through: not matched, back to the pad for Play Here", !FoolMatchTries(FoolToPad, "Summer Hunt") && StrSplit(calls, "FoolToPad;").Length - 1 = 3, calls)
cfg["raidMatch"] := 0

; --- the raid's title
title := "Raid: The Guardian"
Check("the title read", RaidTitle() = "Raid: The Guardian")
title := "Stats (Hard)"
Check("something else read: nothing", RaidTitle() = "")

; --- the end of a raid
Reset(), lastResult := "win", words["i)^replay$"] := [520, 470]
RaidReplay()
Check("a win: the word Replay is clicked, then the raid's map", calls = "Clk 520,470;LoadStage Strange Town;", calls)
Reset(), lastResult := "win"
RaidReplay()
Check("a win with no Replay seen: back to the lobby (the raid is picked again)", calls = "Lobby;", calls)
Reset(), lastResult := "loss"
RaidReplay()
Check("a loss: the yellow Replay", calls = "OpenDungeon;LoadStage Strange Town;", calls)
cfg["raidMatch"] := 1
Reset(), lastResult := "win", words["i)^replay$"] := [520, 470]
RaidReplay()
Check("Find Match: back to the lobby for a new match (Replay keeps the same players, or none)", calls = "Lobby;" && LogHas("back to the lobby to Find Match again"), calls)
cfg["raidMatch"] := 0

FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
# wired in: the main loop, the end of a round, the settings and the app
R=$(python3 - "$(pwd)" <<'P'
import re, sys
root = sys.argv[1]
eng = open(root + "/Lib/Engine.ahk", encoding="utf-8-sig").read()
main = open(root + "/Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read()
app = open(root + "/UI/app.js", encoding="utf-8").read()
html = open(root + "/UI/index.html", encoding="utf-8").read()
checks = [
  ("the lobby starts a raid in Raid mode", re.search(r"else if RaidMode\(\)\s*\n\s*StartRaid\(\)", eng)),
  ("the end of a raid replays it", re.search(r"if RaidMode\(\) \{\s*\n\s*RaidReplay\(\)", eng)),
  ("a pad's Join Matchmaking / Open Portal left open is handled in Raid mode too", eng.count("RaidMode()) && ") == 2),
  ("Raid is a mode in the settings, the order list and the check", len(re.findall(r'\[[^\[\]]*"Legend", "Raid"[^\[\]]*\]', main)) >= 3),
  ("the raid world and raid are saved", '"legendStage", "raidWorld", "raidAct"' in main and '"raidWorld", "Sacred Planet", "raidAct", 1' in main),
  ("the app gets the raid worlds", '"raidWorlds", RAID_WORLDS()' in main),
  ("the app: a Raid button (in Classic too)", '"Legend", "Raid", "Portal"]' in app and re.search(r'FREE_MODES = \[[^\]]*"Raid"', app)),
  ("the app: the raid panel", all(x in html for x in ['id="raidSub"', 'id="raidWorld"', 'id="raidAct"'])),
  ("Find Match for raids is saved (off at first)", '"raidAct", 1, "raidMatch", 0' in main and '"raidAct", "raidMatch"' in main),
  ("the app: Play Here / Find Match on the raid panel", 'id="segRaidJoin"' in html and re.search(r'seg\(\$\("#segRaidJoin"\), \["Play Here", "Find Match"\]', app)),
  ("Summer Hunt's Find Match still goes back to its own pad", 'FoolMatchTries(FoolToPad, "Summer Hunt")' in eng),
]
for name, ok in checks:
    print(("PASS " if ok else "FAIL ") + name)
P
)
echo "$R"
OUT=$(WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r')
rm -rf "$T"
if echo "$R" | grep -q "^FAIL"; then echo "$OUT" | grep -v "ALL PASSED"; echo "FAILED (static)"; else echo "$OUT"; fi
