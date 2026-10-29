#!/bin/bash
# The Legend flow's decisions (Lib\Story.ahk) with the game faked: what the screen reader "reads" is
# queued up, and every click is written down. Run under Wine, no game needed
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
src = open(sys.argv[2] + "/Lib/Story.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => "MISSING"'
parts = [fn(n) for n in ["LegendReplay", "CloseTournament", "RedSpotAt", "PadList", "LegendClickStage", "LegendRows", "LegendStageOf", "LegendPickStage", "LegendGuessRow"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, calls := "", words := Map(), lastResult := "", RBX := "LegendFlowTestWindow", scr := 0
g := Gui(, RBX), g.Show("x0 y0 w800 h600 NA")
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
; the fakes: clicks and moves are written down
Note(t) {
    global calls
    calls .= t
}
Clk(x, y, *) => Note("Clk " x "," y ";")
ClickOpenDungeon() => Note("OpenDungeon;")
BackToLobby() => Note("Lobby;")
LoadStage(p*) => Note("LoadStage;")
ClosePopups() => (Note("Popups;"), false)
ScrollAt(x, y, n) => Note("Scroll " x "," y "," n ";")
AddLog(t) => 0
Step(t) => 0
Wait(ms) => 0
Stale() => 0
Fresh() => 0
Det(name) => false
OcrLang() => "en"
LEGEND_WORLD() => "Magic Hills (Elf Invasion)"
LEGEND_STAGE() => 1
ChallengeLeave() => false
LegendBaseMap(w) => "Magic Hills"
FindText() => scr
OcrFindWord(x, y, w, h, re, &cx, &cy) {
    for r, p in words
        if r = re
            return (cx := p[1], cy := p[2], true)
    return false
}
; what the reader reads next: one result per OCR.FromRect call, then nothing
class OCR {
    static Q := []
    static FromRect(*) => OCR.Q.Length ? OCR.Q.RemoveAt(1) : {Lines: [], Words: [], Text: ""}
}
Read(items*) {          ; items: [text, x, y, w, h], ...  (x, y inside the read area)
    lines := [], ws := [], txt := ""
    for it in items
        lines.Push({Text: it[1], x: it[2], y: it[3], w: it[4], h: it[5]}), ws.Push({Text: StrSplit(it[1], " ")[1], x: it[2], y: it[3], w: 40, h: it[5]}), txt .= it[1] " "
    return {Lines: lines, Words: ws, Text: Trim(txt)}
}
class Fake {
    __New(sq) => this.sq := sq
    GetColor(x, y, *) {
        for s in this.sq
            if x >= s[1] && x < s[1] + s[3] && y >= s[2] && y < s[2] + s[3]
                return s[4]
        return 0x202020
    }
}
Reset() {
    global calls := "", words := Map()
    OCR.Q := []
}
'''
body += "\n".join(parts) + "\n"
body += r'''
; --- Replay after a round: after a win the yellow button can be "Next", so the word Replay is clicked
Reset(), lastResult := "win", words["i)^replay$"] := [520, 470]
LegendReplay()
Check("a win: the Replay word is clicked", InStr(calls, "Clk 520,470;") && !InStr(calls, "OpenDungeon") && !InStr(calls, "Lobby;"), calls)
Reset(), lastResult := "win"
LegendReplay()
Check("a win with no Replay seen: back to the lobby, not the yellow button", InStr(calls, "Lobby;") && !InStr(calls, "OpenDungeon"), calls)
Reset(), lastResult := "loss"
LegendReplay()
Check("a loss with no Replay word read: the yellow button (Replay after a loss)", InStr(calls, "OpenDungeon;") && !InStr(calls, "Lobby;"), calls)

; --- the Tournament popup: only its title counts, and only closed when it's gone afterwards
WinGetClientPos(&ox, &oy, , , RBX)
Reset(), scr := Fake([[ox + 600, oy + 100, 16, 0xE02020]]), OCR.Q := [Read(["Tournament", 500, 200, 90, 18])]
Check("the word Tournament alone isn't the popup", !CloseTournament() && !InStr(calls, "Clk"), calls)
Reset(), OCR.Q := [Read(["Don't Miss Out!", 400, 180, 200, 24])]
Check("the popup is closed with its red X", CloseTournament() && InStr(calls, "Clk 607,107;"), calls)
Reset(), OCR.Q := [Read(["Don't Miss Out!", 400, 180, 200, 24]), Read(["Don't Miss Out!", 400, 180, 200, 24])]
Check("still there after the click: not counted as closed", !CloseTournament(), calls)

; --- the list switch above Select World (read area x 500, y 60)
Reset(), OCR.Q := [Read(["Legend Stages", 150, 40, 100, 20]), Read(["Main Stages", 150, 40, 100, 20])]
Check("Legend: its button pressed once, then it says Main Stages", PadList(true) && calls = "Clk 670,110;", calls)
Reset(), OCR.Q := [Read(["Main Stages", 150, 40, 100, 20]), Read(["Legend Stages", 150, 40, 100, 20])]
Check("Infinite on a pad left on the Legend list: switched back", PadList(false) && calls = "Clk 670,110;", calls)
Reset()
Check("Infinite, nothing read there: goes on as before, no clicks", PadList(false) && calls = "", calls)
Reset(), OCR.Q := [Read(["Legend Stages", 150, 40, 100, 20]), Read(["Legend Stages", 150, 40, 100, 20]), Read(["Legend Stages", 150, 40, 100, 20]), Read(["Legend Stages", 150, 40, 100, 20])]
Check("Legend list never shows: false after 3 presses", !PadList(true) && StrSplit(calls, "Clk").Length - 1 = 3, calls)

; --- the stage column (read area x 100, y 150; each read is done twice, the 2nd with the colours flipped)
St(n, y) => ["Legend Stage " n, 150, y, 90, 14]
Reset(), OCR.Q := [Read(["Legen d Stage 2", 150, 120, 90, 14], St(3, 155)), Read()]
Check("a stage read with a stray space is clicked, no scrolling (it zoomed the camera)", LegendClickStage(2) = 2 && calls = "Clk 295,277;", calls)
Reset(), OCR.Q := [Read(St(1, 90), St(2, 125), St(3, 160)), Read(), Read(St(4, 90), St(5, 125), St(6, 160)), Read()]
Check("stage 5 below: scrolled down over the stage buttons, then clicked", LegendClickStage(5) = 5 && calls = "Scroll 289,290,1;Clk 295,282;", calls)
Reset(), OCR.Q := [Read(St(4, 90), St(5, 125), St(6, 160)), Read(), Read(St(1, 90), St(2, 125), St(3, 160)), Read()]
Check("stage 1 above: scrolled up", LegendClickStage(1) = 1 && calls = "Scroll 289,290,-1;Clk 295,247;", calls)
Reset(), OCR.Q := [Read(), Read(St(2, 125))]
Check("read only with the colours flipped: still found", LegendClickStage(2) = 2 && calls = "Clk 295,282;", calls)
Reset(), OCR.Q := [Read(St(2, 125), St(3, 160)), Read(), Read(St(2, 125), St(3, 160)), Read()]
Check("stage 1 never read, 2 and 3 are (a player's log): clicked one row above stage 2", LegendClickStage(1) = 1 && calls = "Scroll 289,290,-1;Clk 295,247;", calls)
Reset()
Check("nothing read: no scrolling, 0", LegendClickStage(2) = 0 && !InStr(calls, "Scroll"), calls)

FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
