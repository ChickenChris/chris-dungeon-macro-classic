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
global bossDone := false
global chestsDone := false      ; this dungeon's saved chests have been opened
global curMap := "Unknown"
global mapHow := ""             ; how the map was recognised (shown in the log)
global dungeonTotal := 20       ; rooms in a dungeon run (read from "DEPTH: 14/20" when possible)
global curDepth := ""          ; dungeon room depth read from the loading screen
global lastMapRaw := ""        ; the last text read while looking for the map name (for the log)
global placedUnits := []
global allPlaced := false       ; every unit is down: from now on the F panel may be used
global lastResult := ""
global idleSince := 0
global snapTick := 0
global closeStreak := 0       ; times in a row the room picker had no Enter button
global slotStops := Map()       ; "slot|map" -> how many it managed before giving up last time
global slotPrice := Map()       ; slot -> its price in the unit bar (this stage)
global slotCap := Map()         ; "slot|map" -> the most that fit on that map, once it's been seen twice
; (per map: a cramped map used to cap a slot for every later map, so later rooms were played
; with fewer units until the macro was restarted)
CapKey(n) => n "|" curMap
global slotOne := Map()         ; slot -> true: a unique unit, the game allows one of it
global autoOpenSeen := false   ; a menu has opened by itself after placing (the game setting is right)
global autoOpenOff := false    ; menus only open when the new unit is clicked (setting is wrong)
global clickOpened := 0
global slotFull := Map()        ; slot -> stage it hit the game's limit in (no more that stage)

; trims `need` to what the game allows for slot n right now
SlotRoom(n, need) {
    if slotCap.Has(CapKey(n))
        need := Min(need, slotCap[CapKey(n)] - CountPlaced(n))
    if slotOne.Has(n)
        need := Min(need, 1 - CountPlaced(n))
    if slotFull.Get(n, -1) = stageStart
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
    return FT(&x, &y, a[1], a[2], a[3], a[4], o.err, o.err, o.pats) ? true : false
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
    global running, idleSince, slotStops, slotCap, slotOne, slotFull, autoOpenSeen, autoOpenOff, clickOpened
    errors := 0
    idleSince := 0
    slotStops := Map(), slotCap := Map(), slotOne := Map(), slotFull := Map(), autoOpenSeen := false, autoOpenOff := false, clickOpened := 0
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
    if Det("EnterDungeon") {
        idleSince := 0
        Step("opening the dungeon")
        Clk(395, 380)
        WaitFor(() => ScanRooms().Length || SpecialScreen(), 3000)
        return
    }
    if Det("Lobby") {
        idleSince := 0
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
    }
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
        if kind != ""
            found.Push({i: i, kind: kind, a: ar})
    }
    return found
}

ChooseRoom(rooms) {
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
        AddLog("No preferred room left, taking the least bad one" (c != "" ? " (curse of " c ")" : ""))
        Clk(best.a.cx, best.a.cy)
        Wait(400)
        EnterRoom()
        return
    }
    AddLog("No rooms to pick from, trying the middle one")
    Clk(400, 355)
    Wait(400)
    EnterRoom()
}

; click a room; if it has a curse you skip, back out. Returns true when it went in.
TryRoom(r, prio, unsafe, curseOf, nextKind := "") {
    global bossDone
    Clk(r.a.cx, r.a.cy)
    Wait(400)
    curseName := ""
    if r.kind = "Cursed" {
        curseName := DetectCurse()
        curseOf[r.i] := curseName
        ; a curse it can't tell counts as one to avoid (it used to go in, so avoided curses got through)
        if (curseName != "" && AvoidCurse(curseName)) || (curseName = "" && cfg["skipWorst"] > 0) {
            AddLog("Skipping " RoomLabel(prio) " room (" (curseName != "" ? "curse of " curseName : "a curse it couldn't read") ")")
            unsafe[r.i] := true
            Clk(r.a.cx, r.a.cy)
            Wait(600)
            return false
        }
    }
    if prio = "Boss"
        bossDone := true
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
    rareX := -2, picks := []
    shopOk := true
    for r in rooms {
        if r.kind = "Unavailable"
            continue
        own := "", rank := 0
        for i, prio in route {
            if prio = "None"
                continue
            if prio = "Rare_Chest" {
                if rareX = -2
                    rareX := FindRareChestX()
                hit := rareX >= 0 && Abs(r.a.cx - rareX) < 70
            } else
                hit := Seen(r.a.sx1, r.a.sy1, r.a.sx2, r.a.sy2, RoomPattern(prio), 0.2)
            if hit {
                own := prio, rank := i
                break
            }
        }
        picks.Push({r: r, prio: own, rank: rank ? rank : 99, score: 0, next: "", cursed: r.kind = "Cursed"})
    }
    for pk in picks
        pk.score := pk.prio != "" ? ThingValue(pk.prio, shopOk) : 0
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

RoomBefore(x, y) => x.score != y.score ? x.score > y.score : x.rank != y.rank ? x.rank < y.rank : !x.cursed && y.cursed

; what one thing is worth: its place on your room list (top = most). A rare chest counts
; double (it's what dungeons are farmed for), a curse costs more than a chest and a hoard
; together (cursed rooms lose runs), and a shop is worth nothing until you have the coins
; to spend in it ("Only go to a shop with" setting).
ThingValue(kind, shopOk := true) {
    if kind = "Curse"
        return -8
    if kind = "Shop" && !shopOk
        return 0
    i := IndexOf(cfg["route"], kind)
    v := i ? cfg["route"].Length + 1 - i : 0
    return kind = "Rare_Chest" ? v * 2 : v
}

FindRareChestX() {
    return ImgFind(RareChestImage, 247, 325, 561, 457, &ix, &iy) ? ix : -1
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
    static words := [["fli|fly", "Flying"], ["win", "Wind"], ["shop|mon", "Money"], ["hea", "Health"],
        ["shi", "Shielding"], ["reg", "Regen"], ["exp", "Exploding"]]
    try {
        WinGetClientPos &ox, &oy, , , RBX
        txt := OCR.FromRect(ox + 110, oy + 130, 570, 340, OcrLang(), {scale: 2, grayscale: true}).Text
    } catch
        return ""
    if !RegExMatch(txt, "i)curse\s*o\s*f\s*([a-z]{3,})", &m)
        return ""
    for pr in words
        if RegExMatch(m[1], "i)^(" pr[1] ")")
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
    static spellings := Map("Armor", "ARMOR", "Burst", "BURST", "Chaos", "CHAOS", "Frenzy", "FRENZY", "Vamparism", "VAMPARISM|VAMPIRISM")
    txt := ScreenText()
    if !RegExMatch(txt, "CURSE ?[O0]F ?([A-Z]{3,})", &m) {
        found := false
        for area in [[412, 236, 190, 145, {scale: 3, grayscale: true}], [412, 236, 190, 145, {scale: 3, grayscale: true, invertcolors: true}],
            [120, 160, 560, 320, {scale: 2.5, grayscale: true}]] {
            txt := ""
            try {
                WinGetClientPos &ox, &oy, , , RBX
                txt := StrUpper(OCR.FromRect(ox + area[1], oy + area[2], area[3], area[4], OcrLang(), area[5]).Text)
            }
            if RegExMatch(RegExReplace(txt, "\s+", " "), "CURSE ?[O0]F ?([A-Z]{3,})", &m) {
                found := true
                break
            }
        }
        if !found
            return ""
    }
    best := "", bestD := 3
    for k, spelled in spellings {
        for sp in StrSplit(spelled, "|") {
            d := Levenshtein(sp, m[1])
            if d < bestD
                best := k, bestD := d
        }
    }
    if best = ""
        AddLog("Shrine curse read as '" m[1] "', not one I know")
    return best
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
    "Magic Tome", "Solar Cleaver", "Headsplitter", "Axe", "Mage Coat", "Reaper Scythe", "Glacial Axe", "Ice Dagger",
    "Ninja Belt", "Nimble Cloak", "Elf Bow", "Longbow", "Dagger", "Bow"]
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

ReadShopRows() {
    rows := []
    for y in [225, 280, 335] {
        raw := ShopRowText(y)
        name := FuzzyPick(raw, cfg["shopRank"])
        ; short names that are the end of longer ones: the description's % tells them apart
        if name = "Fish Hook" && RegExMatch(raw, "4\s*0\s*%")
            name := "Golden Fishhook"
        else if name = "Bow" && RegExMatch(raw, "5\s*0\s*%")
            name := "Elf Bow"
        else if name = "Dagger" && RegExMatch(raw, "i)\b[il1]ce\b|2\s*0\s*%|speed")
            name := "Ice Dagger"                ; Ice Dagger: -20% enemy speed
        else if name = "Ice Dagger" && RegExMatch(raw, "1\s*5\s*%|attack") && !RegExMatch(raw, "i)\b[il1]ce\b")
            name := "Dagger"                    ; Dagger: +15% attack
        else if name = "Axe" && RegExMatch(raw, "i)g[il1]ac|slow")
            name := "Glacial Axe"
        else if name = "Glacial Axe" && RegExMatch(raw, "i)crit") && !RegExMatch(raw, "i)g[il1]ac")
            name := "Axe"                       ; Axe: +50% physical crit chance
        rows.Push({y: y, name: name, raw: raw})
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
            if low > 0.34 {
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
        ClaimReward()
        opened++
    }
    return opened
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
            SendWebhook("Dungeon cleared", Summary(), 0x22C55E)
        }
        lastCleared := A_TickCount, cancels := 0
        chestsDone := false, bossDone := false
        if !Det("EndScreen")
            Clk(666, 145)                       ; the dungeon window's X
        WaitFor(() => Det("EndScreen") || Det("Lobby"), 3000)
        if Det("EndScreen") {                   ; "Open Dungeon", not "Return to lobby": no trip to the lobby
            Step("opening the next dungeon")
            ClickOpenDungeon()
        }
        return true
    }
    if Det("DungeonDeath") {
        static deaths := 0, deathFirst := 0
        if A_TickCount - deathFirst > 90000
            deaths := 0, deathFirst := A_TickCount
        if ++deaths = 1
            AddLog("Out of lives in this dungeon, starting a new one")
        ; its button: by picture, or by its text, or where it usually is (on some PCs the
        ; picture didn't match and this repeated every 2 seconds)
        if Det("DeathContinue")
            ClickDet("DeathContinue", 0, -30)
        else if OcrFindWord(120, 300, 560, 180, "i)^(continue|open|new|start|retry|ok)", &bx, &by)
            Clk(bx, by)
        else
            Clk(396, 383)
        if deaths = 4 {
            AddLog("The out-of-lives screen won't go away. Send Logs\out_of_lives_....bmp in Discord so it can be fixed")
            SaveDebugShot("out_of_lives")
        }
        if WaitDet("RedX", 1500)
            ClickDet("RedX", -3, -35)
        bossDone := false, chestsDone := false
        Wait(500)
        return true
    }
    return false
}

; =====================================================================
;  Inside a stage
; =====================================================================
LoadStage(knownMap := "", knownDepth := "") {
    global curMap, curDepth, mapHow
    Step("loading the map")
    curMap := knownMap != "" ? knownMap : "Unknown", curDepth := knownDepth
    UpdateMapLabel()
    if knownMap != ""
        AddLog("Map: " knownMap (knownDepth != "" ? ", depth " knownDepth : "") "  (from the room panel)")
    ; the loading screen double-checks the room panel: its map name (picture or text) wins if
    ; they disagree (a misread panel once turned Snowy Kingdom into Cursed Festival)
    checked := knownMap = ""
    t0 := A_TickCount
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
        if IsLoaded()
            break
        ; the room picker stays up for a moment after pressing Enter, so only treat it
        ; as "we didn't actually enter" once a few seconds have passed
        if A_TickCount - t0 > 6000 && (SpecialScreen() || ScanRooms().Length || Det("FinishDungeon"))
            return
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
    global lastMapRaw
    static warned := false
    raw := ""
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
            AddLog("Text reading isn't available (" err.Message "), using pictures only")
        }
        return ""
    }
    if RegExMatch(raw, "i)depth\D{0,4}(\d(?: ?\d)?)(?!\d)", &m)
        depth := StrReplace(m[1], " ")
    return MatchMapName(raw)
}

; reads the top-left of the loading screen: "Traveling to...", the map name, "Dungeon Room (Depth N)"
MapFromLoadingText() {
    global curDepth
    static lastLogged := "", warned := false
    if !WinExist(RBX)
        return ""
    try {
        WinGetClientPos &ox, &oy, , , RBX
        ; map name + "Dungeon Room (Depth N)" + difficulty (the Roblox buttons cover "Traveling to...")
        txt := OCR.FromRect(ox + 8, oy + 50, 470, 125, OcrLang(), {scale: 2, grayscale: true}).Text
    } catch as err {
        if !warned {
            warned := true
            AddLog("Text reading isn't available (" err.Message "), using pictures only")
        }
        return ""
    }
    if RegExMatch(txt, "i)depth\D{0,4}(\d+)", &m)
        curDepth := m[1]
    name := MatchMapName(txt)
    one := Trim(RegExReplace(txt, "\s+", " "))
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
        postStage := 0
        stageActive := true
        stageStart := A_TickCount
        lastResult := ""
        placedUnits := [], allPlaced := false, slotPrice := Map()
        SetupCamera()
        WaitForVote()
        ctx := NewPlaceCtx()
        if cfg["useBuild"] && cfg["build"].Length
            RunBuildOrder(ctx)
        if !ctx.over
            PlaceAll(ctx)
    }
    allPlaced := true                       ; placing is over: upgrades can use the F panel now
    UpgradeAndWatch()
}

SetupCamera() {
    Step("getting ready")
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
    if cfg["zoom"]
        ZoomCamera()
    if tp && walk
        WalkRoute(mapName)
}

ZoomCamera() {
    Step("lining up the camera")
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
            if !found
                found := SpawnFound(&fx, &fy) || (Wait(300), SpawnFound(&fx, &fy))
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

; The Teleport to Spawn picture is matched loosely (20%), and on some players' settings lists
; that also fit another row: it clicked that, stopped scrolling and never teleported. So a
; loose hit must also read "Spawn"/"Teleport" on that row, or match the picture closely.
SpawnFound(&fx, &fy) {
    if !Det("Spawn", &fx, &fy)
        return false
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
CloseSettings() {
    loop 3 {
        Wait(250)
        Clk(583, 147)
        if WaitFor(() => !Det("Spawn"), 500)
            return true
    }
    return false
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
    route := cfg["walks"].Has(mapName) ? cfg["walks"][mapName] : BuiltInWalk(mapName)
    if route = ""
        return
    Step("walking to the spot")
    PlayRoute(route)
    AddLog("Walked to the " mapName " spot")
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
                SendInput "{" m[1] (m[2] = "+" ? " down}" : " up}")
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
    for k in ["w", "a", "s", "d", "Space"]
        if GetKeyState(k)
            SendInput "{" k " up}"
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
                u := {x: p.x, y: p.y, slot: n, maxed: false, capped: false, dx: 0, dy: -3, misses: 0, lost: false}
                placedUnits.Push(u), newUnits.Push(u)
                AddLog("Placed slot " n "  (" got "/" need ")")
            } else {
                ctx.fails[key] := ctx.fails.Get(key, 0) + 1
                misses++
                if !SlotRoom(n, 1)
                    return newUnits                 ; the game's limit for this unit
            }
        }
        if !attempts && got < need
            ctx.fails := Map()                 ; every spot is used or failed twice: give them another go
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

; ---------- build order ----------
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
            list := []
            for u in placedUnits
                if u.slot = st.slot
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
    AddLog("Build order done")
}

StepText(st) {
    up := st.up < 0 ? "to max" : st.up " time" (st.up = 1 ? "" : "s")
    if st.kind = "place"
        return "Place slot " st.slot " x" st.count (st.up = 0 ? "" : ", upgrade each " up)
    return "Upgrade slot " st.slot " " up
}

; Upgrades a group of units `times` times each (-1 = to max), taking turns:
; unit 1 as far as it can afford -> unit 2 -> unit 3 -> back to unit 1 ... until every
; unit has reached the target. Waits for yen when nobody can afford anything.
; A build order step is exact: the "Until" limit on the Units tab doesn't cut it short.
; Returns false if the stage ended.
UpgradeGroup(units, times) {
    done := Map()
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
                if !g
                    break
                done[u] += g, roundGain += g, lastGainAt := A_TickCount
                if u.maxed || u.lost || (times >= 0 && done[u] >= times)
                    break
            }
        }
        if !left {
            AddLog("Slot " units[1].slot ": " (times < 0 ? "all fully upgraded" : "upgraded " times " time" (times = 1 ? "" : "s")))
            return true                             ; everyone reached the target
        }
        if limitMs && A_TickCount - t0 > limitMs {
            AddLog("Slot " units[1].slot ": upgrade step took too long, moving to the next step")
            return true
        }
        if !roundGain {
            if A_TickCount - lastGainAt > waitMs {
                AddLog("Slot " units[1].slot " couldn't upgrade for " waitMs // 60000 " min, moving to the next step")
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
    if cfg["useSpots"] && cfg["spots"].Has(curMap)
        for p in cfg["spots"][curMap]
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
    if autoOpenOff ? WaitUnitMenu(300) : (WaitUnitMenu(PlaceTimeout()) || WaitUnitMenu(1200))
        how := "auto"
    else if PlaceRefused(slot)
        return false
    else if !autoOpenSeen && !NearUnit(x, y, 45) {
        ; With 'Disable Auto-Open Upgrade UI' on in the game, no menu opens by itself after
        ; placing. Clicking the spot opens the new unit's menu (an empty spot does nothing).
        ; Skipped next to known units, whose menu could pass for a new one.
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
        else if ++clickOpened = 2 && !autoOpenOff {
            autoOpenOff := true
            AddLog("The unit menu doesn't open by itself after placing, so the macro clicks each new unit. Faster: in the game's settings, set 'Disable Auto-Open Upgrade UI' so the menu pops up when you place a unit")
        }
        CheckAbility()
        Clk(325, 185)                       ; close the unit menu
        return true
    }
    return false
}

; The game refused the unit with a red message: remember the limit so the macro stops trying.
PlaceRefused(slot) {
    msg := LimitMessage()
    if msg = "unique" {
        ; only one of a unique unit. One is down already, even if it wasn't counted (its
        ; menu didn't show), so no more of this slot this stage, and one per stage after this
        if !slotOne.Has(slot)
            AddLog("Slot " slot " is a unique unit: the game allows only one. Placing one from now on")
        if !CountPlaced(slot)
            AddLog("Slot " slot ": one is on the map but its placing wasn't seen, so it won't be upgraded this stage")
        slotOne[slot] := true
        slotFull[slot] := stageStart
        return true
    }
    if msg = "limit" {
        slotCap[CapKey(slot)] := CountPlaced(slot)
        slotFull[slot] := stageStart
        AddLog("Slot " slot ": the game allows only " CountPlaced(slot) " of this unit, placing no more")
        return true
    }
    return false
}

; the game's red refusal in the middle of the screen: "unique" for "Unique units may not be
; placed with others of its kind", "limit" for "Cannot place more than N of this unit!", else ""
LimitMessage() {
    red := 0
    try {
        WinGetClientPos &ox, &oy, , , RBX
        Stale(), Fresh()
        scr := FindText()
        yy := 120
        while yy <= 500 {
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
    if red < 40
        return ""
    txt := ""
    try {
        WinGetClientPos &ox, &oy, , , RBX
        txt := OCR.FromRect(ox + 100, oy + 120, 600, 390, OcrLang(), {scale: 2, grayscale: true}).Text
    }
    if RegExMatch(txt, "i)uniq|its kind|others of")
        return "unique"
    if RegExMatch(txt, "i)cannot|can.t place|more than")
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
    for o in tries {
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
        TopUpUnits()
        busy := UpgradePass()
        if !busy {
            Step("units done, watching the stage")
            UpgradesDoneHint()
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
            if !u.maxed && !u.capped && !u.lost && cfg["slots"][u.slot].up && cfg["slots"][u.slot].prio = p
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
    lim := useLimit ? cfg["slots"][u.slot].limit : 0
    Step("upgrading slot " u.slot)
    if !OpenUnit(u)
        return 0
    lvl := ReadLevel()
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
    if cfg["autoAbility"] && Det("AutoOff")
        Clk(373, 237)
}

StageOver() {
    Chk()
    return Det("Xp") || Det("EndScreen") || Det("Next") || Det("Lobby")
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
    ReadResult()
    FinishStage()
    if lastResult = "loss" && cfg["stopAfterDefeat"] {
        AddLog("Defeat, stopping (Stop after a defeat is on)")
        SendWebhook("Stopped after a defeat", Summary(), 0xDC2626)
        ClickDet("EndScreen", 0, -35)
        StopMacro()
        Chk()
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
    stat.runs++
    if lastResult = "win"
        stat.wins++
    else if lastResult = "loss"
        stat.losses++
    stat.streak := lastResult = "win" ? stat.streak + 1 : lastResult = "loss" ? 0 : stat.streak
    took := FmtTime(A_TickCount - stageStart)
    word := lastResult = "win" ? "Victory" : lastResult = "loss" ? "Defeat" : "Run finished"
    AddLog(word " on " curMap " in " took)
    UpdateStats()
    if cfg["hookRuns"] {
        ; a short card: result, map, room, time, three numbers and a picture of just the game
        total := stat.wins + stat.losses
        where := "**" curMap "**" (IsInteger(curDepth) ? "   Room " curDepth " of " dungeonTotal : "") "   " took
        shot := A_ScriptDir "\Logs\last_result.png"
        SendWebhook(lastResult = "win" ? "Victory" : lastResult = "loss" ? "Defeat" : "Stage finished", where,
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
IsDisconnected() => PixelIs(430, 384, 0xFFFFFF) && PixelIs(489, 341, 0x393B3D)

; returns true if it had to reconnect
CheckConnection() {
    global stageActive
    if WinExist(RBX) && !IsDisconnected()
        return false
    AddLog(WinExist(RBX) ? "Disconnected! Reconnecting..." : "Roblox is closed, reopening it...")
    SendWebhook("Disconnected", "Trying to reconnect.`n" Summary(), 0xF59E0B)
    stageActive := false
    loop 5 {
        Launch()
        Wait(15000)
        t0 := A_TickCount
        while A_TickCount - t0 < 150000 {
            if WinExist(RBX) {
                FixWindow()
                try WinActivate RBX
                Sleep 200
                if Det("Lobby") {
                    AddLog("Reconnected")
                    return true
                }
                Clk(490, 400)
            }
            Wait(5000)
        }
        AddLog("Not back yet, trying again (" A_Index "/5)")
    }
    AddLog("Couldn't reconnect, stopping")
    StopMacro()
    Chk()
}

Launch() {
    link := Trim(cfg["psLink"])
    try {
        if link != ""
            Run link
        else
            Run "roblox://placeID=" AA_PLACE_ID
    } catch as err {
        AddLog("Couldn't open Roblox: " err.Message)
    }
}

; =====================================================================
;  Roblox window
; =====================================================================
EnsureRoblox() {
    if !WinExist(RBX)
        return false
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
    FocusRoblox()
    MouseMove x, y
    MouseMove 1, 0, , "R"
    MouseClick btn, -1, 0, , , , "R"
    Sleep 50
    Stale()
}

Keys(k) {
    FocusRoblox()
    SendInput k
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
CaptureGamePng(file) {
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
