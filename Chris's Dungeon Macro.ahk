#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir
SendMode "Event"

; =====================================================================
;  Chris's Dungeon Macro Classic  -  Anime Adventures dungeon auto-farm
;  F1 snap Roblox into the window  |  F2 start  |  F3 stop  |  F4 pause
;
;  Files:  Lib\Engine.ahk    the dungeon logic
;          Lib\Patterns.ahk  screen-detection patterns (from Ryn's macro)
;          Lib\FindText.ahk  pattern finder by FeiYue
;          Settings\config.ini, Logs\log.txt
; =====================================================================

#Include %A_ScriptDir%\Lib\Patterns.ahk
#Include %A_ScriptDir%\Lib\Engine.ahk

global APP_VER := "3.0 Classic"
global cfgFile := A_ScriptDir "\Settings\config.ini"
global ovrFile := A_ScriptDir "\Settings\patterns.ini"   ; recaptured detections
global logFile := A_ScriptDir "\Logs\log.txt"
DirCreate A_ScriptDir "\Settings"
DirCreate A_ScriptDir "\Logs"

global CL := {
    bg: "0E0D17", card: "181627", input: "211F33", line: "2C2942",
    text: "ECEBF5", muted: "8E8BA8", ok: "4ADE80", warn: "FBBF24",
    accent: "8B5CF6", accentHi: "A78BFA", accent2: "22D3EE",
    green: "16A34A", greenHi: "22C55E",
    red: "DC2626", redHi: "EF4444",
    btn: "26233A", btnHi: "34304D",
    hole: "FF00FE"          ; see-through colour where Roblox shows
}
; accent colours you can pick on the Look tab: main, highlight, gradient partner
global ACCENT_ORDER := ["Purple", "Cyan", "Pink", "Emerald", "Amber", "Crimson"]
global ACCENTS := Map(
    "Purple", ["8B5CF6", "A78BFA", "22D3EE"],
    "Cyan", ["0891B2", "22D3EE", "8B5CF6"],
    "Pink", ["DB2777", "F472B6", "A78BFA"],
    "Emerald", ["059669", "34D399", "22D3EE"],
    "Amber", ["D97706", "FBBF24", "F472B6"],
    "Crimson", ["E11D48", "FB7185", "F59E0B"])
global BG_NAMES := ["Off", "Faint", "Soft", "Medium", "Strong"]
; the animated background fills the right side, under the tabs too
global BG_X := 803, BG_Y := 33, BG_W := 619, BG_H := 605
global bgFrames := [], bgDelays := [], bgIdx := 0

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

global cfg := DefaultConfig()
LoadConfig()
LoadShippedWalks()
LoadOverrides()
ApplyAccent()
global curPanel := ""

global hover := Map(), panels := Map(), cur := "", lastHover := ""
; Roblox sits in the left part of the window, the controls are on the right.
; Panel controls are written for a 0-based layout and shifted by OX / OY in A().
global GUI_W := 1423, GUI_H := 640, OX := 618, OY := 64

; =====================================================================
;  GUI
; =====================================================================
; +E0x02000000 (composited) paints every control in one go, so the moving background never flickers
global MG := Gui("+AlwaysOnTop -Caption -DPIScale +E0x02000000", "Chris's Dungeon Macro Classic")
MG.BackColor := CL.bg
MG.MarginX := 0, MG.MarginY := 0
MG.SetFont("s10 norm c" CL.text, "Segoe UI")
MG.OnEvent("Close", (*) => (SaveConfig(), ExitApp()))

; ---------- title bar ----------
; (a backdrop picture is pushed under everything at the end, see PushBottom)
global titleBg := GradPic(0, 0, GUI_W, 31, Blend(CL.card, CL.accent, 0.38), CL.card)
MG.SetFont("s12 bold c" CL.accentHi)
MG.Add("Text", "x12 y5 w40 h22 BackgroundTrans", "AA")
MG.SetFont("s11 bold c" CL.text)
MG.Add("Text", "x46 y5 w400 h22 BackgroundTrans", "Dungeon Macro   v" APP_VER)
MG.SetFont("s9 norm c" CL.muted)
MG.Add("Text", "x" (GUI_W - 470) " y8 w380 h20 Right BackgroundTrans", "F1 snap Roblox   ·   F2 start   ·   F3 stop   ·   F4 pause")
TitleBtn(GUI_W - 78, "—", (*) => MG.Minimize(), CL.btnHi)
TitleBtn(GUI_W - 39, "✕", (*) => (SaveConfig(), ExitApp()), CL.red)
GradPic(0, 31, GUI_W, 2, CL.accent, CL.accent2)

; ---------- animated background (filled in by LoadBackground) ----------
global bgPic := MG.Add("Picture", "x" BG_X " y" BG_Y " w" BG_W " h" BG_H " 0xE")

; ---------- Roblox frame (see-through) ----------
MG.SetFont("s10 norm c" CL.muted)
global holeHint := MG.Add("Text", "x3 y33 w797 h597 +0x200 Center Background" CL.bg, "Open Roblox and press F1 to snap it in here")
MG.Add("Text", "x3 y33 w797 h597 Background" CL.hole)
MG.Add("Text", "x802 y31 w1 h" (GUI_H - 31) " Background" CL.line)
MG.Add("Text", "x0 y" (GUI_H - 1) " w" GUI_W " h1 Background" CL.line)
MG.Add("Text", "x0 y31 w1 h" (GUI_H - 31) " Background" CL.line)
MG.Add("Text", "x" (GUI_W - 1) " y31 w1 h" (GUI_H - 31) " Background" CL.line)

; ---------- tabs ----------
global navCtl := Map(), navBar := Map()
MG.SetFont("s10 norm c" CL.muted)
for i, n in ["Dashboard", "Units", "Build", "Spots", "Dungeon", "Settings", "Look"] {
    x := 811 + (i - 1) * 87
    nav := MG.Add("Text", "x" x " y38 w85 h34 +0x200 Center BackgroundTrans", n)
    navBar[n] := GradPic(x, 72, 85, 3, CL.accent, CL.accent2)
    nav.OnEvent("Click", ShowPanel.Bind(n))
    navCtl[n] := nav
    hover[nav.Hwnd] := {ctrl: nav, norm: "Trans", hi: CL.card}
}
MG.Add("Text", "x803 y75 w" (GUI_W - 804) " h1 Background" CL.line)
MG.SetFont("s10 norm c" CL.text)

; ---------- Dashboard ----------
StartPanel("Dashboard")
Heading("Dashboard", "Start in the lobby, on the dungeon map or mid-stage. It works out where it is.")
global statusV := Card(205, "STATUS", "Idle", CL.accent)
statusV.SetFont("c" CL.muted)
global runsV := Card(351, "RUNS", "0", CL.accent2)
global rateV := Card(497, "WIN RATE", "-", CL.ok)
global timeV := Card(643, "ELAPSED", "0m 00s", CL.warn)
MG.SetFont("s9 norm c" CL.muted)
global statsV := A("Text", "x205 y180 w570", "")
MG.SetFont("s10 norm c" CL.muted)
global mapV := A("Text", "x205 y202 w570", "Map:  -")
global stepV := A("Text", "x205 y224 w570", "Step:  waiting to start")
MG.SetFont("s9 norm c" CL.muted, "Consolas")
global logV := A("Text", "x205 y252 w570 h196 Background" CL.card, "")
MG.SetFont("s10 norm c" CL.text, "Segoe UI")
Btn("x205 y462 w280 h48", "▶    START    (F2)", StartMacro, CL.green, CL.greenHi)
Btn("x495 y462 w135 h48", "❚❚   PAUSE", TogglePause)
Btn("x640 y462 w135 h48", "■   STOP", StopMacro, CL.red, CL.redHi)

; ---------- Units ----------
StartPanel("Units")
Heading("Units", "Your 6 hotbar slots. Units are placed by trying spots until they land, so any map works.")
MG.SetFont("s8 bold c" CL.muted)
A("Text", "x205 y92 w120", "SLOT")
A("Text", "x335 y92 w90", "HOW MANY")
A("Text", "x440 y92 w110", "UPGRADE")
A("Text", "x560 y92 w90", "PRIORITY")
A("Text", "x670 y92 w105", "UPGRADE UNTIL")
MG.SetFont("s10 norm c" CL.text)
nums := ["1", "2", "3", "4", "5", "6"]
limits := ["Max", "Level 1", "Level 2", "Level 3", "Level 4", "Level 5", "Level 6", "Level 7", "Level 8", "Level 9"]
loop 6 {
    y := 114 + (A_Index - 1) * 42
    TogSlot("x205 y" y " w120", "Slot " A_Index, A_Index, "on")
    SlotDDL("x335 y" (y + 2) " w80", nums, A_Index, "count", 0)
    TogSlot("x440 y" y " w110", "Upgrade", A_Index, "up")
    SlotDDL("x560 y" (y + 2) " w80", nums, A_Index, "prio", 0)
    SlotDDL("x670 y" (y + 2) " w105", limits, A_Index, "limit", 1)
}
Divider(372)
MG.SetFont("s10 bold c" CL.text)
A("Text", "x205 y388 w200 h26 +0x200", "Placement pattern")
MG.SetFont("s10 norm c" CL.text)
global patDDL := DDL("x420 y388 w150", PATTERNS, IndexOf(PATTERNS, cfg["pattern"]) || 1)
patDDL.OnEvent("Change", (c, *) => (cfg["pattern"] := c.Text, SaveConfig()))
MG.SetFont("s9 norm c" CL.muted)
A("Text", "x585 y388 w190 h26 +0x200", "where it tries first")
MG.SetFont("s10 norm c" CL.text)
TogCfg("x205 y424 w570", "Save yen for the top priority (don't upgrade others meanwhile)", "saveForTop")
TogCfg("x205 y456 w570", "Turn on unit auto-abilities", "autoAbility")
MG.SetFont("s10 bold c" CL.text)
A("Text", "x205 y490 w200 h26 +0x200", "Placement retries")
MG.SetFont("s10 norm c" CL.text)
global retryDDL := DDL("x420 y492 w150", RETRIES, cfg["retries"])
retryDDL.OnEvent("Change", (c, *) => (cfg["retries"] := c.Value, SaveConfig()))
MG.SetFont("s9 norm c" CL.muted)
A("Text", "x585 y490 w190 h26 +0x200", "how long it keeps trying")
A("Text", "x205 y526 w570 h34", "Failed spots are skipped and it moves on to new ones, all over the map if needed. Priority 1 is upgraded first.")
MG.SetFont("s10 norm c" CL.text)

; ---------- Build ----------
StartPanel("Build")
Heading("Build order", "Your own plan, run step by step at the start of every stage. The Units tab fills in the rest.")
global useBuildTog := TogCfg("x205 y86 w570", "Use the build order", "useBuild")
MG.SetFont("s8 bold c" CL.muted)
A("Text", "x205 y122 w50 h26 +0x200 Background" CL.line, "    #")
A("Text", "x255 y122 w520 h26 +0x200 Background" CL.line, "  STEP")
MG.SetFont("s10 norm c" CL.text)
global buildLV := A("ListView", "x205 y148 w570 h190 -Hdr -Multi -E0x200 +LV0x10000 Background" CL.card " c" CL.text, ["#", "Step"])
buildLV.ModifyCol(1, 50), buildLV.ModifyCol(2, 510)
buildLV.OnEvent("ItemSelect", BuildSelect)
try DllCall("uxtheme\SetWindowTheme", "Ptr", buildLV.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
global bKindDDL := DDL("x205 y352 w105", ["Place", "Upgrade"], 1)
bKindDDL.OnEvent("Change", (*) => BuildKindChanged())
A("Text", "x318 y350 w36 h28 +0x200", "slot")
global bSlotDDL := DDL("x354 y352 w55", ["1", "2", "3", "4", "5", "6"], 1)
global bTimesV := A("Text", "x417 y350 w20 h28 +0x200 Center", "x")
global bCountDDL := DDL("x439 y352 w55", ["1", "2", "3", "4", "5", "6"], 1)
global bUpDDL := DDL("x504 y352 w271", UP_NAMES, 1)
Btn("x205 y392 w120 h34", "Add step", BuildAdd, CL.accent, CL.accentHi)
Btn("x335 y392 w100 h34", "Update", BuildUpdate)
Btn("x445 y392 w100 h34", "Remove", BuildRemove)
Btn("x555 y392 w105 h34", "Move up", () => BuildMove(-1))
Btn("x670 y392 w105 h34", "Move down", () => BuildMove(1))
MG.SetFont("s9 norm c" CL.muted)
A("Text", "x205 y438 w570 h110", "Example:  1. Place slot 1 x2, upgrade each 2 times   2. Place slot 6 x1, upgrade each to max   3. Upgrade slot 1 to max.`n`nA step only moves on once it's done, waiting for yen if it needs to (an upgrade stuck for 90s is skipped). After the last step it places whatever the Units tab still asks for, and keeps upgrading by priority. Upgrade limits on the Units tab still apply.")
MG.SetFont("s10 norm c" CL.text)

; ---------- Spots ----------
StartPanel("Spots")
Heading("Spots", "Optional. Pick spots for a map and they're tried first. The pattern fills in the rest.")
A("Text", "x205 y88 w40 h28 +0x200", "Map")
global spotMapDDL := DDL("x245 y90 w220", MapNames(), 1)
spotMapDDL.OnEvent("Change", (*) => RefreshSpots())
TogCfg("x490 y88 w285", "Use my spots", "useSpots")
MG.SetFont("s8 bold c" CL.muted)
A("Text", "x205 y128 w60 h26 +0x200 Background" CL.line, "    #")
A("Text", "x265 y128 w255 h26 +0x200 Background" CL.line, "  X")
A("Text", "x520 y128 w255 h26 +0x200 Background" CL.line, "  Y")
MG.SetFont("s10 norm c" CL.text)
global spotLV := A("ListView", "x205 y154 w570 h140 -Hdr -Multi -E0x200 +LV0x10000 Background" CL.card " c" CL.text, ["#", "X", "Y"])
spotLV.ModifyCol(1, 60), spotLV.ModifyCol(2, 255), spotLV.ModifyCol(3, 250)
try DllCall("uxtheme\SetWindowTheme", "Ptr", spotLV.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
Btn("x205 y304 w130 h34", "Pick spot", SpotPick, CL.accent, CL.accentHi)
Btn("x345 y304 w100 h34", "Remove", SpotRemove)
Btn("x455 y304 w100 h34", "Move up", () => SpotMove(-1))
Btn("x565 y304 w100 h34", "Move down", () => SpotMove(1))
Btn("x675 y304 w100 h34", "Clear map", SpotClear)
MG.SetFont("s9 norm c" CL.muted)
A("Text", "x205 y344 w570 h36", "Press Pick spot and click on open ground in Roblox. Spots are used in order (slot 1's units first), then the pattern fills in the rest.")
MG.SetFont("s10 norm c" CL.text)
Divider(386)
SubHead(205, 396, "Walk after teleporting", "Where your character walks before placing on this map")
MG.SetFont("s10 norm c" CL.muted)
global walkV := A("Text", "x205 y442 w570", "")
MG.SetFont("s10 norm c" CL.text)
Btn("x205 y470 w170 h34", "Record walk", RecordWalk, CL.accent, CL.accentHi)
Btn("x385 y470 w130 h34", "Test walk", TestWalk)
Btn("x525 y470 w130 h34", "Clear walk", ClearWalk)
MG.SetFont("s9 norm c" CL.muted)
A("Text", "x205 y514 w570 h36", "Record: it teleports you to spawn, you walk there with W A S D (don't turn the camera), then press F6. F3 cancels.")
MG.SetFont("s10 norm c" CL.text)

; ---------- Dungeon ----------
StartPanel("Dungeon")
Heading("Dungeon", "Which rooms to go for, which curses to dodge and what to do with shrines.")
SubHead(205, 88, "Room priority", "Top is the first choice")
loop 6 {
    y := 132 + (A_Index - 1) * 34
    MG.SetFont("s10 bold c" CL.muted)
    A("Text", "x205 y" y " w24 h26 +0x200", A_Index ".")
    MG.SetFont("s10 norm c" CL.text)
    RouteDDL("x232 y" y " w200", A_Index)
}
TogCfg("x205 y348 w270", "Save chests for after the boss", "saveChests")
TogCfg("x205 y380 w270", "Buy everything in shops", "buyShop")
TogCfg("x205 y412 w270", "Stop after a defeat", "stopAfterDefeat")

SubHead(500, 88, "Curses, worst first", "If every room is cursed, it takes the mildest")
loop CURSES.Length {
    y := 126 + (A_Index - 1) * 29
    MG.SetFont("s10 bold c" CL.muted)
    A("Text", "x500 y" y " w24 h26 +0x200", A_Index ".")
    MG.SetFont("s10 norm c" CL.text)
    CurseDDL("x526 y" y " w150", A_Index)
}
A("Text", "x500 y334 w110 h26 +0x200", "Skip the worst")
global skipDDL := DDL("x610 y336 w66", ["0", "1", "2", "3", "4", "5", "6", "7"], cfg["skipWorst"] + 1)
skipDDL.OnEvent("Change", (c, *) => (cfg["skipWorst"] := c.Value - 1, SaveConfig()))
MG.SetFont("s9 norm c" CL.muted)
A("Text", "x684 y334 w91 h26 +0x200", "curses")
MG.SetFont("s10 norm c" CL.text)

SubHead(500, 372, "Deny shrines", "Ticked shrines are turned down")
for i, name in ["Burst", "Armor", "Chaos", "Vamparism", "Frenzy"]
    TogMap("x" (i <= 3 ? 500 : 640) " y" (414 + Mod(i - 1, 3) * 30) " w135", name, cfg["denyShrine"], name)
TogCfg("x640 y474 w135", "Unknown", "denyUnknownShrine")
TogCfg("x500 y506 w275", "Deny every shrine", "denyAllShrines")

; ---------- Settings ----------
StartPanel("Settings")
Heading("Settings", "Everything saves by itself.")
SubHead(205, 88, "Placement speed", "How long to wait for a unit to land before trying the next spot")
global speedDDL := DDL("x575 y96 w200", SPEEDS, cfg["placeSpeed"])
speedDDL.OnEvent("Change", (c, *) => (cfg["placeSpeed"] := c.Value, SaveConfig()))
Divider(140)
TogCfg("x205 y152 w570", "Zoom the camera out at the start of each stage", "zoom")
TogCfg("x205 y184 w570", "Teleport to spawn at the start of each stage", "tpSpawn")
Divider(224)
SubHead(205, 236, "Discord webhook", "Optional. Get pinged after runs, clears and disconnects")
global hookE := A("Edit", "x205 y284 w450 h28 -E0x200 Background" CL.input, cfg["webhook"])
hookE.OnEvent("Change", (c, *) => cfg["webhook"] := c.Value)
hookE.OnEvent("LoseFocus", (*) => SaveConfig())
Btn("x665 y284 w110 h28", "Test", TestWebhook, CL.accent, CL.accentHi)
TogCfg("x205 y318 w570", "Message after every run (not just clears and disconnects)", "hookRuns")
Divider(358)
SubHead(205, 370, "Private server link", "Used to reconnect. Leave it empty to join a public server")
global psE := A("Edit", "x205 y418 w570 h28 -E0x200 Background" CL.input, cfg["psLink"])
psE.OnEvent("Change", (c, *) => cfg["psLink"] := c.Value)
psE.OnEvent("LoseFocus", (*) => SaveConfig())
TogCfg("x205 y454 w570", "Snap Roblox into the frame when the macro starts (F1 does it any time)", "fixOnStart")
Btn("x205 y494 w180 h36", "Open macro folder", (*) => Run(A_ScriptDir))
Btn("x395 y494 w180 h36", "Open log", (*) => (FileExist(logFile) ? Run(logFile) : Notify("No log yet")))
Btn("x585 y494 w190 h36", "Save screenshot", SaveShot)
Btn("x205 y538 w280 h32", "Import settings…", ImportPick)
Btn("x495 y538 w280 h32", "Save a backup…", BackupConfig)

; ---------- Look ----------
StartPanel("Look")
Heading("Look", "Make it yours. Background changes show right away.")
SubHead(205, 88, "Animated background", "A GIF that plays faintly behind the controls")
MG.SetFont("s10 bold c" CL.text)
A("Text", "x205 y136 w200 h26 +0x200", "Strength")
MG.SetFont("s10 norm c" CL.text)
global bgDDL := DDL("x420 y138 w150", BG_NAMES, ClampInt(cfg["bgStrength"], 1, 5, 3))
bgDDL.OnEvent("Change", (c, *) => (cfg["bgStrength"] := c.Value, SaveConfig(), LoadBackground()))
MG.SetFont("s10 bold c" CL.text)
A("Text", "x205 y172 w200 h26 +0x200", "Picture")
MG.SetFont("s10 norm c" CL.muted)
global gifV := A("Text", "x420 y172 w355 h26 +0x200", "")
MG.SetFont("s10 norm c" CL.text)
Btn("x205 y212 w180 h34", "Choose GIF...", ChooseGif, CL.accent, CL.accentHi)
Btn("x395 y212 w180 h34", "Use the built-in one", DefaultGif)
MG.SetFont("s9 norm c" CL.muted)
A("Text", "x205 y256 w570 h50", "Any .gif works (a .png or .jpg gives a still picture). It's cropped to fill this side. Long GIFs play their first few seconds on a loop to save memory. Set it to Off if your PC struggles.")
Divider(316)
SubHead(205, 328, "Accent colour", "Buttons, tabs and highlights. The window restarts to apply it")
for i, name in ACCENT_ORDER
    Swatch(205 + (i - 1) * 96, 376, name)
MG.SetFont("s10 norm c" CL.text)

cur := ""
RefreshBuild()
BuildKindChanged()
RefreshSpots()
UpdateStats()
ShowPanel("Dashboard")
; reopen the Look tab after an accent change restarted the window
if (reopenTab := IniRead(cfgFile, "General", "reopenTab", "")) != "" {
    try IniDelete cfgFile, "General", "reopenTab"
    if panels.Has(reopenTab)
        ShowPanel(reopenTab)
}
; backdrops go under every other control (composited painting draws bottom to top)
PushBottom(titleBg)
PushBottom(bgPic)
MG.Show("w" GUI_W " h" GUI_H)
WinSetTransColor CL.hole, MG
SetTimer LoadBackground, -150
OnExit((*) => ReleaseKeys())
OnMessage(0x0201, GuiDrag)          ; drag the window by any empty spot
OnMessage(0x0232, GuiMoved)         ; Roblox follows when you let go
SetTimer HoverCheck, 50
SetTimer UpdateHoleHint, 2000
if WinExist(RBX)
    FixWindow()
UpdateHoleHint()
AddLog("Ready. Press F2 to start.")
AddLog("Game settings needed: 'Show Upgrade UI on left' ON, and the upgrade menu must pop up when you place a unit (setting 'Disable Auto-Open Upgrade UI').")
if !WinExist(RBX)
    AddLog("Open Roblox, then press F1 to snap it in.")
if A_ScreenDPI != 96
    AddLog("Windows display scale isn't 100%. Detection may miss.")

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
;  Start / stop / pause
; =====================================================================
StartMacro(*) {
    global running, paused
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
    UpdateStats()
    SetStatus("Running", CL.greenHi)
    SetTimer ClockTick, 1000
    AddLog("Macro started")
    if cfg["fixOnStart"]
        FixWindow()
    try WinActivate RBX
    Sleep 300
    EngineRun()
    running := false
    SetTimer ClockTick, 0
    ClockTick()
    SetStatus("Stopped", CL.redHi)
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
    SetStatus("Stopping", CL.redHi)
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
    SetStatus(paused ? "Paused" : "Running", paused ? CL.warn : CL.greenHi)
    AddLog(paused ? "Paused. F4 to carry on" : "Resumed")
    ClockTick()
}

FixWindowNow(*) {
    if !WinExist(RBX)
        return Notify("Open Roblox first")
    FixWindow()
    try WinActivate RBX
    Notify(WindowOk() ? "Roblox snapped in" : "Couldn't resize Roblox. Turn off fullscreen and try again")
}

; =====================================================================
;  Status helpers (the engine calls these)
; =====================================================================
AddLog(msg) {
    static lines := []
    lines.Push(FormatTime(, "HH:mm:ss") "   " msg)
    if lines.Length > 11
        lines.RemoveAt(1)
    out := "`n"
    for l in lines
        out .= "  " l "`n"
    try logV.Value := out
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " msg "`n", logFile, "UTF-8")
}

Step(text) {
    static last := ""
    if text = last
        return
    last := text
    try stepV.Value := "Step:  " text
}

SetStatus(text, col) {
    try {
        statusV.Value := "  " text
        statusV.SetFont("c" col)
    }
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

UpdateStats() {
    total := stat.wins + stat.losses
    hrs := RunTime() / 3600000
    perHour := hrs > 0.05 ? Round(stat.runs / hrs, 1) : "-"
    try {
        runsV.Value := "  " stat.runs
        rateV.Value := "  " (total ? Round(stat.wins / total * 100) "%" : "-")
        statsV.Value := "Wins " stat.wins "   ·   Losses " stat.losses "   ·   Rooms " stat.rooms
            . "   ·   Chests " stat.chests "   ·   Cleared " stat.dungeons "   ·   " perHour " runs/hour"
    }
}

UpdateMapLabel() {
    try mapV.Value := "Map:  " curMap (curDepth != "" ? "      Depth " curDepth : "")
}

ClockTick() {
    if stat.startTick
        try timeV.Value := "  " FmtTime(RunTime())
    UpdateStats()
}

; puts Roblox in the frame on the left (its game area lines up with the see-through box)
DockGui() {
    if !WinExist(RBX)
        return
    try {
        MG.GetPos(&gx, &gy)
        WinMove gx + CAP_X, gy + CAP_Y, , , RBX
    }
    Stale()
    UpdateHoleHint()
}

GuiDrag(wParam, lParam, msg, hwnd) {
    if hwnd = MG.Hwnd || hwnd = bgPic.Hwnd || hwnd = titleBg.Hwnd
        PostMessage 0xA1, 2, , , "ahk_id " MG.Hwnd
}

GuiMoved(wParam, lParam, msg, hwnd) {
    if hwnd = MG.Hwnd && WinExist(RBX)
        DockGui()
}

; covers the frame with a message while Roblox isn't open
UpdateHoleHint() {
    try holeHint.Visible := !WinExist(RBX)
}

TestWebhook(*) {
    cfg["webhook"] := hookE.Value
    SaveConfig()
    if Trim(cfg["webhook"]) = ""
        return Notify("Paste a webhook URL first")
    ok := SendWebhook("Test message", "If you can read this, the webhook works.", 0x7C4DFF)
    Notify(ok ? "Webhook works" : "That didn't work. Check the URL")
}

Notify(msg) {
    ToolTip msg
    SetTimer () => ToolTip(), -2000
}

; =====================================================================
;  Spots
; =====================================================================
SpotList() {
    name := spotMapDDL.Text
    if !cfg["spots"].Has(name)
        cfg["spots"][name] := []
    return cfg["spots"][name]
}

RefreshSpots(sel := 0) {
    spotLV.Delete()
    for i, p in SpotList()
        spotLV.Add(i = sel ? "Select Focus" : "", "  " i, "  " p.x, "  " p.y)
    RefreshWalkText()
}

; =====================================================================
;  Build order (Build tab)
; =====================================================================
RefreshBuild(sel := 0) {
    buildLV.Delete()
    for i, st in cfg["build"]
        buildLV.Add(i = sel ? "Select Focus" : "", "  " i, "  " StepText(st))
}

BuildKindChanged() {
    bCountDDL.Enabled := bTimesV.Enabled := bKindDDL.Value = 1    ; "how many" only matters for Place
}

BuildFromEditor() {
    kind := bKindDDL.Value = 1 ? "place" : "upgrade"
    up := UP_VALUES[bUpDDL.Value]
    if kind = "upgrade" && up = 0 {
        Notify("Pick how many times to upgrade")
        return 0
    }
    return {kind: kind, slot: bSlotDDL.Value, count: bCountDDL.Value, up: up}
}

BuildAdd(*) {
    if !(st := BuildFromEditor())
        return
    cfg["build"].Push(st)
    if !cfg["useBuild"] {                   ; a build you just made is meant to be used
        cfg["useBuild"] := 1
        try useBuildTog.Value := "☑   Use the build order", useBuildTog.SetFont("c" CL.text)
        Notify("Build order switched on")
    }
    RefreshBuild(cfg["build"].Length)
    SaveConfig()
}

BuildUpdate(*) {
    if !(r := buildLV.GetNext())
        return Notify("Select a step first")
    if !(st := BuildFromEditor())
        return
    cfg["build"][r] := st
    RefreshBuild(r)
    SaveConfig()
}

BuildRemove(*) {
    if !(r := buildLV.GetNext())
        return Notify("Select a step first")
    cfg["build"].RemoveAt(r)
    RefreshBuild(Min(r, cfg["build"].Length))
    SaveConfig()
}

BuildMove(d) {
    list := cfg["build"]
    r := buildLV.GetNext(), dest := r + d
    if !r || dest < 1 || dest > list.Length
        return
    tmp := list[r], list[r] := list[dest], list[dest] := tmp
    RefreshBuild(dest)
    SaveConfig()
}

BuildSelect(ctrl, item, selected) {
    if !selected || item > cfg["build"].Length
        return
    st := cfg["build"][item]
    bKindDDL.Choose(st.kind = "place" ? 1 : 2)
    bSlotDDL.Choose(st.slot)
    bCountDDL.Choose(Max(1, Min(6, st.count)))
    bUpDDL.Choose(IndexOf(UP_VALUES, st.up) || 1)
    BuildKindChanged()
}

; =====================================================================
;  Walks (Spots tab)
; =====================================================================
RefreshWalkText() {
    name := spotMapDDL.Text
    if cfg["walks"].Has(name) {
        parts := StrSplit(cfg["walks"][name], ",")
        last := RegExMatch(parts[parts.Length], "(\d+)$", &m) ? m[1] / 1000 : 0
        walkV.Value := "Recorded walk: " parts.Length // 2 " key presses, " Round(last, 1) "s"
        walkV.SetFont("c" CL.ok)
    } else if HasBuiltInWalk(name) {
        walkV.Value := "Using the built-in walk for " name ". Record your own to replace it."
        walkV.SetFont("c" CL.warn)
    } else {
        walkV.Value := "No walk: units are placed from where you spawn"
        walkV.SetFont("c" CL.muted)
    }
}

RecordWalk(*) {
    global manualRun, cancelManual
    if running || manualRun
        return
    name := spotMapDDL.Text
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
                st := GetKeyState(k, "P")
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
            cfg["walks"][name] := route
            SaveConfig()
            AddLog("Saved a walk for " name)
            Notify("Walk saved for " name)
        }
    } catch as err {
        ToolTip()
        AddLog("Recording stopped: " err.Message)
    }
    ReleaseKeys()
    manualRun := false
    RefreshWalkText()
}

TestWalk(*) {
    global manualRun, cancelManual
    if running || manualRun
        return
    if !WinExist(RBX)
        return Notify("Open Roblox first")
    name := spotMapDDL.Text
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

ClearWalk(*) {
    name := spotMapDDL.Text
    if cfg["walks"].Has(name) {
        cfg["walks"].Delete(name)
        SaveConfig()
    }
    RefreshWalkText()
}

; =====================================================================
;  Screenshot (Settings tab) and saved recaptures
; =====================================================================
; saves exactly what the macro sees into the Logs folder (handy for fixing detection)
; =====================================================================
;  Import / backup (Settings tab)
; =====================================================================
; reads another macro's config.ini (an older version, Premium or a friend's) and asks what to
; bring over. The window is built once, so after importing the macro restarts to show it all.
ImportPick(*) {
    if running || manualRun
        return Notify("Stop the macro first")
    MG.Opt("+OwnDialogs")
    f := FileSelect(1, A_Desktop, "Pick config.ini in the other macro's Settings folder", "Macro settings (*.ini)")
    if f = ""
        return
    if f = cfgFile
        return Notify("That's this macro's own settings file. Pick the other one")
    try sections := "`n" IniRead(f) "`n"
    catch
        return Notify("Couldn't read that file")
    has := (name) => InStr(sections, "`n" name "`n")
    theirs := ReadConfigFile(f)
    parts := []
    add := (id, label, on := true) => parts.Push({id: id, label: label, on: on})
    if has("Build")
        add("build", "Build order (" theirs["build"].Length " step" (theirs["build"].Length = 1 ? "" : "s") ")")
    if has("Slot1")
        add("units", "Units (slots, pattern, retries)")
    if has("Route") || has("Curses") || has("DenyShrine")
        add("dungeon", "Dungeon (room priority, curses, shrines, shop)")
    if has("Spots") || has("Walks")
        add("spots", "Spots and walks (only the maps in that file change)")
    if has("General") {
        add("general", "Other settings (placement speed, camera, teleport)")
        if theirs["webhook"] != "" || theirs["psLink"] != ""
            add("links", "Discord webhook and private server link (personal)", false)
    }
    if !parts.Length
        return Notify("No macro settings in that file")
    ; a small window to tick what to bring over
    SplitPath f, , &dir
    dlg := Gui("+Owner" MG.Hwnd " -MinimizeBox", "Import settings")
    dlg.SetFont("s10", "Segoe UI")
    dlg.Add("Text", "w420", "From: " dir "`nYour current settings are replaced for what you tick.")
    boxes := []
    for pt in parts
        boxes.Push(dlg.Add("CheckBox", "w420 " (pt.on ? "Checked" : ""), pt.label))
    go := dlg.Add("Button", "w120 Default", "Import")
    no := dlg.Add("Button", "x+10 w120", "Cancel")
    no.OnEvent("Click", (*) => dlg.Destroy())
    go.OnEvent("Click", (*) => ImportDo(theirs, parts, boxes, dlg))
    dlg.Show()
}

ImportDo(theirs, parts, boxes, dlg) {
    picked := []
    for i, pt in parts
        if boxes[i].Value
            picked.Push(pt.id)
    dlg.Destroy()
    if !picked.Length
        return Notify("Nothing ticked, nothing imported")
    copyKeys := (names) => ForEachKey(names, theirs)
    done := []
    for id in picked {
        switch id {
            case "build":
                cfg["build"] := theirs["build"], copyKeys(["useBuild"]), done.Push("build order")
            case "units":
                cfg["slots"] := theirs["slots"], copyKeys(["pattern", "retries", "saveForTop", "autoAbility"]), done.Push("units")
            case "dungeon":
                for k in ["route", "curseRank", "denyShrine", "avoid", "shopRank", "shopOff"]
                    if theirs.Has(k)
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
    SaveConfig()
    list := ""
    for i, d in done
        list .= (i = 1 ? "" : i = done.Length ? " and " : ", ") d
    AddLog("Imported " list ". Restarting to load them")
    MsgBox("Imported " list ".`n`nThe macro restarts now to load them.", "Import settings", "Iconi T4")
    Reload()
}

ForEachKey(names, theirs) {
    for k in names
        if theirs.Has(k) && cfg.Has(k)
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

; a copy of your settings, to keep or to import into another copy of the macro
BackupConfig(*) {
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
        Notify("Saved " fname ". Import it here or in any copy of the macro")
    } catch as err
        Notify("Couldn't save: " err.Message)
}

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
; haven't recorded yourself gets them; your own recordings always win.
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

SpotPick() {
    if running
        return Notify("Stop the macro first")
    if p := PickPoint() {
        SpotList().Push(p)
        RefreshSpots(SpotList().Length)
        SaveConfig()
    }
}

SpotRemove() {
    if !(r := spotLV.GetNext())
        return Notify("Select a spot first")
    SpotList().RemoveAt(r)
    RefreshSpots(Min(r, SpotList().Length))
    SaveConfig()
}

SpotMove(d) {
    list := SpotList()
    r := spotLV.GetNext(), dest := r + d
    if !r || dest < 1 || dest > list.Length
        return
    tmp := list[r], list[r] := list[dest], list[dest] := tmp
    RefreshSpots(dest)
    SaveConfig()
}

SpotClear() {
    if !SpotList().Length
        return
    if MsgBox("Remove all spots for " spotMapDDL.Text "?", "Clear map", "YesNo Icon! Owner" MG.Hwnd) != "Yes"
        return
    cfg["spots"][spotMapDDL.Text] := []
    RefreshSpots()
    SaveConfig()
}

; positions are relative to Roblox's game area, like every click the macro makes
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
;  UI building blocks
; =====================================================================
StartPanel(name) {
    global cur
    cur := name
    panels[name] := []
}

A(type, opts, text := "") {
    ; plain labels are see-through so the animated background shows behind them
    if type = "Text" && !InStr(opts, "Background")
        opts .= " BackgroundTrans"
    ctl := MG.Add(type, ShiftOpts(opts), text)
    if cur != ""
        panels[cur].Push(ctl)
    return ctl
}

; moves every "x123" / "y123" in an options string by OX / OY
ShiftOpts(opts) {
    out := "", pos := 1
    while p := RegExMatch(opts, "(?<![\w+-])([xy])(\d+)", &m, pos) {
        out .= SubStr(opts, pos, p - pos) m[1] (m[2] + (m[1] = "x" ? OX : OY))
        pos := p + m.Len
    }
    return out SubStr(opts, pos)
}

TitleBtn(x, text, fn, hi) {
    MG.SetFont("s11 bold c" CL.text)
    ctl := MG.Add("Text", "x" x " y0 w38 h31 +0x200 Center BackgroundTrans", text)
    ctl.OnEvent("Click", fn)
    hover[ctl.Hwnd] := {ctrl: ctl, norm: "Trans", hi: hi}
    return ctl
}

Heading(title, sub) {
    GradPic(193, 24, 4, 30, CL.accentHi, CL.accent2, true, true)
    MG.SetFont("s18 bold c" CL.text)
    A("Text", "x205 y20 w570", title)
    MG.SetFont("s9 norm c" CL.muted)
    A("Text", "x205 y56 w570", sub)
    MG.SetFont("s10 norm c" CL.text)
}

SubHead(x, y, title, sub) {
    MG.SetFont("s11 bold c" CL.text)
    A("Text", "x" x " y" y " w275", title)
    MG.SetFont("s9 norm c" CL.muted)
    A("Text", "x" x " y" (y + 22) " w" (x = 205 ? 360 : 275), sub)
    MG.SetFont("s10 norm c" CL.text)
}

Divider(y) => A("Text", "x205 y" y " w570 h1 Background" CL.line)

Card(x, label, value, stripe := "") {
    if stripe != ""        ; made first so it sits on top of the card
        A("Text", "x" x " y90 w3 h74 Background" stripe)
    MG.SetFont("s8 bold c" CL.muted)
    A("Text", "x" x " y90 w132 h28 +0x200 Background" CL.card, "   " label)
    MG.SetFont("s16 bold c" CL.text)
    v := A("Text", "x" x " y118 w132 h46 +0x200 Background" CL.card, "  " value)
    MG.SetFont("s10 norm c" CL.text)
    return v
}

Btn(opts, text, fn, bg := "", hi := "") {
    bg := bg || CL.btn, hi := hi || CL.btnHi
    MG.SetFont("s10 bold cFFFFFF")
    ctl := A("Text", opts " +0x200 Center Background" bg, text)
    MG.SetFont("s10 norm c" CL.text)
    ctl.OnEvent("Click", (*) => fn())
    hover[ctl.Hwnd] := {ctrl: ctl, norm: bg, hi: hi}
    return ctl
}

; a tick box drawn with text so it matches the dark theme
Toggle(opts, label, getFn, setFn) {
    ctl := A("Text", opts " h28 +0x200", "")
    draw := (*) => (ctl.Value := (getFn() ? "☑   " : "☐   ") label, ctl.SetFont(getFn() ? "c" CL.text : "c" CL.muted))
    ctl.OnEvent("Click", (*) => (setFn(getFn() ? 0 : 1), draw(), SaveConfig()))
    draw()
    return ctl
}

TogCfg(opts, label, key) => Toggle(opts, label, () => cfg[key], (v) => cfg[key] := v)
TogMap(opts, label, mp, key) => Toggle(opts, label, () => mp[key], (v) => mp[key] := v)
TogSlot(opts, label, i, prop) => Toggle(opts, label, () => cfg["slots"][i].%prop%, (v) => cfg["slots"][i].%prop% := v)

DDL(opts, items, choose) {
    ctl := A("DropDownList", opts " R12 Choose" choose, items)
    try DllCall("uxtheme\SetWindowTheme", "Ptr", ctl.Hwnd, "Str", "DarkMode_CFD", "Ptr", 0)
    return ctl
}

; offset 1 is for the "Max, Level 1..9" list where Max means 0
SlotDDL(opts, items, i, prop, offset) {
    ctl := DDL(opts, items, cfg["slots"][i].%prop% + offset)
    ctl.OnEvent("Change", (c, *) => (cfg["slots"][i].%prop% := c.Value - offset, SaveConfig()))
    return ctl
}

CurseDDL(opts, i) {
    ctl := DDL(opts, CURSES, IndexOf(CURSES, cfg["curseRank"][i]) || i)
    ctl.OnEvent("Change", (c, *) => (cfg["curseRank"][i] := c.Text, SaveConfig()))
    return ctl
}

RouteDDL(opts, i) {
    ctl := DDL(opts, ROOM_NAMES, IndexOf(ROOM_KEYS, cfg["route"][i]) || ROOM_KEYS.Length)
    ctl.OnEvent("Change", (c, *) => (cfg["route"][i] := ROOM_KEYS[c.Value], SaveConfig()))
    return ctl
}

ShowPanel(name, *) {
    global curPanel
    curPanel := name
    for n, ctrls in panels
        for ctl in ctrls
            ctl.Visible := (n = name)
    for n, nav in navCtl {
        on := (n = name)
        navBar[n].Visible := on
        bgc := on ? CL.card : "Trans"
        nav.Opt("+Background" bgc)
        nav.SetFont(on ? "c" CL.text " bold" : "c" CL.muted " norm")
        nav.Redraw()
        hover[nav.Hwnd].norm := bgc
    }
    if name = "Spots"
        RefreshSpots()
}

HoverCheck() {
    global lastHover
    MouseGetPos , , , &hwndUnder, 2
    if hwndUnder = lastHover
        return
    if hover.Has(lastHover) {
        h := hover[lastHover]
        h.ctrl.Opt("+Background" h.norm), h.ctrl.Redraw()
    }
    if hover.Has(hwndUnder) {
        h := hover[hwndUnder]
        h.ctrl.Opt("+Background" h.hi), h.ctrl.Redraw()
    }
    lastHover := hwndUnder
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
        "bgStrength", 3, "bgGif", "", "accent", "Purple",
        "route", ["Rare_Chest", "Chest", "Shop", "Hoard", "Shrine", "Boss"],
        "avoid", Map("Flying", 1, "Wind", 0, "Money", 1, "Health", 1, "Exploding", 0, "Shielding", 1, "Regen", 1),
        "curseRank", ["Flying", "Money", "Health", "Shielding", "Regen", "Wind", "Exploding"], "skipWorst", 5,
        "denyShrine", Map("Burst", 0, "Armor", 0, "Chaos", 0, "Vamparism", 0, "Frenzy", 0),
        "dmgType", "Both", "shopUnknown", 1, "lookAhead", 0, "shopMinCoins", 0, "usePanel", 0, "shopRank", SHOP_ITEMS(), "shopOff", Map(),
        "slots", [
            {on: 1, count: 2, prio: 3, up: 0, limit: 0},
            {on: 1, count: 1, prio: 1, up: 1, limit: 0},
            {on: 1, count: 3, prio: 4, up: 0, limit: 0},
            {on: 1, count: 4, prio: 5, up: 0, limit: 0},
            {on: 1, count: 1, prio: 2, up: 0, limit: 4},
            {on: 0, count: 1, prio: 6, up: 0, limit: 0}
        ],
        "spots", Map(),
        "walks", Map(),
        "build", []
    )
}

ScalarKeys() => ["pattern", "useSpots", "saveForTop", "autoAbility", "zoom", "tpSpawn", "saveChests", "buyShop",
    "denyAllShrines", "denyUnknownShrine", "stopAfterDefeat", "placeSpeed", "webhook", "hookRuns", "psLink", "fixOnStart", "tolerance", "skipWorst", "retries", "useBuild",
    "bgStrength", "bgGif", "accent"]

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
    loop 6 {
        s := cfg["slots"][A_Index], sec := "Slot" A_Index
        s.on := ClampInt(IniRead(cfgFile, sec, "On", s.on), 0, 1, s.on)
        s.count := ClampInt(IniRead(cfgFile, sec, "Count", s.count), 1, 6, s.count)
        s.prio := ClampInt(IniRead(cfgFile, sec, "Priority", s.prio), 1, 6, s.prio)
        s.up := ClampInt(IniRead(cfgFile, sec, "Upgrade", s.up), 0, 1, s.up)
        s.limit := ClampInt(IniRead(cfgFile, sec, "Limit", s.limit), 0, 9, s.limit)
    }
    cfg["placeSpeed"] := ClampInt(cfg["placeSpeed"], 1, SPEEDS.Length, 1)
    cfg["tolerance"] := ClampInt(cfg["tolerance"], 1, 3, 2)
    cfg["retries"] := ClampInt(cfg["retries"], 1, RETRIES.Length, 3)
    ; build order: S1=place,1,2,2  (kind, slot, count, upgrades: 0 none, N times, -1 max)
    loop ClampInt(IniRead(cfgFile, "Build", "Count", 0), 0, 100, 0) {
        f := StrSplit(IniRead(cfgFile, "Build", "S" A_Index, ""), ",")
        if f.Length = 4 && (f[1] = "place" || f[1] = "upgrade") && IsInteger(f[2]) && IsInteger(f[3]) && IsInteger(f[4])
            && !(f[1] = "upgrade" && f[4] = 0)
            cfg["build"].Push({kind: f[1], slot: ClampInt(f[2], 1, 6, 1), count: ClampInt(f[3], 1, 6, 1), up: ClampInt(f[4], -1, 10, 0)})
    }
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

SaveConfig(*) {
    try {
        for k in ScalarKeys()
            IniWrite cfg[k], cfgFile, "General", k
        for i, v in cfg["route"]
            IniWrite v, cfgFile, "Route", "Room" i
        for name, v in cfg["avoid"]
            IniWrite v, cfgFile, "Avoid", name
        for name, v in cfg["denyShrine"]
            IniWrite v, cfgFile, "DenyShrine", name
        for i, name in cfg["curseRank"]
            IniWrite name, cfgFile, "Curses", "Rank" i
        for i, s in cfg["slots"] {
            sec := "Slot" i
            IniWrite s.on, cfgFile, sec, "On"
            IniWrite s.count, cfgFile, sec, "Count"
            IniWrite s.prio, cfgFile, sec, "Priority"
            IniWrite s.up, cfgFile, sec, "Upgrade"
            IniWrite s.limit, cfgFile, sec, "Limit"
        }
        try IniDelete cfgFile, "Spots"
        for name, list in cfg["spots"] {
            if !list.Length
                continue
            str := ""
            for p in list
                str .= (A_Index > 1 ? "|" : "") p.x "," p.y
            IniWrite str, cfgFile, "Spots", name
        }
        try IniDelete cfgFile, "Build"
        IniWrite cfg["build"].Length, cfgFile, "Build", "Count"
        for i, st in cfg["build"]
            IniWrite st.kind "," st.slot "," st.count "," st.up, cfgFile, "Build", "S" i
        try IniDelete cfgFile, "Walks"
        for name, route in cfg["walks"]
            IniWrite route, cfgFile, "Walks", name
    } catch as err {
        AddLog("Couldn't save settings: " err.Message)
    }
}

ClampInt(v, lo, hi, dflt) => IsInteger(v) ? Min(hi, Max(lo, Integer(v))) : dflt

; =====================================================================
;  Look: accent colours, gradients and the animated background (GDI+)
; =====================================================================
ApplyAccent() {
    acc := ACCENTS.Has(cfg["accent"]) ? ACCENTS[cfg["accent"]] : ACCENTS["Purple"]
    CL.accent := acc[1], CL.accentHi := acc[2], CL.accent2 := acc[3]
}

; a colour swatch on the Look tab
Swatch(x, y, name) {
    acc := ACCENTS[name]
    MG.SetFont("s9 bold cFFFFFF")
    ctl := A("Text", "x" x " y" y " w88 h40 +0x200 Center Background" acc[1], (name = cfg["accent"] ? "✓ " : "") name)
    ctl.OnEvent("Click", (*) => SetAccent(name))
    hover[ctl.Hwnd] := {ctrl: ctl, norm: acc[1], hi: acc[2]}
    MG.SetFont("s10 norm c" CL.text)
}

SetAccent(name) {
    if name = cfg["accent"]
        return
    if running || manualRun
        return Notify("Stop the macro first (the window restarts to change colour)")
    cfg["accent"] := name
    SaveConfig()
    IniWrite "Look", cfgFile, "General", "reopenTab"
    Reload
}

; mixes two "RRGGBB" colours, t = 0..1
Blend(c1, c2, t) {
    n1 := Integer("0x" c1), n2 := Integer("0x" c2), mix := 0
    for shift in [16, 8, 0] {
        v1 := (n1 >> shift) & 0xFF, v2 := (n2 >> shift) & 0xFF
        mix |= Round(v1 + (v2 - v1) * t) << shift
    }
    return Format("{:06X}", mix)
}

ARGB(hex) => 0xFF000000 | Integer("0x" hex)

; puts a backdrop control under all the others
PushBottom(ctl) => DllCall("SetWindowPos", "Ptr", ctl.Hwnd, "Ptr", 1, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x13)

GdipStart() {
    static token := 0
    if token
        return token
    DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    si := Buffer(24, 0)
    NumPut("UInt", 1, si, 0)
    tok := 0
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok, "Ptr", si, "Ptr", 0)
    token := tok
    return token
}

; a 24-bit bitmap (no alpha, so picture controls use it as-is) drawn by drawFn(graphics)
DibDraw(w, h, drawFn) {
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8)
    NumPut("UShort", 1, bi, 12), NumPut("UShort", 24, bi, 14)
    bits := 0
    hbm := DllCall("CreateDIBSection", "Ptr", 0, "Ptr", bi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
    hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    obm := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm, "Ptr")
    gr := 0
    DllCall("gdiplus\GdipCreateFromHDC", "Ptr", hdc, "Ptr*", &gr)
    try drawFn(gr)
    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gr)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", obm)
    DllCall("DeleteDC", "Ptr", hdc)
    return hbm
}

; a picture control filled with a gradient (left to right, or top to bottom)
GradPic(x, y, w, h, c1, c2, vertical := false, inPanel := false) {
    GdipStart()
    opts := "x" x " y" y " w" w " h" h " 0xE"
    pic := inPanel ? A("Picture", opts) : MG.Add("Picture", opts)
    SendMessage 0x172, 0, DibDraw(w, h, GradFill.Bind(w, h, c1, c2, vertical)), pic
    return pic
}

GradFill(w, h, c1, c2, vertical, gr) {
    p1 := Buffer(8, 0), p2 := Buffer(8, 0)
    NumPut("Int", vertical ? 0 : w, "Int", vertical ? h : 0, p2)
    br := 0
    DllCall("gdiplus\GdipCreateLineBrushI", "Ptr", p1, "Ptr", p2, "UInt", ARGB(c1), "UInt", ARGB(c2), "Int", 3, "Ptr*", &br)
    DllCall("gdiplus\GdipFillRectangleI", "Ptr", gr, "Ptr", br, "Int", 0, "Int", 0, "Int", w, "Int", h)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
}

BgFile() => cfg["bgGif"] != "" && FileExist(cfg["bgGif"]) ? cfg["bgGif"] : A_ScriptDir "\Images\ui\background.gif"

; turns the GIF into ready-made faded frames, then plays them with BgTick
LoadBackground(*) {
    global bgFrames, bgDelays, bgIdx
    static alphas := [0, 0.12, 0.2, 0.3, 0.45]
    SetTimer BgTick, 0
    old := bgFrames
    bgFrames := [], bgDelays := [], bgIdx := 0
    try SendMessage 0x172, 0, 0, bgPic
    for hb in old
        DllCall("DeleteObject", "Ptr", hb)
    file := BgFile()
    if cfg["bgGif"] != "" && FileExist(cfg["bgGif"]) {
        SplitPath file, &fname
        try gifV.Value := fname
    } else
        try gifV.Value := "Built-in (night sky)"
    alpha := alphas[ClampInt(cfg["bgStrength"], 1, 5, 3)]
    if alpha <= 0 || !FileExist(file) {
        bgPic.Visible := false
        return
    }
    GdipStart()
    img := 0
    if DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", file, "Ptr*", &img) || !img {
        AddLog("Couldn't load the background picture")
        bgPic.Visible := false
        return
    }
    iw := 0, ih := 0
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", img, "UInt*", &iw)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", img, "UInt*", &ih)
    if !iw || !ih {
        DllCall("gdiplus\GdipDisposeImage", "Ptr", img)
        bgPic.Visible := false
        return
    }
    ; how many frames, and how long each one shows (GIF stores 1/100 s)
    dim := Buffer(16, 0), frameCount := 1, dims := 0
    DllCall("gdiplus\GdipImageGetFrameDimensionsCount", "Ptr", img, "UInt*", &dims)
    if dims {
        DllCall("gdiplus\GdipImageGetFrameDimensionsList", "Ptr", img, "Ptr", dim, "UInt", 1)
        DllCall("gdiplus\GdipImageGetFrameCount", "Ptr", img, "Ptr", dim, "UInt*", &frameCount)
    }
    frameCount := Max(1, frameCount)
    delays := [], sz := 0
    DllCall("gdiplus\GdipGetPropertyItemSize", "Ptr", img, "UInt", 0x5100, "UInt*", &sz)
    if sz {
        item := Buffer(sz, 0)
        if !DllCall("gdiplus\GdipGetPropertyItem", "Ptr", img, "UInt", 0x5100, "UInt", sz, "Ptr", item) {
            pv := NumGet(item, A_PtrSize = 8 ? 16 : 12, "Ptr")
            loop Min(NumGet(item, 4, "UInt") // 4, frameCount) {
                d := NumGet(pv, (A_Index - 1) * 4, "UInt") * 10
                delays.Push(d <= 10 ? 100 : d)          ; 0 means "as fast as possible": browsers use 100 ms
            }
        }
    }
    ; same colours, faded to the chosen strength
    ia := 0
    DllCall("gdiplus\GdipCreateImageAttributes", "Ptr*", &ia)
    cm := Buffer(100, 0)
    for i in [0, 6, 12, 24]
        NumPut("Float", 1.0, cm, i * 4)
    NumPut("Float", alpha, cm, 18 * 4)
    DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "Ptr", ia, "Int", 0, "Int", 1, "Ptr", cm, "Ptr", 0, "Int", 0)
    DllCall("gdiplus\GdipSetImageAttributesWrapMode", "Ptr", ia, "Int", 3, "UInt", 0, "Int", 0)
    ; crop the middle so it fills the area without stretching
    fit := Max(BG_W / iw, BG_H / ih)
    sw := Round(BG_W / fit), sh := Round(BG_H / fit)
    sx := (iw - sw) // 2, sy := (ih - sh) // 2
    ; very fast GIFs skip frames to about 12 per second, and long ones play their
    ; first 64 frames (~1 MB each) on a loop, so motion stays smooth
    total := 0
    loop frameCount
        total += delays.Length >= A_Index ? delays[A_Index] : 100
    stepBy := Max(1, Round(80 / (total / frameCount)))
    keep := Min(64, Ceil(frameCount / stepBy))
    loop keep {
        first := (A_Index - 1) * stepBy
        ms := 0
        loop Min(stepBy, frameCount - first)
            ms += delays.Length >= first + A_Index ? delays[first + A_Index] : 100
        if dims
            DllCall("gdiplus\GdipImageSelectActiveFrame", "Ptr", img, "Ptr", dim, "UInt", first)
        bgFrames.Push(DibDraw(BG_W, BG_H, BgFill.Bind(img, ia, sx, sy, sw, sh)))
        bgDelays.Push(Max(40, ms))
    }
    DllCall("gdiplus\GdipDisposeImageAttributes", "Ptr", ia)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", img)
    bgPic.Visible := true
    BgTick()
}

BgFill(img, ia, sx, sy, sw, sh, gr) {
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gr, "Int", 7)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", gr, "Int", 4)
    DllCall("gdiplus\GdipGraphicsClear", "Ptr", gr, "UInt", ARGB(CL.bg))
    DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", gr, "Ptr", img, "Int", 0, "Int", 0, "Int", BG_W, "Int", BG_H, "Int", sx, "Int", sy, "Int", sw, "Int", sh, "Int", 2, "Ptr", ia, "Ptr", 0, "Ptr", 0)
}

; shows the next frame (the picture control keeps using our bitmap, nothing is copied)
BgTick() {
    global bgIdx
    if !bgFrames.Length
        return
    bgIdx := Mod(bgIdx, bgFrames.Length) + 1
    try SendMessage 0x172, 0, bgFrames[bgIdx], bgPic
    if bgFrames.Length > 1
        SetTimer BgTick, -bgDelays[bgIdx]
}

ChooseGif(*) {
    MG.Opt("+OwnDialogs")
    f := FileSelect(1, A_MyDocuments, "Pick a background GIF", "Pictures (*.gif; *.png; *.jpg; *.jpeg; *.bmp)")
    if f = ""
        return
    cfg["bgGif"] := f
    if cfg["bgStrength"] = 1 {
        cfg["bgStrength"] := 3
        bgDDL.Choose(3)
    }
    SaveConfig()
    LoadBackground()
}

DefaultGif(*) {
    cfg["bgGif"] := ""
    SaveConfig()
    LoadBackground()
}

; libraries go last so nothing in them can cut the startup code short
#Include %A_ScriptDir%\Lib\FindText.ahk
; OCR.ahk: Windows' built-in text reader (by Descolada, MIT licence)
#Include %A_ScriptDir%\Lib\OCR.ahk
