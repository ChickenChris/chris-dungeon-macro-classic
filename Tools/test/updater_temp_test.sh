#!/bin/bash
# The updater's download folder in Temp (Lib\Updater.ps1). Shadow 22 Nov, user folder "Jão": Update.bat stopped
# after the license check with "Não existe um objeto no caminho especificado C:\Users\JO8240~1." (An object at
# the specified path ... does not exist). A user name with letters like ã or Cyrillic gets Temp an 8.3 short
# name (C:\Users\JO8240~1\AppData\Local\Temp), and PowerShell's Remove-Item can't handle those (PowerShell issue
# 21070): the clean-up after an update failed quietly, the folder stayed, and the next update stopped on it.
# Now: such a Temp isn't used (the long-named AppData\Local instead), the folder is cleared and made with .NET
# (no Remove-Item on it), and a leftover that won't go gets a new folder. Static (no PowerShell here)
cd "$(dirname "$0")/../.."
python3 - "$(pwd)/Lib/Updater.ps1" <<'P'
import re, sys
s = open(sys.argv[1], encoding="utf-8-sig").read()
fails = 0
def check(name, ok):
    global fails
    print(("PASS " if ok else "FAIL ") + name); fails += not ok
m = re.search(r"^function RunUpdate \{.*?^\}", s, re.S | re.M)
b = m.group(0) if m else ""
check("the update folder is never removed with Remove-Item (8.3 Temp paths break it)",
      bool(b) and not re.search(r"Remove-Item\s+(-LiteralPath\s+)?\$tmp\b", b))
check("  it's cleared and made with .NET", "[IO.Directory]::Delete($tmp, $true)" in b and "[IO.Directory]::CreateDirectory($tmp)" in b)
check("  a short-named Temp (with ~) isn't used: AppData\\Local instead",
      re.search(r"\$root\s*=\s*\$env:TEMP", b) is not None and re.search(r"if \(\$root -match '~'[^\n]*\$env:LOCALAPPDATA[^\n]*\{\s*\$root\s*=\s*\$env:LOCALAPPDATA\s*\}", b) is not None
      and re.search(r"\$tmp\s*=\s*Join-Path \$root 'cdm-(premium|classic)'", b) is not None)
check("  a leftover folder that won't go: a new folder instead of stopping",
      re.search(r"catch \{\s*\$tmp\s*=\s*Join-Path \$root \('cdm-(premium|classic)-'\s*\+\s*\[Guid\]::NewGuid\(\)", b) is not None)
check("  the clean-up at the end with .NET too, never stopping the update", re.search(r"try \{\s*\[IO\.Directory\]::Delete\(\$tmp, \$true\)\s*\} catch \{\s*\}", b) is not None)
print("ALL PASSED" if not fails else "FAILED %d" % fails)
sys.exit(1 if fails else 0)
P
