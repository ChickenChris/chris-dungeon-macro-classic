#!/bin/bash
# The minimap arrow vs the base's heart (Lib\Engine.ahk FacingOf, read by MiniFacing for the camera line-up).
# J 22 Nov: "the macro gets the white cross and heart of the base mixed up, it makes sense why my alts keep going
# that direction". The heart blinks (when the base is hit) and a half-drawn heart (19-28 px, 8-9 wide or tall,
# or a 3x5 bit) was taken for the arrow pointing down or left; with the real arrow hidden (standing at the heart
# after the teleport to spawn) the camera was turned wrong and the walk went another way. The arrow is 8-12 px
# in a 6x3 / 6x4 box; the heart's spot is remembered from when it's seen whole. The white pixels below are from
# a player's recording (debug_20261122_070208: minimap white pixels only), "_noarrow" without the real arrow. Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T" "$(pwd)" <<'P'
import re, sys
T, root = sys.argv[1], sys.argv[2]
src = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
m = re.search(r"^FacingOf\(white\) \{.*?^\}", src, re.S | re.M)
fn = m.group(0) if m else "FacingOf(white) => -2"
body = r'''#Requires AutoHotkey v2.0
#Warn VarUnset, StdOut
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")`n", "*"), ExitApp(3)))
global fails := 0, miniHeart := "", PIX := Map()
Check(name, ok, got := "") {
    global fails
    FileAppend((ok ? "PASS " : "FAIL ") name (ok ? "" : " (got " got ")") "`n", "*", "UTF-8")
    fails += !ok
}
W(name) {
    w := Map()
    for p in StrSplit(PIX[name], " ") {
        xy := StrSplit(p, ",")
        w[Integer(xy[1]) * 1000 + Integer(xy[2])] := 1
    }
    return w
}
DATA
''' + fn + r'''

; a fresh run: the heart not seen whole yet
for k in ["blink1", "blink2", "blink3"] {
    miniHeart := ""
    r := FacingOf(W(k "_noarrow"))
    Check("the heart half-drawn (" k "), the real arrow hidden: not taken for an arrow", r = -1, r)
}
for k in ["blink2", "blink3"] {
    miniHeart := ""
    r := FacingOf(W(k))
    Check("the heart half-drawn (" k ") and the real arrow: the arrow is read (up)", r = 0, r)
}
miniHeart := ""
r := FacingOf(W("blink4"))
Check("  a 3x5 bit of it before the heart was ever seen whole: two arrow-sized marks, not guessed", r = -1, r)
; the heart seen whole once: its spot is remembered, a small bit of it there isn't an arrow
miniHeart := ""
for k in ["whole", "nearheart", "away"] {
    r := FacingOf(W(k))
    Check("a normal minimap (" k "): up", r = 0, r)
}
r := FacingOf(W("blink4_noarrow"))
Check("then a 3x5 bit of the blinking heart, the real arrow hidden: not an arrow", r = -1, r)
r := FacingOf(W("blink4"))
Check("  with the real arrow: up", r = 0, r)
FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")
ExitApp fails ? 1 : 0
'''
open(T + "/t.ahk", "w", encoding="utf-8-sig").write(body.replace("DATA", open(f"{root}/Tools/test/mini_heart_test.sh", encoding="utf-8").read().split("#DATA#\n")[1].split("\n#END#")[0]))
P
WINEDEBUG=-all timeout 90 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
exit 0
#DATA#
PIX["whole"] := "777,497 777,498 777,499 777,500 778,497 778,498 778,499 778,500 778,501 779,497 779,498 779,499 779,500 779,501 779,502 780,497 780,498 780,499 780,500 780,501 780,502 781,497 781,498 781,499 781,500 781,501 781,502 781,503 782,490 782,497 782,498 782,499 782,500 782,501 782,502 782,503 783,488 783,489 783,490 783,496 783,497 783,498 783,499 783,500 783,501 783,502 784,487 784,488 784,496 784,497 784,498 784,499 784,500 784,501 785,487 785,488 785,497 785,498 785,499 785,500 786,488 787,488 787,489"
PIX["whole_noarrow"] := "777,497 777,498 777,499 777,500 778,497 778,498 778,499 778,500 778,501 779,497 779,498 779,499 779,500 779,501 779,502 780,497 780,498 780,499 780,500 780,501 780,502 781,497 781,498 781,499 781,500 781,501 781,502 781,503 782,497 782,498 782,499 782,500 782,501 782,502 782,503 783,496 783,497 783,498 783,499 783,500 783,501 783,502 784,496 784,497 784,498 784,499 784,500 784,501 785,497 785,498 785,499 785,500"
PIX["nearheart"] := "777,497 777,498 777,499 777,500 778,497 778,498 778,499 778,500 778,501 779,497 779,498 779,499 779,500 779,501 779,502 780,497 780,498 780,499 780,500 780,501 780,502 781,498 781,499 781,500 781,501 781,502 781,503 781,504 782,494 782,498 782,499 782,500 782,501 782,502 782,503 783,491 783,492 783,493 783,497 783,498 783,499 783,500 783,501 783,502 784,491 784,492 784,497 784,498 784,499 784,500 784,501 785,491 785,497 785,498 785,499 785,500 786,492 787,492"
PIX["nearheart_noarrow"] := "777,497 777,498 777,499 777,500 778,497 778,498 778,499 778,500 778,501 779,497 779,498 779,499 779,500 779,501 779,502 780,497 780,498 780,499 780,500 780,501 780,502 781,498 781,499 781,500 781,501 781,502 781,503 781,504 782,498 782,499 782,500 782,501 782,502 782,503 783,497 783,498 783,499 783,500 783,501 783,502 784,497 784,498 784,499 784,500 784,501 785,497 785,498 785,499 785,500"
PIX["away"] := "726,488 726,489 727,487 727,488 728,487 729,487 729,488 730,488 731,489 777,497 777,498 777,499 777,500 778,496 778,497 778,498 778,499 778,500 778,501 779,496 779,497 779,498 779,499 779,500 779,501 779,502 780,497 780,498 780,499 780,500 780,501 780,502 781,497 781,498 781,499 781,500 781,501 781,502 781,503 781,504 782,497 782,498 782,499 782,500 782,501 782,502 782,503 783,496 783,497 783,498 783,499 783,500 783,501 783,502 784,496 784,497 784,498 784,499 784,500 784,501 785,497 785,498 785,499 785,500"
PIX["away_noarrow"] := "777,497 777,498 777,499 777,500 778,496 778,497 778,498 778,499 778,500 778,501 779,496 779,497 779,498 779,499 779,500 779,501 779,502 780,497 780,498 780,499 780,500 780,501 780,502 781,497 781,498 781,499 781,500 781,501 781,502 781,503 781,504 782,497 782,498 782,499 782,500 782,501 782,502 782,503 783,496 783,497 783,498 783,499 783,500 783,501 783,502 784,496 784,497 784,498 784,499 784,500 784,501 785,497 785,498 785,499 785,500"
PIX["blink1"] := "777,497 777,498 777,499 777,500 778,496 778,497 778,498 778,499 778,500 778,501 779,496 779,497 779,501 780,502 780,503 781,502 781,503 781,504 782,498 782,502 782,503 783,496 783,497 783,501 783,502 784,496 784,500 784,501 785,496 785,497 786,497 787,498"
PIX["blink1_noarrow"] := "777,497 777,498 777,499 777,500 778,496 778,497 778,498 778,499 778,500 778,501 779,496 779,497 779,501 780,502 780,503 781,502 781,503 781,504 782,502 782,503 783,501 783,502 784,500 784,501"
PIX["blink2"] := "726,488 726,489 727,487 727,488 728,486 728,487 729,487 729,488 730,488 731,489 777,497 778,497 779,496 779,497 780,497 781,497 782,497 783,496 783,497 783,498 784,496 784,497 784,498 784,499 784,500 785,497 785,498 785,499 785,500"
PIX["blink2_noarrow"] := "777,497 778,497 779,496 779,497 780,497 781,497 782,497 783,496 783,497 783,498 784,496 784,497 784,498 784,499 784,500 785,497 785,498 785,499 785,500"
PIX["blink3"] := "726,488 726,489 727,487 727,488 728,487 729,487 729,488 730,488 730,489 731,489 777,497 777,498 778,496 778,497 778,498 779,497 779,498 780,497 780,498 781,497 781,498 782,497 782,498 783,496 783,497 783,498 783,499 783,500 784,496 784,497 784,498 784,499 784,500 784,501 785,497 785,498 785,499 785,500"
PIX["blink3_noarrow"] := "777,497 777,498 778,496 778,497 778,498 779,497 779,498 780,497 780,498 781,497 781,498 782,497 782,498 783,496 783,497 783,498 783,499 783,500 784,496 784,497 784,498 784,499 784,500 784,501 785,497 785,498 785,499 785,500"
PIX["blink4"] := "726,488 726,489 727,487 727,488 728,486 728,487 729,487 729,488 730,488 731,489 783,496 783,497 784,496 784,497 784,498 785,497 785,498 785,499 785,500"
PIX["blink4_noarrow"] := "783,496 783,497 784,496 784,497 784,498 785,497 785,498 785,499 785,500"
#END#
