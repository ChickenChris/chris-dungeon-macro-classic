; =====================================================================
;  Debug recording (Settings > Debug recording)
;  What the macro saw and did, so bugs get fixed from real rounds instead of guesses (Chris 5 Nov).
;  While farming: the game as a JPG every second and right before clicks, every log line, step, click
;  and key with its time, and what the card check measured. Kept in Logs\debug_<time>\, only the last
;  2 minutes of pictures. On pause (F4) or stop it's zipped to Logs\debug_<time>.zip to send in Discord.
;  On for everyone since 9 Nov ("Recording when something goes wrong", autoRec): it also saves itself when
;  the macro logs a "Couldn't..." line or the watchdog finds it stuck (players' recordings started after
;  the moment that mattered). At most one save per 3 minutes, the newest 10 zips kept
; =====================================================================
global dbgDir := "", dbgFrames := [], dbgVote := "", dbgStarted := 0, dbgWant := "", dbgSavedAt := -999999
DBG_KEEP_MS := 120000           ; pictures kept: the last 2 minutes (a zip of ~10 MB, small enough for Discord)

DbgOn() => IsSet(cfg) && IsObject(cfg) && cfg.Has("autoRec") && cfg["autoRec"]
DbgNow() => A_TickCount
DbgRun(cmd) => Run(cmd, , "Hide")

; something went wrong: the last 2 minutes saved on the next tick (not more often than every 3 minutes)
DbgSaveSoon(reason) {
    global dbgWant
    if dbgWant != "" || DbgNow() - dbgSavedAt < 180000
        return
    dbgWant := reason
}

SetTimer DbgTick, 1000

DbgTick() {
    global dbgDir, dbgWant, dbgSavedAt
    static busy := false
    if busy
        return
    busy := true
    try {
        if DbgOn() && running && !paused {
            if dbgDir = ""
                DbgBegin()
            else if dbgWant != "" {             ; saved by itself, and a new 2 minutes starts
                dbgSavedAt := DbgNow()
                why := dbgWant, dbgWant := ""
                DbgPack(why)
                DbgBegin(true)
            }
            DbgFrame("every second")
        } else if dbgDir != ""
            DbgPack()
    }
    busy := false
}

DbgBegin(quiet := false) {
    global dbgDir, dbgFrames, dbgStarted
    dir := A_ScriptDir "\Logs\debug_" FormatTime(, "yyyyMMdd_HHmmss")
    if DirExist(dir) || FileExist(dir ".zip")   ; saved and started again in the same second: the old one
        dir .= "_" A_TickCount                  ; is still being zipped (and then removed)
    try DirCreate dir
    catch
        return
    dbgDir := dir, dbgFrames := [], dbgStarted := A_TickCount
    info := "Version: " (IsSet(APP_VER) ? APP_VER : "?") "`nRunning: " A_ScriptName " (built " FileGetTime(A_ScriptFullPath, "M") ")`nMode: " (cfg.Has("mode") ? cfg["mode"] : "?")
        . "`nWindows: " A_OSVersion "`nScreen: " A_ScreenWidth "x" A_ScreenHeight " at " A_ScreenDPI " dpi"
    try {
        WinGetClientPos &ox, &oy, &cw, &ch, RBX
        info .= "`nRoblox game area: " cw "x" ch " at " ox "," oy
    }
    try FileAppend(info "`n", dir "\info.txt", "UTF-8")
    if !quiet
        AddLog("Recording the last 2 minutes (saved by itself when something goes wrong)")
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
        live := ""
        if CaptureGameJpg(file, 50, &live) {
            dbgFrames.Push([A_TickCount, file])
            st := "", mp := ""
            try st := stepNow
            try mp := curMap
            old := A_CoordModeMouse              ; the mouse on Roblox's game area (screen minus its corner)
            CoordMode "Mouse", "Screen"
            MouseGetPos &mx, &my
            CoordMode "Mouse", old
            mx2 := "", my2 := ""
            try {
                WinGetClientPos &ox, &oy, , , RBX
                mx2 := mx - ox, my2 := my - oy
            }
            FileAppend(name "  [" why "]  step: " st "  |  map: " mp "  |  mouse: " mx2 "," my2 "  |  cards: " dbgVote
                . "  |  live: " live "`n",
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
    if kind = "log" && RegExMatch(text, "^Couldn't")
        DbgSaveSoon(SubStr(text, 1, 60))
    if dbgDir = ""
        return
    try FileAppend(FormatTime(, "HH:mm:ss") "." Format("{:03}", A_MSec) "  " kind ": " text "`n", dbgDir "\events.txt", "UTF-8")
}

; zipped next to the folder, the folder removed once the zip is there (PowerShell, in the background)
DbgPack(why := "") {
    global dbgDir, dbgFrames
    dir := dbgDir, dbgDir := "", dbgFrames := []
    if dir = "" || !DirExist(dir)
        return
    zip := dir ".zip"
    q(s) => "'" StrReplace(s, "'", "''") "'"
    ps := "Compress-Archive -LiteralPath " q(dir) " -DestinationPath " q(zip) " -Force; if (Test-Path -LiteralPath " q(zip) ") { Remove-Item -LiteralPath " q(dir) " -Recurse -Force }"
    try DbgRun('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "' ps '"')
    SplitPath zip, &zname
    if why != ""
        AddLog("Saved the last 2 minutes: Logs\" zname " (" why "). Send it in Discord with what went wrong")
    else
        AddLog("Debug recording saved: Logs\" zname ". Send it in Discord with what went wrong")
    SplitPath dir, , &logs
    DbgPrune(logs, 9)                           ; (+ the one being zipped now = 10)
}

; only the newest `keep` recordings stay in Logs (their names start with the date and time)
DbgPrune(dir, keep := 10) {
    zips := []
    try loop files dir "\debug_*.zip"
        zips.Push(A_LoopFileName)
    if zips.Length <= keep
        return
    loop zips.Length - 1                        ; oldest first
        loop zips.Length - A_Index
            if StrCompare(zips[A_Index], zips[A_Index + 1]) > 0
                t := zips[A_Index], zips[A_Index] := zips[A_Index + 1], zips[A_Index + 1] := t
    loop zips.Length - keep
        try FileDelete dir "\" zips[A_Index]
}

; the Roblox game area as a JPG (quality 0-100). Its own screen copy: the macro's checks aren't touched
CaptureGameJpg(file, quality := 60, &live := "") {
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
        live := DbgLive(sdc, hbm, w, h)          ; the checks' numbers on this exact picture (the JPG blurs colours)
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

; The macro's colour checks measured on the captured picture itself, before it's made a JPG (JPG blurs thin
; coloured text: a gold bar measured 0.47 live and 0.30 on the JPG). Same spots and steps as ColorShare
DbgLive(dc, hbm, w, h) {
    bmi := Buffer(40, 0)
    NumPut("UInt", 40, bmi, 0), NumPut("Int", w, bmi, 4), NumPut("Int", -h, bmi, 8)
    NumPut("UShort", 1, bmi, 12), NumPut("UShort", 32, bmi, 14)
    bits := Buffer(w * h * 4, 0)
    if !DllCall("GetDIBits", "Ptr", dc, "Ptr", hbm, "UInt", 0, "UInt", h, "Ptr", bits, "Ptr", bmi, "UInt", 0)
        return ""
    sh(x1, y1, x2, y2, test) {
        hits := 0, total := 0, px := x1
        while px <= x2 && px < w {
            py := y1
            while py <= y2 && py < h {
                v := NumGet(bits, (py * w + px) * 4, "UInt")
                hits += test((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF) ? 1 : 0, total++
                py += 6
            }
            px += 8
        }
        return total ? Round(hits / total, 2) : 0
    }
    white := (r, g, b) => r > 220 && g > 220 && b > 220
    dark := (r, g, b) => r + g + b < 150
    return "vote title " sh(317, 154, 487, 171, white) " ends " sh(340, 457, 462, 473, white)
        . " cards " sh(173, 330, 273, 410, dark) "/" sh(350, 330, 450, 410, dark) "/" sh(527, 330, 627, 410, dark)
        . "; menu box " sh(150, 262, 275, 355, (r, g, b) => r <= 45 && g <= 30 && b <= 35)
        . " gold " sh(150, 234, 262, 250, (r, g, b) => r >= 55 && r <= 130 && g >= 35 && g <= 95 && b <= 25)
        . " X " sh(268, 217, 286, 235, (r, g, b) => r >= 170 && g <= 90 && b <= 90)
        . "; max yellow " sh(170, 278, 272, 326, (r, g, b) => r >= 200 && g >= 140 && b <= 110 && r - b >= 120)
        . " grey " sh(160, 368, 258, 396, (r, g, b) => r >= 50 && r <= 110 && Abs(r - g) <= 14 && Abs(g - b) <= 14)
        . "; wave done " sh(300, 452, 330, 476, (r, g, b) => g >= 200 && r >= 40 && r <= 160 && b <= 120)
}
