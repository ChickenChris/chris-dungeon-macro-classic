#!/bin/bash
# Updating on start (Lib\AutoUpdate.ahk): a newer version out -> the updater is started and the macro
# closes; the same or an older one, no answer, or just updated (--updated) -> the macro starts as it is.
# The internet and the updater are faked. Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" "$(pwd)" <<'P'
import re, sys, os
root = sys.argv[2]
p = f"{root}/Lib/AutoUpdate.ahk"
src = open(p, encoding="utf-8-sig").read() if os.path.exists(p) else ""
missing = []
def fn(n):
    m = re.search(r"^" + n + r"\([^)\n]*\) \{.*?^\}", src, re.S | re.M) or re.search(r"^" + n + r"\([^)\n]*\) => .*$", src, re.M)
    if m:
        return m.group(0)
    missing.append(n)
    return n + '(p*) => ""'
parts = [fn(n) for n in ["AutoUpdate", "VerOf", "VerNewer"]]
if missing:
    print("FAIL not defined: " + ", ".join(missing))
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, started := 0, asked := "", online := "", APP_VER := "3.2.67", args := []
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
NewestVersion(repo, file) {
    global asked
    asked := repo "/" file
    return online
}
StartUpdater() {
    global started
    started++
}
MacroArgs() => args
Try1(ver, have := "3.2.67", a := "") {
    global started, online, APP_VER, args
    started := 0, online := ver, APP_VER := have, args := a = "" ? [] : [a]
    try FileDelete(A_ScriptDir "\Settings\update.ini")       ; every check starts fresh, unless said
    AutoUpdate("ChickenChris/updates", "latest.txt")
    return started
}
'''
body += "\n".join(parts) + "\n"
body += r'''
Check("a newer version out: the updater starts", Try1("Premium 3.2.68 (2026-10-30)") = 1)
Check("it asks the repo's file", asked = "ChickenChris/updates/latest.txt", asked)
Check("the same version: starts as it is", Try1("Premium 3.2.67 (2026-10-28)") = 0)
Check("an older one (a test build is ahead): starts as it is", Try1("3.2.66") = 0)
Check("no answer (offline, GitHub blocked): starts as it is", Try1("") = 0)
Check("garbage back (a block page): starts as it is", Try1("<html>Access denied</html>") = 0)
Check("just updated (--updated): never a second round", Try1("3.2.68", "3.2.67", "--updated") = 0)
Check("3.2.100 is newer than 3.2.99 (numbers, not text)", Try1("3.2.100", "3.2.99") = 1)
Check("3.10.0 is newer than 3.9.9", Try1("3.10.0", "3.9.9") = 1)
Check("Classic's version text ('3.0.99 Classic')", Try1("3.1.0", "3.0.99 Classic") = 1)
; a failed update isn't tried again on every start (the updater blocked, the license server down):
; each new version gets one automatic try, Update.bat is the retry
Try1("3.2.68")
started := 0, online := "3.2.68", APP_VER := "3.2.67", args := []
AutoUpdate("ChickenChris/updates", "latest.txt")
Check("the same new version, the next start (its update didn't take): starts as it is", started = 0)
online := "3.2.69"
AutoUpdate("ChickenChris/updates", "latest.txt")
Check("an even newer one out: tried", started = 1)
Check("VerOf finds the number", VerOf("Premium 3.2.67 (2026-10-28)") = "3.2.67", VerOf("Premium 3.2.67 (2026-10-28)"))
Check("VerNewer: unknown versions never update", !VerNewer("", "3.2.67") && !VerNewer("3.2.68", ""))
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
