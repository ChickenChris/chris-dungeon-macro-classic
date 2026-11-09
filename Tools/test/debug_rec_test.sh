#!/bin/bash
# Debug recording (Lib\DebugRec.ahk): a JPG of the game area with a line in frames.txt, events in
# events.txt, only the last pictures kept, nothing while it's off, packed on pause. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
mkdir -p "$T/Logs"
python3 - "$T/t.ahk" <<'P'
import re, sys
eng = open("Lib/Engine.ahk", encoding="utf-8-sig").read()
gdi = re.search(r"^GdiplusUp\(.*?^\}", eng, re.S | re.M).group(0)
rec = open("Lib/DebugRec.ahk", encoding="utf-8-sig").read().replace("SetTimer DbgTick, 1000", "")
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
global fails := 0, logs := [], running := true, paused := false, stepNow := "placing", curMap := "Walled City"
global APP_VER := "test", cfg := Map("autoRec", 1, "mode", "Fool's Hunt")
Check(name, ok) {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name "`n", "*", "UTF-8"), fails += !ok
}
AddLog(msg) {
    global logs
    logs.Push(msg)
}
g := Gui("-Caption +AlwaysOnTop"), g.BackColor := "3366CC"
g.Add("Text", "x317 y154 w172 h18 BackgroundFFFFFF")
g.Show("x0 y0 w820 h640")
global RBX := "ahk_id " g.Hwnd
Sleep 300
''' + gdi + "\n" + rec + r'''
DbgTick()
Check("on and farming: a session folder", dbgDir != "" && DirExist(dbgDir))
dir := dbgDir
Check("its first picture", dbgFrames.Length = 1 && FileExist(dbgFrames[1][2]) && FileGetSize(dbgFrames[1][2]) > 500)
Check("a JPG", FileRead(dbgFrames[1][2], "RAW m2") && NumGet(FileRead(dbgFrames[1][2], "RAW m2"), 0, "UShort") = 0xD8FF)
Check("info.txt", InStr(FileRead(dir "\info.txt"), "Roblox game area: 820x640"))
Check("frames.txt names the step and the map", InStr(FileRead(dir "\frames.txt"), "step: placing  |  map: Walled City"))
Check("and the live numbers, measured on the picture (white where the card title goes, nothing else)",
    InStr(FileRead(dir "\frames.txt"), "live: vote title 1.00 ends 0.00 cards 0.00/0.00/0.00; menu box 0.00 gold 0.00 X 0.00"))
DbgFrame("again")
Check("not two pictures within 0.5 s", dbgFrames.Length = 1)
Sleep 550
DbgNote("click", "400,300")
DbgFrame("click 400,300")
Check("a picture at a click", dbgFrames.Length = 2)
Check("events.txt", InStr(FileRead(dir "\events.txt"), "click: 400,300"))
global DBG_KEEP_MS := 100
Sleep 550
DbgFrame("later")
Check("old pictures dropped (only the last minutes kept)", dbgFrames.Length = 1)
first := dir
paused := true
DbgTick()
Check("pause: packed (folder handed over, a log line)", dbgDir = "" && InStr(logs[logs.Length], "debug_") && InStr(logs[logs.Length], ".zip"))
paused := false, cfg["autoRec"] := 0
DbgTick()
Check("off: nothing recorded", dbgDir = "")
FileAppend("`n" (fails ? "FAILED " fails : "ALL PASSED") "`n", "*")
ExitApp fails
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 120 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
r=${PIPESTATUS[0]}
rm -rf "$T"
exit $r
