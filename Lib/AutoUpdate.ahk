; =====================================================================
;  Updating on start (Premium and Classic, the same file)
;  When a newer version is out, the macro closes and Lib\Updater.ps1 installs it (Settings and Logs
;  are kept), then starts the macro again with --updated (no second check). No internet, GitHub
;  blocked, or the same version: the macro just starts. Update.bat still works by hand
; =====================================================================

; repo: the GitHub repo holding `file`, a text with the newest version in it
AutoUpdate(repo, file) {
    CleanOldScripts()
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

; the .exe: the script files from before it (Lib\*.ahk, the old window ones) are removed, so the code
; isn't lying around in the folder (Chris 3 Nov). The main .ahk becomes the small starter for the .exe
; (Lib\starter.txt: old shortcuts and updaters start that one). Not in a folder with a ".dev" file
; (Chris's test folder, where the scripts are run as well)
CleanOldScripts() {
    if !A_IsCompiled || FileExist(A_ScriptDir "\.dev")
        return
    loop files A_ScriptDir "\Lib\*.ahk", "R"
        try FileDelete A_LoopFileFullPath
    for f in ["Chris's Dungeon Macro (classic).ahk", "Chris's Dungeon Macro (old window).ahk", "AA Dungeon Macro (classic).ahk"]
        try FileDelete A_ScriptDir "\" f
    main := A_ScriptDir "\Chris's Dungeon Macro.ahk", starter := A_ScriptDir "\Lib\starter.txt"
    if FileExist(main) && FileExist(starter) && FileGetSize(main) != FileGetSize(starter)   ; the whole script (or an older starter): this starter instead
        try FileCopy starter, main, 1
}

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
            . (A_IsCompiled ? A_ScriptFullPath '"' : A_AhkPath '" -Script "' A_ScriptFullPath '"'), A_ScriptDir   ; (.exe: started by itself)
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
