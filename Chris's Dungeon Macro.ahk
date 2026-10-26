#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir
SendMode "Event"

; =====================================================================
;  Chris's Dungeon Macro Classic  -  Anime Adventures dungeon auto-farm
;  F1 snap Roblox into the window  |  F2 start  |  F3 stop  |  F4 pause
;
;  The window is a small web page (UI\index.html) shown with Microsoft
;  Edge WebView2, which comes with Windows 10 and 11. This file hosts it
;  and talks to it; Lib\Engine.ahk does the farming.
;  If the page can't be shown, "Chris's Dungeon Macro (old window).ahk" opens.
;  The page is the same one Premium uses; Premium's own parts show locked here.
;
;  Files:  UI\             the window (HTML / CSS / JS, fonts, icons)
;          Lib\Engine.ahk  the dungeon logic
;          Lib\Patterns.ahk, FindText.ahk, OCR.ahk   screen reading
;          Lib\WebView2\, JSON.ahk, Promise.ahk, ComVar.ahk   by thqby (MIT)
;          Settings\config.ini, Logs\log.txt
; =====================================================================

#Include %A_ScriptDir%\Lib\Patterns.ahk
#Include %A_ScriptDir%\Lib\Engine.ahk

global APP_VER := AppVersion()

; the full version from version.txt (e.g. "3.0.88 Classic"), so players can see which update they're on
AppVersion() {
    try {
        if RegExMatch(FileRead(A_ScriptDir "\version.txt"), "\d+\.\d+\.\d+", &vm)
            return vm[0] " Classic"
    }
    return "3.0 Classic"
}
global cfgFile := A_ScriptDir "\Settings\config.ini"
global ovrFile := A_ScriptDir "\Settings\patterns.ini"   ; recaptured detections
global logFile := A_ScriptDir "\Logs\log.txt"
DirCreate A_ScriptDir "\Settings"
DirCreate A_ScriptDir "\Logs"

global CURSES := ["Flying", "Wind", "Money", "Health", "Exploding", "Shielding", "Regen"]
global ROOM_KEYS := ["Rare_Chest", "Chest", "Hoard", "Shop", "Shrine", "Boss", "None"]
global ROOM_NAMES := ["Rare chest", "Chest", "Hoard", "Shop", "Shrine", "Boss", "(nothing)"]
global RETRIES := ["Few (quick)", "Normal", "Many", "Max (keeps trying)"]
global UP_NAMES := ["no upgrades", "upgrade each 1 time", "upgrade each 2 times", "upgrade each 3 times",
    "upgrade each 4 times", "upgrade each 5 times", "upgrade each 6 times", "upgrade each 7 times",
    "upgrade each 8 times", "upgrade each 9 times", "upgrade each 10 times", "upgrade each to max"]
global UP_VALUES := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, -1]
global PATTERNS := ["Spiral", "Circle", "Grid", "Random"]
global TOLS := ["Strict (exact match)", "Normal (5% off is fine)", "Loose (10% off is fine)"]
global SPEEDS := ["Super fast (1s)", "Fast (1.5s)", "Normal (2s)", "Slow (2.5s)", "Very slow (3s)", "Toaster (4s)", "Potato (5s)"]
global DEFAULT_BG := "../Images/ui/sakura.webm"

global cfg := DefaultConfig()
LoadConfig()
LoadShippedWalks()
LoadOverrides()

; =====================================================================
;  Window: the page fills it, and a hole is cut where Roblox shows
; =====================================================================
global GUI_W := 1423, GUI_H := 640
global HOLE := [3, 33, 800, 630]           ; left, top, right, bottom of the game area
global guiH := GUI_H
global savePending := false               ; settings changed, saved a moment later (SaveSoon)
global wvc := 0, wv := 0, uiReady := false, uiQueue := [], logBuf := []
global runState := "idle", robloxShown := -1, stepNow := ""
global importCfg := 0               ; settings read from another macro, waiting for "Import"

global MG := Gui("+AlwaysOnTop -Caption -DPIScale", "Chris's Dungeon Macro")
MG.BackColor := "050506"
MG.MarginX := 0, MG.MarginY := 0
MG.OnEvent("Close", (*) => (SaveConfig(), ExitApp()))
MG.Show("w" GUI_W " h" GUI_H)

if !StartWebView() {
    oldWin := A_ScriptDir "\Chris's Dungeon Macro (old window).ahk"
    if FileExist(oldWin) {
        Run '"' A_AhkPath '" "' oldWin '"'
        ExitApp
    }
    MsgBox "This window needs Microsoft Edge WebView2, which didn't start.`nInstall the WebView2 Runtime from Microsoft and try again.", "Chris's Dungeon Macro", "Icon!"
    ExitApp
}

OnExit((*) => (savePending ? SaveConfig() : 0, ReleaseKeys()))

; An error nothing else caught used to open AutoHotkey's error box. It often sat hidden behind
; Roblox or this window, and until it was closed the whole macro was frozen: nothing could be
; clicked and it stopped farming (players saw it after 2-3 hours). Now it's logged and skipped.
OnError(UnhandledError)
UnhandledError(err, mode) {
    static lastKey := "", lastAt := 0
    if err is MacroStop
        return 1
    key := err.Message "|" err.Line
    if key = lastKey && A_TickCount - lastAt < 60000       ; the same one over and over: log it once a minute
        return mode = "Return" ? -1 : 1
    lastKey := key, lastAt := A_TickCount
    try AddLog("Error: " err.Message " (line " err.Line "), skipped. If it keeps happening, send Logs\log.txt in Discord")
    return mode = "Return" ? -1 : 1
}
OnMessage(0x0232, GuiMoved)          ; WM_EXITSIZEMOVE: Roblox follows when you let go
SetTimer CheckRoblox, 1500
CheckRoblox()
if WinExist(RBX)
    FixWindow()
; Update.bat can't replace itself while it runs (Windows reads it line by line), so updates leave
; it out. The newest one comes along as Lib\Update.bat.new and is put in place here, while it isn't
; running. (The old one had the download inside the .bat, which one antivirus flagged.)
try {
    newBat := A_ScriptDir "\Lib\Update.bat.new", oldBat := A_ScriptDir "\Update.bat"
    if FileExist(newBat) && (!FileExist(oldBat) || FileRead(newBat) !== FileRead(oldBat))
        FileCopy newBat, oldBat, true
}
AddLog("Ready. Press F2 to start.")
AddLog("Game settings needed: 'Show Upgrade UI on left' ON, and the upgrade menu must pop up when you place a unit (setting 'Disable Auto-Open Upgrade UI').")
if !WinExist(RBX)
    AddLog("Open Roblox, then press F1 to snap it in.")
if A_ScreenDPI != 96
    AddLog("Windows display scale isn't 100%. Detection may miss.")
SetTimer WatchFiles, 2000

; =====================================================================
;  Hotkeys
; =====================================================================
F1::FixWindowNow()
F2::StartMacro()
F3::StopMacro()
#MaxThreadsPerHotkey 2
F4::TogglePause()
#MaxThreadsPerHotkey 1

; =====================================================================
;  WebView2 page
; =====================================================================
StartWebView() {
    global wvc, wv
    try {
        dataDir := EnvGet("LOCALAPPDATA") "\Chris's Dungeon Macro Classic\WebView2"   ; not in OneDrive (and apart from Premium's)
        DirCreate dataDir
        wvc := WebView2.CreateControllerAsync(MG.Hwnd, 0, dataDir).await2(20000)
        try wvc.DefaultBackgroundColor := 0x060505FF      ; A, R, G, B bytes: black, no white flash
        try wvc.ShouldDetectMonitorScaleChanges := 0      ; 1 page pixel = 1 screen pixel, like the game frame
        try wvc.RasterizationScale := 1.0
        wvc.Fill()
        wv := wvc.CoreWebView2
        st := wv.Settings
        try st.AreDevToolsEnabled := FileExist(A_ScriptDir "\Settings\devtools") ? 1 : 0
        try st.AreDefaultContextMenusEnabled := 0
        try st.IsZoomControlEnabled := 0
        try st.IsStatusBarEnabled := 0
        try st.AreBrowserAcceleratorKeysEnabled := 0
        try st.IsPinchZoomEnabled := 0
        try st.IsSwipeNavigationEnabled := 0
        try st.IsGeneralAutofillEnabled := 0
        try st.IsPasswordAutosaveEnabled := 0
        wv.add_WebMessageReceived(OnWebMessage)
        wv.SetVirtualHostNameToFolderMapping("aa.local", A_ScriptDir, 1)
        wv.Navigate("https://aa.local/UI/index.html")
        return true
    } catch as err {
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  WebView2 failed: " err.Message "`n", logFile, "UTF-8")
        return false
    }
}

; calls window.ui.<fn>(args...) in the page (queued until the page says it's ready)
UI(fn, args*) {
    js := "ui." fn "("
    for i, a in args
        js .= (i > 1 ? "," : "") ToJson(a)
    js .= ")"
    if !uiReady {
        uiQueue.Push(js)
        return
    }
    try wv.ExecuteScriptAsync(js)
}

ToJson(v) {
    if IsObject(v) {
        out := ""
        if v is Array {
            for x in v
                out .= (out = "" ? "" : ",") ToJson(x)
            return "[" out "]"
        }
        if v is Map {
            for k, x in v
                out .= (out = "" ? "" : ",") ToJson(String(k)) ":" ToJson(x)
        } else {
            for k, x in v.OwnProps()
                out .= (out = "" ? "" : ",") ToJson(String(k)) ":" ToJson(x)
        }
        return "{" out "}"
    }
    if v is Number
        return String(v)
    v := StrReplace(v, "\", "\\"), v := StrReplace(v, '"', '\"')
    v := StrReplace(v, "`n", "\n"), v := StrReplace(v, "`r", "\r"), v := StrReplace(v, "`t", "\t")
    v := StrReplace(v, Chr(0x2028), " "), v := StrReplace(v, Chr(0x2029), " ")
    return '"' v '"'
}

; the page sends JSON like {"cmd":"set","key":"zoom","value":1}
OnWebMessage(sender, args) {
    try msg := args.TryGetWebMessageAsString()
    catch
        return
    ; Only the long jobs are queued (they'd hold up the page otherwise). Everything else runs
    ; straight away, because a paused script doesn't run queued jobs: queuing the window
    ; buttons, Import, Open folder and so on would make them do nothing while paused.
    if RegExMatch(msg, '^\{"cmd":"(start|spotPick|recordWalk|testWalk)"')
        SetTimer HandleMessage.Bind(msg), -1
    else
        HandleMessage(msg)
}

HandleMessage(msg) {
    try m := JSON.parse(msg)
    catch
        return
    if !(m is Map)
        return
    mp := m.Get("map", "")
    switch m.Get("cmd", "") {
        case "ready": PageReady()
        case "set":
            SetCfg(m.Get("key", ""), m.Get("value", ""))
        case "slot":
            i := m.Get("i", 0), prop := m.Get("prop", "")
            if IsInteger(i) && i >= 1 && i <= 6 && IndexOf(["on", "count", "prio", "up", "limit"], prop) && IsInteger(m.Get("value", ""))
                cfg["slots"][i].%prop% := prop = "count" ? ClampInt(m["value"], 1, MaxCount(), 1) : Integer(m["value"]), SaveSoon()
        case "route":
            i := m.Get("i", 0), key := m.Get("key", "")
            if IsInteger(i) && i >= 1 && i <= cfg["route"].Length && IndexOf(ROOM_KEYS, key)
                cfg["route"][i] := key, SaveConfig()
        case "curses":
            list := m.Get("list", [])
            ok := list is Array && list.Length = CURSES.Length
            if ok
                for c in CURSES
                    ok := ok && IndexOf(list, c)
            if ok {
                cfg["curseRank"] := []
                for c in list
                    cfg["curseRank"].Push(c)
                SaveConfig()
            }
        case "deny":
            name := m.Get("name", "")
            if cfg["denyShrine"].Has(name)
                cfg["denyShrine"][name] := m.Get("value", 0) ? 1 : 0, SaveConfig()
        case "build": SetBuild(m.Get("steps", []))
        case "spots": SendSpots(mp)
        case "spotPick": SpotPick(mp)
        case "spotEdit": SpotEdit(mp, m.Get("i", 0), m.Get("a", ""))
        case "spotMove": SpotMove(mp, m.Get("from", 0), m.Get("to", 0))
        case "spotClear": SpotClear(mp)
        case "recordWalk": RecordWalk(mp)
        case "testWalk": TestWalk(mp)
        case "clearWalk": ClearWalk(mp)
        case "start": StartMacro()
        case "stop": StopMacro()
        case "pause": TogglePause()
        case "fix": FixWindowNow()
        case "testHook": TestWebhook()
        case "openFolder": Run A_ScriptDir
        case "openLog": FileExist(logFile) ? Run(logFile) : Notify("No log yet")
        case "shot": SaveShot()
        case "chooseGif": ChooseBackground()
        case "resetGif": ResetBackground()
        case "importPick": ImportPick()
        case "importDo": ImportDo(m.Get("parts", []))
        case "backup": BackupConfig()
        case "drag": DragWindow()
        case "min": MG.Minimize()
        case "close": SaveConfig(), ExitApp()
    }
}

PageReady() {
    global uiReady
    uiReady := true
    UI("init", UiState())
    for js in uiQueue                       ; init already has the logs, stats and status
        if InStr(js, "ui.toast(") = 1
            try wv.ExecuteScriptAsync(js)
    uiQueue.Length := 0
    UpdateMapLabel()
    if stepNow != ""
        UI("step", stepNow)
}

UiState() {
    c := Map()
    for k in ScalarKeys()
        c[k] := cfg[k]
    for k in ["route", "curseRank", "denyShrine", "slots", "build", "shopRank", "shopOff"]
        c[k] := cfg[k]
    ; Premium's parts show locked on the page, with what Classic does there
    for k, v in Map("mode", "Dungeon", "icHard", 0, "icStopFloors", 0, "foolMatch", 0, "foolOwnTeam", 0, "foolFreeze", 80,
        "foolAccounts", 2, "foolCards", FOOL_CARDS(), "showcase", 0, "showcaseName", "", "showcaseDiscord", "",
        "lookAhead", 0, "dmgType", "Both", "shopUnknown", 1, "shopMinCoins", 0)
        c[k] := v
    return Map("version", APP_VER, "edition", "classic", "maps", MapNames(), "patterns", PATTERNS,
        "roomKeys", ROOM_KEYS, "roomNames", ROOM_NAMES, "curses", CURSES, "speeds", SPEEDS,
        "upNames", UP_NAMES, "upValues", UP_VALUES, "hasRoblox", WinExist(RBX) ? 1 : 0, "duo", 0, "duoOpen", 0, "maxCount", MaxCount(),
        "run", runState, "stats", StatsMap(), "loot", LootList(), "logs", logBuf, "cfg", c,
        "bgUrl", BgUrl(), "bgName", cfg["bgFile"] != "" ? cfg["bgName"] : "Sakura")
}

; a setting changed on the page
SetCfg(key, value) {
    if !IndexOf(ScalarKeys(), key)
        return
    if cfg[key] is Integer {
        if !IsNumber(value)
            return
        value := Integer(value)
    } else
        value := String(value)
    cfg[key] := value
    SaveConfig()
}

SetBuild(steps) {
    if !(steps is Array)
        return
    list := []
    for st in steps {
        if !(st is Map)
            continue
        kind := st.Get("kind", ""), slot := st.Get("slot", 0), count := st.Get("count", 1), up := st.Get("up", 0)
        if (kind = "place" || kind = "upgrade") && IsInteger(slot) && IsInteger(count) && IsInteger(up) && !(kind = "upgrade" && up = 0)
            list.Push({kind: kind, slot: ClampInt(slot, 1, 6, 1), count: ClampInt(count, 1, MaxCount(), 1), up: ClampInt(up, -1, 10, 0)})
    }
    cfg["build"] := list
    SaveSoon()
}

; drags the window while the left button is held on the title bar. Roblox in the frame moves
; along all the way, instead of jumping over when you let go (moved without waiting for Roblox)
DragWindow() {
    CoordMode "Mouse", "Screen"
    MouseGetPos &mx0, &my0
    MG.GetPos(&gx, &gy)
    carry := []
    try {
        if front := WinExist(RBX) {
            WinGetPos &rx, &ry, , , "ahk_id " front
            if Abs(rx - (gx + CAP_X)) <= 1 && Abs(ry - (gy + CAP_Y)) <= 1
                carry.Push(front)
        }
    }
    lastX := mx0, lastY := my0
    while GetKeyState("LButton", "P") {
        MouseGetPos &mx, &my
        if mx != lastX || my != lastY {
            nx := gx + mx - mx0, ny := gy + my - my0
            MG.Move(nx, ny)
            for h in carry                          ; no size / z-order / focus change, don't wait
                DllCall("SetWindowPos", "Ptr", h, "Ptr", 0, "Int", nx + CAP_X, "Int", ny + CAP_Y, "Int", 0, "Int", 0, "UInt", 0x4015)
            lastX := mx, lastY := my
        }
        Sleep 10
    }
    if lastX != mx0 || lastY != my0
        DockGui()
}

GuiMoved(wParam, lParam, msg, hwnd) {
    if hwnd = MG.Hwnd && WinExist(RBX)
        DockGui()
}

; cuts the game hole while Roblox is open (the page shows a "join the game" card otherwise)
CheckRoblox() {
    global robloxShown
    on := WinExist(RBX) ? 1 : 0
    if on = robloxShown
        return
    robloxShown := on
    if on {
        rgn := DllCall("CreateRectRgn", "Int", 0, "Int", 0, "Int", GUI_W, "Int", guiH, "Ptr")
        cut := DllCall("CreateRectRgn", "Int", HOLE[1], "Int", HOLE[2], "Int", HOLE[3], "Int", HOLE[4], "Ptr")
        DllCall("CombineRgn", "Ptr", rgn, "Ptr", rgn, "Ptr", cut, "Int", 4)      ; RGN_DIFF
        DllCall("DeleteObject", "Ptr", cut)
        DllCall("SetWindowRgn", "Ptr", MG.Hwnd, "Ptr", rgn, "Int", 1)            ; Windows owns rgn now
    } else
        DllCall("SetWindowRgn", "Ptr", MG.Hwnd, "Ptr", 0, "Int", 1)
    UI("roblox", on)
}

; reloads by itself when the macro's files change (only while it's not farming)
WatchFiles() {
    static stamps := ""
    now := ""
    for f in [A_ScriptFullPath, A_ScriptDir "\Lib\Engine.ahk"]
        try now .= FileGetTime(f) "|"
    pageStamp := ""
    loop files A_ScriptDir "\UI\*.*"
        pageStamp .= A_LoopFileTimeModified "|"
    if stamps = "" {
        stamps := now "#" pageStamp
        return
    }
    if stamps = now "#" pageStamp || running || manualRun
        return
    old := StrSplit(stamps, "#")[1]
    stamps := now "#" pageStamp
    if old != now {
        SaveConfig()
        Reload
    }
    global uiReady
    uiReady := false
    try wv.Reload()
}

; =====================================================================
;  Status helpers (the engine calls these)
; =====================================================================
AddLog(msg) {
    t := FormatTime(, "HH:mm:ss")
    logBuf.Push([t, msg])
    if logBuf.Length > 120
        logBuf.RemoveAt(1)
    if uiReady
        UI("log", t, msg)
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " msg "`n", logFile, "UTF-8")
}

Step(text) {
    global stepNow
    if text = stepNow
        return
    stepNow := text
    UI("step", text)
}

SetRun(state) {
    global runState
    runState := state
    UI("status", state)
}

; time the macro has been running, not counting pauses
RunTime() {
    if !stat.startTick
        return 0
    ms := A_TickCount - stat.startTick - (pauseTotal - (stat.HasOwnProp("pause0") ? stat.pause0 : 0))
    if paused && pausedAt
        ms -= A_TickCount - pausedAt
    return Max(0, ms)
}

StatsMap() {
    hrs := RunTime() / 3600000
    return Map("runs", stat.runs, "wins", stat.wins, "losses", stat.losses, "rooms", stat.rooms,
        "chests", stat.chests, "dungeons", stat.dungeons, "ic", 0, "floors", 0,
        "perHour", hrs > 0.05 ? String(Round(stat.runs / hrs, 1)) : "–",
        "elapsed", stat.startTick ? FmtTime(RunTime()) : "")
}

UpdateStats() => UI("stats", StatsMap())
LootChanged() => UI("loot", LootList())          ; chest rewards since Start (the engine reads them)

UpdateMapLabel() => UI("map", curMap, IsInteger(curDepth) ? Integer(curDepth) : 0, dungeonTotal)

Notify(msg, kind := "") => UI("toast", msg, kind)

; =====================================================================
;  Start / stop / pause
; =====================================================================
StartMacro(*) {
    global running, paused, chestLoot
    if running || manualRun
        return
    if !WinExist(RBX) {
        Notify("Open Roblox first")
        return
    }
    SaveConfig()
    running := true, paused := false
    stat.runs := 0, stat.wins := 0, stat.losses := 0, stat.rooms := 0, stat.chests := 0, stat.dungeons := 0
    stat.startTick := A_TickCount, stat.pause0 := pauseTotal
    chestLoot := Map()
    UpdateStats(), LootChanged()
    SetRun("running")
    SetTimer ClockTick, 1000
    AddLog("Macro started (v" APP_VER ")")
    if FollowCamera()
        Notify("Set Roblox's Camera Mode to Classic (Esc > Settings). Follow makes the walks go the wrong way", "bad")
    if cfg["fixOnStart"]
        FixWindow()
    try WinActivate RBX
    Sleep 300
    EngineRun()
    running := false
    SetTimer ClockTick, 0
    ClockTick()
    SetRun("stopped")
    Step("stopped")
    AddLog("Macro stopped.  " stat.runs " run(s), " stat.wins " win(s)")
}

StopMacro(*) {
    global running, paused, cancelManual
    if manualRun && !running {
        cancelManual := true
        return
    }
    if !running
        return
    running := false
    SetRun("stopping")
    paused := false                     ; a paused macro notices the stop straight away
}

; Pausing just flips a switch. The macro checks it all the time (every wait) and holds still
; until it's flipped back. (AutoHotkey's own Pause froze the whole script, clock included,
; and could leave the status saying Running while it was really paused.)
TogglePause(*) {
    global paused, pauseTotal, pausedAt
    if !running
        return
    paused := !paused
    if paused {
        pausedAt := A_TickCount
        ReleaseKeys()
    } else
        pauseTotal += A_TickCount - pausedAt, pausedAt := 0
    SetRun(paused ? "paused" : "running")
    AddLog(paused ? "Paused. F4 to carry on" : "Resumed")
    UpdateStats()
}

FixWindowNow(*) {
    if !WinExist(RBX)
        return Notify("Open Roblox first")
    FixWindow()
    try WinActivate RBX
    if WindowOk()
        Notify("Roblox snapped in", "good")
    else
        Notify("Roblox didn't snap in. Press F11 in Roblox to leave fullscreen, then F1", "bad")
}

ClockTick() {
    UpdateStats()
}

DockGui() {
    if !WinExist(RBX)
        return
    try {
        MG.GetPos(&gx, &gy)
        WinGetPos &mx, &my, , , RBX
        WinMove gx + CAP_X, gy + CAP_Y, , , RBX
    }
    Stale()
    CheckRoblox()
}

TestWebhook(*) {
    SaveConfig()
    if Trim(cfg["webhook"]) = ""
        return Notify("Paste a webhook URL first")
    ok := SendWebhook("Webhook connected", "Stage results will show up here.", 0x7DD3FC)
    Notify(ok ? "Test message sent. Check your Discord channel" : "That didn't work. Check the link", ok ? "good" : "bad")
}

; =====================================================================
;  Spots and walks (Spots page)
; =====================================================================
SpotsOf(name) {
    key := PlaceKey(name)
    if !cfg["spots"].Has(key)
        cfg["spots"][key] := []
    return cfg["spots"][key]
}

SendSpots(name) {
    if name = ""
        return
    if cfg["lastSpotMap"] != name {
        cfg["lastSpotMap"] := name
        SaveConfig()
    }
    pts := []
    for p in SpotsOf(name)
        pts.Push([p.x, p.y])
    key := PlaceKey(name)
    if cfg["walks"].Has(key) {
        parts := StrSplit(cfg["walks"][key], ",")
        secs := RegExMatch(parts[parts.Length], "(\d+)$", &m) ? m[1] / 1000 : 0
        kind := "recorded", text := "Your recorded walk: " parts.Length // 2 " key presses, " Round(secs, 1) " seconds"
    } else if HasBuiltInWalk(name) {
        kind := "builtin", text := "Using the built-in walk for " name ". Record your own to replace it."
    } else
        kind := "none", text := "No walk. Units are placed from where you spawn."
    UI("spots", name, pts, kind, text)
}

SpotPick(name) {
    if running
        return Notify("Stop the macro first")
    if name = "" || name = "Unknown"
        return Notify("Pick the map first")
    if p := PickPoint() {
        SpotsOf(name).Push(p)
        SaveConfig()
        Notify("Spot " SpotsOf(name).Length " saved for " name, "good")
    }
    SendSpots(name)
}

SpotEdit(name, i, action) {
    list := SpotsOf(name)
    if !IsInteger(i) || i < 1 || i > list.Length
        return
    if action = "del"
        list.RemoveAt(i)
    else {
        j := action = "up" ? i - 1 : i + 1
        if j < 1 || j > list.Length
            return
        tmp := list[i], list[i] := list[j], list[j] := tmp
    }
    SaveConfig()
    SendSpots(name)
}

; a spot was dragged from position `from` to `to`
SpotMove(name, from, to) {
    list := SpotsOf(name)
    if IsInteger(from) && IsInteger(to) && from >= 1 && to >= 1 && from <= list.Length && to <= list.Length && from != to {
        p := list.RemoveAt(from)
        list.InsertAt(to, p)
        SaveConfig()
    }
    SendSpots(name)
}

SpotClear(name) {
    if !SpotsOf(name).Length
        return Notify("No spots on " name)
    MG.Opt("+OwnDialogs")
    if MsgBox("Remove all spots for " name "?", "Clear map", "YesNo Icon!") != "Yes"
        return
    cfg["spots"][PlaceKey(name)] := []
    SaveConfig()
    SendSpots(name)
}

RecordWalk(name) {
    global manualRun, cancelManual
    if running || manualRun
        return
    if name = "Unknown"
        return Notify("Pick the map first")
    if !WinExist(RBX)
        return Notify("Open Roblox and load into " name " first")
    manualRun := true, cancelManual := false
    keysWatched := ["w", "a", "s", "d", "Space"]
    try {
        AddLog("Recording a walk for " name)
        FocusRoblox()
        GoToSpot(name, false, true)
        ToolTip("RECORDING  -  walk to the spot with W A S D`nPress F6 when you're there   (F3 cancels)", 10, 10)
        events := [], down := Map(), t0 := A_TickCount, result := ""
        for k in keysWatched
            down[k] := false
        loop {
            if cancelManual || A_TickCount - t0 > 120000
                break
            if GetKeyState("F6", "P") {
                result := "ok"
                break
            }
            now := A_TickCount - t0
            for k in keysWatched {
                st := GetKeyState(StrLen(k) = 1 ? "vk" Format("{:02X}", Ord(StrUpper(k))) : k, "P")   ; by key code: any keyboard layout
                if st != down[k] {
                    down[k] := st
                    events.Push({k: k, d: st, t: now})
                }
            }
            Sleep 10
        }
        ToolTip()
        now := A_TickCount - t0
        for k in keysWatched
            if down[k]
                events.Push({k: k, d: false, t: now})
        if result != "ok" {
            AddLog("Walk recording cancelled")
        } else if !events.Length {
            Notify("No keys were pressed, nothing saved")
        } else {
            first := events[1].t, route := ""
            for ev in events
                route .= (route = "" ? "" : ",") ev.k (ev.d ? "+" : "-") (ev.t - first)
            cfg["walks"][PlaceKey(name)] := route
            SaveConfig()
            AddLog("Saved a walk for " PlaceKey(name))
            Notify("Walk saved for " PlaceKey(name))
        }
    } catch as err {
        ToolTip()
        AddLog("Recording stopped: " err.Message)
    }
    ReleaseKeys()
    manualRun := false
    SendSpots(name)
}

TestWalk(name) {
    global manualRun, cancelManual
    if running || manualRun
        return
    if !WinExist(RBX)
        return Notify("Open Roblox first")
    manualRun := true, cancelManual := false
    try {
        FocusRoblox()
        GoToSpot(name, true, true)
    } catch as err {
        AddLog("Test walk failed: " err.Message)
    }
    ReleaseKeys()
    manualRun := false
}

ClearWalk(name) {
    if cfg["walks"].Has(PlaceKey(name)) {
        cfg["walks"].Delete(PlaceKey(name))
        SaveConfig()
        Notify("Walk cleared for " name)
    }
    SendSpots(name)
}

PickPoint() {
    if !WinExist(RBX) {
        Notify("Open Roblox first")
        return 0
    }
    WinActivate RBX
    Sleep 250
    loop {
        MouseGetPos &mx, &my
        ToolTip "Click where the unit should go   (Esc to cancel)", mx + 20, my + 20
        if GetKeyState("Escape", "P") {
            ToolTip()
            return 0
        }
        if GetKeyState("LButton", "P") {
            KeyWait "LButton"
            ToolTip()
            if !WinActive(RBX)          ; clicked on the macro, not in the game
                return 0
            return {x: mx, y: my}
        }
        Sleep 20
    }
}

; =====================================================================
;  Background (Look page)
; =====================================================================
BgUrl() {
    if cfg["bgFile"] != "" && FileExist(A_ScriptDir "\" StrReplace(cfg["bgFile"], "/", "\"))
        return "../" cfg["bgFile"] "?v=" FileGetTime(A_ScriptDir "\" StrReplace(cfg["bgFile"], "/", "\"))
    return DEFAULT_BG
}

ChooseBackground() {
    MG.Opt("+OwnDialogs")
    f := FileSelect(1, A_MyDocuments, "Pick a background (a short looping video is smallest)", "Videos, GIFs and pictures (*.webm; *.mp4; *.gif; *.png; *.jpg; *.jpeg; *.webp)")
    if f = ""
        return
    SplitPath f, &fname, , &ext
    loop files A_ScriptDir "\Images\ui\custom.*"
        try FileDelete A_LoopFileFullPath
    try FileCopy f, A_ScriptDir "\Images\ui\custom." ext, true
    catch as err
        return Notify("Couldn't copy that file: " err.Message, "bad")
    cfg["bgFile"] := "Images/ui/custom." ext, cfg["bgName"] := fname
    SaveConfig()
    UI("bg", BgUrl(), fname)
    Notify("Background changed", "good")
}

ResetBackground() {
    cfg["bgFile"] := "", cfg["bgName"] := ""
    SaveConfig()
    UI("bg", DEFAULT_BG, "Sakura")
}

; =====================================================================
;  Import / backup (Settings page)
; =====================================================================
; reads another macro's config.ini (older version or a friend's) and asks what to bring over
ImportPick() {
    global importCfg
    if running || manualRun
        return Notify("Stop the macro first")
    MG.Opt("+OwnDialogs")
    f := FileSelect(1, A_Desktop, "Pick config.ini in the other macro's Settings folder", "Macro settings (*.ini)")
    if f = ""
        return
    if f = cfgFile
        return Notify("That's this macro's own settings file. Pick the other one", "bad")
    try sections := "`n" IniRead(f) "`n"
    catch
        return Notify("Couldn't read that file", "bad")
    has := (name) => InStr(sections, "`n" name "`n")
    theirs := ReadConfigFile(f)
    parts := []
    add := (id, label, detail, on := true) => parts.Push(Map("id", id, "label", label, "detail", detail, "on", on))
    if has("Build")
        add("build", "Build order", theirs["build"].Length " step" (theirs["build"].Length = 1 ? "" : "s")
            . (theirs["useBuild"] ? ", turned on" : ", turned off"))
    if has("Slot1") {
        on := 0
        for s in theirs["slots"]
            on += s.on
        add("units", "Units", on " of 6 slots on, " theirs["pattern"] " pattern")
    }
    if has("Route") || has("Curses") || has("DenyShrine")
        add("dungeon", "Dungeon", "Room priority, curse ranking and shrines")
    if has("Spots") || has("Walks") {
        nSpots := 0, nWalks := 0
        for name, list in theirs["spots"]
            nSpots += list.Length ? 1 : 0
        for name in theirs["walks"]
            nWalks++
        add("spots", "Spots and walks", nSpots " map" (nSpots = 1 ? "" : "s") " with spots, " nWalks " recorded walk" (nWalks = 1 ? "" : "s")
            . ". Only those maps change")
    }
    if has("General") {
        add("general", "Other settings", "Placement speed, camera, teleport and similar")
        if theirs["webhook"] != "" || theirs["psLink"] != ""
            add("links", "Discord webhook and private server link", "Off by default: these are personal", false)
    }
    if !parts.Length
        return Notify("No macro settings in that file", "bad")
    importCfg := theirs
    SplitPath f, , &dir
    UI("importAsk", dir, parts)
}

ImportDo(parts) {
    global importCfg
    if !IsObject(importCfg) || !(parts is Array)
        return
    theirs := importCfg, done := []
    copyKeys := (names) => ForEachKey(names, theirs)
    for p in parts {
        switch p {
            case "build":
                cfg["build"] := theirs["build"], copyKeys(["useBuild"]), done.Push("build order")
            case "units":
                cfg["slots"] := theirs["slots"], copyKeys(["pattern", "retries", "saveForTop", "autoAbility"]), done.Push("units")
            case "dungeon":
                for k in ["route", "curseRank", "denyShrine", "avoid"]
                    cfg[k] := theirs[k]
                copyKeys(["skipWorst", "saveChests", "buyShop", "stopAfterDefeat", "denyAllShrines", "denyUnknownShrine"])
                done.Push("dungeon choices")
            case "spots":
                for name, list in theirs["spots"]
                    if list.Length
                        cfg["spots"][name] := list
                for name, route in theirs["walks"]
                    cfg["walks"][name] := route
                copyKeys(["useSpots"]), done.Push("spots and walks")
            case "general":
                copyKeys(["placeSpeed", "zoom", "tpSpawn", "fixOnStart", "tolerance", "hookRuns"]), done.Push("other settings")
            case "links":
                copyKeys(["webhook", "psLink"]), done.Push("webhook and server link")
        }
    }
    importCfg := 0
    if !done.Length
        return
    SaveConfig()
    UI("refresh", UiState())
    list := ""
    for i, d in done
        list .= (i = 1 ? "" : i = done.Length ? " and " : ", ") d
    AddLog("Imported " list)
    Notify("Imported " list, "good")
}

ForEachKey(names, theirs) {
    for k in names
        if theirs.Has(k)
            cfg[k] := theirs[k]
}

; loads a settings file into its own map (the same reader as our own config)
ReadConfigFile(f) {
    global cfg, cfgFile
    Critical "On"
    mine := cfg, myFile := cfgFile
    cfg := DefaultConfig(), cfgFile := f
    try LoadConfig()
    theirs := cfg
    cfg := mine, cfgFile := myFile
    Critical "Off"
    return theirs
}

BackupConfig() {
    SaveConfig()
    MG.Opt("+OwnDialogs")
    f := FileSelect("S16", A_Desktop "\Chris's Dungeon settings " FormatTime(, "yyyy-MM-dd") ".ini", "Save a copy of your settings", "Settings (*.ini)")
    if f = ""
        return
    if !RegExMatch(f, "i)\.ini$")
        f .= ".ini"
    try {
        FileCopy cfgFile, f, true
        SplitPath f, &fname
        Notify("Saved " fname ". Import it here or in any copy of the macro", "good")
    } catch as err
        Notify("Couldn't save: " err.Message, "bad")
}

; =====================================================================
;  Screenshot (Settings page) and saved recaptures
; =====================================================================
SaveShot(*) {
    if !WinExist(RBX)
        return Notify("Open Roblox first")
    Snap()
    WinGetPos &wx, &wy, &ww, &wh, RBX
    file := A_ScriptDir "\Logs\screen_" FormatTime(, "yyyyMMdd_HHmmss") ".bmp"
    try {
        FindText().SavePic(file, wx, wy, wx + ww - 1, wy + wh - 1, 0)
        AddLog("Screenshot saved: Logs\" SubStr(file, InStr(file, "screen_")))
        Notify("Screenshot saved in the Logs folder")
    } catch as err {
        Notify("Couldn't save: " err.Message)
    }
}

; The download ships Chris's own map walks and spots in Lib\defaults.ini. Any map you
; haven't recorded yourself gets them; your own recordings always win, so updating the
; macro never overwrites what you set up.
LoadShippedWalks() {
    file := A_ScriptDir "\Lib\defaults.ini"
    if !FileExist(file)
        return
    try sec := IniRead(file, "Walks")
    catch
        sec := ""
    for line in StrSplit(sec, "`n", "`r")
        if (eq := InStr(line, "=")) && SubStr(line, eq + 1) != "" && !cfg["walks"].Has(SubStr(line, 1, eq - 1))
            cfg["walks"][SubStr(line, 1, eq - 1)] := SubStr(line, eq + 1)
    try sec := IniRead(file, "Spots")
    catch
        sec := ""
    for line in StrSplit(sec, "`n", "`r") {
        if !(eq := InStr(line, "=")) || cfg["spots"].Has(SubStr(line, 1, eq - 1))
            continue
        list := []
        for pair in StrSplit(SubStr(line, eq + 1), "|") {
            xy := StrSplit(pair, ",")
            if xy.Length = 2 && IsInteger(xy[1]) && IsInteger(xy[2])
                list.Push({x: Integer(xy[1]), y: Integer(xy[2])})
        }
        if list.Length
            cfg["spots"][SubStr(line, 1, eq - 1)] := list
    }
}

LoadOverrides() {
    if !FileExist(ovrFile)
        return
    try section := IniRead(ovrFile, "Patterns")
    catch
        return
    for line in StrSplit(section, "`n", "`r") {
        if !(eq := InStr(line, "="))
            continue
        name := SubStr(line, 1, eq - 1), text := SubStr(line, eq + 1)
        box := ""
        b := StrSplit(IniRead(ovrFile, "Boxes", name, ""), ",")
        if b.Length = 4 && IsInteger(b[1]) && IsInteger(b[2]) && IsInteger(b[3]) && IsInteger(b[4])
            box := [Integer(b[1]), Integer(b[2]), Integer(b[3]), Integer(b[4])]
        if !DetDefs().Has(name) || !InStr(text, "$")
            continue
        SetDetCustom(name, text, box)
    }
}

SaveOverrides() {
    try {
        try IniDelete ovrFile, "Patterns"
        try IniDelete ovrFile, "Boxes"
        for name, o in DetDefs() {
            if o.custom = ""
                continue
            IniWrite o.custom, ovrFile, "Patterns", name
            if IsObject(o.box)
                IniWrite o.box[1] "," o.box[2] "," o.box[3] "," o.box[4], ovrFile, "Boxes", name
        }
    } catch as err {
        AddLog("Couldn't save detections: " err.Message)
    }
}

IndexOf(arr, val) {
    for i, v in arr
        if v = val
            return i
    return 0
}

; =====================================================================
;  Settings file
; =====================================================================
; defaults are your settings from Ryn's macro
DefaultConfig() {
    return Map(
        "pattern", "Spiral", "useSpots", 1, "saveForTop", 0, "autoAbility", 1,
        "zoom", 1, "tpSpawn", 1, "saveChests", 1, "buyShop", 1,
        "denyAllShrines", 0, "denyUnknownShrine", 1, "stopAfterDefeat", 0,
        "placeSpeed", 1, "webhook", "", "hookRuns", 1, "psLink", "", "fixOnStart", 1, "tolerance", 2, "retries", 3, "useBuild", 0,
        "bgStrength", 3, "bgGif", "", "accent", "Crimson",
        "bgOpacity", 70, "bgBlur", 0, "glass", 60, "bgAnimate", 1, "bgFile", "", "bgName", "", "lastSpotMap", "",
        "route", ["Rare_Chest", "Chest", "Shop", "Hoard", "Shrine", "Boss"],
        "avoid", Map("Flying", 1, "Wind", 0, "Money", 1, "Health", 1, "Exploding", 0, "Shielding", 1, "Regen", 1),
        "curseRank", ["Flying", "Money", "Health", "Shielding", "Regen", "Wind", "Exploding"], "skipWorst", 5,
        "denyShrine", Map("Burst", 0, "Armor", 0, "Chaos", 0, "Vamparism", 0, "Frenzy", 0),
        ; Premium-only (look-ahead, F-panel upgrades, shop item choices): fixed here, not saved
        "dmgType", "Both", "shopUnknown", 1, "lookAhead", 0, "shopMinCoins", 0, "usePanel", 0, "shopRank", SHOP_ITEMS(), "shopOff", Map(),
        "slots", [
            {on: 1, count: 2, prio: 3, up: 0, limit: 0},
            {on: 1, count: 1, prio: 1, up: 1, limit: 0},
            {on: 1, count: 3, prio: 4, up: 0, limit: 0},
            {on: 1, count: 4, prio: 5, up: 0, limit: 0},
            {on: 1, count: 1, prio: 2, up: 0, limit: 0},
            {on: 0, count: 1, prio: 6, up: 0, limit: 0}
        ],
        "spots", Map(),
        "walks", Map(),
        "build", []
    )
}

; the most of one slot (Premium's Fool's Hunt allows 20)
MaxCount() => 6

CopySlots(list) {
    out := []
    for s in list
        out.Push({on: s.on, count: s.count, prio: s.prio, up: s.up, limit: s.limit})
    return out
}

; reads [Slot1..6] into a list (missing sections keep the values of `base`)
ReadSlots(prefix, base, most) {
    list := CopySlots(base)
    loop 6 {
        s := list[A_Index], sec := prefix A_Index
        s.on := ClampInt(IniRead(cfgFile, sec, "On", s.on), 0, 1, s.on)
        s.count := ClampInt(IniRead(cfgFile, sec, "Count", s.count), 1, most, Min(s.count, most))
        s.prio := ClampInt(IniRead(cfgFile, sec, "Priority", s.prio), 1, 6, s.prio)
        s.up := ClampInt(IniRead(cfgFile, sec, "Upgrade", s.up), 0, 1, s.up)
        s.limit := ClampInt(IniRead(cfgFile, sec, "Limit", s.limit), 0, 9, s.limit)
    }
    return list
}

; build order: S1=place,1,2,2  (kind, slot, count, upgrades: 0 none, N times, -1 max)
ReadBuild(sec, most) {
    list := []
    loop ClampInt(IniRead(cfgFile, sec, "Count", 0), 0, 100, 0) {
        f := StrSplit(IniRead(cfgFile, sec, "S" A_Index, ""), ",")
        if f.Length = 4 && (f[1] = "place" || f[1] = "upgrade") && IsInteger(f[2]) && IsInteger(f[3]) && IsInteger(f[4])
            && !(f[1] = "upgrade" && f[4] = 0)
            list.Push({kind: f[1], slot: ClampInt(f[2], 1, 6, 1), count: ClampInt(f[3], 1, most, 1), up: ClampInt(f[4], -1, 10, 0)})
    }
    return list
}

WriteSlots(ini, prefix, list) {
    for i, s in list {
        sec := prefix i
        ini.Set(sec, "On", s.on), ini.Set(sec, "Count", s.count), ini.Set(sec, "Priority", s.prio)
        ini.Set(sec, "Upgrade", s.up), ini.Set(sec, "Limit", s.limit)
    }
}

WriteBuild(ini, sec, list) {
    ini.Drop(sec)
    ini.Set(sec, "Count", list.Length)
    for i, st in list
        ini.Set(sec, "S" i, st.kind "," st.slot "," st.count "," st.up)
}

; The settings file, edited in memory and written to disk in one go. Saving used to be one
; IniWrite per setting (about 250), and each of those rewrites the whole file: every click on
; the Units / Build pages froze the window for a moment, worst in a OneDrive folder, which
; syncs every one of those writes. Sections and keys it doesn't touch are kept as they were.
class IniDoc {
    __New(path) {
        this.path := path, this.names := [], this.secs := Map()
        this.secs.CaseSense := "Off"
        txt := ""
        try txt := FileRead(path)
        cur := ""
        for line in StrSplit(txt, "`n", "`r") {
            if RegExMatch(line, "^\s*\[(.*)\]\s*$", &m)
                cur := this.Sec(m[1])
            else if IsObject(cur) && SubStr(LTrim(line), 1, 1) != ";" && (eq := InStr(line, "="))
                cur[Trim(SubStr(line, 1, eq - 1))] := SubStr(line, eq + 1)
        }
    }
    Sec(name) {
        if !this.secs.Has(name) {
            keys := Map()
            keys.CaseSense := "Off"
            this.secs[name] := keys, this.names.Push(name)
        }
        return this.secs[name]
    }
    Set(sec, key, value) => (this.Sec(sec)[key] := value)
    Drop(sec) {
        if this.secs.Has(sec)
            this.secs[sec] := Map(), this.secs[sec].CaseSense := "Off"
    }
    Save() {
        out := ""
        for name in this.names {
            keys := this.secs[name]
            if !keys.Count
                continue
            out .= "[" name "]`r`n"
            for k, v in keys
                out .= k "=" v "`r`n"
        }
        tmp := this.path ".tmp"
        f := FileOpen(tmp, "w", "UTF-16")          ; UTF-16 with BOM: IniRead reads any name (ø, é...) right
        f.Write(out)
        f.Close()
        loop 5 {                                    ; OneDrive or antivirus can hold the file for a moment
            try {
                FileMove tmp, this.path, 1
                return
            }
            Sleep 60
        }
        FileMove tmp, this.path, 1                 ; still busy: let the error say so
    }
}

ScalarKeys() => ["pattern", "useSpots", "saveForTop", "autoAbility", "zoom", "tpSpawn", "saveChests", "buyShop",
    "denyAllShrines", "denyUnknownShrine", "stopAfterDefeat", "placeSpeed", "webhook", "hookRuns", "psLink", "fixOnStart", "tolerance", "skipWorst", "retries", "useBuild",
    "bgStrength", "bgGif", "accent", "bgOpacity", "bgBlur", "glass", "bgAnimate", "bgFile", "bgName", "lastSpotMap"]

; Fool's Hunt cards (Premium): only shown, locked, on the Dungeon page
FOOL_CARDS() => ["shield", "regen", "health", "speed", "yen", "range", "cooldown", "attack", "explosive", "resistant", "spellproof", "plated", "boss"]

LoadConfig() {
    if !FileExist(cfgFile)
        return
    for k in ScalarKeys() {
        v := IniRead(cfgFile, "General", k, "~missing~")
        if v == "~missing~"
            continue
        if cfg[k] is Integer
            cfg[k] := IsInteger(v) ? Integer(v) : cfg[k]
        else
            cfg[k] := v
    }
    loop 6 {
        v := IniRead(cfgFile, "Route", "Room" A_Index, "")
        if IndexOf(ROOM_KEYS, v)
            cfg["route"][A_Index] := v
    }
    for name in ["Flying", "Wind", "Money", "Health", "Exploding", "Shielding", "Regen"]
        cfg["avoid"][name] := IniRead(cfgFile, "Avoid", name, cfg["avoid"][name]) = 1 ? 1 : 0
    for name in ["Burst", "Armor", "Chaos", "Vamparism", "Frenzy"]
        cfg["denyShrine"][name] := IniRead(cfgFile, "DenyShrine", name, cfg["denyShrine"][name]) = 1 ? 1 : 0
    if IndexOf(CURSES, IniRead(cfgFile, "Curses", "Rank1", "")) {
        loop CURSES.Length {
            v := IniRead(cfgFile, "Curses", "Rank" A_Index, "")
            if IndexOf(CURSES, v)
                cfg["curseRank"][A_Index] := v
        }
    } else {
        ; first run with ranking: the curses you had ticked go to the top (worst)
        rank := [], skipped := 0
        for name in CURSES
            if cfg["avoid"][name]
                rank.Push(name), skipped++
        for name in CURSES
            if !cfg["avoid"][name]
                rank.Push(name)
        cfg["curseRank"] := rank, cfg["skipWorst"] := skipped
    }
    cfg["skipWorst"] := ClampInt(cfg["skipWorst"], 0, 7, 5)
    cfg["slots"] := ReadSlots("Slot", cfg["slots"], 6)
    cfg["placeSpeed"] := ClampInt(cfg["placeSpeed"], 1, SPEEDS.Length, 1)
    cfg["tolerance"] := ClampInt(cfg["tolerance"], 1, 3, 2)
    cfg["retries"] := ClampInt(cfg["retries"], 1, RETRIES.Length, 3)
    cfg["build"] := ReadBuild("Build", 6)
    try walkSec := IniRead(cfgFile, "Walks")
    catch
        walkSec := ""
    for line in StrSplit(walkSec, "`n", "`r")
        if (eq := InStr(line, "=")) && SubStr(line, eq + 1) != ""
            cfg["walks"][SubStr(line, 1, eq - 1)] := SubStr(line, eq + 1)
    if !IndexOf(PATTERNS, cfg["pattern"])
        cfg["pattern"] := "Spiral"
    try section := IniRead(cfgFile, "Spots")
    catch
        section := ""
    for line in StrSplit(section, "`n", "`r") {
        if !(eq := InStr(line, "="))
            continue
        name := SubStr(line, 1, eq - 1), list := []
        for pair in StrSplit(SubStr(line, eq + 1), "|") {
            xy := StrSplit(pair, ",")
            if xy.Length = 2 && IsInteger(xy[1]) && IsInteger(xy[2])
                list.Push({x: Integer(xy[1]), y: Integer(xy[2])})
        }
        if list.Length
            cfg["spots"][name] := list
    }
}

; quick clicks on the Units / Build pages (1 to 17 units = 16 clicks) saved 16 times: now once,
; a moment after the last click (and right away when the macro closes)
SaveSoon() {
    global savePending := true
    SetTimer SaveNow, -250
}
SaveNow() {
    global savePending := false
    SaveConfig()
}

SaveConfig(*) {
    try {
        ini := IniDoc(cfgFile)
        for k in ScalarKeys()
            ini.Set("General", k, cfg[k])
        for i, v in cfg["route"]
            ini.Set("Route", "Room" i, v)
        for name, v in cfg["avoid"]
            ini.Set("Avoid", name, v)
        for name, v in cfg["denyShrine"]
            ini.Set("DenyShrine", name, v)
        for i, name in cfg["curseRank"]
            ini.Set("Curses", "Rank" i, name)
        WriteSlots(ini, "Slot", cfg["slots"])
        ini.Drop("Spots")
        for name, list in cfg["spots"] {
            if !list.Length
                continue
            str := ""
            for p in list
                str .= (A_Index > 1 ? "|" : "") p.x "," p.y
            ini.Set("Spots", name, str)
        }
        WriteBuild(ini, "Build", cfg["build"])
        ini.Drop("Walks")
        for name, route in cfg["walks"]
            ini.Set("Walks", name, route)
        ini.Save()
    } catch as err {
        AddLog("Couldn't save settings: " err.Message)
    }
}

ClampInt(v, lo, hi, dflt) => IsInteger(v) ? Min(hi, Max(lo, Integer(v))) : dflt

; libraries go last so nothing in them can cut the startup code short
#Include %A_ScriptDir%\Lib\FindText.ahk
; OCR.ahk: Windows' built-in text reader (by Descolada, MIT licence)
#Include %A_ScriptDir%\Lib\OCR.ahk
; WebView2 + JSON + Promise + ComVar by thqby (MIT licence, see Lib\ahk2_lib-LICENSE.txt)
#Include %A_ScriptDir%\Lib\JSON.ahk
#Include %A_ScriptDir%\Lib\WebView2\WebView2.ahk
