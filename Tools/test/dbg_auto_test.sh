#!/bin/bash
# The recording on for everyone (autoRec), saving itself when something goes wrong (Chris 9 Nov):
# Lib\DebugRec.ahk DbgOn, DbgSaveSoon, DbgNote, DbgTick, DbgPack, DbgBegin, DbgPrune. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
mkdir -p "$T/Logs"
for i in $(seq -w 1 11); do : > "$T/Logs/debug_202611010000$i.zip"; done
STATIC=1
grep -q '"autoRec", 1' "Chris's Dungeon Macro.ahk" || STATIC=0
grep -q '"debugRec"' "Chris's Dungeon Macro.ahk" && STATIC=0               # not read or saved anymore
[ "$(grep -o '"autoRec"' "Chris's Dungeon Macro.ahk" | wc -l)" -ge 2 ] || STATIC=0   # a default and a saved key
grep -q 'data-key="autoRec"' UI/index.html || STATIC=0
export STATIC
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys
root = sys.argv[2]
src = open(f"{root}/Lib/DebugRec.ahk", encoding="utf-8-sig").read()
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + "(p*) => 0"
body = r'''#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, cfg := Map("autoRec", 1, "debugRec", 0), running := true, paused := false, logs := [], runs := []
global fakeNow := 1000000, RBX := "", APP_VER := "test", stepNow := "", curMap := "", dbgDir := "", dbgFrames := [], dbgVote := "", dbgStarted := 0
global dbgWant := "", dbgSavedAt := -999999
DBG_KEEP_MS := 120000
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
AddLog(m) => logs.Push(m)
DbgNow() => fakeNow
DbgRun(c) => runs.Push(c)
DbgFrame(why) => 0
LastLog() => logs.Length ? logs[logs.Length] : ""
''' + "\n".join(fn(n) for n in ["DbgOn", "DbgSaveSoon", "DbgNote", "DbgTick", "DbgBegin", "DbgPack", "DbgPrune"]) + r'''

Check("autoRec on with an old debugRec=0: recording on", DbgOn())
DbgTick()
first := dbgDir
Check("farming: a 2-minute buffer started, said once", first != "" && InStr(LastLog(), "Recording the last 2 minutes"), LastLog())
n0 := logs.Length
DbgNote("log", "Couldn't reach the Summer Hunt pad. Send Logs\fools_entry_....bmp in Discord so it can be fixed")
Check("a Couldn't line asks for a save", dbgWant != "", dbgWant)
DbgTick()
Check("the next tick saves it (zipped once)", runs.Length = 1, runs.Length)
Check("  and says which zip and why", RegExMatch(logs[n0 + 1], "^Saved the last 2 minutes: Logs\\debug_\S+\.zip \(Couldn't reach the Summer Hunt pad"), logs.Length > n0 ? logs[n0 + 1] : "")
Check("  a new buffer, in a new folder, without another 'Recording' line", dbgDir != "" && dbgDir != first && logs.Length = n0 + 1, dbgDir " / " first)
DbgNote("log", "Couldn't get back to the lobby after the dungeon.")
Check("another Couldn't within 3 minutes: no second save", dbgWant = "", dbgWant)
fakeNow += 180001
DbgSaveSoon("stuck: no round for 4 minutes")
Check("3 minutes later: saves again", dbgWant = "stuck: no round for 4 minutes", dbgWant)
running := false
DbgTick()
Check("stopped: packed", runs.Length = 2 && dbgDir = "", runs.Length)
Zips(&oldest) {
    left := 0, oldest := ""
    loop files A_ScriptDir "\Logs\debug_*.zip"
        left++, oldest := (oldest = "" || StrCompare(A_LoopFileName, oldest) < 0) ? A_LoopFileName : oldest
    return left
}
n := Zips(&oldest)
Check("after a save, 9 old ones left (+ the one being zipped = 10)", n = 9 && oldest = "debug_20261101000003.zip", n " " oldest)
FileAppend("", A_ScriptDir "\Logs\debug_20261109000001.zip"), FileAppend("", A_ScriptDir "\Logs\debug_20261109000002.zip")
DbgPrune(A_ScriptDir "\Logs", 10)
n := Zips(&oldest)
Check("11 zips: the newest 10 kept", n = 10 && oldest = "debug_20261101000004.zip", n " " oldest)
Check("settings: autoRec on by default and saved, the toggle in the app", EnvGet("STATIC") = "1")
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
if missing:
    body = body.replace("ExitApp fails ? 1 : 0", 'FileAppend("FAIL not defined: ' + ", ".join(missing) + '`n", "*")\nExitApp 1')
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
