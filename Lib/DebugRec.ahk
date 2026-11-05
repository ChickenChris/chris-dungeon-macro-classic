; =====================================================================
;  Debug recording (Settings > Debug recording)
;  What the macro saw and did, so bugs get fixed from real rounds instead of guesses (Chris 5 Nov).
;  While farming: the game as a JPG every second and right before clicks, every log line, step, click
;  and key with its time, and what the card check measured. Kept in Logs\debug_<time>\, only the last
;  2 minutes of pictures. On pause (F4) or stop it's zipped to Logs\debug_<time>.zip to send in Discord.
;  Off by default; nothing else changes while it's off.
; =====================================================================
global dbgDir := "", dbgFrames := [], dbgVote := "", dbgStarted := 0
DBG_KEEP_MS := 120000           ; pictures kept: the last 2 minutes (a zip of ~10 MB, small enough for Discord)

DbgOn() => IsSet(cfg) && IsObject(cfg) && cfg.Has("debugRec") && cfg["debugRec"]

SetTimer DbgTick, 1000

DbgTick() {
    global dbgDir
    static busy := false
    if busy
        return
    busy := true
    try {
        if DbgOn() && running && !paused {
            if dbgDir = ""
                DbgBegin()
            DbgFrame("every second")
        } else if dbgDir != ""
            DbgPack()
    }
    busy := false
}

DbgBegin() {
    global dbgDir, dbgFrames, dbgStarted
    dir := A_ScriptDir "\Logs\debug_" FormatTime(, "yyyyMMdd_HHmmss")
    try DirCreate dir
    catch
        return
    dbgDir := dir, dbgFrames := [], dbgStarted := A_TickCount
    info := "Version: " (IsSet(APP_VER) ? APP_VER : "?") "`nMode: " (cfg.Has("mode") ? cfg["mode"] : "?")
        . "`nWindows: " A_OSVersion "`nScreen: " A_ScreenWidth "x" A_ScreenHeight " at " A_ScreenDPI " dpi"
    try {
        WinGetClientPos &ox, &oy, &cw, &ch, RBX
        info .= "`nRoblox game area: " cw "x" ch " at " ox "," oy
    }
    try FileAppend(info "`n", dir "\info.txt", "UTF-8")
    AddLog("Debug recording: on (the last 2 minutes are kept, zipped when you pause or stop)")
}

; a picture of the game now, with what the macro was doing (at most one every 0.5 s)
DbgFrame(why) {
    global dbgFrames
    static last := 0, busy := false
    if dbgDir = "" || busy || A_TickCount - last < 500
        return
    busy := true, last := A_TickCount
    try {
        name := FormatTime(, "HHmmss") "_" Format("{:03}", A_MSec)
        file := dbgDir "\" name ".jpg"
        if CaptureGameJpg(file, 50) {
            dbgFrames.Push([A_TickCount, file])
            st := "", mp := ""
            try st := stepNow
            try mp := curMap
            MouseGetPos &mx, &my
            mx2 := "", my2 := ""
            try {
                WinGetClientPos &ox, &oy, , , RBX
                mx2 := mx - ox, my2 := my - oy
            }
            FileAppend(name "  [" why "]  step: " st "  |  map: " mp "  |  mouse: " mx2 "," my2 "  |  cards: " dbgVote "`n",
                dbgDir "\frames.txt", "UTF-8")
        }
        while dbgFrames.Length && A_TickCount - dbgFrames[1][1] > DBG_KEEP_MS {
            try FileDelete dbgFrames[1][2]
            dbgFrames.RemoveAt(1)
        }
    }
    busy := false
}

; a line in events.txt: log lines, steps, clicks, keys (all of the session)
DbgNote(kind, text) {
    if dbgDir = ""
        return
    try FileAppend(FormatTime(, "HH:mm:ss") "." Format("{:03}", A_MSec) "  " kind ": " text "`n", dbgDir "\events.txt", "UTF-8")
}

; zipped next to the folder, the folder removed once the zip is there (PowerShell, in the background)
DbgPack() {
    global dbgDir, dbgFrames
    dir := dbgDir, dbgDir := "", dbgFrames := []
    if dir = "" || !DirExist(dir)
        return
    zip := dir ".zip"
    q(s) => "'" StrReplace(s, "'", "''") "'"
    ps := "Compress-Archive -LiteralPath " q(dir) " -DestinationPath " q(zip) " -Force; if (Test-Path -LiteralPath " q(zip) ") { Remove-Item -LiteralPath " q(dir) " -Recurse -Force }"
    try Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' ps '"', , "Hide")
    SplitPath zip, &zname
    AddLog("Debug recording saved: Logs\" zname ". Send it in Discord with what went wrong")
}

; the Roblox game area as a JPG (quality 0-100). Its own screen copy: the macro's checks aren't touched
CaptureGameJpg(file, quality := 60) {
    hbm := 0, pBmp := 0
    try {
        WinGetClientPos &ox, &oy, &cw, &ch, RBX
        w := Min(cw, 800), h := Min(ch, 600)
        if w < 50 || h < 50
            return false
        sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
        mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
        hbm := DllCall("CreateCompatibleBitmap", "Ptr", sdc, "Int", w, "Int", h, "Ptr")
        obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
        DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", sdc, "Int", ox, "Int", oy, "UInt", 0x40CC0020)
        DllCall("SelectObject", "Ptr", mdc, "Ptr", obm)
        DllCall("DeleteDC", "Ptr", mdc)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
        GdiplusUp()
        DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &pBmp)
        clsid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{557CF401-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)   ; JPEG encoder
        ; EncoderParameters: one Quality value (a ULONG)
        off := A_PtrSize = 8 ? 8 : 4
        params := Buffer(off + 16 + 8 + A_PtrSize, 0), q := Buffer(4, 0)
        NumPut("UInt", quality, q)
        NumPut("UInt", 1, params, 0)
        DllCall("ole32\CLSIDFromString", "WStr", "{1D5BE4B5-FA4A-452D-9CDD-5DB35105E7EB}", "Ptr", params.Ptr + off)
        NumPut("UInt", 1, params, off + 16)     ; one value
        NumPut("UInt", 4, params, off + 20)     ; of type Long
        NumPut("Ptr", q.Ptr, params, off + 24)
        res := DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBmp, "WStr", file, "Ptr", clsid, "Ptr", params)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp), pBmp := 0
        DllCall("DeleteObject", "Ptr", hbm), hbm := 0
        return res = 0 && FileExist(file)
    }
    try (pBmp && DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp))
    try (hbm && DllCall("DeleteObject", "Ptr", hbm))
    return false
}
