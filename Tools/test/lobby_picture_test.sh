#!/bin/bash
# The lobby's "Areas" label picture (Lib\Patterns.ahk AreaText21, Lib\Engine.ahk DetDefs "Lobby"). The old
# one stopped matching with UPD 21: every lobby since was found by reading the word "Areas" (slower), and a
# PC whose screen reader reads Japanese never found the lobby at all (10 Nov, "looking for something to do").
# Lobby pictures must match, pictures of a round mustn't (at the 5 % the detectors allow). Run under Wine
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
FX=Tools/test/fixtures
R=$(python3 - "$(pwd)" <<'P'
import re, sys
s = open(sys.argv[1] + "/Lib/Engine.ahk", encoding="utf-8-sig").read()
ok = re.search(r'DetAdd\(d, "Lobby", "Lobby", [^\n]*\bAreaText21\b', s) is not None
print(("PASS" if ok else "FAIL") + " the lobby detector searches UPD 21's Areas label")
P
)
echo "$R"
if [ ! -f $FX/party_full_lobby.bmp ]; then echo "SKIP pictures (players' pictures: Premium only)"; echo "$R" | grep -q "^FAIL" && echo "FAILED (static)" || echo "ALL PASSED"; exit 0; fi
T=$(mktemp -d); W="Z:$(pwd | sed 's#/#\\#g')"
cat > $T/t.ahk <<AHK
#Requires AutoHotkey v2.0
OnError((e, m) => (FileAppend("ERROR " e.Message " (line " e.Line ")\`n", "*"), ExitApp(3)))
#Include $W\Lib\FindText.ahk
#Include $W\Lib\Patterns.ahk
global fails := 0
Areas(f) {
    FindText().ShowPic("$W\Tools\test\fixtures\" f ".bmp", 0)
    return FindText(&x, &y, 600, 400, 800, 598, 0.05, 0.05, AreaText21, 0) && Abs(x - 765) <= 3 && Abs(y - 489) <= 3
}
for f in ["picker_upd21_ahead", "party_full_lobby", "party_alt_popup", "party_kick_dialog", "popup_over_party_box"]
    ok := Areas(f), FileAppend((ok ? "PASS" : "FAIL") " lobby buttons seen: " f "\`n", "*"), fails += !ok
for f in ["facing_down_dungeon_throne", "facing_up_snowy_kingdom", "hill_snowy_held", "leave_over_chests", "menu_water_goddess", "otherwordly_no_menu", "snowy_unit_held", "fool_waiting_players"]
    ok := !Areas(f), FileAppend((ok ? "PASS" : "FAIL") " in a round, not the lobby: " f "\`n", "*"), fails += !ok
FileAppend(fails ? "FAILED " fails "\`n" : "ALL PASSED\`n", "*")
ExitApp fails ? 1 : 0
AHK
OUT=$(WINEDEBUG=-all timeout 120 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r')
rm -rf "$T"
if echo "$R" | grep -q "^FAIL"; then echo "$OUT" | grep -v "ALL PASSED"; echo "FAILED (static)"; else echo "$OUT"; fi
