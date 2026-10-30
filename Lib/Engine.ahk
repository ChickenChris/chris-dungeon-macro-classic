#Requires AutoHotkey v2.0

; =====================================================================
;  Engine.ahk  -  the dungeon auto-farm                            v2.2
; ---------------------------------------------------------------------
;  How it works
;   * Every loop it looks at the screen, works out where it is (lobby,
;     room picker, shop, shrine, chest, in a stage, results...) and does
;     the right thing, so it recovers from anything unexpected.
;   * Detection: ONE screenshot of the Roblox window is taken and every
;     check runs on it in memory (Snap / FT). A new screenshot is only
;     taken when the last one is older than SNAP_AGE ms or after a click.
;   * Each thing it looks for is a named "detector" (DetDefs). You can
;     teach it a new look for any detector from the Detect tab; those
;     recaptures live in Settings\patterns.ini.
;   * Clicks are relative to Roblox's game area (AutoHotkey's default
;     "Client" mode) so Roblox must be the active window. FindText areas
;     were captured with Roblox at (-5, 1); FT() shifts them to wherever
;     Roblox is now. Roblox must be 816 x 638 (F1).
; =====================================================================

global RBX := "ahk_exe RobloxPlayerBeta.exe"
global AA_PLACE_ID := 8304191830
global CAP_X := -5, CAP_Y := 1
global WIN_W := 816, WIN_H := 638
global SNAP_AGE := 90
global YenHud := "|<>*84$8.zzzzaQD3kwDbzs"   ; HUD yen icon (Patterns.ahk reuses "Yen" for a card)

global running := false
global paused := false
global manualRun := false      ; true while a button (Reset camera, Record walk...) uses engine steps
global cancelManual := false   ; F3 during one of those buttons
global pauseTotal := 0         ; ms spent paused (keeps walk timing right)
global pausedAt := 0           ; when the current pause started
global stageActive := false
global stageStart := 0
global walkedHere := false     ; walked to the map's spot this stage (PlaceSlot: back to spawn if nothing fits)
global MOVE_FLAG := A_ScriptDir "\Settings\click_to_move_on"   ; Roblox left in Click to Move (ClickWalk)
global bossDone := false
global chestsDone := false      ; this dungeon's saved chests have been opened
global curMap := "Unknown"
global mapHow := ""             ; how the map was recognised (shown in the log)
global dungeonTotal := 20       ; rooms in a dungeon run (read from "DEPTH: 14/20" when possible)
global curDepth := ""          ; dungeon room depth read from the loading screen
global icFloor := 0             ; Infinity Castle floor as the game shows it (0 = not read yet)
global icFloors := 0            ; Infinity Castle floors cleared this session
global lastMapRaw := ""
global lastCurseRaw := ""      ; the text last read while looking for a room's curse (for the log)        ; the last text read while looking for the map name (for the log)
global placedUnits := []
global placeUnsure := Map()     ; slot -> spots clicked this stage where no menu showed (maybe placed unseen)
global unseenFound := []        ; units found that way, for PlaceSlot to count as placed
global allPlaced := false       ; every unit is down: from now on the F panel may be used
global lastResult := ""
global idleSince := 0
global snapTick := 0
global closeStreak := 0       ; times in a row the room picker had no Enter button
global slotStops := Map()       ; "slot|map" -> how many it managed before giving up last time
global slotPrice := Map()       ; slot -> its price in the unit bar (this stage)
global slotCap := Map()         ; "slot|map" -> the most that fit on that map, once it's been seen twice
global goodSpots := Map()       ; "slot|map" -> spots where that slot landed before (tried first next time)
; (per map: a cramped map used to cap a slot for every later map, so later rooms were played
; with fewer units until the macro was restarted)
CapKey(n) => n "|" curMap (ElemTeamsOn() ? "|" cfg["team"] : "")    ; with Element teams a slot holds another unit per team
global slotOne := Map()         ; slot -> true: a unique unit, the game allows one of it
global autoOpenSeen := false   ; a menu has opened by itself after placing (the game setting is right)
global autoOpenOff := false    ; menus only open when the new unit is clicked (setting is wrong)
global clickOpened := 0
global slotFull := Map()        ; slot -> stage it hit the game's limit in (no more that stage)
global mapFull := 0             ; when the game last said the map holds no more units at all (not one unit's limit)

; trims `need` to what the game allows for slot n right now
SlotRoom(n, need) {
    if slotCap.Has(CapKey(n))
        need := Min(need, slotCap[CapKey(n)] - CountPlaced(n))
    if slotFull.Get(n, -1) = stageStart
        need := 0
    if mapFull && A_TickCount - mapFull < 60000  ; the map is full right now: upgrade, try again in a bit
        need := 0
    return Max(0, need)
}
global postStage := 0         ; when the last stage ended (reward popups follow)
global lastGain := 0          ; levels gained in the last upgrade pass
global stat := {runs: 0, wins: 0, losses: 0, rooms: 0, chests: 0, dungeons: 0, startTick: 0, streak: 0}

class MacroStop extends Error {
}

; =====================================================================
;  Detectors
; =====================================================================
; name -> {label, area [x1,y1,x2,y2] (capture space), err, std (built-in patterns),
;          pats (what is searched), custom (recaptured pattern or "")}
DetDefs() {
    static d := 0
    if IsObject(d)
        return d
    d := Map()
    DetAdd(d, "Lobby", "Lobby", 746, 514, 789, 530, 0, AreaText)
    DetAdd(d, "EnterDungeon", "Enter dungeon (lobby)", 310, 395, 495, 440, 0.2, EnterDungeon)
    DetAdd(d, "RoomBorder", "Room picker", 200, 340, 600, 437, 0.2, DungeonRoomBorder)
    DetAdd(d, "Enter", "Room Enter button", 120, 425, 680, 500, 0.2, Enter)
    DetAdd(d, "FinalRoom", "Final room label", 434, 215, 479, 230, 0, FinalRoom)
    DetAdd(d, "Shop", "Shop", 140, 200, 375, 250, 0, Shop)
    DetAdd(d, "Shrine", "Shrine", 140, 200, 375, 250, 0, Shrine)
    DetAdd(d, "ShrineAccept", "Shrine accept", 334, 395, 672, 483, 0, ShrineAccept)
    DetAdd(d, "ShrineDeny", "Shrine deny", 334, 395, 672, 483, 0, DenyShrine)
    DetAdd(d, "Chest", "Chest room", 140, 200, 604, 261, 0, ChestRoom, ChestRoomLuck)
    DetAdd(d, "DungeonContinue", "Dungeon continue", 380, 385, 615, 490, 0, DungeonContinue)
    DetAdd(d, "FinishText", "Finish dungeon text", 174, 102, 631, 545, 0, FinishDungeonText)
    DetAdd(d, "FinishButton", "Finish button", 174, 102, 631, 545, 0, DungeonFinish)
    DetAdd(d, "FinishDungeon", "Dungeon cleared popup", 240, 180, 565, 480, 0.1, FinishDungeon)
    DetAdd(d, "DungeonDeath", "Out of lives", 370, 225, 545, 300, 0.1, DungeonDeath)
    DetAdd(d, "DeathContinue", "Out of lives: continue", 308, 391, 494, 437, 0, DungeonDeathContinue)
    DetAdd(d, "RedX", "Red X close", 588, 107, 780, 249, 0, DungeonRedX)
    DetAdd(d, "VoteStart", "Vote start", 301, 64, 503, 154, 0, VoteStart, VoteStartLaptop)
    DetAdd(d, "Yen", "Yen counter", 340, 537, 468, 557, 0, YenHud)
    DetAdd(d, "Units", "Units button", 742, 287, 832, 377, 0.1, Units)
    DetAdd(d, "Spawn", "Teleport to Spawn (settings)", 215, 160, 596, 480, 0.2, Spawn)
    ; the two MAX styles each in their own small spot (as in Ryn's macro): one big box over the
    ; whole menu let the new-style MAX match among the stats, so units counted as maxed too early
    DetAdd(d, "Max", "Max upgrade (button)", 225, 388, 278, 412, 0, MaxText)
    DetAdd(d, "MaxNew", "Max upgrade (title)", 255, 234, 299, 250, 0, MaxTextNew)
    DetAdd(d, "AutoOff", "Ability auto: off", 342, 253, 401, 281, 0, AutoOff)
    DetAdd(d, "Chat", "Chat window open", 123, 50, 156, 79, 0, OpenChat)
    DetAdd(d, "UnitExit", "Unit info close", 300, 190, 360, 250, 0, UnitExit)
    DetAdd(d, "Next", "Next button", 260, 400, 390, 450, 0, NextText)
    DetAdd(d, "Xp", "XP / rewards", 575, 145, 641, 210, 0, XpText)
    DetAdd(d, "Victory", "Victory", 150, 176, 492, 279, 0, VictoryText, VictoryText2, VictoryTextApril)
    DetAdd(d, "Defeat", "Defeat", 150, 176, 492, 279, 0, DefeatText, DefeatText2)
    DetAdd(d, "EndScreen", "Results buttons", 80, 85, 739, 224, 0, LobbyText, LobbyText2)
    DetAdd(d, "Elyssia", "Elyssia summon", 14, 226, 138, 246, 0, ElyssiaSummons)
    return d
}

DetAdd(d, name, label, x1, y1, x2, y2, err, pats*) {
    joined := ""
    for p in pats
        joined .= p
    d[name] := {label: label, area: [x1, y1, x2, y2], baseArea: [x1, y1, x2, y2], err: err,
        std: joined, pats: joined, custom: "", box: ""}
}

; the order detectors are listed on the Detect tab
DetOrder() => ["Lobby", "EnterDungeon", "RoomBorder", "Enter", "FinalRoom", "Shop", "Shrine", "ShrineAccept",
    "ShrineDeny", "Chest", "DungeonContinue", "FinishDungeon", "DungeonDeath", "DeathContinue", "RedX",
    "VoteStart", "Yen", "Units", "Spawn", "Max", "MaxNew", "AutoOff", "Chat", "UnitExit", "Next", "Xp", "Victory",
    "Defeat", "EndScreen", "FinishText", "Elyssia"]

; teach a detector a new look (keeps the built-in one too). box is in capture space.
SetDetCustom(name, text, box := "") {
    d := DetDefs()
    if !d.Has(name)
        return
    o := d[name]
    o.custom := text, o.box := box
    o.pats := o.std text
    o.area := o.baseArea.Clone()
    if IsObject(box) && box.Length = 4 {
        o.area[1] := Min(o.area[1], box[1] - 20), o.area[2] := Min(o.area[2], box[2] - 20)
        o.area[3] := Max(o.area[3], box[3] + 20), o.area[4] := Max(o.area[4], box[4] + 20)
    }
}

ClearDetCustom(name) {
    d := DetDefs()
    if !d.Has(name)
        return
    o := d[name]
    o.custom := "", o.box := "", o.pats := o.std, o.area := o.baseArea.Clone()
}

Det(name, &x := "", &y := "") {
    o := DetDefs()[name]
    a := o.area
    if !FT(&x, &y, a[1], a[2], a[3], a[4], o.err, o.err, o.pats)
        return name = "Lobby" && LobbyByText(&x, &y)
    if !OnAd(x, y, &b)
        return true
    ; it found the tournament ad: look again above and left of it
    for r in [[a[1], a[2], a[3], Min(a[4], b[2] - 1)], [a[1], a[2], Min(a[3], b[1] - 1), a[4]]]
        if r[3] > r[1] + 4 && r[4] > r[2] + 4 && FT(&x, &y, r[1], r[2], r[3], r[4], o.err, o.err, o.pats) && !OnAd(x, y)
            return true
    return false
}

; The lobby is found by a picture of the "Areas" button's label. On some PCs it never matches
; (a colour filter, HDR, a Roblox mod with other fonts...) and the macro sat on "looking for
; something to do" in the lobby. Then the label is read as text instead (at most every 2.5 s).
LobbyByText(&x := "", &y := "") {
    static last := -9999, hit := false, told := false
    if A_TickCount - last < 2500 {
        if hit
            x := 767, y := 522
        return hit
    }
    last := A_TickCount, hit := false
    try {
        WinGetClientPos &ox, &oy, , , RBX
        txt := OCR.FromRect(ox + 728, oy + 500, 72, 40, OcrLang(), {scale: 3, grayscale: true}).Text
        hit := RegExMatch(txt, "i)\bar[e3c]a[s5]\b") > 0
    }
    if hit {
        x := 767, y := 522
        if !told {
            told := true
            AddLog("Found the lobby by its text (its picture doesn't match on this PC)")
            SaveDebugShot("lobby")
        }
    }
    return hit
}

; The "Don't Miss Out!" tournament ad pops up over the right side of the screen. It isn't part
; of the dungeon, so the macro ignores it: a detection that lands on it doesn't count (its red X
; was taken for the room picker's X: "The Red X close wouldn't go away"). Found by its yellow title.
; Returns its box in detection coordinates [left, top, right, bottom], or 0 when it isn't up.
AdBox() {
    static pts := 0, last := -9999, box := 0
    if A_TickCount - last < 400
        return box
    last := A_TickCount, box := 0
    if !IsObject(pts) {
        pts := []
        for e in StrSplit("1,0,F8E100|70,0,E0CB02|3,1,FFE300|54,1,FFE300|103,1,FFE300|1,2,FFE000|41,2,FFE000|72,2,E0C502|128,2,FFE000|35,3,E0C202|64,3,FFDD00|127,3,FFDD00|17,4,EFCB01|43,4,FFD900|65,4,FFD900|89,4,CDAF03|127,4,FFD900|10,5,FFD600|28,5,FFD600|45,5,FFD600|64,5,FED500|81,5,FFD600|111,5,D8B602|130,5,FFD600|14,6,FFD300|28,6,FFD300|45,6,FFD300|65,6,FFD300|81,6,FCD100|110,6,FFD300|129,6,FFD300|11,7,F3C501|31,7,FFCF00|62,7,FFCF00|86,7,FFCF00|122,7,FFCF00|13,8,F5C301|41,8,FFCB00|70,8,FFCB00|89,8,E5B602|127,8,FFCB00|14,9,FFC800|42,9,FFC800|71,9,FFC800|99,9,FFC800|127,9,FFC800|16,10,F3BB01|43,10,FFC400|82,10,F4BB01|114,10,FFC400|2,11,FFC000|18,11,FFC000|43,11,FFC000|75,11,FBBD00|88,11,EEB301|108,11,FFC000|128,11,FFC000|6,12,FFBD00|31,12,FFBD00|67,12,FBBA00|85,12,FFBD00|107,12,FFBD00|130,12,FFBD00|25,13,F6B300|117,13,F7B400|2,-4,0E0E0E|11,-4,0E0E0E|20,-4,0E0E0E|29,-4,0E0E0E|38,-4,0E0E0E|47,-4,0E0E0E|56,-4,0E0E0E|65,-4,0E0E0E|74,-4,0E0E0E|83,-4,0E0E0E|92,-4,0E0E0E|101,-4,0E0E0E|110,-4,0E0E0E|119,-4,0E0E0E|128,-4,0E0E0E|2,-3,0E0E0E|11,-3,0E0E0E|20,-3,0E0E0E|29,-3,0E0E0E|38,-3,0E0E0E|47,-3,0E0E0E|56,-3,0E0E0E|65,-3,0E0E0E|74,-3,0E0E0E|83,-3,0E0E0E|92,-3,0E0E0E|101,-3,0E0E0E|110,-3,0E0E0E|119,-3,0E0E0E|128,-3,0E0E0E", "|") {
            f := StrSplit(e, ","), rgb := Integer("0x" f[3])
            pts.Push([Integer(f[1]), Integer(f[2]), (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF])
        }
    }
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        loop 25 {
            ay := 209 + A_Index
            loop 25 {
                ax := 599 + A_Index, quick := true
                for k in [1, 17, 33, 49] {             ; 4 title pixels first: most spots fail here
                    p := pts[k], col := scr.GetColor(ox + ax + p[1], oy + ay + p[2], 0)
                    if Abs(((col >> 16) & 0xFF) - p[3]) > 25 || Abs(((col >> 8) & 0xFF) - p[4]) > 25 || Abs((col & 0xFF) - p[5]) > 25 {
                        quick := false
                        break
                    }
                }
                if quick && IconScore(scr, ox + ax, oy + ay, pts, 0.8) >= 0.8 {
                    box := [ax - 22 + 3 - 4, ay - 20 + 33 - 4, ax + 164 + 3 + 4, ay + 108 + 33 + 4]
                    return box
                }
            }
        }
    }
    return box
}

; is a detection point (x, y) on the tournament ad? (cheap: only looks when it's where the ad goes)
OnAd(x, y, &b := 0) {
    if !IsNumber(x) || !IsNumber(y) || x < 580 || y < 220 || y > 380
        return false
    b := AdBox()
    return IsObject(b) && x >= b[1] && x <= b[3] && y >= b[2] && y <= b[4]
}


; run every detector on one screenshot (Detect tab). Returns {hits: Map, ms}
DetectAll() {
    t0 := A_TickCount
    Snap()
    hits := Map()
    for name in DetOrder()
        hits[name] := Det(name)
    return {hits: hits, ms: A_TickCount - t0}
}

; =====================================================================
;  Main loop
; =====================================================================
EngineRun() {
    global running, idleSince, slotStops, slotCap, slotOne, slotFull, autoOpenSeen, autoOpenOff, clickOpened, icFloors, icFloor
    errors := 0
    idleSince := 0
    global goodSpots := Map(), teamLoaded := 0  ; which team the game has isn't known at Start
    slotStops := Map(), slotCap := Map(), slotOne := Map(), slotFull := Map(), autoOpenSeen := false, autoOpenOff := false, clickOpened := 0
    icFloors := 0, icFloor := 0
    loop {
        try {
            Chk()
            Tick()
            errors := 0
        } catch MacroStop {
            ReleaseKeys()
            return
        } catch as err {
            ReleaseKeys()
            if !running
                return
            errors++
            AddLog("Hiccup: " err.Message " (line " err.Line ")")
            if errors >= 15 {
                AddLog("Too many errors in a row, stopping")
                SendWebhook("Macro stopped", "Too many errors in a row. Last one: " err.Message, 0xDC2626)
                return
            }
            try Wait(2000)
            catch
                return
        }
    }
}

Tick() {
    global idleSince
    if !EnsureRoblox() {
        CheckConnection()
        return
    }
    if CheckConnection()
        return
    Snap()                                   ; one screenshot for this whole pass

    if Det("EndScreen") {
        idleSince := 0
        HandleEnd()
        return
    }
    if EndButtonsSeen(true) {                ; the results screen by its button colours
        EndByColourLog()
        idleSince := 0
        if NextByColour(&nx, &ny) {          ; VICTORY / DEFEAT with its green Next
            ReadResult()
            FinishStage()
            Step("results: pressing Next")
            Clk(nx, ny)
            Wait(600)
        } else
            HandleEnd()                      ; "Return to lobby" / "Open Dungeon"
        return
    }
    ; Next comes before XP: the XP panel stays up next to the Next button,
    ; so checking XP first made it click around forever without pressing Next
    if Det("Next") {
        idleSince := 0
        ReadResult()
        FinishStage()
        Step("results: pressing Next")
        ClickDet("Next", 0, -40, 8000)
        Wait(400)
        return
    }
    if challengeOn && postStage && !stageActive {   ; a challenge counted at Next: rewards, the lobby
        idleSince := 0
        ChallengeEnded()
        return
    }
    if Det("Xp") {
        idleSince := 0
        ReadResult()
        Clk(325, 185), Clk(560, 560)
        Wait(400)
        return
    }
    if Det("UnitExit", &fx, &fy) {
        Clk(fx - 4, fy - 35)
        Wait(300)
        return
    }
    if HandleDungeonPopups() {
        idleSince := 0
        return
    }
    if Det("Shop") {
        idleSince := 0
        HandleShop()
        return
    }
    if Det("Shrine") || ShrineButtons() {
        idleSince := 0
        HandleShrine()
        return
    }
    if Det("Chest") {
        idleSince := 0
        HandleChests()
        return
    }
    rooms := ScanRooms()
    if rooms.Length {
        idleSince := 0
        ; a shrine whose picture didn't match can look like rooms: read its words first
        if TextScreen() = "Shrine" {
            HandleShrine()
            return
        }
        ChooseRoom(rooms)
        return
    }
    if Det("Enter") {
        idleSince := 0
        EnterRoom()
        return
    }
    if (Det("EnterDungeon") || EnterDungeonByColour(&bx, &by)) && InStageWorld() {
        idleSince := 0
        Clk(666, 145)                            ; close it: "Enter Dungeon" only works in the lobby
        Wait(800)
        BackToLobby()
        return
    }
    if Det("EnterDungeon") {
        idleSince := 0
        Step("opening the dungeon")
        Clk(395, 380)
        WaitFor(() => ScanRooms().Length || SpecialScreen(), 3000)
        return
    }
    if EnterDungeonByColour(&bx, &by) {      ; same screen, its picture didn't match on this PC
        idleSince := 0
        Step("opening the dungeon")
        Clk(bx, by)
        WaitFor(() => ScanRooms().Length || SpecialScreen(), 3000)
        return
    }
    if (ICMode() || LegendMode()) && FoolJoinUp() {   ; "Join Matchmaking?" left open: Play Here
        idleSince := 0
        Clk(330, 325)
        Wait(800)
        return
    }
    if Det("Lobby") {
        idleSince := 0
        if ChallengeLobby()                  ; Auto challenge: a new one goes first
            StartChallenge()
        else if ICMode()
            StartInfinityCastle()
        else if LegendMode()
            StartLegend()
        else
            OpenDungeonFromLobby()
        return
    }
    if IsLoaded() {
        idleSince := 0
        PlayStage()
        return
    }
    IdleTick()
}

; =====================================================================
;  Infinity Castle (free in Classic since 3.0.100, the same as Premium)
; =====================================================================
ICMode() => cfg.Has("mode") && cfg["mode"] = "Infinity Castle"

; From the lobby: the Areas button, the Infinity Castle area, then a short walk to the entrance
; (the route from Ryn's macro). The entrance window is recognised by its Cancel button; then
; it picks the difficulty and presses Start, just above Cancel.
StartInfinityCastle() {
    Step("lobby: going to Infinity Castle")
    AddLog("In the lobby, going to Infinity Castle (" (cfg["icHard"] ? "Hard" : "Normal") ")")
    Clk(400, 340), Clk(400, 390)
    CloseChat()
    loop 3 {
        if FT(&fx, &fy, 325, 520, 489, 587, 0, 0, ModeCancel)
            break
        before := SceneSig()
        Clk(765, 475)                           ; Areas
        Wait(300)
        Clk(370, 330)                           ; the Infinity Castle area
        ; the game takes a few seconds to move the player there: walking straight away walked
        ; the lobby, then the teleport landed and the player just stood there
        Step("lobby: waiting for the teleport to Infinity Castle")
        WaitAreaTeleport(before)
        FocusRoblox()
        SendKeys("{w down}")
        Wait(500)
        SendKeys("{w up}")
        Wait(500)
        SendKeys("{a down}")
        Wait(4000)
        SendKeys("{a up}")
        Wait(500)
        Stale()
    }
    if !FT(&fx, &fy, 325, 520, 489, 587, 0, 0, ModeCancel) {
        AddLog("Couldn't reach the Infinity Castle entrance. Send Logs\inf_castle_....bmp in Discord so it can be fixed")
        SaveDebugShot("inf_castle")
        Wait(3000)
        return
    }
    Clk(cfg["icHard"] ? 485 : 418, 375)         ; Normal / Hard
    Wait(400)
    Stale()
    t0 := A_TickCount
    while A_TickCount - t0 < 8000 {
        ; the game added matchmaking to Infinity Castle too: Start brings up "Join Matchmaking?"
        ; (the same window as Fool's Hunt). Play Here starts it alone, like Start used to
        if FoolJoinUp() {
            Clk(330, 325)                       ; Play Here
            Wait(800)
            Stale()
            continue
        }
        if !FT(&fx, &fy, 325, 520, 489, 587, 0, 0, ModeCancel)
            break
        Clk(fx - 10, fy - 120)                  ; Start
        Wait(800)
        Stale()
    }
    AddLog("Infinity Castle started")
    ; the lobby stays on screen while the stage loads: don't walk the lobby again meanwhile
    Step("waiting for Infinity Castle to load")
    t0 := A_TickCount
    while A_TickCount - t0 < 30000 {
        Stale()
        if !Det("Lobby")
            break
        Wait(500)
    }
    if !Det("Lobby")
        LoadStage()                             ; reads the floor's map off the loading screen, then plays
}

IdleTick() {
    global idleSince
    static lastNudge := 0, lastPoke := 0, hinted := false
    if !idleSince
        idleSince := A_TickCount, lastNudge := A_TickCount, hinted := false
    secs := (A_TickCount - idleSince) // 1000
    ; just finished a stage: money / drop / reward popups close with a click anywhere,
    ; so keep tapping the empty corner quickly until the next screen shows up
    if postStage && A_TickCount - postStage < 90000 {
        Step("closing reward popups")
        if A_TickCount - lastPoke > 700 {
            lastPoke := A_TickCount
            Clk(560, 560)
        }
        Wait(150)
        return
    }
    Step("looking for something to do  (" secs "s)")
    ; right after a stage: tap the empty corner every few seconds (closes most result popups)
    if stageActive && A_TickCount - lastPoke > 3000 {
        lastPoke := A_TickCount
        Clk(560, 560)
        if secs >= 10 && !hinted {
            hinted := true
            AddLog("Stuck after a stage? Detect tab: select 'Next button', press Recapture, box the button")
        }
    }
    if A_TickCount - lastNudge > 30000 {
        ; nudge: dismiss stray popups and the chat
        lastNudge := A_TickCount
        Clk(400, 340), Clk(400, 390)
        CloseChat()
    }
    Wait(250)
}

; =====================================================================
;  Lobby -> dungeon
; =====================================================================
OpenDungeonFromLobby() {
    ; a new dungeon, no boss beaten yet: one from an earlier dungeon (or from before a Stop) opened
    ; this dungeon's chests from the first room with "Save chests for after the boss" on (Apocalipse)
    global bossDone := false, chestsDone := false
    Step("lobby: opening dungeons")
    AddLog("In the lobby, opening dungeons")
    Clk(400, 340), Clk(400, 390)
    CloseChat()
    Clk(85, 400)
    WaitFor(() => Det("DungeonDeath") || Det("EnterDungeon") || ScanRooms().Length, 3000)
    if Det("DungeonDeath")
        ClickDet("DeathContinue", 0, -30)
    if WaitDet("EnterDungeon", 1500) {
        Clk(395, 380)
        WaitFor(() => ScanRooms().Length || SpecialScreen(), 3000)
    } else if EnterDungeonByColour(&bx, &by) {
        Clk(bx, by)
        WaitFor(() => ScanRooms().Length || SpecialScreen(), 3000)
    }
}

; still standing in a dungeon stage: the green wave health bar across the top (the lobby has none)
InStageWorld() {
    n := 0
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        py := 58
        while py <= 78 {
            px := 170
            while px <= 640 {
                col := scr.GetColor(ox + px, oy + py, 0) & 0xFFFFFF
                r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
                if g > 190 && r < 90 && b < 90
                    n++
                px += 4
            }
            py += 2
        }
    }
    return n >= 60
}

; From the results screen to the lobby (green "Return to lobby"), where the next dungeon is opened.
BackToLobby() {
    static told := false
    Step("back to the lobby for the next dungeon")
    loop 3 {
        Stale()
        if Det("Lobby")
            return true
        if Det("EndScreen")
            ClickDet("EndScreen", 0, -35)           ; "Return to lobby"
        else if FindOpenDungeon(&bx, &by)
            Clk(bx - 210, by)                       ; the green button left of "Open Dungeon"
        else
            break
        if WaitFor(() => Det("Lobby"), 15000, 500)
            return true
    }
    Stale()
    if Det("Lobby")
        return true
    if !told {
        told := true
        AddLog("Couldn't get back to the lobby after the dungeon. Send Logs\to_lobby_....bmp in Discord so it can be fixed")
        SaveDebugShot("to_lobby")
    }
    return false
}

; The "DUNGEON RUN" window with its big green "Enter Dungeon" button, found by colour: the purple
; title plus a wide green button in the middle. On some PCs the button's picture didn't match and
; the macro sat there after clearing a dungeon. Gives the button's middle in game-area coords.
EnterDungeonByColour(&bx, &by) {
    static told := false
    if Det("Shop")                              ; the shop has the same title (and a green Continue)
        return false
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        purple := 0, py := 110
        while py <= 210 {
            px := 60
            while px <= 420 {
                col := scr.GetColor(ox + px, oy + py, 0) & 0xFFFFFF
                r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
                if r > 140 && g < 110 && b > 140 && b > g + 60
                    purple++
                px += 3
            }
            py += 3
        }
        if purple < 60
            return false
        xs := [], ys := [], py := 355
        while py <= 430 {
            from := 0, last := -99, bestW := 0, bestX := 0
            px := 240
            while px <= 572 {
                isG := false
                if px <= 570 {
                    col := scr.GetColor(ox + px, oy + py, 0) & 0xFFFFFF
                    r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
                    isG := g > 170 && r < 150 && b < 120
                }
                if isG {
                    if px - last > 14
                        from := px
                    last := px
                } else if last > 0 && px - last > 14 && from {
                    if last - from > bestW
                        bestW := last - from, bestX := (from + last) // 2
                    from := 0
                }
                px += 2
            }
            if bestW >= 140 && bestW <= 290
                xs.Push(bestX), ys.Push(py)
            py += 3
        }
        if xs.Length < 3
            return false
        bx := MiddleOf(xs), by := MiddleOf(ys)
        if bx < 330 || bx > 480
            return false
        if !told
            told := true, AddLog("Enter Dungeon found by its colours (its picture didn't match)")
        return true
    }
    return false
}

; =====================================================================
;  Room picker
; =====================================================================
RoomAreas() {
    static areas := [
        {x1: 200, y1: 340, x2: 222, y2: 437, sx1: 204, sy1: 343, sx2: 290, sy2: 435, cx: 250, cy: 360},
        {x1: 507, y1: 340, x2: 530, y2: 437, sx1: 514, sy1: 343, sx2: 600, sy2: 435, cx: 555, cy: 360},
        {x1: 352, y1: 343, x2: 379, y2: 437, sx1: 358, sy1: 343, sx2: 447, sy2: 435, cx: 400, cy: 360},
        {x1: 275, y1: 340, x2: 300, y2: 437, sx1: 280, sy1: 343, sx2: 370, sy2: 435, cx: 322, cy: 360},
        {x1: 430, y1: 340, x2: 450, y2: 437, sx1: 438, sy1: 343, sx2: 525, sy2: 435, cx: 477, cy: 360}
    ]
    return areas
}

ScanRooms() {
    found := []
    border := DetDefs()["RoomBorder"].pats
    for i, ar in RoomAreas() {
        kind := ""
        if Seen(ar.x1, ar.y1, ar.x2, ar.y2, border, 0.2)
            kind := "Available"
        else if Seen(ar.x1, ar.y1, ar.x2, ar.y2, DungeonRoomBorderDark, 0.1)
            kind := "Unavailable"
        else if Seen(ar.x1, ar.y1, ar.x2, ar.y2, DungeonRoomBorderCursed, 0.1)
            kind := "Cursed"
        else if Seen(ar.x1, ar.y1, ar.x2, ar.y2, DungeonRoomBorderChestOpen, 0.1)
            kind := "Opening"
        else if Seen(ar.x1, ar.y1, ar.x2, ar.y2, DungeonRoomBorderBoss, 0.1)
            kind := "Boss"
        ; a cursed room is purple inside (78% on a real screenshot, normal rooms 0-5%): far more
        ; reliable than the border picture, which let cursed rooms pass as normal ones
        ; only for a room the border already found: on its own, a purple patch of a map in the middle
        ; of a stage was taken for a cursed room (and the macro tried to pick a room mid-round)
        if kind = "Available" && ColorShare(ar.cx - 35, 328, ar.cx + 35, 393, IsCurseRoom) >= 0.4
            kind := "Cursed"
        if kind != ""
            found.Push({i: i, kind: kind, a: ar})
    }
    return found
}

ChooseRoom(rooms) {
    global roomBoosts := []
    Step("choosing a room")
    ; shops / shrines / chests can pop up a moment after the map appears
    if WaitFor(() => SpecialScreen(), 1200)
        return
    unsafe := Map(), curseOf := Map()
    for pick in RoomOrder(rooms)
        if TryRoom(pick.r, pick.prio, unsafe, curseOf, pick.next)
            return
    ; nothing on the priority list is acceptable: take the least bad room
    ; (a clean room if there is one, otherwise the mildest curse on your list)
    best := 0, bestBad := 99
    for r in rooms {
        if r.kind = "Unavailable"
            continue
        bad := 0
        if r.kind = "Cursed" {
            if !curseOf.Has(r.i) && r.HasOwnProp("curseIcon") && r.curseIcon != ""
                curseOf[r.i] := r.curseIcon         ; read from its box already, no click needed
            if !curseOf.Has(r.i) {
                Clk(r.a.cx, r.a.cy)
                Wait(400)
                curseOf[r.i] := DetectCurse()
                Clk(r.a.cx, r.a.cy)
                Wait(500)
            }
            bad := CurseBadness(curseOf[r.i])
        }
        if bad < bestBad
            best := r, bestBad := bad
    }
    if best {
        c := curseOf.Has(best.i) ? curseOf[best.i] : ""
        global lastRoomI := best.i
        AddLog("No preferred room left, taking the least bad one" (c != "" ? " (curse of " c ")" : ""))
        OpenRoom(best)
        if ElemTeamsOn()
            ReadRoomBoosts()
        EnterRoom()
        return
    }
    AddLog("No rooms to pick from, trying the middle one")
    Clk(400, 355)
    Wait(400)
    EnterRoom()
}

; click a room so its panel (with the Enter button) opens. A room that's already selected (left
; open by the curse check, or picked before a trip to the lobby) closes again on a click, so when
; no Enter button shows up it's clicked once more. Before: "No Enter button" right after
; "taking the least bad one".
OpenRoom(r) {
    Clk(r.a.cx, r.a.cy)
    Wait(400)
    if WaitDet("Enter", 1500)
        return true
    AddLog("Room " r.i ": its panel didn't open, clicking it again")
    Clk(r.a.cx, r.a.cy)
    Wait(400)
    return WaitDet("Enter", 1500)
}

; click a room; if it has a curse you skip, back out. Returns true when it went in.
TryRoom(r, prio, unsafe, curseOf, nextKind := "") {
    global bossDone
    static shots := 0
    ; the curse icon on the room box, read before the click opens the panel over things
    iconCurse := r.HasOwnProp("curseIcon") && r.curseIcon != "" ? r.curseIcon : r.kind != "Boss" ? CurseIcon(r) : ""
    if iconCurse != "" && r.kind != "Cursed" {
        r.kind := "Cursed"
        AddLog("Room " r.i ": its box shows the curse of " iconCurse " (the border didn't)")
    }
    OpenRoom(r)
    if ElemTeamsOn()
        ReadRoomBoosts()                        ; the room's boosted elements, for picking the team
    if shots < 8 {                              ; pictures of room panels, to build exact curse icons from
        shots++
        Wait(300)
        SaveDebugShot("room_panel_" shots)
    }
    curseName := ""
    ; the border picture can pass a cursed room for a normal one (the curse was then never read):
    ; when you skip curses, the room's panel is read too, and a curse there counts
    if r.kind != "Cursed" && cfg["skipWorst"] > 0 && r.kind != "Boss" && iconCurse = "" {
        Wait(200)
        if (c := CurseFromText()) != "" {
            r.kind := "Cursed"
            AddLog("Room " r.i ": the panel shows a curse (" c ") its border didn't")
        } else {
            ; one picture of a checked room panel per session, so curse reading can be checked
            static told := false
            if !told {
                told := true
                AddLog("Room panel checked for a curse, none found (read: " SubStr(lastCurseRaw, 1, 80) ")")
            }
        }
    }
    if r.kind = "Cursed" {
        curseName := iconCurse != "" ? iconCurse : DetectCurse()
        curseOf[r.i] := curseName
        ; a curse it can't tell counts as one to avoid (it used to go in, so avoided curses got through)
        if (curseName != "" && AvoidCurse(curseName)) || (curseName = "" && cfg["skipWorst"] > 0) {
            AddLog("Skipping " RoomLabel(prio) " room (" (curseName != "" ? "curse of " curseName : "a curse it couldn't read: " SubStr(lastCurseRaw, 1, 70)) ")")
            unsafe[r.i] := true
            Clk(r.a.cx, r.a.cy)
            Wait(600)
            return false
        }
    }
    if prio = "Boss"
        bossDone := true
    global lastRoomI := r.i
    AddLog("Going for " RoomLabel(prio) (nextKind != "" ? ", then " RoomLabel(nextKind) : "") (curseName != "" ? "  (curse of " curseName ")" : ""))
    EnterRoom()
    return true
}

RoomPattern(name) {
    static m := 0
    if !IsObject(m)
        m := Map("Chest", Chest, "Hoard", Hoard, "Shop", DungeonShop, "Shrine", ShrineRoom, "Boss", BossRoom2)
    return m.Has(name) ? m[name] : ""
}

RoomLabel(name) => name = "" ? "a plain room" : StrReplace(name, "_", " ")

; The order to try the rooms in. Each room is worth its place on your priority list
; (top = most). Ties keep your list order, clean rooms before cursed ones.
; (Looking one room ahead is a Premium feature.)
RoomOrder(rooms) {
    route := cfg["route"], n := route.Length
    picks := []
    shopOk := true
    for r in rooms {
        if r.kind = "Unavailable"
            continue
        ; a room can hold several things (Shop + Chest + Shrine...): it's worth all of them.
        ; "own" is the best of them (for the log), "has" all of them.
        own := "", rank := 0, rare := RareChestAt(r), has := []
        ; the CHEST label is on both kinds of chest: counted, so a rare chest's own label isn't taken
        ; for a second, normal chest, and a room with both counts both (Lunoc)
        chests := ChestLabels(r), kinds := RoomChests(rare, chests)
        for i, prio in route {
            if prio = "None"
                continue
            if prio = "Rare_Chest" || prio = "Chest"
                hit := IndexOf(kinds, prio)
            else
                hit := Seen(r.a.sx1, r.a.sy1, r.a.sx2, r.a.sy2, RoomPattern(prio), 0.2)
            if hit {
                has.Push(prio)
                if own = ""
                    own := prio, rank := i
            }
        }
        picks.Push({r: r, prio: own, has: has, rank: rank ? rank : 99, score: 0, next: "", cursed: r.kind = "Cursed", chests: chests})
    }
    for pk in picks
        for thing in pk.has
            pk.score += ThingValue(thing, shopOk)
    ; a room that beat you twice in a row at this choice: the others first (the same room was played
    ; 5 times at depth 12 and lost every time, until the dungeon ran out of lives)
    others := 0
    for pk in picks
        others += !(lostRooms.Has(pk.r.i) && lostRooms[pk.r.i] >= 2)
    if others
        for pk in picks
            if lostRooms.Has(pk.r.i) && lostRooms[pk.r.i] >= 2 {
                pk.score -= 100
                AddLog("Room " pk.r.i " beat you " lostRooms[pk.r.i] " times here, trying another room")
            }
    ; every room's curse, read from the icon on its box before anything is clicked, and scored with
    ; your curse list: a curse you skip makes the room worth nothing (it's only taken when nothing
    ; else is left), one you don't skip keeps its worth, and on a tie the milder curse goes first.
    ; (It used to be read only once it was that room's turn, so the log just said "Curse")
    for pk in picks {
        pk.curse := "", pk.bad := 0
        if pk.r.kind = "Boss"
            continue
        c := CurseIcon(pk.r)
        pk.r.curseIcon := c
        if c = "" && !pk.cursed
            continue
        pk.cursed := true, pk.curse := c, pk.bad := CurseBadness(c), pk.r.kind := "Cursed"
        CursedRare(pk)
        if c != "" && AvoidCurse(c)
            pk.score := -99, pk.skip := true
    }
    ; one line with how every room was valued, so each pick can be checked straight from the log
    ; (worth = its place on your room list, rare chest double; a shop without enough coins = 0)
    sum := ""
    for pk in picks {
        what := !pk.cursed ? "" : pk.HasOwnProp("curse") && pk.curse != "" ? "Curse of " pk.curse : "Curse (which one isn't known yet)"
        for t in pk.has
            what .= (what = "" ? "" : "+") RoomLabel(t)
        sum .= (sum = "" ? "" : "  |  ") "[" (what = "" ? "nothing on your list" : what) "] = " (pk.HasOwnProp("skip") ? "skipped, you avoid " pk.curse : pk.score)
    }
    if sum != ""
        AddLog("Rooms: " sum)
    ; rooms that aren't on your list and lead nowhere useful are left for the "least bad" fallback
    order := []
    for pk in picks
        if pk.score > 0 {
            j := order.Length + 1
            while j > 1 && RoomBefore(pk, order[j - 1])
                j--
            order.InsertAt(j, pk)
        }
    return order
}

; best score first; on a tie your room list decides, then more good rooms after it, then clean before cursed
RoomBefore(x, y) => x.score != y.score ? x.score > y.score : x.rank != y.rank ? x.rank < y.rank : RoomSpare(x) != RoomSpare(y) ? RoomSpare(x) > RoomSpare(y) : x.cursed != y.cursed ? !x.cursed : RoomBad(x) < RoomBad(y)
RoomBad(p) => p.HasOwnProp("bad") ? p.bad : 0
RoomSpare(p) => p.HasOwnProp("spare") ? p.spare : 0

; what one thing is worth: its place on your room list (top = most). A rare chest counts
; double (it's what dungeons are farmed for), a curse costs more than a chest and a hoard
; together (cursed rooms lose runs), and a shop is worth nothing until you have the coins
; to spend in it ("Only go to a shop with" setting).
; a cursed room always holds a rare chest (150 of 150 cursed rooms in a player's log), so it counts
; one even when its picture wasn't matched: in a room with 4 things the icons are smaller, the rare
; chest picture missed, and only the plain "CHEST" label was found. A "Chest" read there is that rare chest
CursedRare(pk) {
    if IndexOf(pk.has, "Rare_Chest")
        return
    ; one CHEST label: it's the rare chest's. Two: a rare chest and a normal one (Lunoc)
    if (pk.HasOwnProp("chests") ? pk.chests : 1) < 2 && (i := IndexOf(pk.has, "Chest"))
        pk.has.RemoveAt(i), pk.score -= ThingValue("Chest")
    pk.has.Push("Rare_Chest"), pk.score += ThingValue("Rare_Chest")
}

ThingValue(kind, shopOk := true) {
    if kind = "Curse"
        return -8
    if kind = "Shop" && !shopOk
        return 0
    i := IndexOf(cfg["route"], kind)
    v := i ? cfg["route"].Length + 1 - i : 0
    return kind = "Rare_Chest" ? v * 2 : v
}

; a rare chest in this room, looked for around the room itself (it used to look once, in the middle
; of the screen only: a rare chest in an outer room, or a second one, counted as a plain chest)
RareChestAt(r) => ImgFind(RareChestImage, r.a.cx - 48, 315, r.a.cx + 48, 462, &ix, &iy)

; how many CHEST labels a room box shows (rare and normal chests both have one). The search can
; find one label at a few spots next to each other: matches within 15 px count once
ChestLabels(r) {
    if !(ok := FT(&fx, &fy, r.a.sx1, r.a.sy1, r.a.sx2, r.a.sy2, 0.2, 0.2, Chest))
        return 0
    return LabelCount(ok)
}
LabelCount(found) {
    seen := []
    for f in found {
        new := true
        for p in seen
            if Abs(p[1] - f.x) <= 15 && Abs(p[2] - f.y) <= 15
                new := false
        if new
            seen.Push([f.x, f.y])
    }
    return seen.Length
}

; the chests a room holds, from the rare chest picture and the number of CHEST labels
RoomChests(rare, labels) => rare ? (labels >= 2 ? ["Rare_Chest", "Chest"] : ["Rare_Chest"]) : labels ? ["Chest"] : []

FindRareChestX() {
    return ImgFind(RareChestImage, 247, 325, 561, 457, &ix, &iy) ? ix : -1
}

; ---------- the curse of a room, from the icon on its room box ----------
; Every curse has its own picture above the room's CURSE label (a ring for Money, a shield for
; Shielding, a heart for Health, a heart with a plus for Regen ...). They're drawn the same every
; time, so they're matched pixel by pixel. Read before the room is clicked: no panel text needed.
; Returns the curse's name as on the Dungeon tab, or "" (no CURSE label, or an icon it doesn't know).
CurseIcon(r) {
    static tpl := 0, lab := 0
    if !IsObject(tpl) {
        tpl := Map()
        lab := IconPoints("003D2861105F3E972051357F305B3C90508859D7808859D7A08859D7B04E337CC0593A8CD06F49AFF04F347DG04E337CH05F3E97K08859D7L04E337CM04D3279N04D3279018947D9518947D9818947D9A18947D9C1472570D18947D9F18746D6H13F2164K18947D9027740C4528849E0828849E0A28849E0B2532D89C26A39AEF23B2062G2381E5CH241236BI2472676K28849E0L24A287AM2492777033C2A6B135D41A6234E378C33593E9F536245B1634C368973563D9A83543B97A3845DEDC36F4EC7D36245B0F35B40A4G34B3587H3563D9AI37351CEK3845DEDL34C3689M34B3586N34B3586", 0, 0)
        tpl["Money"] := IconPoints("A6460A5CC615089EE61709A1G61709A1I6500E6797420959B74E1292D76028B9F76028B9H7541EBDJ7490F8B88460A5EA8190AA3C87A1CE1E8A947CFG8A947CFI81C0BA5K81709A17946095D994913C2B99232D8D9A14AF0F9A14AF0H99A3EE4J97620DAL94C11AA6A4108588A4913C2AA590EDBCAA947CFEAC877FFGAC877FFIA7A1CE1KA3800D5MA1709A25B440A5B7B190AA39B7124D2BBC877FFDBB95FE7FBA947CFHBC16BF3JBC16BF3LB6519D7NB470F8A6C4C12918C7124D2ACC877FFCCC877FFECA947CFGCC877FFICC877FFKCC877FFMC3800D5OC4D0C655D15089E7D7A1CE19DC877FFBDC877FFDDC877FFFDC877FFHDC877FFJDC877FFLDB95FE7ND4712C0PD4009576E2906BB8EC877FFAEC877FFCEA947CFEE7A1CE1GE7A1CE1IEC877FFKEC877FFMEC877FFOE1609A05F1709A07F7A1CE19FC877FFBFC877FFDF3800D5FF3800D5HF590EDBJFC877FFLFB95FE7NF4913C2PF4B0C636G4913C28GC16BF3AGB95FE7CG7A1CE1EG3800D5GG3800D5IGC877FFKGA947CFMGC877FFOG1609A05H1609A07H3800D59HC877FFBHC877FFDH3800D5FH3800D5HH590EDBJHC877FFLHB95FE7NH2906BBPH490B606I2805BB8IC16BF3AIC16BF3CI7A1CE1EI3800D5GI3800D5IIC877FFKIC877FFMIB95FE7OI16089F5J4C0C647J1C0BA59JC877FFBJC877FFDJ7A1CE1FJ7A1CE1HJ9232D8JJC877FFLJA14AF0NJ4B11906K460F898K7D2CE6AKC877FFCKB95FE7EKA14AF0GKA14AF0IKC877FFKKC877FFMK590EDBOK43095B7L1609A19L7A1CE1BLC877FFDLC877FFFLB95FE7HLC877FFJLC877FFLL590EDBNL410C828M3E0CA7AM7D2CE6CMB95FE7EMA947CFGMC877FFIMA14AF0KM590EDBMM460E8A9N1809A2BN7A1CE1DNC877FFFNB95FE7HNB95FE7JN590EDBLN470E8BAO3B0BA3CO2805BBEO4A13C3GO4913C2IO2705BAKO440C87BP14089DDP1709A1FP1709A1HP1609A0JP400B82", 4, 28)
        tpl["Shopping"] := IconPoints("J73A0D57I8E50A65K83F0E5EF9390B56H956177BL9390A56GA511475IA75076DBB3C0B5CDB430C68FB581582JB550573LB53137AAC450E67EC571284IC570261MC470E6B9D49106DFD741DACHD75076DJD75076DND3E0B606E390A558E511474CE40059FME621792OE450F66QE390B567F551678BF5708C1HF2D027BJF1C037CLF7D22B6NF661995PF521576AG40059FKG2D027B5H4D136D7HA806FB9H3404C7BH3404C7DH1902B4FH3B03B7HH2D027BJHAA0AB6LH2D027BNH570261PH2D027BRH59187E4I430F626IA806FB8IA806FBAI6A04EDCI1902B4EI1902B4GI3B03B7IIE03B61KI440492MI570261OI870051QICC0568SI4A116D3J3E0D5C7J1902B49J1902B4BJ6A04EDDJ6A04EDFJ3B03B7JJAA0AB6TJ3A0A59AK6A04EDCK3B03B7EK6A04EDIK000BAEQK550573SK49106D3L440F637L5505739LA806FBBL3B03B7DLA806FBNL440492PL5505734M5317756MAA0AB68MAA0AB6AM6A04EDIM013BD4OM711FA2QM56177C3N390C545N621F857N5505739N550573DN1C037CHN000BAEPN5214784O3A0D546OAA0AB6OO460D6A5P3F0F5A7P5505739P550573DP1C037CHP1C037CLP1C037C", 4, 28)
        tpl["Shielding"] := IconPoints("B53D0754D5410659F5410559H5410759J53D075486420B59M64208599766167FL765117FA8E6ECF9C8AAB7D7E87887B0G87887B0I8E6ECF9K8AAB7D799AAB7D7B9AC774CD9B38A64F96A4236H9B38A64J96A4236L94B57856A4D0C658AAAB7D7AA6A4236CAAC774CEA6A4236GAAC774CIA6A4236KAAC774CMA4B5785OA4A03655B3F08579BE6ECF9BBAC774CDBB38A64FB6A4236HBB38A64JB6A4236LB4B5785PB3E02576C580D728CAAB7D7AC6A4236CCAC774CEC6A4236GCAC774CIC6A4236KCAC774CMC4B5785OC5605725D4107599DAAB7D7BDAC774CDDB38A64FD6A4236HDB38A64JD6A4236LD4B5785PD4003596E590A738E7887B0AE6A4236CEAC774CEE6A4236GEAC774CIE6A4236KEAC774CME7887B0OE5907745F4106599F7887B0BFAC774CDFB38A64FF6A4236HFB38A64JF6A4236LF7887B0PF4104596G590B738G7887B0AG6A4236CGAC774CEG6A4236GGAC774CIG6A4236KGAC774CMG7887B0OG5907735H4107589HAAB7D7BHAC774CDHB38A64FH6A4236HHB38A64JH6A4236LH7887B0PH4004586I560E708IE6ECF9AI6A4236CIAC774CEI6A4236GIAC774CII6A4236KIAC774CMI4B5785OI5506709JAAB7D7BJAC774CDJB38A64FJ6A4236HJB38A64JJ6A4236LJ4B57856K480A608KAAB7D7AK6A4236CKAC774CEK6A4236GKAC774CIK6A4236KKAC774CMK4B5785OK4603607L550D6FBLAC774CDLB38A64FL6A4236HLB38A64JL6A4236NL53046FAM4B5785CMAC774CEM6A4236GMAC774CIM6A4236KM4B5785BNAC774CDNB38A64FN6A4236HNB38A64JN6A42368O41045ACO4B5785EO7887B0GO4B5785IO4B5785MO40025A9P43035CLP41025C", 4, 28)
        tpl["Regen"] := IconPoints("A6470F61C63F0C57K6440E5DM6440E5D774F1268D75F197AF7430E5BH7491061P73F0B576852136BA8FFFFFFC8FFFFFFG8581671K8FFFFFFM8FFFFFFQ83E0A5759410D5899FFFFFFB9FFFFFFF9711F8CH9772192J9FFFFFFL9FFFFFFN99E33FF4A4910618AFFFFFFAA9E33FFCA9E33FFEAFFFFFFIAFFFFFFKA9E33FFMA9E33FFOAFFFFFF3B3F0C577B9E33FF9BDC5FFFBBDC5FFFDB9E33FFFBFFFFFFHBFFFFFFJBDC5FFFLBDC5FFFNBDC5FFFPB2E04896CFFFFFF8C9E33FFACDC5FFFCCDC5FFFEC9E33FFGCFFFFFFIC9E33FFKCDC5FFFMCDC5FFFOC9E33FFQC2E04893D4E11687D9E33FF9DDC5FFFBDDC5FFFDDFFFFFFFD9E33FFHD9E33FFJDDC5FFFLDDC5FFFNDDC5FFFPD2E04896EFFFFFF8E9E33FFAEDC5FFFCEFFFFFFEE9E33FFGE2E0489IE9E33FFKEFFFFFFMEDC5FFFOE9E33FFQE2E0489SE4000613F4F126A7F9E33FF9FDC5FFFBFDC5FFFDF9E33FFFF2E0489HF2E0489JFFFFFFFLFDC5FFFNFDC5FFFPF2E04896GFFFFFF8G9E33FFAGFFFFFFCG9E33FFEG9E33FFGG2E0489IG9E33FFKG9E33FFMGDC5FFFOG9E33FFQG2E0489SG3D005C3H450E5E7H9E33FF9HDC5FFFBH9E33FFDH2E0489FH2E0489HH2E0489JH2E0489LH9E33FFNHDC5FFFPH2E04896IFFFFFF8I9E33FFAI9E33FFCI2E0489EI2E0489GI2E0489II2E0489KI2E0489MIDC5FFFOI9E33FFQI2E04895J4A0C647J2E04899JDC5FFFBJ9E33FFDJ2E0489FJ2E0489HJ2E0489JJ2E0489LJ9E33FFNJDC5FFF6K590A78AKDC5FFFCKFFFFFFEKFFFFFFGK2E0489IKFFFFFFKKFFFFFFMK2E0489QK4302629L2E0489BLDC5FFFDLFFFFFFFL2E0489HL2E0489JLFFFFFFLLDC5FFFNL2E0489PL4502638M460463AM2E0489CMDC5FFFEMFFFFFFGM2E0489IMFFFFFFKMDC5FFF9N560975DNDC5FFFFNFFFFFFHNFFFFFFJN2E0489NN470563AO460563EO2E0489GODC5FFFIO2E0489BP460563DP2E0489FPDC5FFFHPDC5FFF", 4, 28)
        tpl["Flying"] := IconPoints("E44D0467G44D0368C660067BI6540272B750046AD7A723F1F7A723F1H79400D8J7680289A8400358E8A723F1G8490251I89400D8B95B0577D9A723F1F9490251H9490251L951016EAA4C0366EAA723F1GA6E0C79IA490251KA9400D8MA550273BB6A0689DB9400D8FB490251HB6E0C79JB9400D8NB4C0168AC5A0476EC9400D8GC6E0C79IC6E0C79KC9400D8MC6D03919D52046DDD490251FD490251HD490251JD490251LD9400D8CEA723F1EE490251GE490251IE6E0C79KE6E0C79OE4C01699F61057FDF490251FF490251HF490251JF6E0C79LF9400D8PF43015E8G460360CG9400D8EG490251GG490251IG6E0C79KG6E0C79MG9400D8QG43015E7H3F0258BHA723F1DH490251FH6E0C79HH490251JH6E0C79LH6E0C79NH9400D8PH6102838I5D047BAIA723F1CI490251EI490251GI490251II490251KI6E0C79MI9400D8QI5702765J4002587J6D068CBJ9400D8DJ6E0C79FJ6E0C79HJ490251JJ6E0C79LJ6E0C79NJ490251RJ43015D4K400258AK490251CK490251EK6E0C79GK490251IK490251KK6E0C79MK6E0C79OK9400D85L5E057B9LA723F1BL490251DL6E0C79FL6E0C79HL490251JL6E0C79LL6E0C79NL6E0C79RL5402736MA723F18MA723F1AM490251CM6E0C79EM6E0C79GM6E0C79IM490251KM6E0C79MM6E0C79OM490251QM9400D8SM4E016B3N4602607N6E0C799N6E0C79DN6E0C79FN6E0C79HN6E0C79JN6E0C79LN6E0C79NN6E0C79PN9400D8TN3E01586O6E0C798O6E0C79EO6E0C79GO6E0C79IO490251KO6E0C79MO6E0C79OO490251QO9400D8SO5402735P4B0167BP560077JP6E0C79LP6E0C79NP6E0C79PP9400D8", 4, 28)
        tpl["Health"] := IconPoints("954D0763B54D0863D5410657H5410557J54D0763L54C06636648065E86640D7BA66A0F82C6660E7DE653096AG653096AI6660D7DK66A0D82M6640B7BO648065E57640D7A77410E5297410E52B7410E52D7410E52F78B17A1H7410E52J7410E52L7410E52N7410E52P7640C7A484E076368410E5288D652EDA8D652EDC8D652EDE8410E52G8410E52I8D652EDK8D652EDM8AB2CC4O8410E52Q84F07643948065E59410E5279AB2CC499D652EDB9D652EDD9D652EDF9410E52H9D652EDJ9D652EDL9AB2CC4N9D652EDP9AB2CC4R953086A2A45045A4A410E526AAB2CC48AD652EDAAD652EDCAD652EDEAAB2CC4GAAB2CC4IAAB2CC4KAAB2CC4MAAB2CC4OAAB2CC4QA410E52SA44055A3B64097B5BAB2CC47BD652ED9BD652EDBBAB2CC4DBAB2CC4FBAB2CC4HBAB2CC4JBAB2CC4LBAB2CC4NBAB2CC4PBD652EDRB640C7B2C4D05634C410E526CAB2CC48CD652EDACD652EDCCAB2CC4ECAB2CC4GCAB2CC4ICAB2CC4KCAB2CC4MCAB2CC4OCD652EDQC410E52SC4D06633D6B0A835DAB2CC47DAB2CC49DAB2CC4BDAB2CC4DDAB2CC4FDAB2CC4HDAB2CC4JD8A1C9FLDAB2CC4NDAB2CC4PDD652EDRD6A0C832E4D05634E410E526EAB2CC48ED652EDAEAB2CC4CEAB2CC4EEAB2CC4GEAB2CC4IE8A1C9FKE8A1C9FME8A1C9FOEAB2CC4QE410E52SE4D06633F64097B5FAB2CC47FD652ED9FD652EDBFAB2CC4DFAB2CC4FFAB2CC4HFAB2CC4JF8A1C9FLF8A1C9FNFAB2CC4PFAB2CC4RF640A7B4G410E526GAB2CC48GAB2CC4AGAB2CC4CGAB2CC4EGAB2CC4GGAB2CC4IG410E52KG8A1C9FMG8A1C9FOGAB2CC4QG410E523H48055E5H410E527HAB2CC49HAB2CC4BHAB2CC4DHAB2CC4FHAB2CC4HHAB2CC4JH8A1C9FLH8A1C9FNHAB2CC4PH410E52RH48055E4I4F07646I410E528IAB2CC4AIAB2CC4CIAB2CC4EIAB2CC4GIAB2CC4II8A1C9FKI8A1C9FMI8A1C9FOI410E52QI4F06645J5409697J410E529JAB2CC4BJAB2CC4DJAB2CC4FJAB2CC4HJ8A1C9FJJ410E52LJ8A1C9FNJ410E52PJ5407696K5408698K410E52AK8A1C9FCKAB2CC4EKAB2CC4GK8A1C9FIK410E52KK8A1C9FMK410E52OK5306697L5408699L410E52BLAB2CC4DLAB2CC4FLAB2CC4HL410E52JL410E52LL410E52NL5206698M520669AM410E52CM410E52EM410E52GM410E52IM8A1C9FKM410E52MM5104699N510469BN410E52DN410E52FN410E52HN8A1C9FJN410E52LN510469AO4F0269CO750495EO8A1C9FGO8A1C9FIO770695KO500369BP4F0169DP410E52FP8A1C9FHP410E52JP500369", 4, 28)
        tpl["Wind"] := IconPoints("F540005CH542005DC64E006EE67675C6G6B0B9F0I6B0B9F0K6B0B9F0M63F005AQ67675C6B74F006FD77675C6F7B0B9F0H7B0B9F0J7B0B9F0L7560078N74B0069P77675C6A87675C6C8B0B9F0E8B0B9F0G87740B7I87740B7K87675C6M8610085O859007CQ8B0B9F07941005D99B0B9F0B9B0B9F0D97740B7F97740B7H97740B7J97740B7L9B0B9F0N97675C6P9B0B9F0R94400618A5C0080AAB0B9F0CA7740B7EA7740B7GA7740B7IA7740B7KA7740B7MA7675C6OA7675C6QAB0B9F07BB0B9F09B7675C6BB7740B7DB7675C6FB7675C6HB7740B7JBB0B9F0LBB0B9F0NBB0B9F0PB7675C66C4F006F8CB0B9F0AC7675C6CC7675C6EC7740B7GC7740B7ICB0B9F0KCB0B9F0MCB0B9F0OCB0B9F0QC5400747DB0B9F09D7740B7BD7675C6DD7740B7FD7740B7HD7740B7JDB0B9F0LDB0B9F0NDB0B9F0PD6100846E4D006D8E7675C6AEB0B9F0CEB0B9F0EEB0B9F0GEB0B9F0IEB0B9F0KE7675C6MEB0B9F0OE7675C67F7740B79F7675C6BFB0B9F0DFB0B9F0FFB0B9F0HFB0B9F0JFB0B9F0LFB0B9F0NFB0B9F0PF4900666G4600668G7740B7AGB0B9F0CGB0B9F0EGB0B9F0GGB0B9F0IG7675C6KGB0B9F0MGB0B9F0OG5900797H7675C69H70009DBH7675C6DH7675C6FH7675C6HH7675C6JHB0B9F0LHB0B9F0NHB0B9F0PH42005F8I7675C6AI71009FCI7675C6EI7675C6GIB0B9F0IIB0B9F0KI7675C6MI7675C6OI540075QI7675C69J7675C6BJ7675C6DJB0B9F0FJB0B9F0HJB0B9F0JJB0B9F0LJB0B9F0NJ7675C6PJ40005D8K3E005BAK7675C6CK7675C6EKB0B9F0GKB0B9F0IK7675C6KKB0B9F0MK7675C6OK7675C69L470068BL5B0083DL7740B7FL7675C6HL7675C6JLB0B9F0LL7675C6NL7675C6AM7675C6CM62008BEM7E00ADGMB0B9F0IMB0B9F0KMB0B9F0MM530074BN7675C6DN6B0095FN7675C6HNB0B9F0JNB0B9F0LN550077CO7675C6EOB0B9F0GOB0B9F0IOB0B9F0KO7675C6DP59007CFP7675C6HPB0B9F0JP630087", 4, 28)
        tpl["Exploding"] := IconPoints("6444055A75590A71954207574652076986630F7BA63F0854G63F035537500668577641C1B75C1173D7510769F75D0777H75E0879J7500868L7490860N745055CP74104576831367388F96BFFC86B1283G87641C1I8670C82M85D0B76394D066459313673797641C199F96BFFB99122A8D97C1097J9791496L9781594P97641C1R94104574A4E06648AF96BFFAAF96BFFEA9E19B9KAF96BFFOA7641C15B6B0D829B313673BB7641C1DB7641C1HB8D13ABNB9F1ABFRB45055D6C73108A8C313673AC7641C1CC7641C1GC9919B5KCF96BFFQC5D09775D4C05637D770D92BD7641C1DD7641C1FD7641C1HDB626CFLDF96BFFRD5009686E60077A8E9C13B9CE313673EE7641C1GE7641C1KEF96BFFME7641C1OEF96BFFSE4107575F4F05689FA815C5BF313673DFF96BFFFF7641C1LF7641C1PFF96BFFRF5E1076CG313673EG7641C1GG7641C1KGF96BFFMG7641C1OGF96BFFSG4D0A645H4D05659H9210B1DH313673FH7641C1HHF96BFFJH7641C1LHF96BFFNHF96BFFPHF96BFFRH6B14846I5807728I820FA0AIAF1ECDEI7641C1GI7641C1II7641C1KIF96BFFMIF96BFFOIF96BFFSI4F0B675J47075E7J6B10859J9C22B9FJ313673HJ7641C1JJ7641C1LJF96BFFNJ7641C1PJF96BFFRJ6C11856K600F79AKF96BFFCKF96BFFEKF96BFFGK313673IK7641C1KKF96BFFMK313673OK313673SK5008685L520C6ABLF96BFFDLF96BFFFLF96BFFHL7641C1JL7641C1LL313673NL7641C1PL313673RL6C0D858MF96BFFAM7641C1CM7641C1EMF96BFFGMF96BFFIMF96BFFKM313673MM313673OM313673SM5005685N4E0B65FNF96BFFHN7641C1JN7641C1LN7641C1NN313673PN313673RN6C09856O540D6C8O71128CAOA521C3GOF96BFFIO7641C1KO313673MO313673OO313673SO4C04637P4107579P6D1089HPF96BFFJP7641C1LP313673NP313673PP313673RP63097B", 4, 28)
    }
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        ; the CURSE label sits left of the box's middle, higher up when the room holds 3-4 things
        loop 56 {
            ly := 334 + A_Index
            loop 36 {
                lx := r.a.cx - 46 + A_Index
                if IconScore(scr, ox + lx, oy + ly, lab, 0.85) < 0.85
                    continue
                ; the icons glow and pulse: a Money ring mid-pulse matched 58% (the old cut was 60%), while
                ; a wrong icon never matched more than 19% on Chris's screenshots. So 40% is enough, as long
                ; as the best is well ahead of the next one
                best := "", bestV := 0, secondV := 0
                for name, pts in tpl {
                    v := 0
                    for sh in [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]
                        v := Max(v, IconScore(scr, ox + lx + sh[1], oy + ly + sh[2], pts, 0.3))
                    if v > bestV
                        secondV := bestV, best := name, bestV := v
                    else if v > secondV
                        secondV := v
                }
                if bestV >= 0.4 && bestV - secondV >= 0.25
                    return best = "Shopping" ? "Money" : best    ; Shopping is listed with Money
                static told := false
                if !told {
                    told := true
                    AddLog("A curse icon it doesn't know yet (best match " Round(bestV * 100) "%), reading the panel instead")
                    SaveDebugShot("curse_icon")
                }
                return ""
            }
        }
    }
    return ""
}

; points of a picture: 2 letters for where (from the label), then the colour as RRGGBB
IconPoints(s, ox, oy) {
    static abc := "0123456789ABCDEFGHIJKLMNOPQRSTUV"
    pts := []
    loop StrLen(s) // 8 {
        i := (A_Index - 1) * 8 + 1, rgb := Integer("0x" SubStr(s, i + 2, 6))
        pts.Push([InStr(abc, SubStr(s, i, 1), true) - 1 - ox, InStr(abc, SubStr(s, i + 1, 1), true) - 1 - oy,
            (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF])
    }
    return pts
}

; share of the points that have their colour (within 25) at screen spot sx, sy. Gives up (0) as
; soon as it can't reach need any more, so trying many spots stays quick.
IconScore(scr, sx, sy, pts, need) {
    allowed := Floor(pts.Length * (1 - need)), miss := 0
    for p in pts {
        col := scr.GetColor(sx + p[1], sy + p[2], 0)
        if Abs(((col >> 16) & 0xFF) - p[3]) > 25 || Abs(((col >> 8) & 0xFF) - p[4]) > 25 || Abs((col & 0xFF) - p[5]) > 25
            if ++miss > allowed
                return 0
    }
    return 1 - miss / pts.Length
}

DetectCurse() {
    static curses := 0
    if !IsObject(curses)
        curses := Map("Flying", CurseofFlight, "Wind", CurseOfWind, "Money", CurseOfMoney, "Health", CurseofHealth,
            "Shielding", CurseOfShielding, "Regen", CurseOfRegen, "Exploding", CurseOfExplosion)
    t0 := A_TickCount, n := 0
    while A_TickCount - t0 < 3000 {
        for name, pat in curses
            if Seen(121, 168, 681, 493, pat, 0.05)
                return name
        ; the pictures are of the old names ("Curse of Money" is "Curse of Shopping" now), so
        ; the panel's words are read too
        if Mod(++n, 2) = 1 && (name := CurseFromText()) != ""
            return name
        Wait(150)
    }
    return ""
}

; "Curse of Shopping" etc. read from the room's panel, as one of the names on the Dungeon tab
CurseFromText() {
    static words := [["fli|fly", "Flying"], ["win", "Wind"], ["shop|mon", "Money"], ["hea|vit", "Health"],
        ["shi", "Shielding"], ["reg", "Regen"], ["exp|eru", "Exploding"]]
    ; the effect line under the name ("-10% Hoard Money Drops"): the name itself was often misread
    ; ("cur„SE ... oard Konev Drops"), and then the room was skipped as an unknown curse
    static effects := [["m[o]n[e][yv]|[kh]on[e][vy]\b|drops|shop\s*pric|prices", "Money"],
        ["exp[il]|erupt|deaths\s*range", "Exploding"], ["f[il]y[il]ng|f[il]ight", "Flying"],
        ["sh[il]e[il]d", "Shielding"], ["regen", "Regen"], ["hea[il]th|v[il]ta[il]", "Health"], ["\bw[il]nd\b|enemy\s*speed", "Wind"]]
    global lastCurseRaw
    ; the room's panel sits above its Enter button and moves with it: read the curse box there,
    ; enlarged and both ways round (purple text on dark read as garbage with one fixed box)
    txt := ""
    try WinGetClientPos &ox, &oy, , , RBX
    catch
        return ""
    Stale()
    if Det("Enter", &ex, &ey) {
        cx := ex - 3, cy := ey - 32
        x := Max(0, cx - 210), y := Max(0, cy - 230)
        w := Min(800 - x, 420), h := Max(40, cy - 15 - y)
        for tf in [{scale: 3, grayscale: true}, {scale: 3, grayscale: true, invertcolors: true}]
            try txt .= " " OCR.FromRect(ox + x, oy + y, w, h, OcrLang(), tf).Text
    }
    try txt .= " " OCR.FromRect(ox + 110, oy + 130, 570, 340, OcrLang(), {scale: 2, grayscale: true}).Text
    lastCurseRaw := Trim(RegExReplace(txt, "\s+", " "))
    if RegExMatch(txt, "i)curse\s*o\s*f\s*([a-z]{3,})", &m)
        for pr in words
            if RegExMatch(m[1], "i)^(" pr[1] ")")
                return pr[2]
    low := StrLower(txt)
    for pair in [["1", "l"], ["|", "l"], ["0", "o"], ["5", "s"], ["$", "s"]]
        low := StrReplace(low, pair[1], pair[2])
    for pr in effects
        if RegExMatch(low, pr[1])
            return pr[2]
    return ""
}

; curses are ranked worst first; the worst "skipWorst" of them are skipped
AvoidCurse(name) {
    i := IndexOf(cfg["curseRank"], name)
    return i && i <= cfg["skipWorst"]
}

; how bad a room's curse is: 0 = clean ... 9 = your worst
CurseBadness(name) {
    if name = ""
        return 5                                ; cursed, but couldn't tell which: assume it's a bad one
    i := IndexOf(cfg["curseRank"], name)
    return i ? 10 - i : 1
}

EnterRoom() {
    global bossDone, stageActive, dungeonTotal, closeStreak
    Step("entering the room")
    if !WaitDet("Enter", 5000, &ex, &ey) {
        ; maybe it isn't the room picker at all (a shrine / chest screen the pictures missed)
        Stale()
        if ShrineButtons() {
            HandleShrine()
            return
        }
        switch TextScreen() {
            case "Shrine":
                HandleShrine()
                return
            case "Chest":
                AddLog("This is the chest screen, not the room picker")
                SaveDebugShot("chest_screen")
                HandleChests()
                return
        }
        closeStreak++
        AddLog("No Enter button, closing the room picker")
        if closeStreak >= 2
            SaveDebugShot("no_enter")
        ClickDet("RedX", -3, -32, 8000)
        Wait(800)
        return
    }
    closeStreak := 0
    ; is this the last room? the top bar says "DUNGEON DEPTH: 14/20"
    if RoomIsFinal(&at, &total) {
        bossDone := true
        AddLog("Final room (depth " at "/" total ")")
    }
    if total
        dungeonTotal := total
    ; the room's info panel says "Dungeon Room / <map> / Depth: N" before you enter.
    ; It slides in, so keep reading for a moment until the name shows up.
    Step("reading the room panel")
    depth := "", raw := "", roomMap := ""
    t0 := A_TickCount
    loop {
        roomMap := ReadRoomPanel(ex, ey, &depth, &raw)
        if roomMap != "" {
            AddLog("Room panel read: " SubStr(Trim(RegExReplace(raw, "\s+", " ")), 1, 70))
            break
        }
        if A_TickCount - t0 > 2000
            break
        Wait(200)
    }
    ; the bar's "DEPTH: 12/20" is the room you're about to enter; trust it over a misread panel
    if at && (!IsInteger(depth) || Integer(depth) != at)
        depth := at
    if roomMap = ""
        AddLog("Couldn't read the map on the room panel" (raw != "" ? ". It said: " SubStr(Trim(RegExReplace(raw, "\s+", " ")), 1, 70) : " (no text found)"))
    ClickDet("Enter", 0, -30, 15000)
    stat.rooms++
    UpdateStats()
    stageActive := false
    ; the panel's "Depth: 20" (of 20) also means this is the boss room
    if !bossDone && IsInteger(depth) && Integer(depth) >= dungeonTotal {
        bossDone := true
        AddLog("Final room (depth " depth ")")
    }
    LoadStage(roomMap, depth)
}

; =====================================================================
;  Shop / shrine / chests / finish popups
; =====================================================================
SpecialScreen() => Det("Shop") || Det("Shrine") || Det("Chest") || ShrineButtons() || TextScreen() = "Shrine"

; The shrine's yellow ACCEPT and red DENY buttons side by side (the shrine can also be waiting
; in the lobby's DUNGEON RUN window). Plain colours, so it works whatever the font looks like.
; Checked against a recording of the shrine screen and 3150 spots on gameplay screenshots (no false alarms).
ShrineButtons() => ColorShare(366, 394, 470, 420, IsYellowish) >= 0.35 && ColorShare(496, 394, 598, 420, IsReddish) >= 0.35
    && ColorShare(476, 396, 488, 420, IsDarkish) >= 0.8 && ColorShare(360, 430, 600, 448, IsDarkish) >= 0.8
IsYellowish(r, g, b) => r > 190 && g > 140 && b < 110
IsCurseRoom(r, g, b) => b >= r + 12 && b >= g + 25 && r >= g + 5 && b >= 35
IsReddish(r, g, b) => r > 150 && g < 90 && b < 90
IsDarkish(r, g, b) => r + g + b < 170

ShrineGone() => !Det("Shrine") && !ShrineButtons() && TextScreen() != "Shrine"

; share (0..1) of a grid of points in a game-area box whose colour passes test(r, g, b)
ColorShare(x1, y1, x2, y2, test) {
    hits := 0, total := 0
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        px := x1
        while px <= x2 {
            py := y1
            while py <= y2 {
                col := scr.GetColor(ox + px, oy + py, 0) & 0xFFFFFF
                hits += test((col >> 16) & 0xFF, (col >> 8) & 0xFF, col & 0xFF) ? 1 : 0
                total++
                py += 6
            }
            px += 8
        }
    }
    return total ? hits / total : 0
}

; ---------------------------------------------------------------------
;  Reading popups by their words. A backup for when a saved picture stops
;  matching (game updates change fonts / colours), e.g. the shrine screen.
; ---------------------------------------------------------------------
; text in the middle of the game area, upper-cased. One read per screenshot.
ScreenText() {
    static cache := "", key := -1
    Fresh()
    if snapTick && key = snapTick
        return cache
    cache := ""
    try {
        WinGetClientPos &ox, &oy, , , RBX
        cache := OCR.FromRect(ox + 100, oy + 120, 600, 400, OcrLang(), {scale: 1.5, grayscale: true}).Text
        cache := StrUpper(RegExReplace(cache, "\s+", " "))
    }
    key := snapTick
    return cache
}

; "Shrine" / "Chest" when the screen's words say so, otherwise ""
TextScreen() {
    t := ScreenText()
    if t = ""
        return ""
    hits := 0
    for w in ["OFFER", "RECEIVE", "ACCEPT", "DENY"]
        if InStr(t, w)
            hits++
    if hits >= 2 || (hits && RegExMatch(t, "SHR[I1L!|]NE"))
        return "Shrine"
    if RegExMatch(t, "OPEN ?CHESTS")
        return "Chest"
    return ""
}

; the curse in the shrine's offer list ("[*] Curse of Chaos") -> "Chaos"
ShrineKindFromText() {
    static spellings := Map("Armor", "ARMOR", "Burst", "BURST", "Chaos", "CHAOS", "Frenzy", "FRENZY", "Vamparism", "VAMPARISM|VAMPIRISM", "Eruption", "ERUPTION")
    ; the effect line under the name, for when the name is misread
    static effects := [["BURST", "Burst"], ["ARMOU?RED", "Armor"], ["RANDOM", "Chaos"], ["ENEMY ?SPEED", "Frenzy"], ["REGEN", "Vamparism"], ["EXPLOSIVE ?DEATH|DEATH ?RANGE", "Eruption"]]
    ; "You will receive" is a list that scrolls: the curse can be below the visible rows
    loop 4 {
        if A_Index > 1 {
            Clk(510, 300)                       ; on the list, so the wheel scrolls it
            Keys("{WheelDown 3}")
            Wait(450)
        }
        txt := ""
        for area in [[412, 236, 190, 145, {scale: 3, grayscale: true}], [412, 236, 190, 145, {scale: 3, grayscale: true, invertcolors: true}],
            [120, 160, 560, 320, {scale: 2.5, grayscale: true}]] {
            try {
                WinGetClientPos &ox, &oy, , , RBX
                txt .= " " StrUpper(OCR.FromRect(ox + area[1], oy + area[2], area[3], area[4], OcrLang(), area[5]).Text)
            }
        }
        txt := RegExReplace(txt, "\s+", " ")
        if RegExMatch(txt, "CURSE ?[O0]F ?([A-Z]{3,})", &m) {
            best := "", bestD := 3
            for k, spelled in spellings
                for sp in StrSplit(spelled, "|") {
                    d := Levenshtein(sp, m[1])
                    if d < bestD
                        best := k, bestD := d
                }
            if best != ""
                return best
        }
        if InStr(txt, "CURSE")
            for pr in effects
                if RegExMatch(txt, pr[1])
                    return pr[2]
    }
    if IsSet(m) && IsObject(m)
        AddLog("Shrine curse read as '" m[1] "', not one I know")
    return ""
}

; press Accept or Deny: by its picture, or else by finding the word on screen
ClickShrineButton(deny) {
    name := deny ? "ShrineDeny" : "ShrineAccept"
    if Det(name)
        return ClickDet(name, 0, -30, 6000)
    if OcrFindWord(120, 300, 560, 220, deny ? "i)^D[E3]NY" : "i)^ACC[E3]PT", &bx, &by) {
        loop 3 {
            Clk(bx, by)
            if WaitFor(ShrineGone, 1500, 250)
                return true
        }
    }
    ; the buttons always sit here: ACCEPT (yellow) left, DENY (red) right
    if ShrineButtons() {
        loop 3 {
            Clk(deny ? 546 : 417, 407)
            if WaitFor(ShrineGone, 1500, 250)
                return true
        }
    }
    return false
}

; finds a word by reading the screen; gives its middle in game-area coords
; (OCR.ahk gives word positions relative to the box, already un-zoomed)
OcrFindWord(x, y, w, h, re, &cx, &cy) {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        res := OCR.FromRect(ox + x, oy + y, w, h, OcrLang(), {scale: 2, grayscale: true})
        for wd in res.Words {
            if RegExMatch(wd.Text, re) {
                cx := Round(x + wd.x + wd.w / 2), cy := Round(y + wd.y + wd.h / 2)
                return true
            }
        }
    }
    return false
}

; saves one screenshot per kind of problem per session, so it can be sent for fixing
SaveDebugShot(tag) {
    static done := Map()
    if done.Has(tag) || !WinExist(RBX)
        return
    done[tag] := true
    try {
        DirCreate A_ScriptDir "\Logs"
        Snap()
        WinGetPos &wx, &wy, &ww, &wh, RBX
        file := A_ScriptDir "\Logs\" tag "_" FormatTime(, "yyyyMMdd_HHmmss") ".bmp"
        FindText().SavePic(file, wx, wy, wx + ww - 1, wy + wh - 1, 0)
        AddLog("Saved a screenshot of it: Logs\" tag "_....bmp")
    }
}

; ---------- dungeon shop ----------
; every item the shop can sell, best first (the Dungeon page lets you reorder and switch them off)
SHOP_ITEMS() => ["Philosophers Stone", "Mask of Riches", "Golden Mushroom", "Golden Branch", "Genie Lamp",
    "Golden Fishhook", "Fish Hook", "Shimmering Moon Fragment", "Celestial Blade", "Stormbringer", "Scimitar", "Archmage's Hat", "Aures Maul",
    "Magic Tome", "Solar Cleaver", "Headsplitter", "Axe", "Sword", "Mage Coat", "Reaper Scythe", "Glacial Axe", "Ice Dagger",
    "Speedy Boots", "Ninja Belt", "Nimble Cloak", "Elf Bow", "Longbow", "Dagger", "Bow"]
SHOP_MAGIC() => ["Archmage's Hat", "Magic Tome", "Mage Coat"]
SHOP_PHYSICAL() => ["Aures Maul", "Solar Cleaver", "Headsplitter", "Axe"]

; is this item on the buy list? (switched on, and fits the units' damage type)
ShopWanted(name) {
    if name = ""
        return cfg["shopUnknown"]
    if cfg["shopOff"].Has(name) && cfg["shopOff"][name]
        return false
    if cfg["dmgType"] = "Magic" && IndexOf(SHOP_PHYSICAL(), name)
        return false
    if cfg["dmgType"] = "Physical" && IndexOf(SHOP_MAGIC(), name)
        return false
    return true
}

; the shop shows 3 items; each row's price button sits at x 560 and these heights
ShopRowText(y) {
    txt := ""
    for tf in [{scale: 3, grayscale: true}, {scale: 3, grayscale: true, invertcolors: true}] {
        try {
            WinGetClientPos &ox, &oy, , , RBX
            txt .= " " OCR.FromRect(ox + 424, oy + y - 22, 112, 38, OcrLang(), tf).Text
        }
    }
    return txt
}

; which item a shop row is, from its read text ("" = can't tell). The names are a tiny pixel
; font the screen reader often gets wrong ("Bow" came out as "goo"), so the description helps.
ShopRowName(raw) {
    name := FuzzyPick(raw, cfg["shopRank"])
    low := StrLower(raw)
    ; long names wrap onto a second line ("[*] Philosopher's" / "Stone"): a half-read name
    ; still gives itself away by its first word
    if name = "" {
        for kw, full in Map("philos", "Philosophers Stone", "celest", "Celestial Blade", "shimmer", "Shimmering Moon Fragment",
            "archmage", "Archmage's Hat", "stormbr", "Stormbringer", "headspl", "Headsplitter", "riches", "Mask of Riches",
            "reaper", "Reaper Scythe", "scyth", "Reaper Scythe", "solar", "Solar Cleaver", "glacial", "Glacial Axe",
            "mushroom", "Golden Mushroom", "genie", "Genie Lamp", "tome", "Magic Tome", "maul", "Aures Maul",
            "longb", "Longbow", "iongb", "Longbow")
            if InStr(low, kw) && IndexOf(cfg["shopRank"], full) {
                name := full
                break
            }
    }
    if name = "" {
        if RegExMatch(low, "\belf\b")
            name := "Elf Bow"
        else if RegExMatch(low, "\b[hm]a[gq][eo]\s*[ce][o0]")    ; "Hage Coe", "Hago Coa" = Mage Coat
            name := "Mage Coat"
        else if RegExMatch(low, "[rg]an[gq]e")                     ; "+N% Range" and no other clue: a bow
            name := RegExMatch(low, "5\s*0\s*%") ? "Elf Bow" : "Bow"
        if name != "" && !IndexOf(cfg["shopRank"], name)
            name := ""
    }
    ; a "magic damage" line read as Axe (its name is close to "Hage"): Axe is physical crit
    if name = "Axe" && RegExMatch(low, "[mh]a[gq][il1]?[ce]?\s*da|magic") && !RegExMatch(low, "cr[il1]|er[il1]\+")
        name := ""
    ; "Haoie Torw Magic Damage" is Magic Tome ("Torw"), not Mage Coat
    if InStr(low, "torw") && IndexOf(cfg["shopRank"], "Magic Tome")
        name := "Magic Tome"
    ; only the effect was read ("Attack Attack", "Cloak Cloak", "eri+ Chance"): the item from its effect
    if name = ""
        name := ShopByEffect(low)
    ; short names that are the end of longer ones: the description's % tells them apart
    if name = "Fish Hook" && RegExMatch(raw, "4\s*0\s*%")
        name := "Golden Fishhook"
    else if name = "Bow" && RegExMatch(raw, "5\s*0\s*%")
        name := "Elf Bow"
    else if name = "Dagger" && RegExMatch(raw, "i)\b[il1]ce\b|2\s*0\s*%|speed")
        name := "Ice Dagger"                ; Ice Dagger: -20% enemy speed
    else if name = "Ice Dagger" && RegExMatch(raw, "1\s*5\s*%|attack") && !RegExMatch(raw, "i)\b[il1]ce\b")
        name := "Dagger"                    ; Dagger: +15% attack
    else if name = "Axe" && RegExMatch(raw, "i)g[il1]ac|slow|speed|3\s*0\s*%")
        name := "Glacial Axe"
    else if name = "Glacial Axe" && RegExMatch(raw, "i)crit") && !RegExMatch(raw, "i)g[il1]ac")
        name := "Axe"                       ; Axe: +50% physical crit chance
    return name
}

; A shop row from its effect line when the name wasn't read (Nightbubi's macro left his attack and
; cooldown items in the shop as "?"). The % picks the item; with no % read, the effect's items count
; only when you buy every one of them (then it's the one lowest on your list)
ShopByEffect(low) {
    for kw, full in Map("cloak", "Nimble Cloak", "ninja", "Ninja Belt", "eeper", "Reaper Scythe", "eaper", "Reaper Scythe",
        "golden roo", "Golden Mushroom",
        "peedv", "Speedy Boots", "peedy", "Speedy Boots", "boots", "Speedy Boots", "eoo+s", "Speedy Boots")
        if InStr(low, kw)
            return IndexOf(cfg["shopRank"], full) ? full : ""
    ; the %: "SO%" is 50% (S and O misread for 5 and 0)
    pct := RegExMatch(low, "([\dso]{1,3})\s*%", &m) && RegExMatch(m[1], "\d|^so$|^s[o0]{2}$")
        ? Integer(StrReplace(StrReplace(m[1], "s", "5"), "o", "0")) : 0
    for g in [["c[o0]{2}[l1i]\s*d[o0]", Map(7, "Nimble Cloak", 12, "Ninja Belt", 20, "Speedy Boots", 50, "Stormbringer")],
        ["(cr[il1]|er[il1])[t+]?\s*chan", Map(50, "Axe", 100, "Solar Cleaver")],
        ["[mh]a[gq][il1]?[ce]?\b.{0,12}da[tr]|magic", Map(50, "Mage Coat", 100, "Magic Tome", 250, "Archmage's Hat")],
        ["a[t+]{2}ac?k", Map(15, "Dagger", 30, "Sword", 75, "Scimitar")],
        ["[rg]an[gq]e", Map(20, "Bow", 30, "Longbow", 50, "Elf Bow")]] {
        if !RegExMatch(low, g[1])
            continue
        if g[2].Has(pct)
            return IndexOf(cfg["shopRank"], g[2][pct]) ? g[2][pct] : ""
        worst := "", at := 0
        for , full in g[2] {
            if !ShopWanted(full)
                return ""
            if (i := IndexOf(cfg["shopRank"], full)) > at
                worst := full, at := i
        }
        return worst
    }
    return ""
}

ReadShopRows() {
    rows := []
    for y in [225, 280, 335] {
        raw := ShopRowText(y)
        rows.Push({y: y, name: ShopRowName(raw), raw: raw})
    }
    return rows
}

HandleShop() {
    Step("shop")
    Wait(700)
    if !cfg["buyShop"] {
        AddLog("Shop: skipping (buying is off)")
    } else {
        rows := ReadShopRows()
        named := 0, shopRead := ""
        for r in rows {
            named += r.name != "" ? 1 : 0
            shopRead .= (shopRead = "" ? "" : "  |  ") (r.name != "" ? r.name : "?") " (read: " SubStr(Trim(RegExReplace(r.raw, "\s+", " ")), 1, 30) ")"
        }
        AddLog("Shop rows: " shopRead)
        SaveDebugShot("shop_seen")                  ; one per session, to check the item reading
        if !named {
            ; couldn't read any item: buy all three only if you allow items it can't read
            if cfg["shopUnknown"] {
                AddLog("Shop: couldn't read the items, buying everything")
                for y in [335, 280, 225]
                    Clk(560, y), Wait(700)
            } else {
                AddLog("Shop: couldn't read the items, skipping (turn on 'Also buy items it can't read' to buy anyway)")
                SaveDebugShot("shop")
            }
        } else {
            ; best wanted item first; read the rows again after each buy (a sold item may move the others)
            tried := Map(), picked := "", skipped := ""
            loop 3 {
                if A_Index > 1
                    rows := ReadShopRows()
                pick := 0
                for r in rows {
                    if tried.Has(r.name)
                        continue
                    if !ShopWanted(r.name) {
                        if r.name != "" && !InStr(", " skipped ", ", ", " r.name ", ")
                            skipped .= (skipped = "" ? "" : ", ") r.name
                        continue
                    }
                    rank := r.name = "" ? 999 : IndexOf(cfg["shopRank"], r.name) || 500
                    if !pick || rank < pick.rank || (rank = pick.rank && r.y > pick.y)
                        pick := {y: r.y, name: r.name, rank: rank}
                }
                if !pick
                    break
                tried[pick.name] := true
                Clk(560, pick.y), Wait(900)
                picked .= (picked = "" ? "" : ", ") (pick.name = "" ? "an item it couldn't read" : pick.name)
            }
            AddLog("Shop: " (picked != "" ? "picked " picked : "nothing on your list") (skipped != "" ? ". Skipped " skipped : ""))
        }
    }
    Clk(485, 410)
    ClickDungeonContinue()
    WaitFor(() => !Det("Shop"), 1500)
}

; Picks which of `names` the text is about, allowing for misread letters (same idea as
; MatchMapName). Answers "" when unsure. A longer name wins a tie ("Elf Bow" over "Bow").
FuzzyPick(txt, names) {
    words := []
    for w in StrSplit(Trim(RegExReplace(StrLower(txt), "[^a-z]+", " ")), " ")
        if w != ""
            words.Push(w)
    if !words.Length
        return ""
    toks := []
    for i, w in words {
        glued := ""
        loop 3 {
            k := i + A_Index - 1
            if k > words.Length
                break
            glued .= words[k]
            toks.Push({txt: FoldOcr(glued), first: i, last: k})
        }
    }
    bestName := "", best := 9, second := 9, bestLen := 0
    for name in names {
        nws := []
        for w in StrSplit(Trim(RegExReplace(StrLower(name), "[^a-z]+", " ")), " ")
            if w != ""
                nws.Push(FoldOcr(w))
        whole := ""
        for nw in nws
            whole .= nw
        if whole = ""
            continue
        total := 0, pos := 0, ok := true
        for nw in nws {
            low := 9, lowEnd := 0, slack := Max(1, StrLen(nw) // 3)
            for tk in toks {
                if tk.first <= pos || Abs(StrLen(tk.txt) - StrLen(nw)) > slack
                    continue
                cost := Levenshtein(tk.txt, nw) / StrLen(nw)
                if cost < low
                    low := cost, lowEnd := tk.last
            }
            if low > (StrLen(nw) <= 3 ? 0 : 0.34) {  ; 3 letters: exact ("age" in "damage" isn't "Axe")
                ok := false
                break
            }
            total += low * StrLen(nw), pos := lowEnd
        }
        slack := Max(1, StrLen(whole) // 3)
        for tk in toks {
            if Abs(StrLen(tk.txt) - StrLen(whole)) > slack
                continue
            cost := Levenshtein(tk.txt, whole) / StrLen(whole)
            if cost <= 0.25 && (!ok || cost * StrLen(whole) < total)
                ok := true, total := cost * StrLen(whole)
        }
        if !ok
            continue
        score := total / StrLen(whole)
        if score < best || (score = best && StrLen(whole) > bestLen)
            second := (score < best ? best : second), best := score, bestName := name, bestLen := StrLen(whole)
        else if score < second
            second := score
    }
    if bestName != "" && best > 0 && second - best < 0.08
        return ""
    return bestName
}

HandleShrine() {
    static kinds := 0
    if !IsObject(kinds)
        kinds := Map("Armor", CurseOfArmor, "Burst", CurseOfBurst, "Chaos", CurseOfChaos,
            "Frenzy", CurseOfFrenzy, "Vamparism", CurseOfVamparism)
    Step("shrine")
    Wait(300)                                  ; the panel slides in
    kind := ""
    for name, pat in kinds {
        if Seen(327, 320, 506, 484, pat, 0.1) {
            kind := name
            break
        }
    }
    if kind = ""
        kind := ShrineKindFromText()
    deny := cfg["denyAllShrines"]
        || (kind = "" && cfg["denyUnknownShrine"])
        || (kind != "" && cfg["denyShrine"].Has(kind) && cfg["denyShrine"][kind])
    label := kind = "" ? "unknown shrine" : "shrine of " kind
    AddLog((deny ? "Denied " : "Accepted ") label)
    if !ClickShrineButton(deny) {
        AddLog("Couldn't find the " (deny ? "Deny" : "Accept") " button on the shrine")
        SaveDebugShot("shrine")
        Wait(1000)
        return
    }
    WaitFor(ShrineGone, 1500, 250)
}

HandleChests() {
    global bossDone, chestsDone
    ; the stage we just played was the last room (depth read from its banner / room panel)
    if !bossDone && IsInteger(curDepth) && Integer(curDepth) >= dungeonTotal {
        bossDone := true
        AddLog("That was the last room (depth " curDepth "), opening the saved chests")
    }
    if !(bossDone || !cfg["saveChests"]) {
        AddLog("Saving chests for after the boss")
        ; if this was the last room the game now asks "Leave Dungeon?" - the popup
        ; handler cancels that and comes back here to open the chests first
        ClickDungeonContinue()
        WaitFor(() => !Det("Chest") || LeavePopupUp(), 1500)
        return
    }
    Step("opening chests")
    n := OpenChestSlot(565, 260) + OpenChestSlot(565, 320)
    stat.chests += n
    UpdateStats()
    AddLog("Opened " n " chest" (n = 1 ? "" : "s"))
    chestsDone := true
    ClickDungeonContinue()
    WaitFor(() => !Det("Chest") || LeavePopupUp(), 1500)
}

OpenChestSlot(x, y) {
    opened := 0
    loop 30 {
        Clk(x, y)
        ; still on the chest screen after a moment = this chest is empty
        if !WaitFor(() => !Det("Chest"), 1500)
            break
        CollectRewards()                        ; what it gave (read before it's clicked away)
        opened++
    }
    return opened
}

; ---------- chest rewards ----------
; After a chest opens, the reward shows big in the middle with its name under it and the rarity
; under that: "Star Remnant (Limited) (x2)" / "Mythic", "Gems (x150)" / "Common", or a unit with
; no amount: "Snow Reaper (War)" / "Secret". During a 2x event one chest shows two rewards, one
; after the other. They're read before being clicked away, added up for the session (the
; Dashboard) and logged; a Secret unit also gets a popup and a webhook message.
global chestLoot := Map()       ; reward name -> how many since Start
global lostRooms := Map(), lastRoomI := 0   ; defeats per room at the current choice (Room 2 -> 2), the room last entered
global dungeonLoot := Map()     ; the same for the dungeon being played (sent with "Dungeon cleared")

; one look at the reward text: {name, n, rarity} or "" when there's none on screen
ReadRewardText() {
    for tf in [{scale: 2, grayscale: true}, {scale: 2, grayscale: true, invertcolors: true}] {
        txt := ""
        try {
            WinGetClientPos &ox, &oy, , , RBX
            txt := OCR.FromRect(ox + 180, oy + 330, 440, 190, OcrLang(), tf).Text   ; just the middle:
        }                                       ; name tags of units around it got read into the name
        if IsObject(r := ParseReward(txt))
            return r
    }
    return ""
}

; the reward in the read text: "Name (x5)" / "Name (Limited) (x5)", or a unit (no amount) as the
; line right above its rarity ("Snow Reaper (War)" / "Secret")
ParseReward(txt) {
    static rarities := "i)^\W*([s5]ecr[e3]t|myth[il1]c|legendary|ep[il1]c|rare|uncommon|common|exclusive|celestial|divine)\b"
    if Trim(txt) = ""
        return ""
    lines := []
    for ln in StrSplit(txt, "`n", "`r")
        if Trim(ln) != ""
            lines.Push(Trim(ln))
    rarity := "", at := 0
    for i, ln in lines
        if RegExMatch(ln, rarities, &rm) {
            rarity := StrTitle(RegExReplace(RegExReplace(RegExReplace(rm[1], "^5", "s"), "3", "e"), "[1l](?=c)", "i")), at := i
            break
        }
    if RegExMatch(txt, "i)([A-Za-z][A-Za-z' ]*?(?:\s*\(\s*[A-Za-z][A-Za-z ]*\))?)\s*\(\s*[x×]\s*(\d[\d,. ]*)\)", &m) {
        name := RewardName(m[1]), n := RegExReplace(m[2], "\D")
        if name != "" && n != "" && Integer(n) > 0
            return {name: name, n: Integer(n), rarity: rarity}
    }
    if at > 1 {
        name := Trim(RegExReplace(lines[at - 1], "[^A-Za-z0-9'(),. ]"))
        n := 1
        ; an amount whose bracket got lost in reading: "Star Remnant (x5"
        if RegExMatch(name, "i)^(.*?)\s*\(?\s*[x×]\s*(\d[\d,.]*)\s*\)?\s*$", &mm) && Trim(mm[1]) != ""
            name := RewardName(mm[1]), n := Integer(RegExReplace(mm[2], "\D"))
        if StrLen(name) >= 3 && !InStr(name, "click") && n > 0
            return {name: name, n: n, rarity: rarity}
    }
    ; no rarity read: its coloured letters over the sparkles were never read in players' logs, so a
    ; Secret unit (no amount) went unseen. Its name is the line above "(Click anywhere to continue)",
    ; or above a half-read rarity. No amount and not a chest item = a unit, and only Secret units
    ; drop from chests ("Rare Chests have a chance to drop a Secret Unit")
    if !at {
        for i, ln in lines {
            if !RegExMatch(ln, "i)click\s*anywhere")
                continue
            j := i - 1
            if j >= 1 && StrLen(NormName(lines[j])) < 6 && j > 1   ; a scrap of the rarity ("S ecr")
                j--
            if j < 1
                break
            name := Trim(RegExReplace(lines[j], "[^A-Za-z0-9'(),. ]"))
            item := false                       ; a chest item whose amount wasn't read
            for k in ChestItems()
                item := item || RewardName(name) = k
            if StrLen(NormName(name)) >= 6 && !item
                return {name: name, n: 1, rarity: "Secret"}
            break
        }
    }
    return ""
}

; The reward's real name in what was read. Stray words come BEFORE it (a unit's name tag on the
; same line: "Abyss Abyss Jelly Gems"), so a known reward is matched against the END of the text,
; longest names first ("Perfect Stat Cube" before "Stat Cube"). Misreads stack with the right
; one ("Ab Star Rermant (Limited)", "t (Limited)" -> Star Remnant (Limited)). Something unknown
; keeps its last few words; a scrap like "hts" gives "" (not counted).
ChestItems() => ["Star Remnant (Limited)", "Perfect Stat Cube", "Trait Crystal", "Cursed Token", "Stat Cube", "Gems"]

RewardName(raw) {
    known := ChestItems()
    flat := NormName(raw)
    if flat = ""
        return ""
    for k in known {
        kf := NormName(k)
        tail := StrLen(flat) > StrLen(kf) ? SubStr(flat, -StrLen(kf)) : flat
        if Levenshtein(tail, kf) / StrLen(kf) <= 0.25
            return k
    }
    if InStr(flat, "limited")                   ; only the end was read: the one "(Limited)" reward
        return "Star Remnant (Limited)"
    words := StrSplit(Trim(RegExReplace(raw, "[^A-Za-z0-9'() ]+", " ")), " ")
    clean := ""
    loop Min(3, words.Length)
        clean := Trim(words[words.Length - A_Index + 1] " " clean)
    return StrLen(NormName(clean)) >= 5 ? clean : ""
}

; waits up to ms for a reward to show up and returns it ("" if none came)
ReadChestReward(ms := 2500) {
    t0 := A_TickCount
    loop {
        if IsObject(r := ReadRewardText())
            return r
        if A_TickCount - t0 > ms
            return ""
        Wait(200)
    }
}

; one opened chest: every reward it shows (two during a 2x event), then back to the chest screen.
; A reward counts as new when it's a different one, or when the text was gone for a while (the
; next reveal). Sparkles hide the text for a moment too: the same reward read again right after
; that counted twice ("Gems x450" and "hts x450")
CollectRewards() {
    last := ReadChestReward(2500)
    if !IsObject(last)
        return ClaimReward()                    ; nothing readable: just click through as before
    AddLoot(last)
    loop 6 {
        Clk(560, 560)
        t0 := A_TickCount, gone := 0            ; gone: when the text went away
        loop {
            Wait(150)
            Stale()
            if Det("Chest")
                return true                     ; back on the chest screen
            if Det("EndScreen")
                return ClaimReward()            ; the "max cursed tokens" popup
            r := ReadRewardText()
            if !IsObject(r) {
                if !gone
                    gone := A_TickCount
            } else if r.name != last.name || r.n != last.n || (gone && A_TickCount - gone >= 600) {
                AddLoot(r), last := r
                break                           ; the next reward: click that one away too
            } else
                gone := 0                       ; the same one, only hidden for a moment
            if A_TickCount - t0 > 3000
                break                           ; the same one for 3 s: the click didn't take
        }
    }
    return ClaimReward()
}

; adds a reward to the session totals (a slightly misread name joins the one it's close to)
AddLoot(r) {
    global chestLoot
    key := r.name, norm := NormName(r.name)
    for k in chestLoot
        if NormName(k) = norm || Levenshtein(NormName(k), norm) <= 2 {
            key := k
            break
        }
    chestLoot[key] := chestLoot.Get(key, 0) + r.n
    dungeonLoot[key] := dungeonLoot.Get(key, 0) + r.n
    AddLog("Chest: " key " x" r.n (r.rarity != "" ? "  (" r.rarity ")" : ""))
    if r.rarity = "Secret" && r.n = 1 {
        AddLog("*** SECRET UNIT: " key " ***")
        SaveDebugShot("secret_unit")            ; a picture of it in Logs (to check the read)
        Notify("Secret unit: " key "!")
        SendWebhook("Secret unit!", "**" key "** dropped from a chest", 0xF59E0B)
        ShowcaseDrop(key, "chest")              ; Premium: posted in Chris's Discord (Settings)
    }
    LootChanged()
}

; the session totals, most first: [[name, count], ...]
; "Gems x1,200 · Trait Crystal x3 · ..." (most first), cut to fit a Discord field
LootText(loot) {
    if !loot.Count
        return "Nothing from chests"
    out := ""
    for e in LootList(loot) {
        part := e[1] " x" RegExReplace(e[2], "\G\d+?(?=(\d{3})+$)", "$0,")
        if StrLen(out) + StrLen(part) > 1000
            return out " · ..."
        out .= (out = "" ? "" : " · ") part
    }
    return out
}

LootList(loot := "") {
    if !IsObject(loot)
        loot := chestLoot
    out := []
    for name, n in loot {
        i := out.Length + 1
        while i > 1 && out[i - 1][2] < n
            i--
        out.InsertAt(i, [name, n])
    }
    return out
}

ClaimReward() {
    loop 40 {
        Clk(560, 560)
        if WaitFor(() => Det("Chest") || Det("EndScreen"), 700, 100) {
            if Det("Chest")
                return true
            Clk(490, 120)          ; closes the "max cursed tokens" popup
            WaitFor(() => Det("Chest"), 1500)
            return true
        }
    }
    return false
}

; presses Continue on the chest / shop screen. Stops if the "Leave Dungeon?" popup comes up:
; whether to Finish or Cancel there is up to HandleDungeonPopups.
ClickDungeonContinue() {
    t0 := A_TickCount
    while Det("DungeonContinue", &fx, &fy) {
        if A_TickCount - t0 > 30000 || LeavePopupUp()
            break
        Clk(fx - 3, fy - 35)
        WaitFor(() => !Det("DungeonContinue") || LeavePopupUp(), 1000)
    }
}

; "Leave Dungeon? You are at the last Room of the Dungeon! Make sure you open all your
; Chests before leaving."  with a green Finish and an orange Cancel button
LeavePopupUp() => Det("FinishDungeon") || Det("FinishText") || Det("FinishButton")

; finds the green Finish and the orange Cancel button side by side
FindLeaveButtons(&fx, &fy, &cx, &cy) {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        gX := [], cX := [], ys := []
        py := 250
        while py <= 450 {
            runs := [], was := "", runFrom := 0, px := 150
            while px <= 702 {
                kind := ""
                if px <= 700 {
                    col := scr.GetColor(ox + px, oy + py, 0) & 0xFFFFFF
                    r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
                    kind := g > 160 && g > r + 40 && b < 120 ? "g" : r > 190 && g < 150 && b < 100 && r - g >= 80 ? "o" : ""
                }
                if kind !== was {
                    if was != "" {
                        if runs.Length && runs[runs.Length][1] == was && runFrom - runs[runs.Length][3] <= 14
                            runs[runs.Length][3] := px - 2
                        else
                            runs.Push([was, runFrom, px - 2])
                    }
                    was := kind, runFrom := px
                }
                px += 2
            }
            for i, gr in runs {
                if gr[1] !== "g" || gr[3] - gr[2] < 60
                    continue
                j := i + 1
                while j <= runs.Length {
                    orr := runs[j]
                    if orr[2] - gr[3] > 40
                        break
                    if orr[1] == "o" && orr[3] - orr[2] >= 60 {
                        gX.Push((gr[2] + gr[3]) // 2), cX.Push((orr[2] + orr[3]) // 2), ys.Push(py)
                        break
                    }
                    j++
                }
            }
            py += 3
        }
        if ys.Length < 3
            return false
        fx := MiddleOf(gX), cx := MiddleOf(cX), fy := MiddleOf(ys), cy := fy
        return true
    }
    return false
}

; answer the "Leave Dungeon?" popup: Finish (finish := true) or Cancel
AnswerLeave(finish) {
    loop 4 {
        if !LeavePopupUp()
            return true
        if FindLeaveButtons(&fx, &fy, &cx, &cy) {
            if finish
                Clk(fx, fy)
            else
                Clk(cx, cy)
        } else if finish && Det("FinishButton", &bx, &by)
            Clk(bx - 3, by - 35)
        else if finish
            Clk(298, 345)                               ; where the buttons sit (from your photo)
        else
            Clk(459, 345)
        if WaitFor(() => !LeavePopupUp(), 1500)
            return true
    }
    SaveDebugShot(finish ? "leave_finish" : "leave_cancel")
    return false
}

HandleDungeonPopups() {
    global bossDone, chestsDone
    static lastCleared := 0, cancels := 0, firstCancel := 0
    if LeavePopupUp() {
        ; at the last room with chests still saved up: cancel, open them, then finish
        if cfg["saveChests"] && !chestsDone {
            if A_TickCount - firstCancel > 180000
                cancels := 0, firstCancel := A_TickCount
            if ++cancels <= 3 {
                AddLog("Last room: opening the saved chests before leaving")
                bossDone := true
                AnswerLeave(false)
                WaitFor(() => Det("Chest"), 2500)
                return true
            }
            AddLog("Couldn't get back to the chests, finishing the dungeon")
        }
        Step("finishing the dungeon")
        AnswerLeave(true)
        Wait(1500)
        ; count it once (the popup can be seen more than once while it closes)
        if A_TickCount - lastCleared > 120000 {
            stat.dungeons++
            UpdateStats()
            AddLog("Dungeon cleared!")
            ; what the chests gave: this dungeon, and everything since Start
            SendWebhook("Dungeon cleared", Summary(), 0x22C55E,
                [["Rewards this dungeon", LootText(dungeonLoot)], ["Since Start", LootText(chestLoot)]])
            global dungeonLoot := Map(), lostRooms := Map(), lastRoomI := 0   ; a new dungeon: its rewards and room losses start over
        }
        lastCleared := A_TickCount, cancels := 0
        chestsDone := false, bossDone := false
        if !Det("EndScreen")
            Clk(666, 145)                       ; the dungeon window's X
        WaitFor(() => Det("EndScreen") || Det("Lobby") || EndButtonsSeen(true), 3000)
        ; a new dungeon can only be started from the lobby: "Open Dungeon" here only brought up
        ; the Dungeon Run window, whose "Enter Dungeon" does nothing outside the lobby
        BackToLobby()
        return true
    }
    if Det("DungeonDeath") {
        static deaths := 0, deathFirst := 0
        if A_TickCount - deathFirst > 90000
            deaths := 0, deathFirst := A_TickCount
        if ++deaths = 1
            AddLog("Out of lives in this dungeon, starting a new one")
        ; still in the dungeon (its Return to lobby / Open Dungeon buttons, or the wave bar): a
        ; new dungeon only starts from the lobby. Pressing Continue or Open Dungeon here just
        ; brought this screen back, over and over. Back to the lobby first, the lobby opens a new one
        if !Det("Lobby") && (EndButtonsSeen(true) || InStageWorld()) {
            if WaitDet("RedX", 800)
                ClickDet("RedX", -3, -35)       ; the popup off the buttons
            Wait(500)
            Stale()
            if BackToLobby() {
                bossDone := false, chestsDone := false
                deaths := 0
                return true
            }
        }
        ; its button: by picture, or by its text, or where it usually is (on some PCs the
        ; picture didn't match and this repeated every 2 seconds)
        if Det("DeathContinue")
            ClickDet("DeathContinue", 0, -30)
        else if OcrFindWord(120, 300, 560, 180, "i)^(continue|new|start|retry|ok)", &bx, &by)   ; not "Open" (Open Dungeon)
            Clk(bx, by)
        else
            Clk(396, 383)
        bossDone := false, chestsDone := false
        if WaitFor(() => !Det("DungeonDeath"), 4000, 250) {
            ; it went: close the Dungeon Run window that can stay open behind it
            if WaitDet("RedX", 1500)
                ClickDet("RedX", -3, -35)
            Wait(500)
            return true
        }
        ; "You Died!" still there after Continue (it stayed for hours on some games, and the red
        ; X clicked right after Continue only brought it back): Roblox is closed and opened again,
        ; which always lands in the lobby, and the macro starts a new dungeon from there
        if deaths >= 3 {
            AddLog("The out-of-lives screen won't go away, rejoining Roblox to get back to the lobby")
            SaveDebugShot("out_of_lives")
            deaths := 0
            RejoinToLobby()
        }
        return true
    }
    return false
}

; =====================================================================
;  Inside a stage
; =====================================================================
; lenient: the round may already be playing (loaded behind Fool's Hunt's freeze), so the green
; wave bar counts as loaded too (by its colour range; otherwise only right after a teleport)
LoadStage(knownMap := "", knownDepth := "", lenient := false) {
    global curMap, curDepth, mapHow, stageActive
    ; a new stage: fresh units, vote and placing. (A stage stopped half-way with F3 stayed
    ; "active", so the next stage skipped the vote and placing and looked for the old units)
    stageActive := false
    Step("loading the map")
    curMap := knownMap != "" ? knownMap : "Unknown", curDepth := knownDepth
    UpdateMapLabel()
    if knownMap != ""
        AddLog("Map: " knownMap (knownDepth != "" ? ", depth " knownDepth : "") "  (from the room panel)")
    ; the loading screen double-checks the room panel: its map name (picture or text) wins if
    ; they disagree (a misread panel once turned Snowy Kingdom into Cursed Festival)
    checked := knownMap = ""
    t0 := A_TickCount, waitShot := false
    loop {
        Snap()
        if curMap = "Unknown" || !checked {
            name := MatchLoadingScreen()
            if name = "" && curMap = "Unknown"
                name := MapFromBanner(), mapHow := "map banner"
            if name != "" && curMap = "Unknown" {
                curMap := name
                AddLog("Map: " name (curDepth != "" ? ", depth " curDepth : "") "  (" mapHow ", " Round((A_TickCount - t0) / 1000, 1) "s)")
                UpdateMapLabel()
            } else if name != "" && mapHow != "scenery picture" {
                checked := true
                if name != curMap {
                    AddLog("The room panel said " curMap ", the loading screen says " name ". Going with " name)
                    curMap := name
                    UpdateMapLabel()
                }
            }
        }
        if IsLoaded() || (lenient && InStageWorld())
            break
        ; the room picker stays up for a moment after pressing Enter, so only treat it
        ; as "we didn't actually enter" once a few seconds have passed
        if A_TickCount - t0 > 6000 && (SpecialScreen() || ScanRooms().Length || Det("FinishDungeon"))
            return
        if A_TickCount - t0 > 30000 && !waitShot {
            waitShot := true                    ; a picture of what it's waiting on
            AddLog("Still waiting for the stage after 30s. Send Logs\load_wait_....bmp in Discord if it stays like this")
            SaveDebugShot("load_wait")
        }
        if A_TickCount - t0 > 120000 {
            AddLog("The map took over 2 minutes to load")
            return
        }
        if CheckConnection()
            return
        Wait(150)
    }
    if curMap = "Unknown" {
        said := Trim(RegExReplace(lastMapRaw, "\s+", " "))
        AddLog("Couldn't tell which map this is, using the auto pattern" (said != "" ? ". Last text read: " SubStr(said, 1, 80) : ""))
        SaveDebugShot("map_unknown")
    }
    if !cfg["useBuild"] && cfg["build"].Length {
        static buildTold := false
        if !buildTold
            buildTold := true, AddLog("Your build order has " cfg["build"].Length " steps but it's switched off (Build tab), so the Units tab is used")
    }
    PlayStage()
}

; all loading screens are checked against one screenshot
; 1) read the "Traveling to... <map>" text on the loading screen (Windows' built-in OCR)
; 2) fall back to matching loading-screen pictures
MatchLoadingScreen() {
    global mapHow
    name := MapFromLoadingText(), mapHow := "loading screen text"
    if name != ""
        return name
    name := MapFromNamePics(), mapHow := "map name picture"
    if name != ""
        return name
    mapHow := "scenery picture"
    Snap()
    ; Only the detailed pictures are used. Low-detail ones (dark or plain patches of scenery)
    ; "matched" other maps once the map itself showed: Spirit Town was taken for Rain Village and
    ; Snowy Kingdom for Cursed Festival. The map-name pictures (MapFromNamePics) and the text
    ; reading cover those maps instead. The looser search only uses the most detailed ones.
    static strong := "|aircraft|antkingdom3|antkingdomraid|assassinpark|dungeonthrone2|fabledkingdom|magichill3|magichills2|magictown|planetgreenie|rainvillage2|sacredplanet|spacecenter2|spirittown2|virtualdungeon2|"
    static detailed := "|aircraft|antkingdomraid|dungeonthrone2|fabledkingdom|magichill3|magichills2|planetgreenie|rainvillage2|sacredplanet|spacecenter2|spirittown2|virtualdungeon2|"
    static lists := 0, sharp := 0
    if !IsObject(lists) {
        lists := Map(), sharp := Map()
        for name, files in LoadingScreens() {
            paths := [], good := []
            for f in files {
                if !InStr(strong, "|" f "|") || !FileExist("Images\loading_screens\" f ".png")
                    continue
                paths.Push("Images\loading_screens\" f ".png")
                if InStr(detailed, "|" f "|")
                    good.Push("Images\loading_screens\" f ".png")
            }
            if paths.Length
                lists[name] := paths
            if good.Length
                sharp[name] := good
        }
    }
    ; 1) exact match
    for name, paths in lists
        if ImgFind(paths, 0, 0, 800, 600, &ix, &iy)
            return name
    ; 2) a little looser, but only trusted when exactly one map fits
    found := ""
    for name, paths in sharp {
        if ImgFind(paths, 0, 0, 800, 600, &ix, &iy, 20, 0.04) {
            if found != ""
                return ""                       ; two maps fit: not sure yet, check again next time
            found := name
        }
    }
    return found
}

; the map's name in big letters on the loading screen, matched as pictures (Ryn's patterns).
; No text reading needed, so it also works on PCs whose text reader isn't English.
MapFromNamePics() {
    static pics := 0
    if !IsObject(pics)
        pics := [
            ["Sacred Planet", SacredPlanet],
            ["Planet Greenie", PlanetGreenie],
            ["Walled City", WalledCity],
            ["Snowy Town", SnowyTown],
            ["Sand Village", Sand],
            ["Navy Bay", Navy],
            ["Fiend City", Fiend],
            ["Spirit World", Spirit],
            ["Ant Kingdom", Ant],
            ["Magic Town", MagicTown],
            ["Magic Hills", MagicHills],
            ["Haunted Academy", Academy],
            ["Alien Spaceship", AlienSpaceship],
            ["Space Center", SpaceCenter],
            ["Fabled Kingdom", Fabled],
            ["Ruined City", Ruined],
            ["Puppet Island", Puppet],
            ["Virtual Dungeon", Virtual],
            ["Snowy Kingdom", SnowyKingdom],
            ["Dungeon Throne", DungeonThrone],
            ["Rain Village", RainVillage],
            ["Spirit Town", SpiritTown],
            ["Mountain Temple", Mount],
            ["Cursed Festival", Cursed],
            ["Nightmare Train", Nightmare],
            ["Air Craft", AirCraft],
            ["Hellish City", Hellish],
            ["Shibuya District", Shibuya],
            ["Storm Hideout", Storm]
        ]
    for pr in pics
        if FT(&fx, &fy, 10, 90, 415, 160, 0, 0, pr[2])
            return pr[1]
    return ""
}

; The game is in English, but Windows reads text in the PC's own language: on a Korean PC
; "Spirit World" and the yen came out as garbage. Use Windows' English reader when it has one.
; Windows' own text reader (Windows.Media.Ocr) isn't on every PC: "Class not registered" = it's
; missing (Windows N without the Media Feature Pack, or a stripped-down "lite" Windows). Everything
; that reads text then fails: map names, the shop, Teleport to Spawn, curses, chest rewards
OcrMissing(err) {
    static told := false
    if told
        return
    told := true
    AddLog("Windows' text reader doesn't work on this PC (" err.Message "). The macro carries on with pictures only, "
        . "but map names, the shop, Teleport to Spawn and chest rewards can fail. Fix: Windows Settings > Apps > "
        . "Optional features > add 'Media Feature Pack' (Windows N), then restart the PC. A 'lite' or debloated Windows can be missing it for good")
}

OcrLang() {
    static lang := ""
    if lang != ""
        return lang
    for l in ["en-US", "en-GB", "en-AU", "en-CA", "en-IN"] {
        try {
            OCR.LoadLanguage(l)
            return lang := l
        }
    }
    lang := "FirstFromAvailableLanguages"
    ; a reader for another language with the same alphabet (Norwegian, German, Spanish...)
    ; reads the game fine. Only PCs set to a different alphabet need English added.
    try {
        prim := Integer("0x" A_Language) & 0x3FF
        ; Arabic, Bulgarian, Chinese, Greek, Hebrew, Japanese, Korean, Russian, Thai, Ukrainian, Hindi, Persian
        for id in [0x01, 0x02, 0x04, 0x08, 0x0D, 0x11, 0x12, 0x19, 0x1E, 0x22, 0x39, 0x29]
            if prim = id {
                AddLog("Your Windows language uses a different alphabet, so map names and yen can be misread. Fix: Windows Settings > Time & language > Language > Add a language > English (United States), then restart the macro.")
                break
            }
    }
    return lang
}

; reads "DUNGEON DEPTH: 14/20" on the room picker. True when this is the last room.
RoomIsFinal(&at := 0, &total := 0) {
    at := 0, total := 0
    try {
        WinGetClientPos &ox, &oy, , , RBX
        txt := OCR.FromRect(ox, oy, 800, 230, OcrLang(), {scale: 2, grayscale: true}).Text
    } catch
        return false
    ; only the numbers right after "DEPTH" (the health bar "81120/81120" also has a slash in it)
    if !RegExMatch(txt, "i)D\s*E\s*P\s*T\s*H\W{0,4}(?:[a-z]{1,6}\W{0,4})?(?<!\d)(\d{1,2})\s*/\s*(\d{1,2})(?!\d)", &m)
        return false
    if Integer(m[2]) < 10 || Integer(m[2]) > 40 || Integer(m[1]) < 1 || Integer(m[1]) > Integer(m[2])
        return false                                ; not a believable "room N of M"
    at := Integer(m[1]), total := Integer(m[2])
    return at >= total
}

; the big blue "<map> / Dungeon Room (Depth N) / Hard" banner at the top-middle when a stage starts
MapFromBanner() {
    global curDepth
    depth := "", raw := ""
    for tf in [{scale: 2, grayscale: true}, {scale: 2, grayscale: true, invertcolors: true}] {
        name := MapFromScreenText(150, 85, 500, 150, &depth, &raw, tf)
        if name != "" {
            if depth != ""
                curDepth := depth
            return name
        }
    }
    return ""
}

; The room panel ("Dungeon Room / <map> / Depth: N") sits right above its Enter button.
; It's a small pixel font, so read just that box, enlarged, and try inverted colours too.
ReadRoomPanel(ex, ey, &depth := "", &raw := "") {
    cx := ex - 3, cy := ey - 32                   ; Enter button centre in game-area coords
    x := Max(0, cx - 210), y := Max(0, cy - 230)
    w := Min(800 - x, 420), h := Max(40, cy - 15 - y)
    for tf in [{scale: 3, grayscale: true}, {scale: 3, grayscale: true, invertcolors: true}, {scale: 2}] {
        name := MapFromScreenText(x, y, w, h, &depth, &raw, tf)
        if name != ""
            return name
    }
    return ""
}

; OCR a part of the game area (client coords) and find a known map name + depth in it
MapFromScreenText(x, y, w, h, &depth := "", &raw := "", tf := "") {
    global lastMapRaw, icFloor
    static warned := false
    raw := "", depth := ""                      ; always set: a banner without "Depth N" (Fool's Hunt) left
                                                ; depth unset and stopped the run ("local variable ... line 3130")
    if !WinExist(RBX)
        return ""
    if !IsObject(tf)
        tf := {scale: 1.5, grayscale: true}
    try {
        WinGetClientPos &ox, &oy, , , RBX
        raw := OCR.FromRect(ox + x, oy + y, w, h, OcrLang(), tf).Text
        if Trim(raw) != ""
            lastMapRaw := raw
    } catch as err {
        if !warned {
            warned := true
            OcrMissing(err)
        }
        return ""
    }
    ; the panel has the dungeon's progress at the top ("DUNGEON DEPTH: 11/20") and the room's own
    ; "Depth: 12" further down: the room's is the one wanted ("DEPTH: 1?/20 ... Depth» 12" was taken as 1).
    ; So the last "depth N" that isn't an "N/20"
    pos := 1
    while pos := RegExMatch(raw, "i)depth\D{0,4}(\d(?: ?\d)?)(?!\d)(\W{0,2}/)?", &m, pos) {
        if m[2] = ""
            depth := StrReplace(m[1], " ")
        pos += m.Len
    }
    if RegExMatch(raw, "i)f[il1]oor\D{0,4}(\d+)", &m)
        icFloor := Integer(m[1])
    return MatchMapName(raw)
}

; reads the top-left of the loading screen: "Traveling to...", the map name, "Dungeon Room (Depth N)"
MapFromLoadingText() {
    global curDepth, icFloor
    static lastLogged := "", warned := false, floorTold := false
    if !WinExist(RBX)
        return ""
    try {
        WinGetClientPos &ox, &oy, , , RBX
        ; map name + "Dungeon Room (Depth N)" + difficulty (the Roblox buttons cover "Traveling to...")
        txt := OCR.FromRect(ox + 8, oy + 50, 470, 125, OcrLang(), {scale: 2, grayscale: true}).Text
    } catch as err {
        if !warned {
            warned := true
            OcrMissing(err)
        }
        return ""
    }
    if RegExMatch(txt, "i)depth\D{0,4}(\d+)", &m)
        curDepth := m[1]
    if RegExMatch(txt, "i)f[il1]oor\D{0,4}(\d+)", &m)
        icFloor := Integer(m[1])
    name := MatchMapName(txt)
    one := Trim(RegExReplace(txt, "\s+", " "))
    if !floorTold && RegExMatch(one, "i)castle") && !RegExMatch(one, "i)f[il1]oor\D{0,4}\d") {
        floorTold := true
        AddLog("Loading screen says: " SubStr(one, 1, 70) "  (no floor number in it)")   ; to learn where the floor shows
    }
    if name = "" && one != "" && one != lastLogged && (InStr(StrLower(one), "dungeon") || InStr(StrLower(one), "depth")) {
        lastLogged := one
        AddLog("Loading screen says: " SubStr(one, 1, 60))     ; helps fix names it can't match
    }
    return name
}

; Finds a known map name in OCR text. Every word of the map name has to show up somewhere:
; a misread letter is fine ("Snouy Toun", "Halled City") and so is a word split in two ("Hell ish").
; Finds the map name in text read off the screen, even when the reader garbles it
; ("Halled City", "Snouy Toun", "Hell ish ... City"). Tested on every misread in the log
; plus thousands of made-up ones: when it isn't sure it answers "" rather than a wrong map.
; a map name in text the screen reader got back: first the careful match, then (for text that
; came out half garbled, e.g. on a PC whose text reader isn't English) the forgiving one
MatchMapName(txt) {
    name := MatchMapStrict(txt)
    return name != "" ? name : MatchMapLoose(txt)
}

MatchMapStrict(txt) {
    static names := 0, folded := Map()
    if !IsObject(names) {
        names := []
        for name in LoadingScreens()
            names.Push(name)
        for name in names {
            parts := []
            for w in StrSplit(StrLower(name), " ")
                parts.Push(FoldOcr(w))
            folded[name] := parts
        }
    }
    flat := NormName(txt)
    if flat = ""
        return ""
    for name in names                               ; read perfectly
        if InStr(flat, NormName(name))
            return name
    ; drop the panel's own words ("Dungeon Room", "DEPTH: 14/20", "Honey Drops"...)
    clean := RegExReplace(txt, "i)dungeon\s*r\s*[o0]{1,2}\s*[mn]\b|dungeon\W*(\w+\W*)?d\s*e\s*p\s*t\s*h\W*(\w+\W*)?\d+\s*/\s*\d+", " ")
    clean := RegExReplace(clean, "i)\b(r\s*[o0]\s*[o0]?\s*[mn]|d\s*e\s*p\s*t\s*h|honey|drops|difficult\w*|chests?|curse\s+of|boss|rare|hoard|shop|shrine|hard|easy|normal)\b", " ")
    words := []
    for w in StrSplit(Trim(RegExReplace(StrLower(clean), "[^a-z]+", " ")), " ")
        if w != ""
            words.Push(w)
    if !words.Length
        return ""
    toks := []                                      ; single words and 2-3 neighbours glued together
    for i, w in words {
        glued := ""
        loop 3 {
            k := i + A_Index - 1
            if k > words.Length
                break
            glued .= words[k]
            toks.Push({txt: FoldOcr(glued), first: i, last: k})
        }
    }
    bestName := "", best := 9, second := 9
    for name in names {
        nws := folded[name], whole := ""
        for nw in nws
            whole .= nw
        total := 0, pos := 0, ok := true
        for nw in nws {                             ; every word of the name, in order
            low := 9, lowEnd := 0, slack := Max(1, StrLen(nw) // 3)
            for tk in toks {
                if tk.first <= pos || Abs(StrLen(tk.txt) - StrLen(nw)) > slack
                    continue
                cost := Levenshtein(tk.txt, nw) / StrLen(nw)
                if cost < low
                    low := cost, lowEnd := tk.last
            }
            if low > 0.34 {
                ok := false
                break
            }
            total += low * StrLen(nw), pos := lowEnd
        }
        slack := Max(1, StrLen(whole) // 3)         ; or the whole name glued ("snowytown")
        for tk in toks {
            if Abs(StrLen(tk.txt) - StrLen(whole)) > slack
                continue
            cost := Levenshtein(tk.txt, whole) / StrLen(whole)
            if cost <= 0.25 && (!ok || cost * StrLen(whole) < total)
                ok := true, total := cost * StrLen(whole)
        }
        if !ok
            continue
        score := total / StrLen(whole)
        if score < best
            second := best, best := score, bestName := name
        else if score < second
            second := score
    }
    if bestName != "" && best > 0 && second - best < 0.08    ; two maps fit about as well: don't guess
        return ""
    return bestName
}

; Text read half wrong ("Sp Toun" for Spirit Town, "Sp°or Id" for Spirit World): take the map
; line (between "Dungeon Room" and "Depth", or just before "Dungeon Room" on loading screens
; and banners) and score every map by the letters they share and how their words start.
; Only a clear winner counts. (Tested on 7920 garbled names: 95% right, 2 wrong, rest skipped.)
MatchMapLoose(txt) {
    static names := 0
    if !IsObject(names) {
        names := []
        for name in LoadingScreens()
            names.Push(name)
    }
    t := RegExReplace(txt, "\s+", " ")
    segs := [], pos := 1
    while pos := RegExMatch(t, "i)dungeon\W{0,2}r\S{0,5}\s+(.{2,40}?)\s*(?=\bd\s*e\s*p|\bde\b|\(|\bdiff|$)", &m, pos)
        segs.Push({s: m[1], need: 0.6}), pos := m.Pos[0] + Max(1, m.Len[0])
    ; the words just before "Dungeon Room" (loading screens) can be any other text on a panel,
    ; so those need a clearer win
    pos := 1
    while pos := RegExMatch(t, "i)((?:\S+\s+){1,3}?)\s*dungeon\W{0,2}r[o0]", &m, pos)
        segs.Push({s: m[1], need: 0.72}), pos := m.Pos[0] + Max(1, m.Len[0])
    bestName := "", bestScore := 0
    for sg in segs {
        ws := [], letters := 0
        for w in StrSplit(RegExReplace(StrLower(sg.s), "[^a-z0-9]+", " "), " ")
            if RegExMatch(w, "[a-z]")
                ws.Push(FoldLoose(w)), letters += StrLen(w)
        if !ws.Length || letters < 3
            continue
        s1 := -99, s2 := -99, n1 := ""
        for name in names {
            s := ScoreMapName(ws, name)
            if s > s1
                s2 := s1, s1 := s, n1 := name
            else if s > s2
                s2 := s
        }
        if s1 >= sg.need && s1 - s2 >= 0.12 && s1 > bestScore
            bestScore := s1, bestName := n1
    }
    return bestName
}

FoldLoose(w) {
    w := FoldOcr(w)
    for pair in [["0", "o"], ["1", "i"], ["5", "s"], ["8", "b"]]
        w := StrReplace(w, pair[1], pair[2])
    return w
}

; how well the read words ws fit a map name: each word of the name takes 1-3 read words
; (glued), junk words in between cost a little; or the whole name glued ("SnowyTown")
ScoreMapName(ws, name) {
    nws := []
    for w in StrSplit(StrLower(name), " ")
        nws.Push(FoldLoose(w))
    n := nws.Length, m := ws.Length
    dp := []                                        ; dp[i+1][j+1]: first i name words in first j read words
    loop n + 1 {
        row := []
        loop m + 1
            row.Push(-9)
        dp.Push(row)
    }
    loop m + 1
        dp[1][A_Index] := 0
    loop n {
        i := A_Index
        loop m {
            j := A_Index
            best := dp[i + 1][j] - 0.1               ; skip a junk word
            loop 3 {
                k := A_Index
                if j - k < 0
                    break
                before := dp[i][j - k + 1]
                if before <= -9
                    continue
                g := ""
                loop k
                    g .= ws[j - k + A_Index]
                best := Max(best, before + WordSim(g, nws[i]))
            }
            dp[i + 1][j + 1] := best
        }
    }
    best := dp[n + 1][m + 1] / n
    whole := ""
    for w in nws
        whole .= w
    loop m {
        a := A_Index, g := ""
        loop m - a + 1 {
            g .= ws[a + A_Index - 1]
            best := Max(best, WordSim(g, whole) - 0.1 * (m - A_Index))
        }
    }
    return best
}

; shared letters (in order) plus a bonus when the words start the same
WordSim(s, w) {
    sim := 2 * LcsLen(s, w) / (StrLen(s) + StrLen(w))
    p := 0
    while p < StrLen(s) && p < StrLen(w) && SubStr(s, p + 1, 1) == SubStr(w, p + 1, 1)
        p++
    return sim + (p >= 2 ? 0.15 : p = 1 ? 0.05 : 0)
}

LcsLen(a, b) {
    lb := StrLen(b), prev := []
    loop lb + 1
        prev.Push(0)
    loop StrLen(a) {
        ca := SubStr(a, A_Index, 1), cur := [0]
        loop lb {
            j := A_Index
            cur.Push(ca == SubStr(b, j, 1) ? prev[j] + 1 : Max(prev[j + 1], cur[j]))
        }
        prev := cur
    }
    return prev[lb + 1]
}

; letters the screen reader mixes up are turned into one form before comparing
FoldOcr(str) {
    str := StrReplace(StrLower(str), "vv", "w")
    for pair in [["v", "u"], ["w", "u"], ["y", "u"], ["j", "i"], ["l", "i"], ["t", "i"], ["f", "i"], ["q", "g"], ["c", "e"]]
        str := StrReplace(str, pair[1], pair[2])
    return str
}

NormName(s) => RegExReplace(StrLower(s), "[^a-z]")

Levenshtein(a, b) {
    la := StrLen(a), lb := StrLen(b)
    if !la
        return lb
    if !lb
        return la
    prev := []
    loop lb + 1
        prev.Push(A_Index - 1)
    loop la {
        i := A_Index, ca := SubStr(a, i, 1)
        cur := [i]
        loop lb {
            j := A_Index
            cost := ca = SubStr(b, j, 1) ? 0 : 1
            cur.Push(Min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost))
        }
        prev := cur
    }
    return prev[lb + 1]
}

LoadingScreens() {
    static m := Map(
        "Air Craft", ["aircraft"], "Alien Spaceship", ["alienspaceship"],
        "Ant Kingdom", ["antkingdom", "antkingdom2", "antkingdom3", "antkingdomraid"],
        "Assassin Park", ["assassinpark"], "Cursed Festival", ["cursedfestival"],
        "Dungeon Throne", ["dungeonthrone", "dungeonthrone2"],
        "Fabled Kingdom", ["fabledkingdom", "fabledkingdom1"], "Fiend City", ["fiendcity"],
        "Future City", ["futurecity"], "Haunted Academy", ["hauntedacademy"],
        "Haunted Mansion", ["hauntedmansion"], "Hellish City", ["hellcity"],
        "Magic Hills", ["magichills", "magichills2", "magichill3"], "Magic Town", ["magictown"],
        "Mountain Temple", ["mountaintemple"], "Navy Bay", ["navybay"],
        "Nightmare Train", ["nightmaretrain"], "Planet Greenie", ["planetgreenie"],
        "Puppet Island", ["puppetisland"], "Rain Village", ["rainvillage", "rainvillage2"],
        "Ruined City", ["ruinedcity"], "Sacred Planet", ["sacredplanet"],
        "Sand Village", ["sandvillage"], "Shibuya District", ["shibuyadistrict"],
        "Snowy Kingdom", ["snowykingdom"], "Snowy Town", ["snowytown"],
        "Space Center", ["spacecenter", "spacecenter2"], "Spirit Town", ["spirittown", "spirittown2"],
        "Spirit World", ["spiritworld"], "Storm Hideout", ["stormhideout"],
        "Strange Town", ["strangetown"], "Virtual Dungeon", ["virtualdungeon", "virtualdungeon2"],
        "Walled City", ["walledcity"]
    )
    return m
}

MapNames() {
    names := []
    for name in LoadingScreens()
        names.Push(name)
    names.Push("Infinity Castle")           ; its own walks and spots, for a floor whose map isn't read
    names.Push("Unknown")
    return names
}

IsLoaded() => Det("VoteStart") || Det("Yen") || Det("Units") || PixelIs(320, 60, 0x00EE00)

PlayStage() {
    global stageActive, stageStart, placedUnits, lastResult, postStage, curMap, allPlaced, slotPrice
    if !stageActive {
        if curMap = "Unknown" {
            ; the big blue map name shows in the middle of the screen when a stage starts
            Step("reading the map name")
            t0 := A_TickCount
            while curMap = "Unknown" && A_TickCount - t0 < 3000 {
                if (name := MapFromBanner()) != "" {
                    curMap := name
                    AddLog("Map: " name (curDepth != "" ? ", depth " curDepth : "") "  (from the map banner)")
                    UpdateMapLabel()
                    break
                }
                Wait(250)
            }
        }
        if ICMode() && curMap = "Unknown" {
            curMap := "Infinity Castle"            ; couldn't read the floor's map: its own walk/spots
            UpdateMapLabel()
        }
        postStage := 0
        stageActive := true
        stageStart := A_TickCount
        lastResult := ""
        placedUnits := [], allPlaced := false, slotPrice := Map()
        global placeUnsure := Map(), unseenFound := []
        global walkedHere := false
        ; the team for this room's boosted element, FIRST: units can only be changed before the game
        ; starts ("You can change your units before the game starts!"). After the teleport, the walk and
        ; the start vote the Units window no longer opened with K (Jbenz's first try)
        if ElemTeamsOn()
            PickRoomTeam()
        SetupCamera()
        WaitForVote()
        ctx := NewPlaceCtx()
        if BuildMode()                          ; the build order OR the Units tab, not both
            RunBuildOrder(ctx)
        else
            PlaceAll(ctx)
    }
    allPlaced := true                       ; placing is over: upgrades can use the F panel now
    UpgradeAndWatch()
}

; Roblox's Camera Mode "Follow" (Esc > Settings) swings the camera round behind you while you walk,
; so a walk (recorded with the Classic camera) goes off in other directions and gets stuck. Roblox
; keeps the setting in its settings file: ComputerCameraMovementMode 0 Default, 1 Classic, 2 Follow
FollowCamera() {
    newest := "", stamp := ""
    try loop files EnvGet("LOCALAPPDATA") "\Roblox\GlobalBasicSettings_*.xml"
        if A_LoopFileTimeModified > stamp
            newest := A_LoopFilePath, stamp := A_LoopFileTimeModified
    if newest = ""
        return false
    try txt := FileRead(newest)
    catch
        return false
    if !RegExMatch(txt, 'name="ComputerCameraMovementMode">\s*(\d+)', &cm) || Integer(cm[1]) != 2
        return false
    AddLog("Your Roblox Camera Mode is Follow, so the walks go the wrong way. In Roblox press Esc > Settings > Camera Mode and pick Classic")
    return true
}

SetupCamera() {
    Step("getting ready")
    if FileExist(MOVE_FLAG) {                  ; a Click to Move walk was cut off: clicks would walk the character
        AddLog("Roblox's Movement Mode was left on Click to Move, setting it back")
        SetMoveMode("default")
    }
    Keys("{Tab}")                      ; close the player list
    Wait(600)
    Clk(569, 72), Wait(300)
    Clk(569, 72), Wait(200)
    CloseChat()
    GoToSpot(curMap)
}

; Teleport FIRST (puts the character back on spawn facing the same way every time),
; THEN line the camera up, THEN walk. Doing the camera before the teleport made it
; depend on wherever the last walk left the character facing.
GoToSpot(mapName, walk := true, force := false) {
    tp := cfg["tpSpawn"] || force
    if tp
        TeleportToSpawn()
    if cfg["zoom"] {
        loop 3 {                        ; a Fool's Hunt card vote over the middle swallows the zoom:
            ClearVote()                 ; pick it first, and zoom again if one came up during it
            votes := foolVotes
            ZoomCamera()
            if foolVotes = votes && !VoteOnScreen()
                break
        }
    }
    if tp && walk {
        ; lost here last time after the walk: the walk went somewhere the enemies never pass
        ; (Magic Hills in the dungeon: every unit down, 5 defeats in a row, "it puts units behind
        ; the spawn"). Placed from spawn this time instead
        if !force && walkLost.Get(mapName, 0) && (cfg["walks"].Has(mapName) || HasBuiltInWalk(mapName)) {
            AddLog("Lost on " mapName " last time after walking to its spot, so placing from spawn this time "
                . "(record your own walk for it on the Spots page if spawn doesn't work either)")
            return
        }
        WalkRoute(mapName)
    }
}

; a stage ended: lost after the walk -> from spawn next time on this map; lost from spawn -> the
; walk again; a win keeps whatever won. Only for this session (a later update can fix the walk)
global walkLost := Map()
WalkLearn() {
    key := curMap
    if lastResult != "loss"
        return
    if walkedHere
        walkLost[key] := 1
    else if walkLost.Has(key)
        walkLost.Delete(key)
}

; the camera is being zoomed: fully zoomed in, Roblox is in first person and a click turns the
; camera, so nothing else may click (a Fool's Hunt card vote picked here left the camera stuck)
global camBusy := false

ZoomCamera() {
    global camBusy
    Step("lining up the camera")
    camBusy := true
    try ZoomCameraNow()
    finally camBusy := false
}

ZoomCameraNow() {
    FocusRoblox()
    MouseMove 400, 300
    Wait(100)
    loop 25 {                          ; all the way in
        Send "{WheelUp}"
        Sleep 30
    }
    Wait(150)
    Click
    MouseMove 400, 400                 ; tilt down
    Wait(100)
    loop 20 {                          ; back out
        Send "{WheelDown}"
        Sleep 30
    }
    MouseMove 400, 300
    Stale()
}

TeleportToSpawn() {
    Step("teleporting to spawn")
    ; still on a loading screen ("Travelling to... Neo-Tokyo"): there's no settings menu to open yet
    ; (a no_spawn picture showed exactly that). Wait for it to go, up to 25 s
    if LoadingScreenUp() {
        Step("waiting for the loading screen")
        WaitFor(() => !LoadingScreenUp(), 25000, 1000)
        Wait(1500)
    }
    found := false
    loop 2 {                                       ; second go reopens the menu
        Clk(26, 570)                               ; settings gear
        Wait(350)
        Clk(400, 215)                              ; mouse over the list so the wheel scrolls it
        Wait(200)
        found := SpawnFound(&fx, &fy) || (Wait(300), SpawnFound(&fx, &fy))
        if !found {
            ; the menu remembers how far it was scrolled: go to the top first,
            ; then step down one notch at a time until the button shows up
            ; (some players have more settings, so it keeps going until the list stops moving)
            loop 30 {
                Keys("{WheelUp 1}")
                Sleep 40
            }
            Wait(500)
            ; one notch at a time, and the list slides for a moment after each one: let it
            ; settle before looking (looking mid-slide missed the button or matched a wrong row)
            same := 0, sig := MenuSig()
            loop 45 {
                if found := SpawnFound(&fx, &fy)
                    break
                Keys("{WheelDown 1}")
                Wait(350)
                now := MenuSig()
                same := now = sig ? same + 1 : 0, sig := now
                if same >= 3                       ; reached the bottom of the list
                    break
            }
            ; went past it (on some players' lists every notch left the Teleport row half under
            ; the "Settings" title, or under the mouse pointer): back up a few notches from the
            ; bottom, where the rows line up differently, the pointer off the list while it looks
            if !found
                loop 8 {
                    MouseMove 400, 215
                    Keys("{WheelUp 1}")
                    MouseMove 700, 560
                    Wait(350)
                    if found := SpawnFound(&fx, &fy, true)
                        break
                }
            if !found
                found := SpawnFound(&fx, &fy, true) || (Wait(300), SpawnFound(&fx, &fy, true))
        }
        if found {
            Clk(fx + 100, fy - 30)
            AddLog("Teleported to spawn")
        } else if A_Index = 2
            SaveDebugShot("no_spawn")               ; the open settings menu, so it can be checked
        CloseSettings()
        if found
            break
    }
    if !found
        AddLog("Couldn't find Teleport to Spawn in the game's settings. Send Logs\no_spawn_....bmp in Discord so it can be fixed. (Settings tab: 'Teleport to spawn' can be turned off meanwhile)")
    return found
}

; "Travelling to..." / "Traveling to..." at the top left of a loading screen
LoadingScreenUp() {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        return RegExMatch(OCR.FromRect(ox + 10, oy + 30, 280, 45, OcrLang(), {scale: 2, grayscale: true}).Text, "i)trav+el")
    }
    return false
}

; The Teleport to Spawn picture is matched loosely (20%), and on some players' settings lists
; that also fit another row: it clicked that, stopped scrolling and never teleported. So a
; loose hit must also read "Spawn"/"Teleport" on that row, or match the picture closely.
SpawnFound(&fx, &fy, words := false) {
    if !Det("Spawn", &fx, &fy) {
        ; the picture missed (a row at the edge of the list): the words on the whole list, only
        ; on the way back up (it's slower). fx, fy as the picture gives them (window coordinates)
        if words && OcrFindWord(225, 140, 370, 335, "i)sp[a@]wn", &wx, &wy) {
            fx := wx + 5, fy := wy + 31
            return true
        }
        return false
    }
    cx := fx - 5, cy := fy - 31                     ; window -> game-area coords
    if OcrFindWord(Max(0, cx - 180), Max(0, cy - 23), 360, 46, "i)sp[a@]wn|tele", &wx, &wy)
        return true
    o := DetDefs()["Spawn"], a := o.area
    return FT(&fx, &fy, a[1], a[2], a[3], a[4], 0.06, 0.06, o.pats) ? true : false
}

; a rough fingerprint of the settings list, to tell when scrolling stops moving it
MenuSig() {
    sig := 0
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        y := 170
        while y <= 470 {
            x := 230
            while x <= 590 {
                sig := Mod(sig * 31 + (scr.GetColor(ox + x, oy + y, 0) & 0xF0F0F0), 1000000007)
                x += 24
            }
            y += 12
        }
    }
    return sig
}

; make sure the settings menu is really shut, so later mouse-wheel zooming doesn't scroll it
; closed when it's really gone: the Spawn row not on show wasn't enough (a list scrolled to its
; top has none, so one missed click counted as closed and placing clicked into it for a stage)
CloseSettings() {
    loop 4 {
        Wait(250)
        ; its X, and if that missed twice (a player's window sat elsewhere: it stayed open the whole
        ; stage, the camera zoom scrolled the list instead and the camera stayed down behind him) the
        ; settings gear, which opens and closes it
        Clk(A_Index <= 2 ? 583 : 26, A_Index <= 2 ? 147 : 570)
        if WaitFor(() => !Det("Spawn"), 500) && !GameSettingsOpen()
            return true
    }
    AddLog("The game's Settings window wouldn't close. Close it yourself (its X) if it's still open")
    SaveDebugShot("game_settings")
    return false
}

; the game's own Settings window (Quick Summon, Graphics, Teleport to Spawn...) over the map
GameSettingsOpen() {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        return IsSettingsText(OCR.FromRect(ox + 180, oy + 120, 440, 380, OcrLang(), {scale: 2, grayscale: true}).Text)
    }
    return false
}
IsSettingsText(t) => RegExMatch(t, "i)settings") && RegExMatch(t, "i)quick\s*summon|graphics|smooth\s*lighting|textures|depth.of.field|teleport|spawn")

; placing failed: is the game's Settings window in the way? Closed if so (a player's clip: it stayed
; open over the map and every placing click went into it). Looked at every 10 s at most (a read)
SettingsInTheWay() {
    static lastAt := 0
    if lastAt && A_TickCount - lastAt < 10000
        return false
    lastAt := A_TickCount
    if !GameSettingsOpen()
        return false
    AddLog("The game's Settings window was open over the map, closing it")
    SaveDebugShot("game_settings")
    CloseSettings()
    return true
}

WaitForVote() {
    global stageStart
    Step("waiting for the game to start")
    t0 := A_TickCount
    while Det("VoteStart") {
        Clk(350, 103), Clk(350, 100), Clk(350, 97)
        WaitFor(() => !Det("VoteStart"), 1000)
        if A_TickCount - t0 > 60000
            break
    }
    stageStart := A_TickCount
}

; ---------- walking to a spot after teleporting ----------
; a route is "key+ms,key-ms,..."  (+ = press, - = release, ms since start)
WalkRoute(mapName) {
    key := PlaceKey(mapName)
    ; Fool's Hunt spawns you elsewhere on a map than its dungeon: only a walk recorded there
    route := cfg["walks"].Has(key) ? cfg["walks"][key] : key = mapName ? BuiltInWalk(mapName) : ""
    if route = ""
        return
    Step("walking to the spot")
    if RegExMatch(route, "^click:(\d+),(\d+)", &cm)
        ClickWalk(Integer(cm[1]), Integer(cm[2]))
    else
        PlayRoute(route)
    global walkedHere := true                   ; PlaceSlot goes back to spawn if nothing fits there
    AddLog("Walked to the " key " spot")
}

; ---------- Click to Move walks ----------
; A walk can be one click instead of recorded keys ("click:x,y", picked on the Spots page): Roblox's
; Movement Mode (Esc > Settings) is set to Click to Move just for the walk, the character finds its
; own way there (around Snowy Town's fences, where W A S D got stuck), and it's set back afterwards.
; Click to Move can't stay on: every click the macro makes would walk the character, and the camera
; follows it. The menu is found by its text (Windows' text reader), not by fixed spots.
ClickWalk(x, y) {
    if FileExist(MOVE_FLAG) && !SetMoveMode("default") {
        AddLog("Roblox's Movement Mode is still on Click to Move and couldn't be set back, so no Click to Move walk. "
            . "Set it to Default (Keyboard) yourself: Esc > Settings > Movement Mode")
        return false
    }
    if !SetMoveMode("click") {
        AddLog("Couldn't switch Roblox's Movement Mode to Click to Move (Esc > Settings), so no walk this time")
        return false
    }
    Step("walking there (Click to Move)")
    moved := false
    for btn in ["Left", "Right"] {              ; Roblox walks on a left click; right as a fallback
        sig0 := SceneSig()
        MouseMove x, y
        Sleep 120
        Clk(x, y, btn)
        Wait(1200)
        if SigDiff(SceneSig(), sig0) >= 8 {     ; the camera follows the character: the picture moves
            moved := true
            break
        }
    }
    if moved {                                  ; walk until the picture stops changing
        t0 := A_TickCount, still := 0, sig := SceneSig()
        while A_TickCount - t0 < 25000 && still < 4 {
            Wait(300)
            now := SceneSig()
            still := SigDiff(now, sig) < 6 ? still + 1 : 0, sig := now
        }
    } else
        AddLog("Click to Move: the character didn't move from the click")
    if !SetMoveMode("default") && !SetMoveMode("default") {
        AddLog("Couldn't set Roblox's Movement Mode back to Default. Set it yourself: Esc > Settings > Movement Mode > Default (Keyboard). "
            . "Until then every click walks your character. It tries again at the next stage")
        Notify("Set Roblox's Movement Mode back to Default (Keyboard)")
        SendWebhook("Movement Mode stuck on Click to Move", "Esc > Settings > Movement Mode > Default (Keyboard). The macro tries again each stage.", 0xF59E0B)
    }
    return moved
}

; sets Roblox's Movement Mode (Esc > Settings) to the option containing `want` ("click", "default")
; and closes the menu again. True when it got there
SetMoveMode(want) {
    ok := false
    try {
        if !MoveModeRow(&rowY, &val)
            return false
        loop 4 {
            if InStr(val, want) {
                ok := true
                break
            }
            ; only click on while the option can be read: blind clicks could stop on Click to Move
            if !RegExMatch(val, "i)default|keyboard|click") {
                SaveDebugShot("move_mode")
                AddLog("Couldn't read Roblox's Movement Mode option (read: '" val "'), leaving it as it is")
                break
            }
            ; the arrow at the right end of the row cycles Default (Keyboard) > Keyboard + Mouse > Click to Move
            MouseMove 762, rowY
            Sleep 120
            Clk(768, rowY)
            Wait(500)
            val := MoveModeValue(rowY)
        }
        ; still in Click to Move: a file says so, so it's put back even after a stop or a closed macro
        ; a failed switch back must keep it (it deleted it: Roblox stayed on Click to Move for every
        ; map after, where each click of the macro walks the character and the camera follows)
        if want != "default" && ok {
            try FileOpen(MOVE_FLAG, "w").Close()
        } else if want = "default" && ok {
            try FileDelete(MOVE_FLAG)
        }
    } finally
        CloseEscMenu()
    return ok
}

; opens Esc > Settings and scrolls to "Movement Mode". rowY: the row's height in the game, val: its option
MoveModeRow(&rowY, &val) {
    WinGetClientPos &ox, &oy, &cw, &ch, RBX
    if !EscMenuUp() {
        Keys("{Esc}")
        Wait(900)
    }
    settingsClicked := false, scrolled := 0
    loop 12 {
        r := 0
        try r := OCR.FromRect(ox, oy, cw, ch, OcrLang(), {scale: 1.5, grayscale: true})
        if !IsObject(r)
            return false
        for line in r.Lines
            if RegExMatch(line.Text, "i)m[o0]vement\s*m[o0]de") && line.y > 100 {
                rowY := line.y + line.h // 2
                val := MoveModeValue(rowY)
                return val != ""
            }
        if !settingsClicked {                   ; the menu opens on People: the Settings tab next to it
            for w in r.Words
                if w.Text = "Settings" && w.y < 140 {
                    MouseMove w.x + w.w // 2, w.y + w.h // 2
                    Sleep 150
                    Clk(w.x + w.w // 2, w.y + w.h // 2)
                    Wait(900)
                    settingsClicked := true
                    continue 2
                }
        }
        if scrolled >= 40
            break
        MouseMove cw // 2, ch // 2              ; down the list a few notches at a time
        loop 5 {
            Send "{WheelDown}"
            Sleep 40
        }
        scrolled += 5
        Wait(500)
    }
    SaveDebugShot("move_mode")
    AddLog("Couldn't find Movement Mode in Roblox's settings menu. Send Logs\move_mode_....bmp in Discord")
    return false
}

MoveModeValue(rowY) {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        t := OCR.FromRect(ox + 360, oy + rowY - 15, 370, 30, OcrLang(), {scale: 2, grayscale: true}).Text
        return StrLower(Trim(RegExReplace(t, "\s+", " ")))
    }
    return ""
}

; Roblox's Esc menu: its Resume / Leave buttons along the bottom
EscMenuUp() {
    try {
        WinGetClientPos &ox, &oy, &cw, &ch, RBX
        t := OCR.FromRect(ox, oy + ch - 90, cw, 90, OcrLang(), {scale: 1.5, grayscale: true}).Text
        return RegExMatch(t, "i)resume") && RegExMatch(t, "i)leave")
    }
    return false
}

CloseEscMenu() {
    loop 3 {
        if !EscMenuUp()
            return
        Keys("{Esc}")
        Wait(700)
    }
}

PlayRoute(route) {
    FocusRoblox()
    t0 := A_TickCount, p0 := pauseTotal
    ; tokens: w+1200 (press w at 1.2s)  w-1500 (release)  rc400;300@0 (right-click to walk there)  end@5000 (wait until 5s)
    try {
        for ev in StrSplit(route, ",") {
            if RegExMatch(ev, "^(\w+)([+-])(\d+)$", &m)
                at := Integer(m[3]), kind := "key"
            else if RegExMatch(ev, "^rc(\d+);(\d+)@(\d+)$", &m)
                at := Integer(m[3]), kind := "rclick"
            else if RegExMatch(ev, "^end@(\d+)$", &m)
                at := Integer(m[1]), kind := "end"
            else
                continue
            while A_TickCount - t0 - (pauseTotal - p0) < at {
                Chk()
                Sleep 5
            }
            if kind = "key"
                SendKeys("{" m[1] (m[2] = "+" ? " down}" : " up}"))
            else if kind = "rclick"
                Clk(Integer(m[1]), Integer(m[2]), "Right")
        }
    } finally
        ReleaseKeys()
    Wait(300)
    Stale()
}

; the built-in walk for this map (Ryn's), used until you record your own.
; Maps with two routes look for a landmark to tell which way the camera faces.
BuiltInWalk(mapName) {
    w := BuiltInWalks()
    if !w.Has(mapName)
        return ""
    for v in w[mapName] {
        ok := true
        for c in v.checks {
            hit := false
            for f in c[2]
                if Seen(f[2], f[3], f[4], f[5], f[1], f[6]) {
                    hit := true
                    break
                }
            if hit != c[1] {
                ok := false
                break
            }
        }
        if ok
            return v.route
    }
    return ""
}

HasBuiltInWalk(mapName) => BuiltInWalks().Has(mapName)

ReleaseKeys() {
    for k in ["w", "a", "s", "d", "z", "q"]      ; checked by key code: a Russian layout has no "w" key name (z, q: AZERTY walking)
        if GetKeyState("vk" Format("{:02X}", Ord(StrUpper(k))))
            SendKeys("{" k " up}")
    if GetKeyState("Space")
        SendInput "{Space up}"
}

; How keys are sent depends on the keyboard layout Roblox is on, each way tested by players:
;  - a layout with English letters (English, German, Norwegian...): by name, as always
;  - one without (Russian, Greek...): by key code. By name they arrived as typed text and R, F, Q
;    and W/A/S/D did nothing; by key code they worked on Kirito's Russian keyboard. (Key codes
;    for everyone broke walking on English keyboards, so they're only used there.)
SendKeys(ks) {
    ; Keyboard "AZERTY" (Settings): this player's Roblox walks with Z Q S D. W opened the emote wheel on
    ; Simon's PC whatever layout Windows was on, so walks (recorded as W A S D) press Z and Q instead
    if KbMode() = "AZERTY"
        ks := RegExReplace(RegExReplace(ks, "i)\{w( down| up)?\}", "{z$1}"), "i)\{a( down| up)?\}", "{q$1}")
    if NonLatinLayout() {
        ks := RegExReplace(ks, "^([A-Za-z])$", "{$1}")
        while RegExMatch(ks, "\{([A-Za-z])( down| up)?\}", &m)
            ks := StrReplace(ks, m[0], "{vk" Format("{:02X}", Ord(StrUpper(m[1]))) m[2] "}")
    }
    SendInput ks
}

; true when the keyboard layout of Roblox's window has no "a" key (Russian, Greek, ...)
; the Keyboard setting (Settings page): Auto (the macro looks at the layout), QWERTY, AZERTY, QWERTZ,
; Non-Latin (Russian, Greek ...: keys by key code)
KbMode() => cfg.Has("keyboard") ? cfg["keyboard"] : "Auto"

NonLatinLayout() {
    static lastAt := 0, res := false, told := false
    if KbMode() != "Auto"
        return KbMode() = "Non-Latin"
    if A_TickCount - lastAt < 3000
        return res
    lastAt := A_TickCount, res := false
    try {
        hwnd := WinExist(RBX)
        if !hwnd
            return res
        tid := DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "Ptr", 0, "UInt")
        hkl := DllCall("GetKeyboardLayout", "UInt", tid, "Ptr")
        res := hkl && DllCall("VkKeyScanExW", "UShort", Ord("a"), "Ptr", hkl, "Short") = -1
    }
    if res && !told {
        told := true
        AddLog("Your keyboard is on a layout without English letters: keys are sent by key code")
    }
    return res
}

; ---------- placing ----------
; where to try, which spots are taken / failed, and the Placement retries setting
NewPlaceCtx() {
    ; [misses in a row per round, rounds once some are down, rounds with none down]
    static levels := [[6, 2, 5], [10, 4, 8], [15, 6, 12], [25, 10, 20]]
    ctx := {pts: PlacementPoints(), used: Map(), fails: Map(), cursor: 1, over: false, build: false,
        lv: levels[Max(1, Min(levels.Length, cfg["retries"]))]}
    for u in placedUnits
        ctx.used[u.x "," u.y] := true
    return ctx
}

CountPlaced(n) {
    c := 0
    for u in placedUnits
        if u.slot = n
            c++
    return c
}

; places what the Units tab asks for that isn't down yet
PlaceAll(ctx := "") {
    if !IsObject(ctx)
        ctx := NewPlaceCtx()
    any := false
    for i, sl in cfg["slots"] {
        if !sl.on || sl.count < 1
            continue
        any := true
        need := sl.count - CountPlaced(i)
        if need <= 0
            continue
        PlaceSlot(ctx, i, need)
        if ctx.over
            return
    }
    if !any
        AddLog("No unit slots are turned on")
    else
        AddLog("Placement done (" placedUnits.Length " units)")
}

; Places up to `need` more units of slot n and returns the ones it placed.
; A new round carries on to new spots instead of going back to ones that just failed;
; a spot that fails twice is skipped. Sets ctx.over if the stage ends.
PlaceSlot(ctx, n, need) {
    global placedUnits
    need := SlotRoom(n, need)
    lv := ctx.lv, pts := ctx.pts
    newUnits := []
    got := 0, stuck := 0, greySince := 0
    while got < need {
        if StageOver() {
            ctx.over := true
            return newUnits
        }
        ; the game greys out a unit's card when it can't be placed right now. Don't try spots
        ; then (that marked good spots as bad and ended the step early): wait for yen instead
        if !SlotReady(n) {
            yen := ReadYen(), cost := SlotCost(n)
            if yen >= 0 && cost > 0 && yen >= cost && !greySince && CountPlaced(n) >= 1 && ReadYen() >= cost {
                ; enough yen but still greyed out: that's the game's limit for this unit
                AddLog("Slot " n ": the game won't allow more (" CountPlaced(n) " placed), moving on")
                break
            }
            if !greySince
                greySince := A_TickCount
            if ctx.build && A_TickCount - greySince < 360000 {
                Step("build order: waiting for yen to place slot " n (yen >= 0 && cost > 0 ? "  (" yen " / " cost ")" : ""))
                Wait(1000)
                continue
            }
            if !ctx.build {
                stuck++
                if stuck >= (got ? lv[2] : lv[3]) {
                    AddLog("Slot " n " stopped at " got "/" need " (not enough yen), moving on")
                    break
                }
                Step("upgrading while waiting to place slot " n)
                UpgradePass(true)
                Wait(1000)
                continue
            }
        }
        greySince := 0
        before := got, misses := 0, tried := 0, attempts := 0
        ; spots where this slot landed before on this map, first: a unit that only goes on hills
        ; spent ages on ground spots every stage, now only the first time
        for p in goodSpots.Get(CapKey(n), []).Clone() {
            if got >= need
                break
            key := p.x "," p.y
            if ctx.used.Has(key) || ctx.fails.Get(key "|" n, 0) || NextToUnit(p.x, p.y)
                continue
            if StageOver() {
                ctx.over := true
                return newUnits
            }
            Step("placing slot " n "  (" got "/" need ", where it went last time)")
            if TryPlace(p.x, p.y, n) {
                ctx.used[key] := true
                got++
                u := {x: p.x, y: p.y, slot: n, maxed: false, capped: false, dx: 0, dy: -3, misses: 0, lost: false}
                placedUnits.Push(u), newUnits.Push(u)
                AddLog("Placed slot " n "  (" got "/" need ")")
            } else {
                ctx.fails[key "|" n] := 1
                for u in TakeUnseen(n)
                    newUnits.Push(u), got++, AddLog("Placed slot " n "  (" got "/" need ", found on the map)")
                if !SlotRoom(n, 1)
                    return newUnits
            }
        }
        while got < need && misses < lv[1] && tried < pts.Length {
            p := pts[ctx.cursor], key := p.x "," p.y
            ctx.cursor := Mod(ctx.cursor, pts.Length) + 1
            tried++
            if ctx.used.Has(key) || ctx.fails.Get(key, 0) >= 2 || NextToUnit(p.x, p.y)
                continue
            if StageOver() {
                ctx.over := true
                return newUnits
            }
            attempts++
            Step("placing slot " n "  (" got "/" need ")")
            if TryPlace(p.x, p.y, n) {
                ctx.used[key] := true
                misses := 0
                got++
                LearnSpot(n, p)
                u := {x: p.x, y: p.y, slot: n, maxed: false, capped: false, dx: 0, dy: -3, misses: 0, lost: false}
                placedUnits.Push(u), newUnits.Push(u)
                AddLog("Placed slot " n "  (" got "/" need ")")
            } else {
                ctx.fails[key] := ctx.fails.Get(key, 0) + 1
                misses++
                for u in TakeUnseen(n)
                    newUnits.Push(u), got++, AddLog("Placed slot " n "  (" got "/" need ", found on the map)")
                if !SlotRoom(n, 1)
                    return newUnits                 ; the game's limit for this unit
            }
        }
        if !attempts && got < need
            ctx.fails := Map()                 ; every spot is used or failed twice: give them another go
        ; walked to the map's spot and not one unit fits anywhere: the walk went off, or it isn't the
        ; map it was taken for (a Fool's Hunt loading screen once said Mountain Temple on another
        ; map, and it walked out to where nothing can be placed). Back to spawn, place from there
        if got < need && !placedUnits.Length && walkedHere && attempts >= lv[1] && !ctx.HasOwnProp("respawned") {
            ctx.respawned := true
            AddLog("Nothing could be placed after walking to the " curMap " spot (wrong map, or the walk went off). Back to spawn, placing from there")
            GoToSpot(curMap, false, true)
            ctx.fails := Map(), ctx.used := Map(), ctx.cursor := 1
            continue
        }
        if got < need {
            stuck := got = before ? stuck + 1 : 0
            ; with some already down, a few empty rounds usually means the game's limit for this unit
            ; (e.g. max 3). With none down it's more likely yen, so it waits longer.
            if stuck >= (got ? lv[2] : lv[3]) {
                total := CountPlaced(n)
                if got && slotStops.Has(CapKey(n)) && slotStops[CapKey(n)] = total {
                    slotCap[CapKey(n)] := total
                    AddLog("Slot " n " only fits " total " on " curMap ". Placing " total " there from now on")
                } else
                    AddLog("Slot " n " stopped at " got "/" need " (unit limit, no space or not enough yen), moving on")
                if !placedUnits.Length
                    AddLog("Nothing placed. In the game's settings: 'Show Upgrade UI on left' ON, and the upgrade menu must pop up when you place a unit ('Disable Auto-Open Upgrade UI').")
                slotStops[CapKey(n)] := total
                break
            }
            if ctx.build {
                ; build order: keep the yen for this step, don't spend it on other upgrades
                Step("build order: waiting to place slot " n)
            } else {
                Step("upgrading while waiting to place slot " n)
                UpgradePass(true)
            }
            Wait(1000)
        }
    }
    return newUnits
}

; the middle of the picture as a few numbers: tells whether the character / camera is moving
SceneSig() {
    sig := []
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Stale(), Fresh()
        scr := FindText()
        y := 110
        while y <= 450 {
            x := 160
            while x <= 640 {
                c := scr.GetColor(ox + x, oy + y, 0)
                sig.Push(((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF))
                x += 40
            }
            y += 40
        }
    }
    return sig
}

SigDiff(a, b) {
    if !a.Length || a.Length != b.Length
        return 999
    d := 0
    for i, v in a
        d += Abs(v - b[i])
    return d / a.Length / 3
}

; remembers where a slot landed on this map (this session), so next stage tries there first
LearnSpot(n, p) {
    list := goodSpots.Has(CapKey(n)) ? goodSpots[CapKey(n)] : (goodSpots[CapKey(n)] := [])
    for q in list
        if q.x = p.x && q.y = p.y
            return
    list.Push({x: p.x, y: p.y})
    if list.Length > 20
        list.RemoveAt(1)
}

; ---------- Element teams ----------
; A dungeon room boosts up to 3 elements: its popup (opened when the room is picked) shows each as a
; coloured % with the element's icon under it (Storm +388%, Air +362%, Dark +222%). Players keep a
; team per element in the game (Units > Teams), and on the Units page each team has its element, the
; game team it loads, and its own units and build order. At the start of a room the macro loads the
; team for the most boosted element (or the default team) and plays with that team's setup.
global roomBoosts := [], teamLoaded := 0        ; teamLoaded: the team loaded in the game this run (0 = not sure)
ElemTeamsOn() => cfg.Has("elemTeams") && cfg["elemTeams"] && cfg.Has("teams") && cfg["teams"].Length > 1

; the element chips on an open room popup, as [{el, pct}] (pct < 0: the number couldn't be read; the
; chips' order then decides). Read by colour: each element's % text has its own colour (pale blue Storm,
; deep blue Aqua, green Air, grey-purple Dark ...; checked on Chris's screenshots)
ReadRoomBoosts() {
    global roomBoosts
    static shots := 0
    roomBoosts := []
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        x0 := 314, x1 := 462, y0 := 350, y1 := 364      ; the chips' % row (game-area coordinates)
        ; the panel opens next to the room clicked, so it isn't always in the middle: its chips are
        ; centred over its Enter button (Lunoc's panel on the right read "none")
        if Det("Enter", &ex, &ey)
            x0 := Max(0, ex - 3 - 74), x1 := Min(800, ex - 3 + 74)
        cols := []                              ; per column: the hues of its coloured pixels
        x := x0
        while x < x1 {
            hs := [], y := y0
            while y < y1 {
                if (h := ElemHue(scr.GetColor(ox + x, oy + y, 0) & 0xFFFFFF)) >= 0
                    hs.Push(h)
                y++
            }
            cols.Push(hs), x++
        }
        chips := [], c0 := 0, last := 0        ; a chip: columns with colour, 4+ empty columns apart
        for i, hs in cols {
            if hs.Length >= 2 {
                c0 := c0 ? c0 : i, last := i
            } else if c0 && i - last >= 4
                chips.Push([c0, last]), c0 := 0
        }
        if c0
            chips.Push([c0, last])
        for n, ch in chips {
            w := ch[2] - ch[1] + 1
            if w < 12 || w > 44                 ; not a "52%" .. "1000%" chip
                continue
            ; pale (Storm) or deep (Aqua) blue: the share of near-white pixels in the text
            pale := 0, bright := 0, xx := ch[1]
            while xx <= ch[2] {
                y := y0
                while y < y1 {
                    c := scr.GetColor(ox + x0 + xx - 1, oy + y, 0) & 0xFFFFFF
                    r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
                    if Max(r, g, b) >= 120
                        bright++, pale += Min(r, g, b) >= 150
                    y++
                }
                xx++
            }
            votes := Map(), isPale := bright && pale / bright > 0.25
            loop w
                for h in cols[ch[1] + A_Index - 1] {
                    k := HueElement(h, isPale)
                    votes[k] := (votes.Has(k) ? votes[k] : 0) + 1
                }
            el := "", most := 0
            for k, v in votes
                if v > most
                    el := k, most := v
            pct := -n
            try {
                txt := OCR.FromRect(ox + x0 + ch[1] - 4, oy + y0 - 3, w + 8, y1 - y0 + 6, OcrLang(), {scale: 3, grayscale: true}).Text
                if RegExMatch(StrReplace(StrReplace(txt, "O", "0"), "o", "0"), "\d{2,4}", &m)
                    pct := Integer(m[0])
            }
            roomBoosts.Push({el: el, pct: pct})
        }
        ; a % that wasn't read on its own (Storm's pale text, on Jbenz's PC): the whole row read at once
        ; gives the numbers left to right ("266% 202% 231%"), one per chip
        miss := false
        for b in roomBoosts
            miss := miss || b.pct < 0
        if miss && roomBoosts.Length {
            row := ""
            try row := OCR.FromRect(ox + x0 - 4, oy + y0 - 4, x1 - x0 + 8, y1 - y0 + 8, OcrLang(), {scale: 3, grayscale: true}).Text
            nums := [], pos := 1
            row := StrReplace(StrReplace(row, "O", "0"), "o", "0")
            while pos := RegExMatch(row, "(\d{2,4})\s*%", &m, pos)
                nums.Push(Integer(m[1])), pos += m.Len
            if nums.Length = roomBoosts.Length
                for i, b in roomBoosts
                    b.pct := b.pct < 0 ? nums[i] : b.pct
        }
    }
    txt := ""
    for b in roomBoosts
        txt .= (txt = "" ? "" : ", ") b.el (b.pct >= 0 ? " +" b.pct "%" : "")
    AddLog("Room boosts: " (txt != "" ? txt : "none read"))
    if shots < 4 {                              ; a few pictures, to check the colours on other PCs
        shots++
        SaveDebugShot("room_boosts")
    }
    return roomBoosts
}

; the hue (0-359) of a pixel of a chip's text, or -1. Dark's text is a soft grey-purple, the others strong
ElemHue(c) {
    r := (c >> 16) & 0xFF, g := (c >> 8) & 0xFF, b := c & 0xFF
    mx := Max(r, g, b), mn := Min(r, g, b)
    if mx >= 115 && mx - mn >= mx * 0.5 {
        d := mx - mn
        h := mx = r ? Mod(60 * (g - b) / d + 360, 360) : mx = g ? 60 * (b - r) / d + 120 : 60 * (r - g) / d + 240
        return h
    }
    if Abs(r - g) < 14 && b - r >= 35 && b >= 128
        return 245                              ; Dark's fill
    return -1
}

HueElement(h, pale) {
    if h < 45 || h >= 345
        return h >= 300 ? "Rose" : "Fire"
    if h < 75
        return "Light"
    if h < 170
        return "Air"
    if h < 228
        return pale ? "Storm" : "Aqua"
    if h < 300
        return "Dark"
    return "Rose"
}

; at the start of a room: the team for its most boosted element, loaded in the game if it isn't yet
PickRoomTeam() {
    global teamLoaded, roomBoosts
    if !roomBoosts.Length                       ; not read (a room picked without its popup): no switching on a guess
        return
    boosts := roomBoosts, roomBoosts := []      ; used once: the next room reads its own
    best := 0, bestPct := -999, why := ""
    for b in boosts
        for k, t in cfg["teams"]
            if t.element != "" && t.element = b.el && b.pct > bestPct
                best := k, bestPct := b.pct, why := b.el (b.pct >= 0 ? " +" b.pct "%" : "")
    k := best ? best : cfg["teamDefault"]
    if k = teamLoaded && k = cfg["team"]
        return
    t := cfg["teams"][k]
    Step("loading " t.name " (Units > Teams)")
    if LoadGameTeam(t.game) {
        global slotOne, slotFull
        if k != teamLoaded
            slotOne := Map(), slotFull := Map()     ; what was learned about the other team's units
        teamLoaded := k
        UseTeam(k, true)
        AddLog("Loaded " t.name " (" (why != "" ? why : "your default team: the room boosts none of your teams' elements") ")")
    } else {
        teamLoaded := 0
        AddLog("Couldn't load " t.name " in the game (Units > Teams), playing with the team that's on")
        SaveDebugShot("team_load")
    }
}

; Units (K) > Teams > LOAD on row n of the game's "Switch Team" list, then both windows closed.
; Measured on Chris's PC in the macro's frame: Teams at 397,222; LOAD at x 566, row 1 at y 231, rows 86
; apart; one wheel notch moves the list 99 px; the list shows y 175-480; "Team changed!" in green below
LoadGameTeam(n) {
    static isGreen := (r, g, b) => g > 150 && r < 130 && b < 130 && g > r + 50
    ReleaseKeys()
    ; K opens the Units window: its green Teams button where it was measured, or the word "Teams"
    ; anywhere in the middle (in a stage the window can sit elsewhere than in the lobby). 4 s, 2 tries
    tx := 397, ty := 222, open := false
    loop 2 {
        Keys("k")
        t0 := A_TickCount
        while !open && A_TickCount - t0 < 4000 {
            if ColorShare(372, 215, 422, 229, isGreen) >= 0.3
                open := true
            else if OcrFindWord(100, 70, 600, 380, "i)^teams?$", &tx, &ty)
                open := true
            else
                Wait(300)
        }
        if open
            break
    }
    if !open {
        AddLog("Teams: the Units window didn't open with K")
        return false
    }
    Clk(tx, ty)                                 ; Teams
    if !WaitFor(() => ColorShare(548, 224, 584, 238, isGreen) >= 0.3 || OcrFindWord(100, 60, 600, 440, "i)switch|^load$", &lx, &ly), 3500, 200) {
        AddLog("Teams: the Switch Team list didn't open")
        CloseTeamWindows()
        return false
    }
    ; to the top of the list, then down until row n's LOAD shows
    MouseMove 400, 330
    loop 12 {
        SendInput "{WheelUp}"
        Sleep 15
    }
    Wait(600)
    ; the list's last ~60 px fade out (a LOAD there is dim, not green): row n is scrolled up to 410
    ; at most (Lunoc's team 6 sat at 462, faded, and wasn't found)
    yAt := 231 + (n - 1) * 86, notches := Max(0, Ceil((yAt - 410) / 99))
    loop notches {
        SendInput "{WheelDown}"
        Sleep 60
    }
    if notches
        Wait(900)
    yAt -= notches * 99
    Stale()
    ; the LOAD button nearest to where row n should be (only LOAD is green: SAVE is blue, CLEAR red);
    ; up to 43 px off (half a row), for a list that stopped scrolling at its end
    best := -1
    loop 87 {
        y := yAt - 43 + A_Index - 1
        if y < 175 || y > 485
            continue
        if ColorShare(552, y - 2, 580, y + 2, isGreen) >= 0.6 && (best < 0 || Abs(y - yAt) < Abs(best - yAt))
            best := y
    }
    if best < 0 {
        AddLog("Teams: no LOAD button where team " n " should be")
        CloseTeamWindows()
        return false
    }
    Clk(566, best)
    ok := WaitFor(() => ColorShare(280, 440, 525, 474, isGreen) >= 0.04, 2500, 120)   ; "Team changed!"
    CloseTeamWindows()
    return ok
}

; closes Switch Team (its red X) and the Units window (its red X)
CloseTeamWindows() {
    Clk(608, 124)
    Wait(500)
    Clk(663, 204)
    Wait(600)
}

; ---------- build order ----------
; The build order and the Units tab are two separate ways to play: with the build order on, only
; its steps place and upgrade (nothing from the Units tab before or after); with it off, the Units
; tab does everything. (They used to mix: the Units tab filled in the rest after the build order.)
BuildMode() => cfg["useBuild"] && cfg["build"].Length
; steps: {kind: "place"|"upgrade", slot, count, up}   up: 0 = none, N = N times, -1 = to max
RunBuildOrder(ctx) {
    ctx.build := true
    for i, st in cfg["build"] {
        if StageOver() {
            ctx.over := true
            return
        }
        AddLog("Step " i ": " StepText(st))
        if st.kind = "place" {
            newOnes := PlaceSlot(ctx, st.slot, st.count)
            if ctx.over
                return
            if newOnes.Length < st.count
                AddLog("Step " i ": only " newOnes.Length " of " st.count " placed")
            if st.up != 0 && newOnes.Length && !UpgradeGroup(newOnes, st.up) {
                ctx.over := true
                return
            }
        } else {
            ; all of that slot's units, or only the first N placed (two Elyssias, only one upgraded)
            list := [], most := st.HasOwnProp("units") && st.units ? st.units : 99
            for u in placedUnits
                if u.slot = st.slot && list.Length < most
                    list.Push(u)
            if !list.Length
                AddLog("Step " i ": no slot " st.slot " units placed yet, skipping")
            else if !UpgradeGroup(list, st.up) {
                ctx.over := true
                return
            }
        }
    }
    ctx.build := false
    AddLog("Build order done (the Units tab isn't used with the build order on)")
    ups := 0
    for st in cfg["build"]
        ups += st.up != 0
    if !ups
        AddLog("Your build order doesn't upgrade anything, so your units stay at level 1. To upgrade units you "
            . "already placed, add an Upgrade step (Build order: switch Place to Upgrade)")
}

StepText(st) {
    up := st.up < 0 ? "to max" : st.up " time" (st.up = 1 ? "" : "s")
    if st.kind = "place"
        return "Place slot " st.slot " x" st.count (st.up = 0 ? "" : ", upgrade each " up)
    n := st.HasOwnProp("units") ? st.units : 0
    return n ? "Upgrade " n " unit" (n = 1 ? "" : "s") " of slot " st.slot " " up : "Upgrade slot " st.slot " " up
}

; how far each unit of an upgrade step got, for the log: "2 of 3 units reached 6 (1 can't be found)"
GroupResult(units, done, times) {
    ok := 0, lost := 0, short := 0
    for u in units {
        if u.lost
            lost++
        else if times < 0 ? u.maxed : (done[u] >= times || u.maxed)
            ok++
        else
            short++
    }
    txt := ok " of " units.Length " unit" (units.Length = 1 ? "" : "s") " reached " (times < 0 ? "max" : times " upgrade" (times = 1 ? "" : "s"))
    extra := []
    if short
        extra.Push(short " not there yet")
    if lost
        extra.Push(lost " couldn't be found on the map")
    for i, e in extra
        txt .= (i = 1 ? " (" : ", ") e (i = extra.Length ? ")" : "")
    return txt
}

; Upgrades a group of units `times` times each (-1 = to max), taking turns:
; unit 1 as far as it can afford -> unit 2 -> unit 3 -> back to unit 1 ... until every
; unit has reached the target. Waits for yen when nobody can afford anything.
; A build order step is exact: the "Until" limit on the Units tab doesn't cut it short.
; Returns false if the stage ended.
UpgradeGroup(units, times) {
    ; counted from the level the menu shows ("Upgrade [5]") when it can be read: counting presses
    ; once called a unit done at level 5 of 6 (a misread level or a flickering price counted a
    ; press that didn't go through). Every unit is checked again before the step moves on.
    done := Map(), start := Map(), checked := false
    for u in units
        done[u] := 0
    lastGainAt := A_TickCount, t0 := A_TickCount
    ; late upgrades cost a lot, so "to max" waits much longer for yen before giving up
    waitMs := times < 0 ? 300000 : 150000
    limitMs := times < 0 ? 0 : (150000 + times * 20000) * units.Length
    loop {
        left := 0, roundGain := 0
        for u in units {
            if u.maxed || u.lost || (times >= 0 && done[u] >= times)
                continue
            left++
            ; this unit: keep upgrading until it reaches the target or can't afford the next one
            loop {
                if StageOver()
                    return false
                g := UpgradeUnit(u, times < 0 ? 3 : Min(3, times - done[u]), false)
                if !start.Has(u) && u.HasOwnProp("lvlOpen") && u.lvlOpen >= 0
                    start[u] := u.lvlOpen
                if start.Has(u) && u.HasOwnProp("lvl") && u.lvl >= 0
                    done[u] := Max(0, u.lvl - start[u])
                else
                    done[u] += g
                if !g
                    break
                roundGain += g, lastGainAt := A_TickCount
                if u.maxed || u.lost || (times >= 0 && done[u] >= times)
                    break
            }
        }
        if !left && times >= 0 && !checked {
            ; one last look at each unit's real level before calling the step done
            checked := true, short := false
            for u in units {
                if u.maxed || u.lost || !start.Has(u)
                    continue
                if !OpenUnit(u)
                    continue
                now := ReadLevel()
                Clk(325, 185)
                Wait(250)
                if now >= 0 && now - start[u] < times {
                    done[u] := Max(0, now - start[u])
                    short := true
                    AddLog("Slot " u.slot ": a unit is at level " now ", not " start[u] + times " yet, upgrading it more")
                }
            }
            if short {
                lastGainAt := A_TickCount
                continue
            }
        }
        if !left {
            ok := 0
            for u in units
                ok += !u.lost && (times < 0 ? u.maxed : done[u] >= times || u.maxed)
            if ok = units.Length
                AddLog("Slot " units[1].slot ": " (times < 0 ? "all fully upgraded" : "upgraded " times " time" (times = 1 ? "" : "s")) (units.Length > 1 ? " (all " units.Length " units)" : ""))
            else
                AddLog("Slot " units[1].slot ": step done. " GroupResult(units, done, times))
            return true                             ; everyone reached the target
        }
        if limitMs && A_TickCount - t0 > limitMs {
            AddLog("Slot " units[1].slot ": upgrade step took too long, moving to the next step. " GroupResult(units, done, times))
            return true
        }
        if !roundGain {
            if A_TickCount - lastGainAt > waitMs {
                AddLog("Slot " units[1].slot ": no upgrade went through for " Round(waitMs / 60000, 1) " min (not enough yen?), moving to the next step. " GroupResult(units, done, times))
                return true
            }
            Step("build order: waiting for yen to upgrade slot " units[1].slot (times < 0 ? " to max" : ""))
            Wait(800)
        }
    }
}

; your saved spots, then the pattern, then a grid over the whole playable area
; (nearest the middle first) so there's always somewhere new to try
PlacementPoints() {
    pts := []
    if cfg["useSpots"] && cfg["spots"].Has(PlaceKey(curMap))
        for p in cfg["spots"][PlaceKey(curMap)]
            pts.Push(p)
    for p in PatternPoints(cfg["pattern"])
        pts.Push(p)
    extra := []
    yy := 100
    while yy <= 530 {
        xx := 40
        while xx <= 760 {
            if !(xx < 295 && yy < 120) {
                near := false
                for q in pts
                    if (q.x - xx) ** 2 + (q.y - yy) ** 2 < 400 {
                        near := true
                        break
                    }
                if !near
                    extra.Push({x: xx, y: yy})
            }
            xx += 45
        }
        yy += 45
    }
    SortByDistance(extra, 390, 300)
    for p in extra
        pts.Push(p)
    return pts
}

PatternPoints(name) {
    cx := 390, cy := 300
    pts := []
    switch name {
        case "Circle":
            for r in [45, 90, 135, 180] {
                n := r = 45 ? 8 : 16
                loop n {
                    ang := (A_Index - 1) * 6.283185 / n
                    pts.Push({x: Round(cx + r * Cos(ang)), y: Round(cy + r * Sin(ang))})
                }
            }
        case "Grid":
            yy := cy - 150
            while yy <= cy + 150 {
                xx := cx - 210
                while xx <= cx + 210 {
                    pts.Push({x: xx, y: yy})
                    xx += 30
                }
                yy += 30
            }
            SortByDistance(pts, cx, cy)
        case "Random":
            loop 300 {
                if pts.Length >= 45
                    break
                p := {x: Random(cx - 200, cx + 200), y: Random(cy - 150, cy + 150)}
                ok := true
                for q in pts
                    if (p.x - q.x) ** 2 + (p.y - q.y) ** 2 < 1600 {
                        ok := false
                        break
                    }
                if ok
                    pts.Push(p)
            }
        default:  ; Spiral: squares outward from the middle
            dirs := [[1, 0], [0, 1], [-1, 0], [0, -1]]
            xx := cx, yy := cy, len := 1, dir := 0
            pts.Push({x: xx, y: yy})
            while pts.Length < 81 {
                loop 2 {
                    loop len {
                        xx += dirs[dir + 1][1] * 40, yy += dirs[dir + 1][2] * 40
                        pts.Push({x: xx, y: yy})
                    }
                    dir := Mod(dir + 1, 4)
                }
                len++
            }
    }
    out := []
    for p in pts {
        if p.x < 30 || p.x > 770 || p.y < 90 || p.y > 540
            continue
        if p.x < 295 && p.y < 120          ; top-left HUD
            continue
        ; right HUD: Current Effects and the DUNGEON INVENTORY button. A click there opened the
        ; inventory (purple curse boxes), taken for the stage being over: Soru's Ruined City spot
        ; stopped after the first units every stage
        if p.x >= 655 && p.y >= 135 && p.y <= 260
            continue
        out.Push(p)
    }
    return out
}

SortByDistance(arr, cx, cy) {
    loop arr.Length - 1 {
        i := A_Index + 1
        item := arr[i]
        dc := (item.x - cx) ** 2 + (item.y - cy) ** 2
        j := i - 1
        while j >= 1 && (arr[j].x - cx) ** 2 + (arr[j].y - cy) ** 2 > dc {
            arr[j + 1] := arr[j]
            j--
        }
        arr[j + 1] := item
    }
}

; can slot n be placed right now? Its price in the unit bar is bright yellow when it can and
; greyed out when it can't (not enough yen, or the game's limit for that unit).
; Unsure (bar hidden) counts as ready, so it just tries.
SlotReady(n) {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        barShown := false, mine := 0
        loop 6 {
            bright := 0, dim := 0, x0 := 252 + (A_Index - 1) * 50, y := 557
            while y < 575 {
                x := x0 + 2
                while x < x0 + 46 {
                    col := scr.GetColor(ox + x, oy + y, 0)
                    r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
                    if r >= 215 && g >= 170 && b <= 110
                        bright++
                    else if r >= 90 && g >= r * 0.6 && b <= r * 0.5
                        dim++
                    x += 2
                }
                y += 2
            }
            if bright + dim >= 8
                barShown := true                        ; the unit bar is on screen
            if A_Index = n
                mine := bright
        }
        return mine >= 4 || !barShown
    }
    return true
}

; slot n's price from the unit bar (read once per stage), or -1
SlotCost(n) {
    global slotPrice
    if slotPrice.Has(n)
        return slotPrice[n]
    v := ReadYellowNumber(252 + (n - 1) * 50, 554, 48, 24)
    if v >= 0 {
        v := String(v)
        if SubStr(v, -1) != "0" && SubStr(v, -2, 1) = "0"
            v := SubStr(v, 1, -1)               ; the yen sign read as a digit: prices end in 0
        if StrLen(v) >= 2 && StrLen(v) <= 7 {
            slotPrice[n] := Integer(v)
            return slotPrice[n]
        }
    }
    return -1
}

; the yen counter above the unit bar, or -1 if it can't be read
ReadYen() => ReadYellowNumber(330, 498, 170, 32)

; ---------- reading the yellow numbers (yen, unit prices) ----------
; The unit portraits stick up over the yen counter, and the screen reader turned that into
; nonsense (2509 read as 10591, or nothing at all). So only the yellow pixels of the digits
; are kept, drawn black on white, and that clean picture is read instead. Small marks lower
; than the digits (the yen sign) are trimmed off. Returns the number, or -1.
ReadYellowNumber(x, y, w, h) {
    txt := ""
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        yel := [], rowCnt := []
        loop h {
            j := A_Index - 1, row := [], n := 0
            loop w {
                col := scr.GetColor(ox + x + A_Index - 1, oy + y + j, 0)
                r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
                isY := (r >= 200 && g >= 140 && b <= 110 && r - b >= 120) ? 1 : 0
                row.Push(isY), n += isY
            }
            yel.Push(row), rowCnt.Push(n)
        }
        ; the line of digits: the tallest block of rows with yellow in them
        b1 := 0, b2 := -1, s := 0
        loop h + 1 {
            i := A_Index
            if i <= h && rowCnt[i] >= 2 {
                if !s
                    s := i
            } else if s {
                if (i - 1) - s > b2 - b1
                    b1 := s, b2 := i - 1
                s := 0
            }
        }
        if !b1 || b2 - b1 < 4
            return -1
        bh := b2 - b1 + 1
        ; characters: runs of columns with yellow (a 1-column gap still counts as the same one)
        occ := []
        loop w {
            c := A_Index, hit := 0
            loop bh
                if yel[b1 + A_Index - 1][c] {
                    hit := 1
                    break
                }
            occ.Push(hit)
        }
        blobs := [], c := 1
        while c <= w {
            if !occ[c] {
                c++
                continue
            }
            st := c
            while c <= w && (occ[c] || (c + 1 <= w && occ[c + 1]))
                c++
            top := 0, bot := 0
            loop bh {
                rr := A_Index
                loop c - st {
                    if yel[b1 + rr - 1][st + A_Index - 1] {
                        if !top
                            top := rr
                        bot := rr
                        break
                    }
                }
            }
            blobs.Push({a: st, z: c - 1, ht: bot - top + 1})
        }
        if !blobs.Length
            return -1
        tall := 0
        for bl in blobs
            tall := Max(tall, bl.ht)
        c1 := 0, c2 := 0
        for bl in blobs
            if bl.ht >= tall * 0.7 {
                if !c1
                    c1 := bl.a
                c2 := bl.z
            }
        ; the yen sign can touch the last digit, but it never reaches the top: trim it off
        topRows := Max(2, Floor(bh * 0.35))
        while c2 > c1 {
            hitTop := false
            loop topRows
                if yel[b1 + A_Index - 1][c2] {
                    hitTop := true
                    break
                }
            if hitTop
                break
            c2--
        }
        ; black on white, 4x bigger, with a white border
        k := 4, pad := 6
        pw := (c2 - c1 + 1 + 2 * pad) * k, ph := (bh + 2 * pad) * k
        pix := Buffer(pw * ph * 4, 0xFF)
        loop bh {
            yy := A_Index - 1, row := yel[b1 + yy]
            loop c2 - c1 + 1 {
                xx := A_Index - 1
                if row[c1 + xx] {
                    loop k {
                        base := (((yy + pad) * k + A_Index - 1) * pw + (xx + pad) * k) * 4
                        loop k
                            NumPut("uint", 0xFF000000, pix, base + (A_Index - 1) * 4)
                    }
                }
            }
        }
        bi := Buffer(40, 0)
        NumPut("uint", 40, bi, 0), NumPut("int", pw, bi, 4), NumPut("int", -ph, bi, 8)
        NumPut("ushort", 1, bi, 12), NumPut("ushort", 32, bi, 14)
        hbm := DllCall("CreateDIBSection", "ptr", 0, "ptr", bi, "uint", 0, "ptr*", &bits := 0, "ptr", 0, "uint", 0, "ptr")
        if !hbm
            return -1
        DllCall("RtlMoveMemory", "ptr", bits, "ptr", pix, "uptr", pw * ph * 4)
        try txt := OCR.FromBitmap(hbm, OcrLang()).Text
        DllCall("DeleteObject", "ptr", hbm)
    }
    for pair in [["O", "0"], ["o", "0"], ["D", "0"], ["l", "1"], ["I", "1"], ["|", "1"], ["S", "5"], ["B", "8"]]
        txt := StrReplace(txt, pair[1], pair[2])
    txt := RegExReplace(txt, "\s+")
    if RegExMatch(txt, "\d[\d,.]{0,9}", &m) {
        v := RegExReplace(m[0], "[^\d]")
        if StrLen(v) >= 1 && StrLen(v) <= 9
            return Integer(v)
    }
    return -1
}

; a spot right next to a unit that's already down: clicking it there selects that unit
; instead of placing (the game says there's no space), which used to count as placed
NextToUnit(x, y) {
    for u in placedUnits
        if (u.x - x) ** 2 + (u.y - y) ** 2 < 22 ** 2
            return true
    return false
}

NearUnit(x, y, r) {
    for u in placedUnits
        if (u.x - x) ** 2 + (u.y - y) ** 2 < r ** 2
            return true
    return false
}

TryPlace(x, y, slot) {
    global autoOpenSeen, autoOpenOff, clickOpened
    ClearVote()                             ; Fool's Hunt: a card vote first (a long run of tries let it run out)
    if VoteOnScreen() {                     ; still up: placing clicks would land on the cards
        Wait(500)                           ; (one picked Enemy Health and never confirmed it)
        return false
    }
    ClosePanel()                            ; the unit panel covers the right side of the map
    if UnitMenuOpen() {                     ; an open menu would look like this placement worked
        Clk(325, 185)
        Wait(250)
    }
    Keys(String(slot))
    Sleep 50
    Clk(x, y)
    Sleep 50
    Keys("q")                               ; cancels the placing if the spot was refused (the path)
    ; the game's red refusals ("Unique units may not be placed with others of its kind",
    ; "Cannot place more than 3 of this unit!") show straight away and fade, so look first
    Sleep 120
    if PlaceRefused(slot)
        return false
    ; Placed = the unit's upgrade menu opens on the left, checked by the menu's own parts (see
    ; MenuParts): the yen can't be read reliably. The game lags now and then, so a late menu
    ; gets extra time.
    how := ""
    if WaitUnitMenu(autoOpenOff ? 300 : PlaceTimeout())
        how := "auto"
    else if PlaceRefused(slot)
        return false
    else if !NearUnit(x, y, 22) {
        ; No menu: nothing was placed, or the menu didn't open (the game's 'Disable Auto-Open
        ; Upgrade UI' setting, or it was just slow). Clicking the spot opens a new unit's menu;
        ; an empty spot does nothing. (It used to click only before any menu had opened by itself
        ; and not within 45 px of a known unit: spots are 40 px apart, so a unit placed next to
        ; another one was never seen, and never upgraded)
        Clk(x, y)
        if WaitUnitMenu(700)
            how := "click"
    }
    if how != "" {
        lvl := ReadLevel()
        if lvl > 0 || MaxShown() {          ; an older unit's menu: the click hit a unit already there
            if !NearUnit(x, y, 45) {        ; no known unit there: maybe a new unit with an odd menu
                AddLog("Slot " slot ": a menu opened (" (lvl > 0 ? "level " lvl : "MAX") ") but no counted unit is near, treated as not placed")
                SaveDebugShot("odd_menu")
            }
            Clk(325, 185)
            Wait(200)
            return false
        }
        if how = "auto"
            autoOpenSeen := true, autoOpenOff := false
        else if !autoOpenSeen && ++clickOpened = 2 && !autoOpenOff {
            autoOpenOff := true
            AddLog("The unit menu doesn't open by itself after placing, so the macro clicks each new unit. Faster: in the game's settings, set 'Disable Auto-Open Upgrade UI' so the menu pops up when you place a unit")
        }
        CheckAbility()
        Clk(325, 185)                       ; close the unit menu
        return true
    }
    if SettingsInTheWay()                   ; the game's Settings window over the map: nothing placed
        return false
    ; no menu and no refusal: usually nothing was placed, but a slow menu means it may have been
    ; (Skyyylyyyy's third Speedwagon was down and never upgraded). Kept in case the game says so later
    if !placeUnsure.Has(slot)
        placeUnsure[slot] := []
    placeUnsure[slot].Push({x: x, y: y})
    return false
}

; the game says a slot is at its limit with `k` more down than were seen: they're at the latest spots
; where no menu showed. Added as placed units, so they get upgraded like the others
FindUnseen(slot, k) {
    found := 0, list := placeUnsure.Get(slot, [])
    while k > 0 && list.Length {
        p := list.Pop()
        if NearUnit(p.x, p.y, 15)
            continue
        u := {x: p.x, y: p.y, slot: slot, maxed: false, capped: false, dx: 0, dy: -3, misses: 0, lost: false}
        placedUnits.Push(u), unseenFound.Push(u), k--, found++
    }
    return found
}

; the units FindUnseen added for this slot (PlaceSlot counts them as placed, and a "place and
; upgrade" step upgrades them too)
TakeUnseen(slot) {
    global unseenFound
    out := [], keep := []
    for u in unseenFound {
        if u.slot = slot
            out.Push(u)
        else
            keep.Push(u)
    }
    unseenFound := keep
    return out
}

; The game refused the unit with a red message: remember the limit so the macro stops trying.
PlaceRefused(slot) {
    global mapFull
    static toldMsg := false, toldFull := -1, lastAt := 0, lastSlot := 0
    msg := LimitMessage(&said)
    if msg = ""
        return false
    ; the red text stays up for a few seconds: seen right after another slot's refusal, it's that
    ; old message, not this slot's (it gave every next slot a limit of 0, one second each)
    if slot != lastSlot && A_TickCount - lastAt < 4000
        return false
    lastAt := A_TickCount, lastSlot := slot
    if msg = "limit" && !toldMsg {
        toldMsg := true
        AddLog("The game said: " RegExReplace(Trim(said), "\s+", " "))
    }
    ; a limit for the whole map (some modes, like Fool's Hunt, cap the total): it isn't this unit's
    ; limit, so no slot gets locked; it upgrades and tries placing again a minute later (room can open up).
    ; Before, it was saved as this unit's limit, even "0" for a slot with none placed
    ; "Cannot place more than 20 units! Sell some weaker ones to make room." (Fool's Hunt): summons
    ; like Elyssia's eels count too, so it can come before your own units reach 20
    ; only a clear "of this unit" is that unit's limit (it stops the slot for the map); anything
    ; else counts as the map being full, which just waits a minute and tries again
    ; the number tells them apart too: a unit's limit is small (3 of this unit), the map's is 20
    most := RegExMatch(said, "i)t{1,3}h?[ae]n\s*(\d[\dOo]?)", &mm) ? Integer(RegExReplace(mm[1], "[Oo]", "0")) : 0   ; "than", "tttan"
    mapWords := RegExMatch(said, "i)sell|weaker|make\s*r|r[o0][o0]m\b|un[il1]ts")
    thisUnit := !mapWords && (RegExMatch(said, "i)th[il1]s\s*un[il1]t|of\s*th[il1]s|of\s*the\s*un") || most && most < 10)
    if msg = "limit" && !thisUnit {
        ; a full map with fewer than 5 units down can't be: some other red text was read (Ted: "the map
        ; is full" at the start with 0 placed, every Place step got 0 and the build order ran out)
        if placedUnits.Length < 5 {
            static toldEarly := -1
            if toldEarly != stageStart {
                toldEarly := stageStart
                AddLog("Red text read (" SubStr(RegExReplace(Trim(said), "\s+", " "), 1, 70) ") with " placedUnits.Length " units down: not taken as the map being full")
            }
            return false
        }
        mapFull := A_TickCount
        if toldFull != stageStart {
            toldFull := stageStart
            most := RegExMatch(said, "(\d+)\s*un", &mm) ? mm[1] : ""
            AddLog("The map is full" (most != "" ? " (the game allows " most " units, summons count too)" : "")
                . ". Upgrading instead; trying to place again every minute in case room opens up")
        }
        return true
    }
    if msg = "limit" {
        ; "more than 3 of this unit" with fewer counted: the rest were placed, but their menu didn't
        ; show in time, so the macro didn't see it. The game's number is the real limit (it was
        ; saved as 0 for the map before, and nothing of that slot was placed there again)
        have := CountPlaced(slot)
        if most > have {
            slotCap[CapKey(slot)] := most
            found := FindUnseen(slot, most - have)
            AddLog("Slot " slot ": the game allows " most " of this unit. " most - have " of them got placed without the macro seeing it"
                . " (the unit's menu didn't show in time)" (found ? ": found where " (found = 1 ? "it is" : "they are") ", upgrading " (found = 1 ? "it" : "them") " too" : "")
                . (found < most - have ? ". Set Placement speed slower in Settings" : ""))
        } else if have {
            ; the number wasn't read ("Cannot place more tttan 3"): no limit is saved for next time, a
            ; wrong 2 kept every later stage at 2 of a unit the game allows 3 of
            AddLog("Slot " slot ": the game says no more of this unit (" have " seen placed), placing no more this stage")
        } else
            AddLog("Slot " slot ": the game says no more of this unit, but none were seen being placed. "
                . "Placing it again next stage (if this keeps happening: Placement speed slower in Settings)")
        slotFull[slot] := stageStart              ; no more of it this stage either way
        return true
    }
    return false
}

; the game's red refusal in the middle of the screen: "unique" for "Unique units may not be
; placed with others of its kind", "limit" for "Cannot place more than N of this unit!", else ""
LimitMessage(&txt := "") {
    red := 0
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Stale(), Fresh()
        scr := FindText()
        yy := 60                                ; from just under the wave counter, where "Cannot place
        while yy <= 500 {                       ; more than 20 units!" shows (it was missed from 120 down)
            xx := 150
            while xx <= 650 {
                col := scr.GetColor(ox + xx, oy + yy, 0)
                r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
                if r >= 200 && g <= 90 && b <= 100
                    red++
                xx += 3
            }
            yy += 3
        }
    }
    txt := ""
    if red < 40
        return ""
    ; the text reader garbles it often over a busy map ("Cannot place more than 20 units!" came
    ; out as "Cannot,rldc"), so any piece of it counts; a second, closer read of the strip under
    ; the wave counter when the first finds nothing
    static limitWords := "i)c[a@]nn[o0]t|can.t\s*pl|m[o0]re\s*th|rn[o0]re\s*th|th[ae]n\s*\d+\s*un|sell\s*s|make\s*r[o0]|weaker"
    try {
        WinGetClientPos &ox, &oy, , , RBX
        txt := OCR.FromRect(ox + 100, oy + 60, 600, 450, OcrLang(), {scale: 2, grayscale: true}).Text
        if !RegExMatch(txt, limitWords)
            txt .= " " OCR.FromRect(ox + 100, oy + 70, 600, 110, OcrLang(), {scale: 3, grayscale: true}).Text
    }
    if RegExMatch(txt, limitWords)
        return "limit"
    return ""
}

PlaceTimeout() {
    static speeds := [1000, 1500, 2000, 2500, 3000, 4000, 5000]
    i := cfg["placeSpeed"]
    return (i >= 1 && i <= speeds.Length) ? speeds[i] : 2000
}

; The unit menu's own parts: its red X, its "Upgrade N" text or MAX. Its dark colours alone
; also matched dark ground, so a click on the path counted as a placed unit. If a PC never
; shows the parts the way the macro knows them (after several colour-only menus and no real
; one), it goes back to the colours, so placing never gets stuck.
global menuLoose := false
MenuParts() => MenuButtons() || Det("UnitExit") || ReadLevel() >= 0 || MaxShown() || FT(&fx, &fy, 171, 348, 337, 447, 0, 0, UnitExistence)

; The menu's three buttons in a row at its bottom: targeting (light blue: "First", "Strongest"...),
; Sell (red) and Upgrade (green). The same colours whatever a button says or the game's language,
; and nothing on the map has those three side by side in that order. (Measured on a screenshot
; of the macro's window: about 120 / 130 / 380 matching dots, and 0 on screenshots without a menu.)
MenuButtons() {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        cn := 0, cx := 0, cy := 0, rn := 0, rx := 0, ry := 0, gn := 0, gx := 0, gy := 0
        y := 330
        while y <= 400 {
            x := 15
            while x <= 320 {
                col := scr.GetColor(ox + x, oy + y, 0)
                r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
                if r <= 70 && g >= 170 && b >= 200
                    cn++, cx += x, cy += y
                else if r >= 150 && g <= 50 && b <= 50
                    rn++, rx += x, ry += y
                else if r <= 90 && g >= 170 && b <= 60
                    gn++, gx += x, gy += y
                x += 3
            }
            y += 3
        }
        if cn < 40 || rn < 30 || gn < 60
            return false
        cx /= cn, cy /= cn, rx /= rn, ry /= rn, gx /= gn, gy /= gn
        return cx < 120 && cx < rx && rx < gx && gx > 160 && Abs(cy - ry) <= 12 && Abs(gy - ry) <= 14
    }
    return false
}

WaitUnitMenu(timeout) {
    global menuLoose
    static partsSeen := false, colourOnly := 0
    Wait(300)
    t0 := A_TickCount, n := 0, colourHit := false
    while A_TickCount - t0 < timeout {
        Chk()
        FocusRoblox()
        if PixelSearch(&px, &py, 178, 309, 305, 336, 0x000000, 12)
            && (PixelSearch(&px, &py, 192, 244, 237, 400, 0xFFFFFF, 12) || PixelSearch(&px, &py, 192, 244, 237, 400, 0xFFC806, 20)) {
            Stale()
            colourHit := true
            if MenuParts() {
                partsSeen := true, colourOnly := 0
                return !IsSummonMenu()
            }
            if menuLoose
                return !IsSummonMenu()
        }
        if Mod(++n, 4) = 0 {                    ; every ~100 ms also look for the menu's buttons / upgrade text
            Stale()
            if MenuButtons() || ReadLevel() >= 0 || MaxShown() {
                partsSeen := true, colourOnly := 0
                return !IsSummonMenu()
            }
        }
        Sleep 25
    }
    if colourHit && !partsSeen && !menuLoose && ++colourOnly >= 6 {
        menuLoose := true
        AddLog("The unit menu's buttons aren't recognised on this PC, going by its colours instead")
        SaveDebugShot("unit_menu")
    }
    return false
}

; is a unit's menu open right now? (same checks as WaitUnitMenu, just once)
UnitMenuOpen() {
    try {
        FocusRoblox()
        if PixelSearch(&px, &py, 178, 309, 305, 336, 0x000000, 12)
            && (PixelSearch(&px, &py, 192, 244, 237, 400, 0xFFFFFF, 12) || PixelSearch(&px, &py, 192, 244, 237, 400, 0xFFC806, 20))
            return !IsSummonMenu()
        Stale()
        return (ReadLevel() >= 0 || MaxShown()) && !IsSummonMenu()
    }
    return false
}

; Clicks a placed unit and checks its menu really opened. A unit doesn't always sit exactly on
; the spot that was clicked to place it (the model stands above it, big units are offset), so
; if the menu doesn't open it tries a few spots close by - mostly just above - and remembers
; the one that worked for next time. Small steps only, so it doesn't grab a neighbour instead.
; After 3 failed visits in a row the unit is left alone (it may have been sold or moved).
OpenUnit(u) {
    static around := [[0, -3], [0, -11], [0, -19], [-8, -8], [8, -8], [0, 5], [-8, -16], [8, -16], [0, -27]]
    ; let any open menu close fully first (a closing menu made the next click look like a miss)
    if UnitMenuOpen() {
        Clk(325, 185)
        WaitFor(() => !UnitMenuOpen(), 1200, 100)
    }
    tries := [[u.dx, u.dy]]
    for o in around
        if o[1] != u.dx || o[2] != u.dy
            tries.Push(o)
    covered := false                            ; a summon (Abyssal Eel) opened instead: the unit is under it
    for o in tries {
        if covered && MaxShown() && IsSummonMenu() {
            Clk(325, 185)                       ; the eel's menu off first
            Sleep(250)
        }
        Clk(u.x + o[1], u.y + o[2])
        ; the menu can take a moment to slide in: give it a full second before calling it a miss
        if WaitUnitMenu(A_Index = 1 ? 1300 : 1000) || (Sleep(250), UnitMenuOpen()) {
            if A_Index > 1 {
                ; only move the remembered spot after the old one missed twice in a row
                u.offMiss := (u.HasOwnProp("offMiss") ? u.offMiss : 0) + 1
                if u.offMiss >= 2 {
                    if !u.HasOwnProp("told")
                        AddLog("Slot " u.slot ": the unit sits a bit off its spot, clicking " (o[2] < 0 ? -o[2] "px higher" : o[2] "px lower") (o[1] ? " and " Abs(o[1]) "px " (o[1] < 0 ? "left" : "right") : "") " from now on"), u.told := true
                    u.dx := o[1], u.dy := o[2], u.offMiss := 0
                }
            } else
                u.offMiss := 0
            u.misses := 0
            return true
        }
        if !covered && MaxShown() && IsSummonMenu()
            covered := true
    }
    if covered {
        ; the unit's there, an eel swims over it: not a miss (it was left for good after 3 of these,
        ; Chris's slot 2). Tried again on the next visit, when the eel has moved on
        Clk(325, 185)
        if !u.HasOwnProp("eelTold")
            u.eelTold := true, AddLog("Slot " u.slot ": a summon (Abyssal Eel) is over this unit, trying it again later")
        return false
    }
    u.misses++
    if u.misses >= 3 {
        u.lost := true
        AddLog("Slot " u.slot ": can't find this unit at " u.x "," u.y " any more, leaving it")
        SaveDebugShot("unit_missing")
    }
    Clk(560, 560)
    return false
}

; ---------- the Unit Overview panel (F) ----------
; Press F in a stage and a panel opens on the right with a card per placed unit: a green
; "Upg: 1500¥" button (dark green "Max" when it's done) and a row of bars that light up
; per upgrade. Newest units are at the top, the first one placed at the bottom. Upgrading
; from here doesn't depend on where a unit stands on the map or how the camera moved.
; Positions measured on a recording of the macro's 800x600 window.
; Never click near a card's top-left corner: that red X sells the unit.

; the red Return button at the bottom and the orange "Unit Overview" title at the top
PanelOpen() => ColorShare(615, 524, 705, 548, IsReddish) >= 0.5 && ColorShare(560, 80, 770, 96, IsTitleOrange) >= 0.1

IsTitleOrange(r, g, b) => r >= 200 && g >= 120 && g <= 200 && b <= 60

ClosePanel() {
    if !PanelOpen()
        return
    Clk(660, 536)                                   ; Return
    WaitFor(() => !PanelOpen(), 1000, 100)
}

; ---------- upgrading ----------
UpgradeAndWatch() {
    lastAfk := A_TickCount
    hudMiss := 0, hudSeen := false
    loop {
        if StageOver()
            return
        ; safety net: if the game's bottom bar (yen / units) was there and has now been gone for
        ; several checks in a row, the stage ended on a screen we don't recognise: stop clicking units
        if Det("Yen") || Det("Units")
            hudSeen := true, hudMiss := 0
        else
            hudMiss++
        if hudSeen && hudMiss >= 4 {
            AddLog("The stage looks over but the end screen wasn't recognised")
            return
        }
        if BuildMode() {                       ; the build order did it all: just watch the stage
            busy := false
            AbilityPass()
            Step("build order done, watching the stage")
        } else {
            TopUpUnits()
            busy := UpgradePass()
            if !busy {
                Step("units done, watching the stage")
                UpgradesDoneHint()
            }
        }
        if A_TickCount - lastAfk > 60000 {
            Clk(560, 560)
            lastAfk := A_TickCount
        }
        CloseChat()
        if Det("UnitExit", &fx, &fy)
            Clk(fx - 4, fy - 35)
        if CheckConnection()
            return
        ; nothing affordable this round: give the yen a moment to build up
        Wait(!busy ? 700 : lastGain ? 200 : 1500)
    }
}

; Units that couldn't be placed at the start (not enough yen yet, e.g. a 10000 yen unit) used
; to be forgotten for the rest of the stage. Now they're placed as soon as the game shows
; their card as affordable. Each slot gets a go at most every 20 s and 4 times a stage, so a
; unit with no room on the map can't hold things up. With "Save yen for the top priority" on,
; a missing unit waits until the higher-priority units are done upgrading.
TopUpUnits() {
    static lastTry := Map(), tries := Map(), stageMark := -1
    if FoolRandom()                                 ; Fool's Hunt places its random units itself
        return false
    if stageMark != stageStart
        lastTry := Map(), tries := Map(), stageMark := stageStart
    topPrio := 99
    for u in placedUnits
        if !u.maxed && !u.capped && !u.lost && cfg["slots"][u.slot].up
            topPrio := Min(topPrio, cfg["slots"][u.slot].prio)
    for i, sl in cfg["slots"] {
        if !sl.on || sl.count < 1
            continue
        need := SlotRoom(i, sl.count - CountPlaced(i))
        if need <= 0 || tries.Get(i, 0) >= 4 || A_TickCount - lastTry.Get(i, 0) < 20000
            continue
        if cfg["saveForTop"] && sl.prio > topPrio
            continue
        if !SlotReady(i)                            ; card greyed out: can't afford it yet
            continue
        yen := ReadYen(), cost := SlotCost(i)
        if yen >= 0 && cost > 0 && yen < cost
            continue
        lastTry[i] := A_TickCount, tries[i] := tries.Get(i, 0) + 1
        AddLog("Slot " i ": enough yen now, placing the " need " still missing")
        PlaceSlot(NewPlaceCtx(), i, need)
        if mapFull >= lastTry[i]                    ; refused because the map was full: doesn't count
            tries[i] -= 1
        return true                                 ; one slot per round, then upgrades get a turn
    }
    return false
}

; once a stage, when everything is done: say which slots aren't being upgraded at all, so
; "it just placed them" is clear (Upgrade off on the Units tab, or the build order is off)
UpgradesDoneHint() {
    static told := -1
    if told = stageStart
        return
    told := stageStart
    off := ""
    for i, sl in cfg["slots"]
        if sl.on && sl.count > 0 && !sl.up && CountPlaced(i)
            off .= (off = "" ? "" : ", ") i
    if off != ""
        AddLog("All upgrades done. Slot" (InStr(off, ",") ? "s " : " ") off " have Upgrade switched off on the Units tab"
            . (!cfg["useBuild"] && cfg["build"].Length ? " (and the build order is switched off on the Build tab)" : ""))
}

; Goes through the units in priority order (1 first). Each one is upgraded while you can
; afford it; a unit you can't afford yet is skipped so the others still get upgraded.
; With "Save yen for the top priority" on, it waits for the top unit instead.
; Returns false when every unit is done.
; ignoreSave: upgrade everyone even with "Save yen for the top priority" on
; (used between placement tries, when it's waiting anyway)
UpgradePass(ignoreSave := false) {
    global lastGain
    lastGain := 0
    todo := []
    loop 6 {
        p := A_Index
        for u in placedUnits
            if !u.maxed && !u.capped && !u.lost && (cfg["slots"][u.slot].up || FoolRandom()) && cfg["slots"][u.slot].prio = p
                todo.Push(u)
    }
    if !todo.Length
        return false
    i := 1
    while i <= todo.Length {
        ; every unit with the same priority gets its turn
        p := cfg["slots"][todo[i].slot].prio, groupDone := true
        while i <= todo.Length && cfg["slots"][todo[i].slot].prio = p {
            u := todo[i], i++
            if StageOver()
                return true
            lastGain += UpgradeUnit(u)
            if !u.maxed && !u.capped && !u.lost
                groupDone := false
        }
        ; saving up: don't spend on lower priorities until this whole group is done
        if cfg["saveForTop"] && !ignoreSave && !groupDone
            return true
    }
    return true
}

; returns how many levels it went up this time (0 = couldn't afford it)
UpgradeUnit(u, presses := 3, useLimit := true) {
    lim := useLimit && !FoolRandom() ? cfg["slots"][u.slot].limit : 0
    Step("upgrading slot " u.slot)
    u.lvlOpen := -1
    if !OpenUnit(u)
        return 0
    lvl := ReadLevel()
    u.lvlOpen := lvl                            ; the level as the menu opened (-1 = couldn't read it)
    if lvl >= 0
        u.lvl := lvl
    gained := 0
    loop presses {
        if lim && (lvl >= 0 ? lvl >= lim : AtUpgradeLevel(lim)) {
            u.capped := true                    ; its limit, not the real max: a build step can still go further
            AddLog("Slot " u.slot " reached upgrade " lim " (its Until limit on the Units tab)")
            break
        }
        priceBefore := UpgradeButtonBits()
        Keys("r")
        if MaxReached() {
            u.maxed := true, gained++
            AddLog("Slot " u.slot " is fully upgraded")
            break
        }
        now := ReadLevel()
        if lvl >= 0 && now >= 0 {
            if now <= lvl {                     ; level didn't change: not enough yen yet, or maxed
                if MaxByText() {
                    u.maxed := true
                    AddLog("Slot " u.slot " is fully upgraded")
                }
                break
            }
            gained += now - lvl, lvl := now
        } else if BitDiff(priceBefore, UpgradeButtonBits()) >= 6
            gained++                            ; can't read the level, but the price changed: it went up
        else
            break                               ; same price: not enough yen yet
    }
    if lvl >= 0
        u.lvl := lvl                            ; the level it ended on
    if gained && !u.maxed
        Step("slot " u.slot " upgraded" (lvl >= 0 ? " to level " lvl : ""))
    CheckAbility()
    Clk(325, 185)
    Clk(560, 560)
    return gained
}

MaxReached() {
    Wait(400)
    return MaxShown() && !IsSummonMenu()
}

; Some units (Elyssia) spawn summons like the Abyssal Eel. A summon's menu says "Upgrade [0] (MAX)"
; (level 0 and maxed at once, which a real unit never is) and sells for 0. When an eel swims over
; a unit, clicking that unit opens the eel's menu: that made the unit count as fully upgraded.
; Such a menu is treated as the wrong one, so the macro clicks around the eel instead.
IsSummonMenu() {
    static told := false
    ; summons always show MAX, so the name is only read when MAX is there (keeps it quick)
    hit := Det("Elyssia") || (MaxShown() && (ReadLevel() = 0 || OcrFindWord(4, 188, 160, 30, "i)^(abyssal|eel|eels)$", &wx, &wy)))
    if hit && !told {
        told := true
        AddLog("A summon (like Elyssia's Abyssal Eel) was in the way of a unit. Its menu is skipped, the macro clicks around it")
    }
    return hit
}

MaxShown() => Det("Max") || Det("MaxNew")

; the white price text on the green Upgrade button, as bits: if it changes after pressing R,
; the unit went up a level (used when the "Upgrade N" text can't be read)
UpgradeButtonBits() {
    bits := ""
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Stale(), Fresh()
        scr := FindText()
        y := 355
        while y <= 376 {
            x := 192
            while x <= 302 {
                col := scr.GetColor(ox + x, oy + y, 0)
                bits .= Min((col >> 16) & 0xFF, (col >> 8) & 0xFF, col & 0xFF) >= 200 ? "1" : "0"
                x += 2
            }
            y += 2
        }
    }
    return bits
}

BitDiff(a, b) {
    if a = "" || StrLen(a) != StrLen(b)
        return 0
    n := 0
    loop StrLen(a)
        n += SubStr(a, A_Index, 1) != SubStr(b, A_Index, 1)
    return n
}

; backup for when the "MAX" picture doesn't match: read the word in the unit menu
MaxByText() {
    if IsSummonMenu()
        return false
    return OcrFindWord(220, 230, 85, 185, "i)^MAX\W*$", &mx, &my)
}

; the unit's upgrade level from its menu (0-10), or -1 if it can't be read
ReadLevel() {
    static texts := 0
    if !IsObject(texts)
        texts := [Upgrade0, Upgrade1, Upgrade2, Upgrade3, Upgrade4, Upgrade5, Upgrade6, Upgrade7, Upgrade8, Upgrade9, Upgrade10]
    i := texts.Length                           ; check 10 before 1, "Upgrade 1" is part of "Upgrade 10"
    while i >= 1 {
        if Seen(170, 228, 312, 252, texts[i], 0, true)
            return i - 1
        i--
    }
    return -1
}

AtUpgradeLevel(level) {
    static texts := 0
    if !IsObject(texts)
        texts := [Upgrade1, Upgrade2, Upgrade3, Upgrade4, Upgrade5, Upgrade6, Upgrade7, Upgrade8, Upgrade9]
    if level < 1 || level > texts.Length
        return false
    return Seen(170, 228, 312, 252, texts[level], 0, true)     ; exact: 1 and 7 look alike
}

CheckAbility() {
    if cfg["autoAbility"] && Det("AutoOff") {
        Clk(373, 237)
        return true
    }
    return false
}

; Build order on: after the last step the macro only watches, so no unit's menu was opened again and
; an ability that shows up later (or a unit without an upgrade step) never got Auto switched on.
; Every 90 s each placed unit's menu is opened once more to check (3 times per unit at most)
AbilityPass() {
    static lastAt := 0
    if !cfg["autoAbility"] || A_TickCount - lastAt < 90000
        return
    lastAt := A_TickCount
    for u in placedUnits.Clone() {
        if u.lost || (u.HasOwnProp("abilityChecks") && u.abilityChecks >= 3) || StageOver()
            continue
        u.abilityChecks := (u.HasOwnProp("abilityChecks") ? u.abilityChecks : 0) + 1
        Step("checking slot " u.slot "'s ability")
        if OpenUnit(u) {
            Wait(300)
            if CheckAbility() {
                u.abilityChecks := 3
                AddLog("Slot " u.slot ": ability switched to Auto")
            }
            Clk(325, 185)                       ; close the unit menu
            Wait(200)
        }
    }
}

StageOver() {
    Chk()
    FoolTick()                                  ; Fool's Hunt: card votes and the hotbar
    return Det("Xp") || Det("EndScreen") || Det("Next") || Det("Lobby") || EndButtonsSeen()
        || Det("FinishDungeon") || Det("DungeonDeath") || SpecialScreen() || ScanRooms().Length
}

; =====================================================================
;  End of a stage
; =====================================================================
ReadResult() {
    global lastResult
    if Det("Victory")
        lastResult := "win"
    else if Det("Defeat")
        lastResult := "loss"
    else if (k := TitleColour()) != ""
        lastResult := k                       ; the gold VICTORY / red DEFEAT title, by colour
    if ICMode() && lastResult = "win"
        IcReadUnlocked()
}

; Infinity Castle on Hard: one win unlocks 2 rooms ("Room completed! Room 42 unlocked!" twice, under
; the VICTORY box), so the session counted 14 floors where 28 were cleared. The green lines are read
; while the results show: how many rooms opened, and the highest one (the floor you're on next).
; Read once per stage; when they can't be read, Hard counts 2 and Normal 1
global icUnlocked := 0, icUnlockedTop := 0
IcReadUnlocked() {
    global icUnlocked, icUnlockedTop
    static stageMark := -1
    if stageMark = stageStart && icUnlocked
        return
    stageMark := stageStart
    try {
        WinGetClientPos &ox, &oy, , , RBX
        txt := OCR.FromRect(ox + 150, oy + 330, 500, 200, OcrLang(), {scale: 2, grayscale: true}).Text
        n := 0, top := 0, pos := 1
        while pos := RegExMatch(txt, "i)r[o0]{2}m\W*(\d{1,4})\W*un[l1i]ock", &m, pos)
            n++, top := Max(top, Integer(m[1])), pos += m.Len
        if n
            icUnlocked := n, icUnlockedTop := top
    }
}

; counts the stage once (win / loss / time), whichever end screen shows first
FinishStage() {
    global stageActive, postStage
    postStage := A_TickCount
    if stageActive {
        stageActive := false
        RecordRun()
    }
}

HandleEnd() {
    global icFloors, icFloor
    ReadResult()
    FinishStage()
    if challengeOn {                            ; Auto challenge: back to the lobby, then farming
        ChallengeEnded()
        return
    }
    if lastResult = "loss" && cfg["stopAfterDefeat"] {
        AddLog("Defeat, stopping (Stop after a defeat is on)")
        SendWebhook("Stopped after a defeat", Summary(), 0xDC2626)
        ClickDet("EndScreen", 0, -35)
        StopMacro()
        Chk()
    }
    if LegendMode() {
        LegendReplay()
        return
    }
    if ICMode() {
        ; the results screen's yellow button is "next floor" after a win and "replay" after a loss
        if lastResult = "win" {
            global icUnlocked, icUnlockedTop
            n := icUnlocked ? icUnlocked : cfg["icHard"] ? 2 : 1    ; Hard: a win opens 2 rooms
            icFloors += n
            if icUnlockedTop
                icFloor := icUnlockedTop        ; "Room 43 unlocked": the next floor
            else if icFloor
                icFloor += n                    ; on to the next floor (the loading screen corrects it)
            AddLog("Infinity Castle" (cfg["icHard"] ? " (Hard)" : "") ": " (n = 1 ? "floor" : n " floors") " cleared"
                . (icUnlockedTop ? ", room " icUnlockedTop " unlocked" : "") " (" icFloors " this session)")
            icUnlocked := 0, icUnlockedTop := 0
            UpdateMapLabel(), UpdateStats()
            if cfg["icStopFloors"] && icFloors >= cfg["icStopFloors"] {
                AddLog("Cleared " icFloors " floors, stopping (Stop after on the Dungeon tab)")
                SendWebhook("Infinity Castle: " icFloors " floors cleared", Summary(), 0x22C55E)
                StopMacro()
                Chk()
            }
        }
        if ChallengeLeave()                     ; a new challenge is up: the lobby instead
            return
        Step(lastResult = "win" ? "going to the next floor" : "trying the floor again")
        ClickOpenDungeon()
        Wait(800)
        t0 := A_TickCount
        while A_TickCount - t0 < 10000 {
            Stale()
            if !Det("EndScreen")
                break
            Wait(250)
        }
        if !Det("EndScreen")
            LoadStage()                         ; each floor can be a different map: read it
        return
    }
    Step("opening the dungeon for the next room")
    ClickOpenDungeon()
    Wait(800)
}

; The results screen has a green "Return to lobby" and a yellow "Open Dungeon" button side by side.
; Reads rows across the top of the screen and looks for a wide green stretch followed straight
; away by a wide yellow one. Needs that on 3+ rows, so a stray green or yellow pixel can't fool it.
; (Tested on the recording where the old check failed: found on every frame once the buttons
; had faded in, and never fired on any other screen.)
EndByColourLog() {
    static told := false
    if !told
        told := true, AddLog("Results screen found by its button colours (its text wasn't recognised)")
}

; The results screen found by its colours: the green "Return to lobby" and yellow "Open Dungeon"
; buttons side by side. Its text didn't match on some players' games (another game language, a
; different text size): the macro never saw the stage end and kept upgrading. At most every 1.5 s.
EndButtonsSeen(now := false) {
    static last := 0, was := false
    if !now && A_TickCount - last < 1500
        return was
    last := A_TickCount
    was := FindOpenDungeon(&bx, &by) || NextByColour(&bx, &by)
    return was
}

; The VICTORY / DEFEAT results with the green Next button under the title, found by colour: on
; some players' games the "Next" text wasn't recognised and the macro kept upgrading forever.
; Gives the button's middle in game-area coords.
NextByColour(&cx, &cy) {
    if Det("Shop") || TitleColour(&tx) = ""
        return false
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        xs := [], ys := []
        py := 370
        while py <= 480 {
            from := 0, last := -99, bestW := 0, bestX := 0
            px := 200
            while px <= 602 {
                isG := false
                if px <= 600 {
                    col := scr.GetColor(ox + px, oy + py, 0) & 0xFFFFFF
                    r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
                    isG := g > 170 && r < 150 && b < 120
                }
                if isG {
                    if px - last > 14                ; letters split the button: small gaps join up
                        from := px
                    last := px
                } else if last > 0 && px - last > 14 && from {
                    if last - from > bestW
                        bestW := last - from, bestX := (from + last) // 2
                    from := 0
                }
                px += 2
            }
            if bestW >= 60 && bestW <= 240
                xs.Push(bestX), ys.Push(py)
            py += 3
        }
        if xs.Length < 3
            return false
        cx := MiddleOf(xs), cy := MiddleOf(ys)
        return Abs(cx - tx) <= 90               ; the button sits under the title
    }
    return false
}

; p-th percentile of a list of numbers
Pct(nums, p) {
    txt := ""
    for n in nums
        txt .= (txt = "" ? "" : ",") n
    parts := StrSplit(Sort(txt, "N D,"), ",")
    return Integer(parts[Max(1, Min(parts.Length, Round(parts.Length * p / 100)))])
}

; the results title by colour: "win" for the gold VICTORY, "loss" for the red DEFEAT, else "".
; Also needs the dark results panel under the title (so a sandy map isn't taken for VICTORY).
; tx = the title's middle.
TitleColour(&tx := 0) {
    gold := 0, red := 0, sx := 0, dark := 0, cnt := 0, gx := [], gy := [], rx := [], ry := []
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        py := 165
        while py <= 290 {
            px := 180
            while px <= 620 {
                col := scr.GetColor(ox + px, oy + py, 0) & 0xFFFFFF
                r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
                if r > 220 && g > 150 && g < 235 && b < 90
                    gold++, gx.Push(px), gy.Push(py)
                else if r > 190 && g < 70 && b < 70
                    red++, rx.Push(px), ry.Push(py)
                px += 3
            }
            py += 3
        }
        if gold < 120 && red < 120
            return ""
        ; the title is one wide, flat band of letters (VICTORY ~280 x 40): not the shop's stacked
        ; yellow price buttons or a lobby's scattered red text
        xs := gold >= red ? gx : rx, ys := gold >= red ? gy : ry
        x1 := Pct(xs, 10), x2 := Pct(xs, 90), y1 := Pct(ys, 10), y2 := Pct(ys, 90)
        if x2 - x1 < 180 || y2 - y1 > 60
            return ""
        tx := (x1 + x2) // 2
        ; the panel between the title and the button ("Total Time", "Waves Completed") is dark
        py := 300
        while py <= 360 {
            px := tx - 120
            while px <= tx + 120 {
                col := scr.GetColor(ox + px, oy + py, 0) & 0xFFFFFF
                cnt++, dark += ((col >> 16) & 0xFF) + ((col >> 8) & 0xFF) + (col & 0xFF) < 270
                px += 6
            }
            py += 6
        }
    }
    if cnt && dark / cnt < 0.45
        return ""
    return gold >= 120 ? "win" : red >= 120 ? "loss" : ""
}

FindOpenDungeon(&cx, &cy) {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        scr := FindText()
        hitX := [], hitY := []
        py := 70
        while py <= 180 {
            runs := [], was := "", runFrom := 0
            px := 140
            while px <= 722 {
                kind := ""
                if px <= 720 {
                    col := scr.GetColor(ox + px, oy + py, 0) & 0xFFFFFF
                    r := (col >> 16) & 0xFF, g := (col >> 8) & 0xFF, b := col & 0xFF
                    kind := g > 170 && r < 150 && b < 120 ? "g" : r > 200 && g > 130 && b < 100 ? "y" : ""
                }
                if kind !== was {
                    if was != "" {
                        ; letters split a button into pieces, so pieces of one colour close together join up
                        if runs.Length && runs[runs.Length][1] == was && runFrom - runs[runs.Length][3] <= 14
                            runs[runs.Length][3] := px - 2
                        else
                            runs.Push([was, runFrom, px - 2])
                    }
                    was := kind, runFrom := px
                }
                px += 2
            }
            for i, gr in runs {
                if gr[1] !== "g" || gr[3] - gr[2] < 70
                    continue
                j := i + 1
                while j <= runs.Length {
                    yr := runs[j]
                    if yr[2] - gr[3] > 30
                        break
                    if yr[1] == "y" && yr[3] - yr[2] >= 70 {
                        hitX.Push((yr[2] + yr[3]) // 2), hitY.Push(py)
                        break
                    }
                    j++
                }
            }
            py += 3
        }
        if hitX.Length < 3
            return false
        cx := MiddleOf(hitX), cy := MiddleOf(hitY)
        return true
    }
    return false
}

MiddleOf(nums) {
    txt := ""
    for n in nums
        txt .= (txt = "" ? "" : ",") n
    txt := Sort(txt, "N D,")
    parts := StrSplit(txt, ",")
    return Integer(parts[parts.Length // 2 + 1])
}

; press "Open Dungeon". The buttons fade in, so keep looking for a few seconds before
; falling back - and the fallback aims well right of "Return to lobby", never at it.
ClickOpenDungeon() {
    t0 := A_TickCount
    while !FindOpenDungeon(&bx, &by) {
        if A_TickCount - t0 > 5000 {
            SaveDebugShot("open_dungeon")
            if ColorShare(440, 116, 520, 138, IsYellowish) >= 0.3 {
                AddLog("Open Dungeon: using its usual spot")
                bx := 480, by := 127
                break
            }
            AddLog("Couldn't see the Open Dungeon button, aiming right of the lobby button")
            ClickDet("EndScreen", 210, -35, 6000)
            return
        }
        Wait(250)
        if !Det("EndScreen") && !FindOpenDungeon(&bx, &by)
            if A_TickCount - t0 > 1500
                return                                           ; the results screen went away by itself
    }
    t1 := A_TickCount
    while A_TickCount - t1 < 8000 {
        Clk(bx, by)
        if WaitFor(() => !FindOpenDungeon(&nx, &ny), 1500)
            return
        FindOpenDungeon(&bx, &by)
    }
}

RecordRun() {
    global lostRooms, lastRoomI
    ; the same choice comes back after a defeat: count losses per room, forget them after a win
    if lastResult = "loss" && lastRoomI
        lostRooms[lastRoomI] := (lostRooms.Has(lastRoomI) ? lostRooms[lastRoomI] : 0) + 1
    else if lastResult = "win"
        lostRooms := Map()
    stat.runs++
    if lastResult = "win"
        stat.wins++
    else if lastResult = "loss"
        stat.losses++
    stat.streak := lastResult = "win" ? stat.streak + 1 : lastResult = "loss" ? 0 : stat.streak
    WalkLearn()                                 ; lost after the walk: from spawn next time
    took := FmtTime(A_TickCount - stageStart)
    word := (challengeOn ? "Challenge: " : "") (lastResult = "win" ? "Victory" : lastResult = "loss" ? "Defeat" : "Run finished")
    AddLog(word " on " curMap " in " took)
    UpdateStats()
    if cfg["hookRuns"] {
        ; a short card: result, map, room, time, three numbers and a picture of just the game
        total := stat.wins + stat.losses
        where := "**" curMap "**" (IsInteger(curDepth) ? "   Room " curDepth " of " dungeonTotal : "") "   " took
        shot := A_ScriptDir "\Logs\last_result.png"
        SendWebhook((challengeOn ? "Challenge: " : "") (lastResult = "win" ? "Victory" : lastResult = "loss" ? "Defeat" : "Stage finished"), where,
            lastResult = "loss" ? 0xF43F5E : lastResult = "win" ? 0x4ADE80 : 0x7DD3FC,
            [["Streak", stat.streak], ["Wins", stat.wins " of " stat.runs], ["Win rate", total ? Round(stat.wins / total * 100) "%" : "–"]],
            CaptureGamePng(shot) ? shot : "", false)
    }
}

Summary() {
    total := stat.wins + stat.losses
    return stat.wins " won, " stat.losses " lost" (total ? " (" Round(stat.wins / total * 100) "%)" : "")
        . ", " stat.dungeons " dungeon" (stat.dungeons = 1 ? "" : "s") " cleared. Running for " FmtTime(A_TickCount - stat.startTick)
}

; =====================================================================
;  Disconnects
; =====================================================================
; Roblox's disconnect box: its grey and its white button at two dots. Game screens can have
; those two colours there too (a player in Magic Town was "disconnected" ~20 s into every
; round, and the reconnect threw the round away), so the box's text has to say so as well
IsDisconnected() {
    static lastAt := 0, lastRes := false, told := false
    if !(PixelIs(430, 384, 0xFFFFFF) && PixelIs(489, 341, 0x393B3D))
        return false
    if A_TickCount - lastAt < 5000              ; it's looked at often: read the text once per 5 s
        return lastRes
    lastAt := A_TickCount
    txt := ""
    try {
        WinGetClientPos &ox, &oy, , , RBX
        txt := OCR.FromRect(ox + 180, oy + 170, 440, 260, OcrLang(), {scale: 2, grayscale: true}).Text
    }
    ; no English text read (reading failed, or Roblox in another language): trust the dots, as before
    lastRes := !RegExMatch(txt, "[A-Za-z]{3}") || RegExMatch(txt, "i)disconnect|reconnect|connection|kicked|leave|lost|error code|shut ?down")
    if !lastRes && !told {
        told := true
        AddLog("Something looked like Roblox's disconnect box but isn't, carrying on")
        SaveDebugShot("not_disconnected")
    }
    return lastRes
}

; Roblox's app page (its left bar: Home, Moments, Chat, Me) instead of a game
RobloxAppPage() {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        return IsAppNav(OCR.FromRect(ox, oy + 40, 90, 320, OcrLang(), {scale: 2, grayscale: true}).Text)
    }
    return false
}

; two of the app bar's words, each on its own line (a misread one can miss)
IsAppNav(txt) {
    n := 0
    for w in ["home", "moments", "chat"]
        n += !!RegExMatch(txt, "im)^\W*" w "\W*$")
    return n >= 2
}

; returns true if it had to reconnect
CheckConnection(force := false) {
    global stageActive
    if !force && WinExist(RBX) && !IsDisconnected()
        return false
    AddLog(WinExist(RBX) ? "Disconnected! Reconnecting..." : "Roblox is closed, reopening it...")
    SendWebhook("Disconnected", "Trying to reconnect.`n" Summary(), 0xF59E0B)
    stageActive := false
    loop 5 {
        if A_Index > 1 && WinExist(RBX) {       ; still not the lobby: maybe another game opened
            AddLog("Roblox didn't get to the Anime Adventures lobby (another game, or stuck loading). Closing it and trying again"
                . (Trim(cfg["psLink"]) != "" ? ". Check your private server link in Settings: it has to be an Anime Adventures server" : ""))
            SaveDebugShot("wrong_game")
            CloseRoblox()
        }
        Launch(A_Index)
        Wait(15000)
        t0 := A_TickCount
        while A_TickCount - t0 < 150000 {
            RelinkRoblox()                      ; Premium: the reopened main has a new window
            if WinExist(RBX) {
                FixWindow()
                try WinActivate RBX
                Sleep 200
                if Det("Lobby") {
                    AddLog("Reconnected")
                    return true
                }
                ; Roblox's own app page instead of the game: a click there opened another game
                if RobloxAppPage() {
                    AddLog("Roblox opened its app page instead of Anime Adventures. Opening the game again")
                    SaveDebugShot("roblox_app")
                    break
                }
                Clk(490, 400)                   ; the game's loading screen: tap through
            }
            Wait(5000)
        }
        AddLog("Not back yet, trying again (" A_Index "/5)")
    }
    AddLog("Couldn't reconnect, stopping")
    StopMacro()
    Chk()
}

; closes Roblox and opens it again (lands in the lobby), then waits there like a reconnect
; Roblox doesn't always close when asked (it can hang on the way out or ask first): the reconnect
; then saw it still open, did nothing, and the macro sat silent for hours. So a Roblox that's still
; there after 10 s is force-closed (only that window's own process: alts keep running), and Roblox
; is always opened again afterwards.
RejoinToLobby() {
    global stageActive
    stageActive := false
    pid := 0
    try pid := WinGetPID(RBX)
    try WinClose RBX
    closed := false
    try closed := WinWaitClose(RBX, , 10)
    if !closed && pid && ProcessExist(pid) {
        AddLog("Roblox didn't close by itself, closing it")
        try ProcessClose pid
        try ProcessWaitClose pid, 10
    }
    Wait(2000)
    if WinExist(RBX) && pid && WinGetPID(RBX) = pid
        AddLog("Roblox still won't close. Reopening it anyway")
    CheckConnection(true)                       ; opens Roblox and waits for the lobby
}

; Opens Anime Adventures: your private server link, else a public server. The old "roblox://placeID="
; link opened a completely different game for some players after a disconnect (Roblox now wants
; "placeId", or its newer experiences/start link): every other try uses the other format
Launch(try_ := 1) {
    link := Trim(cfg["psLink"])
    try {
        if link != ""
            Run link
        else if Mod(try_, 2)
            Run "roblox://experiences/start?placeId=" AA_PLACE_ID
        else
            Run "roblox://placeId=" AA_PLACE_ID
    } catch as err {
        AddLog("Couldn't open Roblox: " err.Message)
    }
}

; closes the Roblox that's open (its own process too if it hangs), e.g. a game that isn't Anime Adventures
CloseRoblox() {
    if !WinExist(RBX)
        return
    pid := 0
    try pid := WinGetPID(RBX)
    try WinClose RBX
    closed := false
    try closed := WinWaitClose(RBX, , 10)
    if !closed && pid && ProcessExist(pid) {
        try ProcessClose pid
        try ProcessWaitClose pid, 10
    }
    Wait(2000)
}

; =====================================================================
;  Roblox window
; =====================================================================
EnsureRoblox() {
    static lastCheck := 0, fails := 0
    if !WinExist(RBX)
        return false
    ; Roblox minimized or pulled out of the macro's frame (Windows, a popup, a click elsewhere):
    ; every screenshot was then of nothing, and it looped "No Enter button" / "The Red X close
    ; wouldn't go away" until someone noticed. Checked every 3 seconds and put back.
    if A_TickCount - lastCheck > 3000 {
        lastCheck := A_TickCount
        mm := 0
        try mm := WinGetMinMax(RBX)
        bad := mm = -1 || (fails < 3 && !WindowOk())     ; a PC where it never fits: only un-minimize
        if bad {
            AddLog(mm = -1 ? "Roblox was minimized, bringing it back" : "Roblox moved out of the macro's frame, putting it back")
            fails := FixWindow() ? 0 : fails + 1
            Wait(500)
        }
    }
    FocusRoblox()
    return true
}

; clicks, keys and native pixel reads are relative to the active window, so Roblox must be it
FocusRoblox() {
    if WinExist(RBX) && !WinActive(RBX) {
        try WinActivate RBX
        Sleep 120
    }
}

; Roblox must be a normal window (border + title bar), 816 x 638, sitting in the frame
FixWindow() {
    if !WinExist(RBX)
        return false
    try {
        if WinGetMinMax(RBX) != 0
            WinRestore RBX
        ; no border = Roblox's own fullscreen (F11), even when it's small: switch it off
        loop 2 {
            if HasFrame()
                break
            WinActivate RBX
            Sleep 150
            Send "{F11}"
            Sleep 900
        }
        loop 3 {
            WinMove , , WIN_W, WIN_H, RBX
            Sleep 150
            DockGui()
            Sleep 100
            if WindowOk()
                break
        }
        Stale()
        return WindowOk()
    }
    return false
}

; true when Roblox has its window border and title bar around the game
HasFrame() {
    try {
        WinGetPos , , &w, &h, RBX
        WinGetClientPos , , &cw, &ch, RBX
        return w - cw >= 4 && h - ch >= 20
    }
    return false
}

; right size, normal window, and exactly where the frame expects it
WindowOk() {
    if !WinExist(RBX)
        return false
    try {
        WinGetPos &x, &y, &w, &h, RBX
        if w != WIN_W || h != WIN_H || !HasFrame()
            return false
        MG.GetPos(&gx, &gy)
        return Abs(x - (gx + CAP_X)) <= 1 && Abs(y - (gy + CAP_Y)) <= 1
    }
    return false
}

; =====================================================================
;  Screenshots and searching
; =====================================================================
; take one screenshot of the Roblox window; every check after this reads it from memory
Snap() {
    global snapTick
    if !WinExist(RBX)
        return false
    try {
        WinGetPos &wx, &wy, &ww, &wh, RBX
        FindText().ScreenShot(wx, wy, wx + ww + 40, wy + wh + 10)
        snapTick := A_TickCount
        return true
    }
    return false
}

; the screen changed (we clicked / pressed something): next check takes a new screenshot
Stale() {
    global snapTick
    snapTick := 0
}

Fresh() => (A_TickCount - snapTick <= SNAP_AGE) || Snap()

Tolerance() {
    static tols := [0, 0.05, 0.1]
    i := cfg["tolerance"]
    return (i >= 1 && i <= 3) ? tols[i] : 0.05
}

; FindText that follows the Roblox window and reads the cached screenshot
FT(&X := "", &Y := "", x1 := 0, y1 := 0, x2 := 0, y2 := 0, err1 := 0, err0 := 0, text := "", strict := false) {
    dx := 0, dy := 0, shot := 1
    try {
        if WinExist(RBX) {
            WinGetPos &wx, &wy, , , RBX
            dx := wx - CAP_X, dy := wy - CAP_Y
            shot := Fresh() ? 0 : 1
        }
    }
    ; FindText quietly retries at 5% when both errors are 0, so "exact" uses a tiny non-zero value
    tol := strict ? 0.0001 : Max(Tolerance(), 0.0001)
    e1 := strict ? 0.0001 : Max(err1, tol), e0 := strict ? 0.0001 : Max(err0, tol)
    ok := FindText(&X, &Y, x1 + dx, y1 + dy, x2 + dx, y2 + dy, e1, e0, text, shot, 0)
    if ok && IsNumber(X) && IsNumber(Y)
        X -= dx, Y -= dy
    return ok
}

Seen(x1, y1, x2, y2, pattern, err := 0, strict := false) {
    if pattern = ""
        return false
    return FT(&fx, &fy, x1, y1, x2, y2, err, err, pattern, strict) ? true : false
}

; image search in the cached screenshot. Coordinates in and out are relative to Roblox's game area.
; err = share of pixels allowed to be off. It's never 0: FindText quietly retries at 5% when
; it's 0, which let one map's loading screen match another's.
ImgFind(files, cx1, cy1, cx2, cy2, &ix := "", &iy := "", variation := 15, err := 0.0001) {
    if !WinExist(RBX)
        return false
    try WinGetClientPos &ox, &oy, , , RBX
    catch
        return false
    Fresh()
    hexVar := Format("{:06X}", variation << 16 | variation << 8 | variation)
    spec := ""
    for f in (files is Array ? files : [files])
        spec .= "|##" hexVar "$" f
    try ok := FindText(&rx, &ry, ox + cx1, oy + cy1, ox + cx2, oy + cy2, err, err, spec, 0, 0)
    catch
        ok := 0
    if !ok
        return false
    ix := ok[1].x - ox, iy := ok[1].y - oy          ; centre of the match
    return true
}

; colour of a point of the game area, read from the cached screenshot
PixelIs(x, y, color) {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Fresh()
        return (FindText().GetColor(ox + x, oy + y, 0) & 0xFFFFFF) = color
    }
    return false
}

; =====================================================================
;  Waiting and clicking
; =====================================================================
; Fool's Hunt is Premium only: these keep the code shared with Premium the same
FoolRandom() => false
FoolTick() => 0
FoolWaitHook() => 0
PlaceKey(mapName) => mapName
ShowcaseDrop(unit, kind := "chest") => 0    ; Premium: posts a Secret unit in Chris's Discord           ; Premium: Fool's Hunt keeps its own spots and walks
RelinkRoblox() => 0                 ; Premium: finds the main's new window after a reopen
VoteOnScreen() => false              ; Premium: a Fool's Hunt card vote is up
ClearVote() => 0
global foolVotes := 0              ; Premium counts its Fool's Hunt card votes (none here)

Chk() {
    if (!running && !manualRun) || (manualRun && cancelManual)
        throw MacroStop("stopped")
    ; paused (F4 / Pause button): hold still here until it's switched back on
    if paused && running {
        ReleaseKeys()
        Step("paused  (F4 to carry on)")
        while paused && running
            Sleep 100
        if !running
            throw MacroStop("stopped")
        Stale()                                ; the screen changed while we waited
    }
}

Wait(ms) {
    endT := A_TickCount + ms
    loop {
        Chk()
        FoolWaitHook()
        left := endT - A_TickCount
        if left <= 0
            break
        Sleep Min(left, 50)
    }
}

; poll until fn() is true (checks every `step` ms). Returns false on timeout.
WaitFor(fn, timeout, step := 100) {
    t0 := A_TickCount
    loop {
        if fn()
            return true
        if A_TickCount - t0 >= timeout
            return false
        Wait(step)
    }
}

WaitDet(name, timeout, &x := "", &y := "") {
    t0 := A_TickCount
    loop {
        if Det(name, &x, &y)
            return true
        if A_TickCount - t0 >= timeout
            return false
        Wait(100)
    }
}

; click a detected button until it goes away (gives up after maxMs)
ClickDet(name, ox, oy, maxMs := 20000) {
    t0 := A_TickCount
    while Det(name, &fx, &fy) {
        if A_TickCount - t0 > maxMs {
            AddLog("The " DetDefs()[name].label " wouldn't go away, moving on")
            return false
        }
        Clk(fx + ox, fy + oy)
        WaitFor(() => !Det(name), 1000)
    }
    return true
}

; a click Roblox reliably registers (it needs the mouse to move first)
Clk(x, y, btn := "Left") {
    if paused && running                        ; F4 holds here, not only at the next wait
        Chk()
    FocusRoblox()
    MouseMove x, y
    MouseMove 1, 0, , "R"
    MouseClick btn, -1, 0, , , , "R"
    Sleep 50
    Stale()
}

Keys(k) {
    if paused && running
        Chk()
    FocusRoblox()
    SendKeys(k)
    Stale()
}

CloseChat() {
    if Det("Chat")
        Clk(138, 30)
}

FmtTime(ms) {
    s := ms // 1000
    return s >= 3600 ? Format("{}h {:02}m", s // 3600, Mod(s // 60, 60)) : Format("{}m {:02}s", s // 60, Mod(s, 60))
}

; =====================================================================
;  Discord webhook
; =====================================================================
; Posts a small Discord card. fields: [[name, value], ...] shown side by side. imageFile: a PNG shown
; under the card. wait := false sends it in the background so farming never waits on Discord.
SendWebhook(title, desc, color := 0x7DD3FC, fields := "", imageFile := "", sync := true) {
    static pending := []
    url := Trim(cfg["webhook"])
    if url = "" || !RegExMatch(url, "i)^https://(\w+\.)?discord(app)?\.com/api/webhooks/")
        return false
    ts := FormatTime(A_NowUTC, "yyyy-MM-dd") "T" FormatTime(A_NowUTC, "HH:mm:ss") ".000Z"
    emb := '{"title":"' JsonEsc(title) '","color":' color ',"timestamp":"' ts '"'
    if desc != ""
        emb .= ',"description":"' JsonEsc(desc) '"'
    if IsObject(fields) && fields.Length {
        list := ""
        for fld in fields
            list .= (list = "" ? "" : ",") '{"name":"' JsonEsc(fld[1]) '","value":"' JsonEsc(String(fld[2])) '","inline":true}'
        emb .= ',"fields":[' list ']'
    }
    hasImg := imageFile != "" && FileExist(imageFile)
    if hasImg
        emb .= ',"image":{"url":"attachment://result.png"}'
    emb .= ',"footer":{"text":"Chris`'s Dungeon Macro"}}'
    payload := '{"username":"Chris`'s Dungeon Macro","embeds":[' emb ']}'
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("POST", url, true)
        if hasImg {
            boundary := "AAMacro" A_TickCount
            req.SetRequestHeader("Content-Type", "multipart/form-data; boundary=" boundary)
            req.Send(MultipartBody(boundary, payload, imageFile))
        } else {
            req.SetRequestHeader("Content-Type", "application/json")
            req.Send(payload)
        }
        if !sync {                              ; keep the request alive while it finishes
            pending.Push(req)
            SetTimer(() => pending.Length && pending.RemoveAt(1), -60000)
            return true
        }
        req.WaitForResponse(8)
        return req.Status >= 200 && req.Status < 300
    }
    return false
}

; the message + a PNG as one upload (Discord's "multipart/form-data" with payload_json)
MultipartBody(boundary, payload, file) {
    img := FileRead(file, "RAW")
    head := "--" boundary "`r`nContent-Disposition: form-data; name=`"payload_json`"`r`nContent-Type: application/json`r`n`r`n" payload
        . "`r`n--" boundary "`r`nContent-Disposition: form-data; name=`"files[0]`"; filename=`"result.png`"`r`nContent-Type: image/png`r`n`r`n"
    tail := "`r`n--" boundary "--`r`n"
    hLen := StrPut(head, "UTF-8") - 1, tLen := StrPut(tail, "UTF-8") - 1
    hb := Buffer(hLen + 1), StrPut(head, hb, "UTF-8")
    tb := Buffer(tLen + 1), StrPut(tail, tb, "UTF-8")
    arr := ComObjArray(0x11, hLen + img.Size + tLen)           ; VT_UI1 byte array
    pData := NumGet(ComObjValue(arr), 8 + A_PtrSize, "Ptr")
    DllCall("RtlMoveMemory", "Ptr", pData, "Ptr", hb, "UPtr", hLen)
    DllCall("RtlMoveMemory", "Ptr", pData + hLen, "Ptr", img, "UPtr", img.Size)
    DllCall("RtlMoveMemory", "Ptr", pData + hLen + img.Size, "Ptr", tb, "UPtr", tLen)
    return arr
}

; saves just Roblox's game area (not the macro) as a PNG
; (x, y, w, h: only that part of the game, e.g. the middle where a reward is revealed)
CaptureGamePng(file, x := 0, y := 0, w := 0, h := 0) {
    try {
        WinGetClientPos &ox, &oy, &cw, &ch, RBX
        if w > 0 && h > 0
            ox += x, oy += y, w := Min(w, cw - x), h := Min(h, ch - y)
        else
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
        pBmp := 0
        DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &pBmp)
        clsid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)   ; PNG encoder
        res := DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBmp, "WStr", file, "Ptr", clsid, "Ptr", 0)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)
        DllCall("DeleteObject", "Ptr", hbm)
        return res = 0 && FileExist(file)
    }
    return false
}

GdiplusUp() {
    static token := 0
    if token
        return
    DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    si := Buffer(24, 0), NumPut("UInt", 1, si)
    tok := 0
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &tok, "Ptr", si, "Ptr", 0)
    token := tok
}

JsonEsc(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "")
    s := StrReplace(s, "`n", "\n")
    return StrReplace(s, "`t", " ")
}

; Ryn's per-map walks for dungeon mode, converted automatically from his macro.
; Some maps have two routes: which one runs depends on a landmark that shows which way the camera faces.
; Each check: [want, [[pattern, x1, y1, x2, y2, err], ...]] -> passes when (any pattern is seen) = want
BuiltInWalks() {
    static m := 0
    if IsObject(m)
        return m
    m := Map()
    m["Air Craft"] := [
        {checks: [[true, [[AirCraftAngle, 535, 110, 620, 175, 0.15]]]], route: "s+0,s-800,d+1800,d-2800,s+3800,s-4600,end@5600"},
        {checks: [[false, [[AirCraftAngle, 535, 110, 620, 175, 0.15]]]], route: "w+0,w-1000,d+2000,d-3000,w+4000,w-4400,d+5400,d-6400,end@7400"}
    ]
    m["Alien Spaceship"] := [
        {checks: [[true, [[AlienSpaceshipAngle, 0, 244, 48, 278, 0.15]]]], route: "rc73;176@0,end@2500"},
        {checks: [[false, [[AlienSpaceshipAngle, 0, 244, 48, 278, 0.15]]]], route: "rc658;61@0,end@2500"}
    ]
    m["Ant Kingdom"] := [
        {checks: [[true, [[AntKingdomAngle, 531, 205, 582, 251, 0.15]]]], route: "a+0,a-1000,s+2000,s-2500,a+3500,a-4000,s+5000,s-5500,a+6500,a-7400,s+8400,s-8700,a+9700,a-13700,w+14700,w-15700,a+16700,a-17200,w+18200,w-21200,end@22200"},
        {checks: [[false, [[AntKingdomAngle, 531, 205, 582, 251, 0.15]]]], route: "a+0,a-500,s+1500,s-2000,a+3000,a-3500,s+4500,s-5900,a+6900,a-7700,s+8700,s-11700,a+12700,a-15500,w+16500,w-18000,a+19000,a-20500,w+21500,w-23500,a+24500,a-25000,w+26000,w-27000,a+28000,a-28800,end@29800"}
    ]
    m["Cursed Festival"] := [
        {checks: [[true, [[FestivalAngle, 560, 285, 615, 350, 0.15]]]], route: "d+0,d-1800,end@2800"},
        {checks: [[false, [[FestivalAngle, 560, 285, 615, 350, 0.15]]]], route: "a+0,a-1800,end@2800"}
    ]
    m["Fiend City"] := [
        {checks: [], route: "s+0,s-500,a+1000,a-4800,s+5300,s-7300,end@7300"}
    ]
    m["Haunted Academy"] := [
        {checks: [], route: "d+0,d-4700,end@4700"}
    ]
    m["Hellish City"] := [
        {checks: [[true, [[HellishAngle, 370, 210, 465, 265, 0.15]]]], route: "d+0,d-1200,end@1200"},
        {checks: [[false, [[HellishAngle, 370, 210, 465, 265, 0.15]]]], route: "a+0,a-800,w+1300,w-2100,d+2600,d-5000,s+5500,s-6100,end@6100"}
    ]
    m["Magic Hills"] := [
        {checks: [[true, [[MagicHillsBench, 518, 334, 566, 404, 0.2], [MagicHillLegendStageBench, 522, 339, 557, 402, 0.2]]]], route: "d+0,d-500,w+1500,w-4100,d+5100,d-5600,w+6600,w-10600,a+11600,a-12600,w+13600,w-17600,d+18600,d-21100,w+22100,w-24900,d+25900,d-27400,end@28400"},
        {checks: [[false, [[MagicHillsBench, 518, 334, 566, 404, 0.2], [MagicHillLegendStageBench, 522, 339, 557, 402, 0.2]]]], route: "w+0,w-500,a+1500,a-8500,s+9500,s-10900,a+11900,a-15400,w+16400,w-19200,a+20200,a-23700,w+24700,w-25800,end@26800"}
    ]
    m["Magic Town"] := [
        {checks: [], route: "d+0,d-3000,s+5000,s-6200,d+8200,d-11400,end@12400"}
    ]
    m["Mountain Temple"] := [
        {checks: [], route: "w+0,d+0,w-2000,d-2000,end@3000"}
    ]
    m["Navy Bay"] := [
        {checks: [], route: "a+0,w+0,a-1700,w-1700,end@1700"}
    ]
    m["Nightmare Train"] := [
        {checks: [], route: "a+0,a-1800,end@1800"}
    ]
    m["Planet Greenie"] := [
        {checks: [], route: "a+0,w+0,a-2200,w-2200,end@2200"}
    ]
    m["Sand Village"] := [
        {checks: [], route: "s+0,s-700,d+1700,d-4400,s+5400,s-7800,a+8800,a-11200,s+12200,s-14000,end@14000"}
    ]
    m["Shibuya District"] := [
        {checks: [], route: "a+0,a-600,a+1100,w+1100,a-2600,w-2600,end@2600"}
    ]
    m["Snowy Town"] := [
        {checks: [], route: "d+0,d-3000,w+4000,w-5000,end@6000"}
    ]
    m["Space Center"] := [
        {checks: [], route: "d+0,d-2000,w+3000,w-4500,end@4500"}
    ]
    m["Spirit World"] := [
        {checks: [], route: "d+0,w+0,d-4000,w-4000,d+5000,d-6900,w+7900,w-9900,end@10900"}
    ]
    return m
}
