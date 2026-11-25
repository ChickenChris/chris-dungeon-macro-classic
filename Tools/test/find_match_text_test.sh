#!/bin/bash
# Summer Hunt's Find Match words (RNG 24 Nov: "why does it say people need to type it manually when it does it
# auto?"): since UPD 21 the macro reads the number and types it in (3 tries), and only if it can't does it wait
# for you and ping. The tooltip said YOU type it, and the step shown while it ran said "waiting for you to type
# the number". UI\index.html #segFoolJoin, Lib\Engine.ahk FoolFindMatch. No Wine
cd "$(dirname "$0")/../.."
python3 - "$(pwd)" <<'P'
import re, sys
root = sys.argv[1]
html = open(f"{root}/UI/index.html", encoding="utf-8").read()
eng = open(f"{root}/Lib/Engine.ahk", encoding="utf-8-sig").read()
fails = 0
def check(name, ok, got=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f" (got {got[:200]})"))
    fails += not ok
tip = re.search(r'id="segFoolJoin" data-tip="([^"]*)"', html)
tip = tip.group(1) if tip else ""
check("the tooltip: the macro types the number in", "the macro types it in" in tip, tip)
check("  and only pings you when it can't", re.search(r"if it can't, it pings you", tip) is not None, tip)
check("  no longer 'YOU type it'", "YOU type it" not in tip, tip)
fm = re.search(r"^FoolFindMatch\(.*?^\}", eng, re.S | re.M)
fm = fm.group(0) if fm else ""
step = re.search(r'Step\(what ": Find Match, ([^"]*)"\)', fm)
check("the step shown while it runs: typing the number, not waiting for you", step is not None and "waiting for you" not in step.group(1) and "number" in step.group(1), step.group(1) if step else fm[:80])
print("FAILED " + str(fails) if fails else "ALL PASSED")
sys.exit(1 if fails else 0)
P
