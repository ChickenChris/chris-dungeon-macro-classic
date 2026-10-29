; =====================================================================
;  Updating on start (Premium and Classic, the same file)
;  When a newer version is out, the macro closes and Lib\Updater.ps1 installs it (Settings and Logs
;  are kept), then starts the macro again with --updated (no second check). No internet, GitHub
;  blocked, or the same version: the macro just starts. Update.bat still works by hand
; =====================================================================

; repo: the GitHub repo holding `file`, a text with the newest version in it
AutoUpdate(repo, file) {
    for a in MacroArgs()
        if a = "--updated"                      ; just updated (or the update failed): start as it is
            return
    newest := VerOf(NewestVersion(repo, file))
    if !VerNewer(newest, VerOf(APP_VER))
        return
    ; each new version gets one try: when its update didn't take (PowerShell blocked, the license
    ; server down), the macro starts as it is from then on and Update.bat is the retry
    tried := A_ScriptDir "\Settings\update.ini"
    if IniRead(tried, "Update", "Tried", "") = newest
        return
    try {
        DirCreate A_ScriptDir "\Settings"
        IniWrite newest, tried, "Update", "Tried"
    }
    StartUpdater()
}

MacroArgs() => A_Args

; the newest version's text, "" when nothing answers (GitHub, then a CDN copy; a few seconds at most)
NewestVersion(repo, file) {
    for url in ["https://raw.githubusercontent.com/" repo "/main/" file, "https://cdn.jsdelivr.net/gh/" repo "@main/" file] {
        try {
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.SetTimeouts(2500, 2500, 2500, 2500)
            req.Open("GET", url, false)
            req.Send()
            if req.Status = 200
                return req.ResponseText
        }
    }
    return ""
}

; the macro closes, the updater window installs the new version and starts the macro again
StartUpdater() {
    try {
        Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' A_ScriptDir '\Lib\Updater.ps1" -Auto -Ahk "'
            . A_AhkPath '" -Script "' A_ScriptFullPath '"', A_ScriptDir
        ExitApp
    }
}

VerOf(t) => RegExMatch(t, "\d+\.\d+\.\d+", &m) ? m[0] : ""

; is version a newer than b (by numbers: 3.2.100 is newer than 3.2.99)
VerNewer(a, b) {
    if a = "" || b = ""
        return false
    pa := StrSplit(a, "."), pb := StrSplit(b, ".")
    loop 3
        if Integer(pa[A_Index]) != Integer(pb[A_Index])
            return Integer(pa[A_Index]) > Integer(pb[A_Index])
    return false
}
