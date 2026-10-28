#!/bin/bash
# Shop row reading (Lib\Engine.ahk ShopRowName / ShopByEffect), run under Wine on its own: the
# functions are cut out of Engine.ahk and fed what the screen reader really gave on players' PCs
cd "$(dirname "$0")/../.."
AHK=/tmp/claude-0/-home-claude/cf9d9217-0cd8-5fd7-b7c3-bca236a851f1/scratchpad/ahkbin/AutoHotkey64.exe
T=$(mktemp -d)
python3 - "$T/t.ahk" <<'P'
import re, sys
src = open("Lib/Engine.ahk", encoding="utf-8-sig").read()
host = open("Chris's Dungeon Macro.ahk", encoding="utf-8-sig").read()
def fn(name, text):
    m = re.search(r"^" + re.escape(name) + r"\(\) => \[.*?\]$", text, re.S | re.M) or \
        re.search(r"^" + re.escape(name) + r"\(.*?^\}", text, re.S | re.M)
    return m.group(0)
parts = [fn(n, src) for n in ["SHOP_ITEMS", "SHOP_MAGIC", "SHOP_PHYSICAL", "ShopWanted", "ShopRowName", "ShopByEffect", "FuzzyPick", "FoldOcr", "Levenshtein"]]
parts.append(fn("IndexOf", host))
# (raw text, items switched off, the name it must give)
checks = [
    ("Cloak Cloak", "", "Nimble Cloak"),
    ("Cloak Attack Cool down Cloak A", "", "Nimble Cloak"),
    ("Attack Attack", "", "Dagger"),                 # every +attack item wanted: the lowest on the list
    ("Attack Attack", "Dagger", ""),                 # one of them switched off: not bought on a guess
    ("4-75% Attack 4-75% Attack", "", "Scimitar"),
    ("5% Attack O aooe« 5% Attack O ", "", "Dagger"),
    ("eri+ Chance eri+ Chance", "", "Axe"),
    ("esoz eri+ Chance esoz eri+ Cha", "Solar Cleaver", ""),
    ("Qeeper Qeeper", "", "Reaper Scythe"),
    ("Golden room Golden room", "", "Golden Mushroom"),
    ("epeedvg eoo+s epeedvg eoo+s", "", "Speedy Boots"),
    ("Hage Dar•age Hage Dar•age", "", "Mage Coat"),  # magic damage, no %: was read as Axe
    ("Hage Dar•age Hage Dar•age", "Magic Tome", ""),
    # the ones that already worked stay the same
    ("Dagger 4-15% Attack Dagger 4-1", "", "Dagger"),
    ("Dagger —20% Ener•u Gpeed Dagge", "", "Ice Dagger"),
    ("Ninja gel* -12% At+ack Cooldow", "", "Ninja Belt"),
    ("Ninble Cloak Ninble Cloak", "", "Nimble Cloak"),
    ("Pou +20% Range Pou +20% Range", "", "Bow"),
    ("Longbou +30% Range Longbou +30", "", "Longbow"),
    ("Meadspli++er Dhusieal Meadspli", "", "Headsplitter"),
    ("Hage Coa+ •50% Hagie Dar•agø H", "", "Mage Coat"),
    ("Fishhook Ches+ Luck Fishhook C", "", "Fish Hook"),
    ("Ninja -12% A++ack Cooldo•n Nin", "", "Ninja Belt"),   # was taken for Dagger
    ("Ninja Ninja", "", "Ninja Belt"),
    ("-sove A++ack Cooldown -SO% A++", "", "Stormbringer"), # "SO%" is 50%
    ("Hagie •100% Dar•age Hagie •100", "", "Magic Tome"),
    ("Hago Coa+ •SO% *agie Dar•age H", "", "Mage Coat"),
    ("Haoie Torw Magic Dat•age Haoie", "", "Magic Tome"),   # was taken for Mage Coat
    ("Qeaper Dar•age Qeaper Dar•age", "", "Reaper Scythe"),
    ("Golden roon Golden roon", "", "Golden Mushroom"),
    ("4-30% Attack 4-30% Attack", "", "Sword"),
    ("Speedv goo+s -20% A++ack Coold", "", "Speedy Boots"),
    ("Glacial —30% Ener•u Gpeed Glac", "", "Glacial Axe"),
    ("Solar i + Chance Solar i + Cha", "", "Solar Cleaver"),
    ("Aureus Haul Phußieal Dar•age H", "", "Aures Maul"),
    ("Genie Larv Cheß+ Luck Genie La", "", "Genie Lamp"),
    ("Golden e ranch Golden e ranch", "", "Golden Branch"),
    ("Golden Fishhook Luck Golden Fi", "", "Golden Fishhook"),
    ("Elf Pou gange Elf Pou Range", "", "Elf Bow"),
    ("Golden Golden", "", ""),                              # Mushroom, Branch or Fishhook: not guessed
    ("", "", ""),
]
body = "#Requires AutoHotkey v2.0\nglobal cfg := Map()\nfails := 0\n" + "\n".join(parts) + "\n"
for raw, off, want in checks:
    r = raw.replace('"', '""')
    body += 'cfg := Map("shopRank", SHOP_ITEMS(), "shopOff", Map(), "dmgType", "Both", "shopUnknown", 0)\n'
    for o in [x for x in off.split(",") if x]:
        body += f'cfg["shopOff"]["{o}"] := 1\n'
    body += f'got := ShopRowName("{r}"), ok := got = "{want}"\n'
    body += f'FileAppend((ok ? "PASS " : "FAIL ") "{r} -> " got " (want {want})`n", "*", "UTF-8"), fails += !ok\n'
body += 'FileAppend(fails ? "FAILED " fails "`n" : "ALL PASSED`n", "*", "UTF-8")\nExitApp fails ? 1 : 0\n'
open(sys.argv[1], "w", encoding="utf-8-sig").write(body)
P
WINEDEBUG=-all timeout 60 xvfb-run -a wine "$AHK" /ErrorStdOut "Z:${T//\//\\}\\t.ahk" 2>&1 | grep -v "^X conn" | tr -d '\r'
rm -rf "$T"
