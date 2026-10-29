# Chris's Dungeon Macro Classic updater (started by Update.bat).
# Downloads the newest Classic from GitHub and copies it over this folder.
# Settings and Logs (your walks, spots, options) are kept.
#   -Full   the new Update.bat: this script draws the whole window (title, pauses, errors).
#   -Auto   started by the macro (a newer version is out): no key presses, and the macro is started
#           again afterwards (-Ahk, -Script) with --updated, also when the update didn't work
param([switch]$Full, [switch]$Auto, [string]$Ahk = '', [string]$Script = '')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'        # PowerShell's progress bar made downloads several times slower
$dir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$repo = 'ChickenChris/chris-dungeon-macro-classic'
# the whole Classic folder as a zip, tried in this order (some networks block one of them)
$sources = @(
    @{ name = 'GitHub'; url = "https://github.com/$repo/archive/refs/heads/main.zip" },
    @{ name = 'GitHub (zip server)'; url = "https://codeload.github.com/$repo/zip/refs/heads/main" }
)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------- looks
function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Step($n, $text) { Write-Host ("  [$n/2] " + $text.PadRight(34)) -NoNewline -ForegroundColor White }
function Ok($text = 'ok') { Write-Host $text -ForegroundColor Green }

function Banner {
    Say ''
    Say '   +----------------------------------------------------+' Magenta
    Write-Host '   |' -NoNewline -ForegroundColor Magenta
    Write-Host "     Chris's Dungeon Macro  " -NoNewline -ForegroundColor White
    Write-Host '*' -NoNewline -ForegroundColor Yellow
    Write-Host '  Classic updater      ' -NoNewline -ForegroundColor Cyan
    Say '|' Magenta
    Say '   +----------------------------------------------------+' Magenta
    Say ''
}

# the cat: two running frames (the legs swap) and a happy one for the finish
$catRun = @(
    @('          /\_/\  ', ' ~~.____/ o.o \  ', '    \_________/  ', '    /  \   /  \  '),
    @('          /\_/\  ', ' ~~.____/ o.o \  ', '    \_________/  ', '     ||    ||    ')
)
$catHappy = @('          /\_/\  ', ' ~~.____/ ^.^ \  ', '    \_________/  ', '     ||    ||    ')

# the cat runs from the old version number to the new one while the bar fills in behind it
function CatRun([string]$from, [string]$to) {
    $track = 44
    $lead = 4 + $from.Length                   # where the bar starts: "   3.2.38 "
    $catW = $catRun[0][0].Length
    $last = $track - $catW + 4                 # the cat's nose ends over the new number
    try {
        try { [Console]::CursorVisible = $false } catch { }      # hide the blinking cursor while it runs
        for ($i = 0; $i -lt 6; $i++) { Write-Host '' }   # room for the scene (the window may scroll)
        $top = [Console]::CursorTop - 6
        for ($x = 0; $x -le $last; $x++) {
            $done = $x -eq $last
            $frame = if ($done) { $catHappy } else { $catRun[$x % 2] }
            for ($r = 0; $r -lt 4; $r++) {
                [Console]::SetCursorPosition(0, $top + $r)
                $dust = ''
                if ($r -eq 3 -and $x -gt 2 -and -not $done) { $dust = ('.  ', ' . ', '  .')[$x % 3] }
                $line = if ($dust) { (' ' * [Math]::Max(0, $lead + $x - 3)) + $dust + $frame[$r] } else { (' ' * ($lead + $x)) + $frame[$r] }
                Write-Host $line.PadRight($lead + $track + 12) -NoNewline -ForegroundColor Yellow
            }
            if ($done) {
                [Console]::SetCursorPosition($lead + $x + $catW, $top + 1)
                Write-Host 'meow!' -NoNewline -ForegroundColor Magenta
            }
            [Console]::SetCursorPosition(0, $top + 4)
            $filled = [Math]::Min($track, [Math]::Round($track * $x / $last))
            Write-Host ('   ' + $from + ' ') -NoNewline -ForegroundColor DarkGray
            Write-Host ('=' * $filled) -NoNewline -ForegroundColor Green
            Write-Host ('-' * ($track - $filled)) -NoNewline -ForegroundColor DarkGray
            Write-Host (' ' + $to + '   ') -NoNewline -ForegroundColor $(if ($done) { 'Green' } else { 'Cyan' })
            Start-Sleep -Milliseconds 55
        }
        [Console]::SetCursorPosition(0, $top + 6)
        try { [Console]::CursorVisible = $true } catch { }
    } catch {
        Say ("   $from  ->  $to") Green           # a window that can't move the cursor: just say it
    }
}

# the cat sitting still: already on the newest version
function CatSit([string]$ver) {
    Say ''
    foreach ($row in $catHappy) { Say ('      ' + $row) Yellow }
    Say ("   You already have the newest version ($ver).") Green
}

# ---------------------------------------------------------------- the update itself
function VersionOf($file) {
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    $t = Get-Content -LiteralPath $file -Raw
    if ($t -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] }
    return $null
}

# one download: PowerShell first, then Windows' own curl.exe (a different network stack)
function Fetch($url, $out) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out -TimeoutSec 90
        if ((Test-Path -LiteralPath $out) -and (Get-Item -LiteralPath $out).Length -gt 1000) { return $true }
    } catch { $script:lastError = $_.Exception.Message }
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path -LiteralPath $curl) {
        & $curl -fsSL --retry 2 --connect-timeout 20 -o $out $url 2>$null
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $out) -and (Get-Item -LiteralPath $out).Length -gt 1000) { return $true }
    }
    return $false
}

function RunUpdate {
    $tmp = Join-Path $env:TEMP 'cdm-classic'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'classic.zip'

    Step 1 'Downloading the newest version...'
    $got = $false
    $tried = @()
    foreach ($s in $sources) {
        if (Fetch $s.url $zip) { $got = $true; $from = $s.name; break }
        $tried += $s.name
    }
    if (-not $got) {
        Say 'failed' Red
        throw ("Couldn't download the update (" + $script:lastError + "). Something on this PC or network blocks GitHub: " +
            'a VPN, antivirus, a school/work network or your internet provider. Try another network (a phone hotspot works), ' +
            'or download the newest Classic zip from the Discord server.')
    }
    Ok $(if ($tried.Count) { "ok (from $from, $($tried -join ' / ') didn't answer)" } else { 'ok' })

    Step 2 'Installing...'
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x') -Force
    $src = Get-ChildItem -LiteralPath (Join-Path $tmp 'x') -Directory | Select-Object -First 1
    if (-not $src -or -not (Test-Path -LiteralPath (Join-Path $src.FullName "Chris's Dungeon Macro.ahk"))) { Say 'failed' Red; throw 'The download looks broken. Try again later.' }
    $have = VersionOf (Join-Path $dir 'version.txt')
    $new = VersionOf (Join-Path $src.FullName 'version.txt')
    robocopy $src.FullName $dir /E /XD Settings Logs .git /XF Update.bat .gitattributes .gitignore README.md /R:5 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { Say 'failed' Red; throw 'Copying the new files failed. Is the macro still open?' }
    Ok
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    if ($have -and $new -and $new -eq $have) { CatSit "$new" }
    elseif ($new) { Say ''; CatRun $(if ($have) { "$have" } else { '?' }) "$new" }
}

# ---------------------------------------------------------------- run
if ($Auto) {
    try { $Host.UI.RawUI.WindowTitle = "Chris's Dungeon Macro Classic - Update" } catch { }
    Banner
    Say '   A new version is out: installing it before the macro starts.' Cyan
    Say '   Your Settings and Logs folders are kept (your own walks, spots and options).'
    Say ''
    Start-Sleep -Milliseconds 1500              # the macro closing lets go of its files
    $ok = $true
    try { RunUpdate } catch {
        $ok = $false
        Say ''
        Say ('   ' + $_.Exception.Message) Red
        Say ''
        Say '   Starting the version you have. Run Update.bat later to try again.' Yellow
    }
    Say ''
    if ($Ahk -ne '' -and $Script -ne '') {
        Say '   Starting the macro...' Green
        Start-Sleep -Seconds $(if ($ok) { 2 } else { 10 })
        # no -WorkingDirectory (a folder name with [ ] broke it on Windows PowerShell); the macro sets its own
        try { Start-Process -FilePath $Ahk -ArgumentList @(('"' + $Script + '"'), '--updated') }
        catch { Say ('   Couldn''t start it: ' + $_.Exception.Message + '. Start it yourself.') Red; Start-Sleep -Seconds 15 }
    }
    exit $(if ($ok) { 0 } else { 1 })
}
if (-not $Full) {
    RunUpdate
    exit 0
}

try { $Host.UI.RawUI.WindowTitle = "Chris's Dungeon Macro Classic - Update" } catch { }
Banner
$cur = VersionOf (Join-Path $dir 'version.txt')
Say '   Close the macro before updating.' Yellow
Say '   Your Settings and Logs folders are kept (your own walks, spots and options).'
Say ''
Write-Host '   Current version: ' -NoNewline
Say $(if ($cur) { "$cur" } else { 'unknown' }) Cyan
Say ''
Write-Host '   Press any key to update...' -NoNewline -ForegroundColor White
try { [void][Console]::ReadKey($true) } catch { Read-Host | Out-Null }
Say ''
Say ''
$code = 0
try {
    RunUpdate
    Say ''
    Say '   Done! Start "Chris''s Dungeon Macro.ahk" again.' Green
} catch {
    $code = 1
    Say ''
    Say ('   ' + $_.Exception.Message) Red
    Say ''
    Say "   The update didn't work. Check your internet and try again," Yellow
    Say '   or download the newest Classic zip from the Discord server.' Yellow
}
Say ''
Write-Host '   Press any key to close.' -NoNewline -ForegroundColor DarkGray
try { [void][Console]::ReadKey($true) } catch { Read-Host | Out-Null }
exit $code
