; =====================================================================
;  The Story pad: Infinite (Premium) and Legend Stages (Premium and Classic)
;  The same file in both macros. Measured on Chris's PC (game-area coordinates): from the play area
;  the Story pads are ahead and to the right (Ryn's walk); on a pad "Select World" lists the worlds
;  (x 615-790, y 160-460), the acts/stages are on the left, then Select (401,438), "Join
;  Matchmaking?" Play Here (330,325), and on the waiting panel Start (401,464) above Cancel (401,525)
; =====================================================================
global worldLastRead := ""       ; what the world list said last (for the log when the world isn't found)

; ---------------------------------------------------------------- lobby -> pad
SigLight(a) {
    t := 0
    for v in a
        t += v
    return a.Length ? t / a.Length / 3 : 0
}

; Waits for the area teleport to land: the scene changes from `before`, then holds still
; (and isn't a black loading screen). Gives up after a while: already in the right area.
WaitAreaTeleport(before) {
    Wait(700)                                   ; the Areas list closing
    t0 := A_TickCount, moved := false
    while A_TickCount - t0 < 6000 {
        if SigDiff(SceneSig(), before) > 35 {
            moved := true
            break
        }
        Wait(400)
    }
    ; landed: a loading screen is dark, so wait for light (units' effects keep moving, so
    ; waiting for a still picture took 10 s or more), then a moment to stand up
    t1 := A_TickCount
    while moved && A_TickCount - t1 < 6000 && SigLight(SceneSig()) <= 25
        Wait(300)
    Wait(900)
    return moved
}

; Play, then Ryn's walk to the Story pads (ahead and right; the other way round on a second try)
; until the pad's Cancel button shows
PadWalk() {
    loop 3 {
        if FT(&fx, &fy, 325, 520, 489, 587, 0, 0, ModeCancel)
            return true
        before := SceneSig()
        Clk(85, 295)                            ; Play
        Step("lobby: waiting for the teleport")
        WaitAreaTeleport(before)
        FocusRoblox()
        Step("walking to the Story pads")
        SendKeys("{w down}"), Wait(300), SendKeys("{w up}"), Wait(300)
        back := A_Index = 2
        SendKeys(back ? "{s down}" : "{w down}"), SendKeys("{d down}")
        t0 := A_TickCount
        while A_TickCount - t0 < 4500 {
            Wait(250)
            Stale()
            if FT(&fx, &fy, 325, 520, 489, 587, 0, 0, ModeCancel)
                break
        }
        SendKeys("{d up}"), SendKeys(back ? "{s up}" : "{w up}")
        Wait(800)
        Stale()
    }
    return FT(&fx, &fy, 325, 520, 489, 587, 0, 0, ModeCancel)
}

; ---------------------------------------------------------------- the world list
; a world's name as the list shows it: each word's first 4 letters, the rest of the word maybe
; misread ("Shibuya Distric†"). Brackets don't count ("Magic Hills (Elf Invasion)")
WorldRegex(name) {
    re := "i)"
    for i, w in StrSplit(Trim(RegExReplace(name, "[()\[\]]")), " ") {
        if w = ""
            continue
        w := RegExReplace(SubStr(w, 1, Min(4, StrLen(w))), "[\\.*?+^$|{}]", "\$0")
        re .= (re = "i)" ? "" : "\W*") w "\S*?"
    }
    return re
}

; is this line of the world list the world `name` (one of `names`)? Its first letters, or the closest
; name. A Legend world has a bracket ("Ruined City (Midnight)"): a line with one isn't a main world
WorldLineIs(line, name, names, re := "") {
    if InStr(line, "(") && !InStr(name, "(")
        return false
    if RegExMatch(line, re != "" ? re : WorldRegex(name))
        return true
    return StrLen(Trim(line)) >= 6 && FuzzyPick(line, names) = name
}

; finds a world in the "Select World" list (game area x 615-790, y 160-460): scrolled to the top, then
; down one notch at a time, reading the names. x, y: the name's middle
WorldFind(name, names, &x, &y) {
    global worldLastRead
    re := WorldRegex(name)
    ClosePopups()
    MouseMove 700, 342
    Sleep 100
    loop 30 {
        SendInput "{WheelUp}"
        Sleep 30
    }
    Wait(800)
    prev := ""
    loop 30 {
        txt := ""
        ; the names are blue on busy pictures and the reader gets letters wrong ("WaIIed City",
        ; "Shlbuya"): a close match counts too, and a second read with the colours flipped
        for tf in [{scale: 2, grayscale: true}, {scale: 3, grayscale: true, invertcolors: true}] {
            try {
                WinGetClientPos &ox, &oy, , , RBX
                res := OCR.FromRect(ox + 615, oy + 160, 175, 300, OcrLang(), tf)
                for ln in res.Lines {
                    txt .= ln.Text "|"
                    if WorldLineIs(ln.Text, name, names, re) {
                        x := Round(615 + ln.x + ln.w / 2), y := Round(160 + ln.y + ln.h / 2)
                        return true
                    }
                }
            }
        }
        if DeclineTrade()                            ; it covered the list: read again
            continue
        if txt = prev && A_Index > 1                 ; the list stopped moving: the bottom
            break
        prev := txt, worldLastRead := txt
        MouseMove 700, 342
        SendInput "{WheelDown}"
        Wait(450)
    }
    return false
}

; ---------------------------------------------------------------- popups in the way
; a trade request or the Tournament popup: closed. True if one was
ClosePopups() {
    t := DeclineTrade()
    return CloseTournament() || t
}

; another player's trade request on screen: Decline. fresh = take a new screenshot first (false: the
; one this pass already took)
DeclineTrade(fresh := true) {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        if fresh
            Fresh()
        if TradePopupAt(FindText(), ox, oy, 0, 0, 780, 560, &dx, &dy) {
            Clk(dx, dy)
            AddLog("Declined a trade request that was in the way")
            Wait(500)
            return true
        }
    }
    return false
}

; "Don't Miss Out! ... Tournament": closed with its red X (never Accept). The X is the red spot
; up and right of its title. Looked for when the pad opens (WorldFind, StartLegend), not every scroll
CloseTournament() {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        res := OCR.FromRect(ox, oy, 800, 600, OcrLang(), {scale: 2, grayscale: true})
        for ln in res.Lines {
            if !RegExMatch(ln.Text, "i)miss\s*out")    ; its title (a "Tournament" sign elsewhere isn't it)
                continue
            Fresh()
            if !RedSpotAt(FindText(), ox, oy, Round(ln.x), Max(0, Round(ln.y) - 140), Min(799, Round(ln.x + ln.w) + 140), Round(ln.y + ln.h), &cx, &cy)
                return false
            Clk(cx, cy)
            Wait(600)
            ; closed = the title is gone (a red spot that wasn't the X changes nothing)
            for ln2 in OCR.FromRect(ox, oy, 800, 600, OcrLang(), {scale: 2, grayscale: true}).Lines
                if RegExMatch(ln2.Text, "i)miss\s*out")
                    return false
            AddLog("Closed the Tournament popup")
            return true
        }
    }
    return false
}

; the middle of the biggest bright red spot (r > 190, g and b < 70, 12+ pixels) in a part of the
; game area, looked at every 2nd pixel. The rightmost one wins a tie (a close X sits top right)
RedSpotAt(scr, ox, oy, x1, y1, x2, y2, &cx := 0, &cy := 0) {
    cells := Map(), pts := []
    y := y1
    while y <= y2 {
        x := x1
        while x <= x2 {
            c := scr.GetColor(ox + x, oy + y, 0)
            if ((c >> 16) & 0xFF) > 190 && ((c >> 8) & 0xFF) < 70 && (c & 0xFF) < 70 {
                k := (x // 24) "," (y // 24)
                if !cells.Has(k)
                    cells[k] := {n: 0, sx: 0, sy: 0}
                cl := cells[k], cl.n++, cl.sx += x, cl.sy += y, pts.Push([x, y])
            }
            x += 2
        }
        y += 2
    }
    best := 0
    for k, cl in cells
        if !best || cl.n > best.n || (cl.n = best.n && cl.sx / cl.n > best.sx / best.n)
            best := cl
    if !best
        return false
    ; a spot can lie across two cells: everything red within 16 px of the best cell's middle
    bx := best.sx / best.n, by := best.sy / best.n, n := 0, sx := 0, sy := 0
    for p in pts
        if Abs(p[1] - bx) <= 16 && Abs(p[2] - by) <= 16
            n++, sx += p[1], sy += p[2]
    if n * 4 < 12
        return false
    cx := Round(sx / n), cy := Round(sy / n)
    return true
}

; a trade request's picture (its yellow Trade Request title); dx, dy: its Decline button
TradePopupAt(scr, ox, oy, x1, y1, x2, y2, &dx := 0, &dy := 0) {
    static tpl := IconPoints("000E0E0E100E0E0E200E0E0E300E0E0E400E0E0E500E0E0E600E0E0E700E0E0E800E0E0E900E0E0EA00E0E0EB00E0E0EC00E0E0ED00E0E0EE00E0E0EF00E0E0EG00E0E0EH00E0E0EI00E0E0EJ00E0E0EK00E0E0EL00E0E0EM00E0E0EN00E0E0EO00E0E0EP00E0E0EQ00E0E0ER00E0E0ES00E0E0ET0767008U0F6EA00V0C4BB0301CDBF0311FFED0021FFED0031FFED0041FFED0051FFED0061FFED0071FFED0081FFED0091D0C103A10E0E0EB10E0E0EC10E0E0ED10E0E0EE10E0E0EF10E0E0EG10E0E0EH10E0E0EI10E0E0EJ10E0E0EK10E0E0EL10E0E0EM10E0E0EN10E0E0EO10E0E0EP10E0E0EQ10E0E0ER10E0E0ES10E0E0ET1A89D05U1FFED00V1FEEC0002F8E20012FFE80022FFE80032FFE80042FFE80052FFE80062FFE80072FFE80082FFE80092F8E200A20E0E0EB20E0E0EC20E0E0ED20E0E0EE20E0E0EF20E0E0EG20E0E0EH20E0E0EI20E0E0EJ20E0E0EK20E0E0EL20E0E0EM20E0E0EN20E0E0EO20E0E0EP20E0E0EQ20E0E0ER20E0E0ES20E0E0ET2A99A05U2FFE800V2FFE80003766A0813A4930523A5940533A5940543FFE30053FFE30063DFC70273A5940583A59405937C6F08A30E0E0EB30E0E0EC30E0E0ED30E0E0EE30E0E0EF30E0E0EG30E0E0EH30E0E0EI30E0E0EJ30E0E0EK30E0E0EL30E0E0EM30E0E0EN30E0E0EO30E0E0EP30E0E0EQ30E0E0ER30E0E0ES30E0E0ET3A99705U3FFE300V3FFE300040E0E0E140E0E0E240E0E0E340E0E0E44FFDE0054FFDE0064A99405740E0E0E840E0E0E94C7AE03A4F7D700B4988506C4C6AD03D4F8D800E4B29B05F40E0E0EG439340BH4C4AB03I4F6D700J4C8AF03K4988506L4F9D900M4C6AD03N40E0E0EO40E0E0EP438320CQ4C3AB03R4F6D700S4CCB203T4CAB003U4FFDE00V4FFDE00050E0E0E150E0E0E250E0E0E350E0E0E45FFD90055FFD90065A99105750E0E0E850E0E0E95FFD900A5FFD900B5FFD900C5FFD900D5FFD900E5EBC801F5332D0CG5F2CE01H5FFD900I5FFD900J5FFD900K5FFD900L5FFD900M5FED800N50E0E0EO5312B0CP5F0CC01Q5FFD900R5FFD900S5FFD900T5FFD900U5FFD900V5FFD900060D0D0D160D0D0D260D0D0D360D0D0D46FFD40056FFD40066A98D05760D0D0D860D0D0D96FFD400A6FFD400B6FED300C6B69804D6A48905E6574A09F6B49604G6FFD400H6FFD400I6CBA903J6CAA803K6FFD400L6FFD400M6FFD400N60D0D0DO6B29504P6FFD400Q6FFD400R6CAA803S6CAA803T6FFD400U6FFD400V6FFD400070D0D0D170D0D0D270D0D0D370D0D0D47FFCF0057FFCF0067A98A05770D0D0D870D0D0D97FFCF00A7FFCF00B7B59404C70D0D0DD70D0D0DE70D0D0DF7F3C501G7FFCF00H7CFA803I70E0E0DJ70E0E0DK7CFA803L7FFCF00M7FFCF00N70D0D0DO7F3C501P7FFCF00Q7CDA703R70D0D0DS70E0E0DT7CFA803U7FFCF00V7FFCF00080D0D0D180D0D0D280D0D0D380D0D0D48FFCA0058FFCA0068A98705780D0D0D880D0D0D98FFCA00A8FFCA00B8A98705C80D0D0DD80D0D0DE80D0D0DF8F3C001G8FFCA00H8CCA203I80D0D0DJ80D0D0DK8CCA203L8FFCA00M8FFCA00N80D0D0DO8F5C201P8FFCA00Q8CEA303R80E0E0DS80D0D0DT8CCA203U8FFCA00V8FFCA00090D0D0D190D0D0D290D0D0D390D0D0D49FFC40059FFC40069A98305790D0D0D890D0D0D99FFC400A9FFC400B9A98305C90D0D0DD90D0D0DE90D0D0DF9B38B04G9FFC400H9FFC400I9CA9C03J9C99B03K9FFC400L9FFC400M9FFC400N90D0D0DO9B68D04P9FFC400Q9FFC400R9CB9D03S9C99B03T9FFC400U9FFC400V9FFC4000A0D0D0D1A0D0D0D2A0D0D0D3A0D0D0D4AFFBE005AFFBE006AA87E057A0D0D0D8A0D0D0D9AFFBE00AAFFBE00BAA87E05CA0D0D0DDA0D0D0DEA0D0D0DFA32280BGAF2B401HAFFBE00IAFFBE00JAFFBE00KAFFBE00LAFFBE00MAFFBE00NA0D0D0DOA352A0BPAF3B501QAFFBE00RAFFBE00SAFFBE00TAFFBE00UAFFBE00VAFEBD000B0D0D0D1B0D0D0D2B0D0D0D3B0D0D0D4BCE96035BF8B4006B7759077B0D0D0D8B0D0D0D9BCB9403ABF7B400BB735607CB0D0D0DDB0D0D0DEB0D0D0DFB0D0D0DGB392C0BHBC48F03IBF7B400JBD19902KB8B6706LBF7B400MBCB9403NB0D0D0DOB0D0D0DPB3B2D0BQBC59003RBF7B400SBD09703TB976F06UBF5B201VBC28E030C0D0D0D1C0D0D0D2C0D0D0D3C0D0D0D4C0D0D0D5C0D0D0D6C0D0D0D7C0D0D0D8C0D0D0D9C0D0D0DAC0D0D0DBC0D0D0DCC0D0D0DDC0D0D0DEC0D0D0DFC0D0D0DGC0D0D0DHC0D0D0DIC0D0D0DJC0D0D0DKC0D0D0DLC0D0D0DMC0D0D0DNC0D0D0DOC0D0D0DPC0D0D0DQC0D0D0DRC0D0D0DSC0D0D0DTC0D0D0DUC0D0D0DVC0D0D0D0D0D0D0D1D0D0D0D2D0D0D0D3D0D0D0D4D0D0D0D5D0D0D0D6D0D0D0D7D0D0D0D8D0D0D0D9D0D0D0DAD0D0D0DBD0D0D0DCD0D0D0DDD0D0D0DED0D0D0DFD0D0D0DGD0D0D0DHD0D0D0DID0D0D0DJD0D0D0DKD0D0D0DLD0D0D0DMD0D0D0DND0D0D0DOD0D0D0DPD0D0D0DQD0D0D0DRD0D0D0DSD0D0D0DTD0D0D0DUD0D0D0DVD0D0D0D", 0, 0)
    static anchors := [[1, 2, 255, 232, 0], [6, 3, 223, 199, 2], [12, 5, 255, 217, 0], [18, 5, 255, 217, 0], [26, 6, 255, 212, 0]]
    y := y1
    while y <= y2 {
        x := x1
        while x <= x2 {
            ok := true
            for a in anchors {
                col := scr.GetColor(ox + x + a[1], oy + y + a[2], 0)
                if Abs(((col >> 16) & 0xFF) - a[3]) > 35 || Abs(((col >> 8) & 0xFF) - a[4]) > 35 || Abs((col & 0xFF) - a[5]) > 40 {
                    ok := false
                    break
                }
            }
            if ok && IconScore(scr, ox + x, oy + y, tpl, 0.8) >= 0.8 {
                dx := x + 92, dy := y + 52
                return true
            }
            x++
        }
        y++
    }
    return false
}

; ---------------------------------------------------------------- Select -> Play Here -> Start
; the settings gear in the bottom left corner (lobby and stage; not on loading screens)
FoolGear() {
    static pat := "|<>*114$22.zzzzzzzzy7zzkDzz0zyQ3bk00D000w0k3k7UDUz1z7CDwQszUz1w1s3k30D000y803zkCTzVzzy7zzsTzzzzzzzzU"
    return FT(&fx, &fy, 0, 560, 90, 637, 0.1, 0.1, pat)
}

; the "Join Matchmaking?" window (its Find Match label, a picture from Ryn's macro)
FoolJoinUp() {
    static pat := "|<>*122$71.Dzzzzzzzzzs0Tzzzzzzzzzk0zzzzzzzzzzk1zzzzzzzzzzk3zzzzzzzzzzk7zzzzzzzzzzkD02DzzwTXz7kS00Tzzsz3wDww08zzzly3sTtsTzzzzXw7UznlzX4Tk7s61w7Vz60S0Dk43UD0CA0Q0TU070S0AMEkkz42AAw0sllXlyAAMtszlXX7XwQMlnlzX7667szlVbXz6CC0DlzXUD7yAQQ0TXz70SDwMsy8z7yDUzzzzzzzzzzztzzzzzzzzzzznzzzzzzzzzzzbzzzzzzzzzzzDzzzzzzzzzzz"
    return FT(&fx, &fy, 250, 250, 600, 470, 0.1, 0.1, pat)
}

; Select, Play Here if "Join Matchmaking?" asks, then Start until the loading screen hides the
; settings gear. label: "Infinite" / "Legend" / "Challenge" for the log. select: false when there's
; no Select button (a challenge's door asks "Join Matchmaking?" straight away)
PadStart(label, select := true) {
    if select {
        Clk(401, 438)                           ; Select
        Wait(1000)
    }
    Stale()
    if FoolJoinUp() {
        Clk(330, 325)                           ; Play Here
        Wait(1200)
    }
    Step("starting " label)
    t0 := A_TickCount
    while A_TickCount - t0 < 60000 {
        Stale()
        if !FoolGear()
            return true
        if FoolJoinUp()
            Clk(330, 325)
        else
            Clk(401, 464)                       ; Start
        Wait(2000)
    }
    AddLog(label " didn't start within a minute. Trying again")
    SaveDebugShot(StrLower(label) "_start")
    Clk(401, 525)                               ; Cancel
    Wait(1500)
    return false
}

; ---------------------------------------------------------------- the worlds
; the Story worlds in the order of the game's "Select World" list (Shibuya District last)
INF_MAPS() => ["Planet Greenie", "Walled City", "Snowy Town", "Sand Village", "Navy Bay", "Fiend City", "Spirit World",
    "Ant Kingdom", "Magic Town", "Haunted Academy", "Magic Hills", "Space Center", "Alien Spaceship", "Fabled Kingdom",
    "Ruined City", "Puppet Island", "Virtual Dungeon", "Snowy Kingdom", "Dungeon Throne", "Mountain Temple", "Rain Village",
    "Shibuya District"]

; ---------------------------------------------------------------- Legend Stages
; the Legend worlds in the order of the game's list
LEGEND_WORLDS() => ["Magic Hills (Elf Invasion)", "Spirit Invasion", "Space Center", "Fabled Kingdom (Generals)",
    "Ruined City (Midnight)", "Virtual Dungeon (Bosses)", "Dungeon Throne", "Rain Village"]
LegendMode() => cfg.Has("mode") && cfg["mode"] = "Legend"
LEGEND_WORLD() => cfg.Has("legendWorld") && IndexOf(LEGEND_WORLDS(), cfg["legendWorld"]) ? cfg["legendWorld"] : "Magic Hills (Elf Invasion)"
LEGEND_STAGE() => cfg.Has("legendStage") && IsInteger(cfg["legendStage"]) ? Max(1, Min(6, Integer(cfg["legendStage"]))) : 1

; the N of a "Legend Stage N" line (0: not one, or the "Legend Stages" button). The reader gives
; "l" or "|" for 1 and "З" for 3, and spaces inside words ("Legen d Stage 2" on Chris's PC);
; "Legend Stage 13" doesn't exist, so it isn't 1
LegendStageOf(text) {
    text := RegExReplace(text, "(?<=[A-Za-z])\s+(?=[a-z])")          ; "Legen d" -> "Legend"
    if !RegExMatch(text, "i)legend\s*stage\s*([1-6Il|Зз])(?![\dA-Za-z])", &m)
        return 0
    d := m[1]
    return IsInteger(d) ? Integer(d) : InStr("Зз", d) ? 3 : 1
}

; the stage to click: the one asked for if it shows, else the highest one that shows when they're all
; below it (a world with fewer stages). A higher one showing means the asked one was misread: 0
LegendPickStage(want, seen) {
    best := 0
    for n in seen {
        if n = want
            return want
        best := Max(best, n)
    }
    return best < want ? best : 0
}

; the map a Legend world plays on, for its walks and spots ("Ruined City (Midnight)" -> Ruined City)
LegendBaseMap(world) {
    w := RegExReplace(world, "\s*\(.*$")
    return w = "Spirit Invasion" ? "Spirit World" : w
}

; lobby -> Story pad -> Legend Stages -> the world -> the stage -> Start
StartLegend() {
    world := LEGEND_WORLD(), want := LEGEND_STAGE()
    Step("lobby: going to Legend Stages")
    AddLog("In the lobby, going to " world " Legend Stage " want)
    Clk(400, 340), Clk(400, 390)
    CloseChat()
    if !PadWalk() {
        AddLog("Couldn't reach a Story pad. Send Logs\legend_entry_....bmp in Discord so it can be fixed")
        SaveDebugShot("legend_entry")
        Wait(3000)
        return
    }
    ClosePopups()
    if !PadList(true, &read)
        return LegendFail("list", "couldn't switch the list to Legend Stages (read: " SubStr(read, 1, 120) ")")
    found := WorldFind(world, LEGEND_WORLDS(), &sx, &sy)
    if !found {
        AddLog("Legend: " world " not seen in the list yet (read: " SubStr(worldLastRead, 1, 120) "), looking again")
        Wait(5000)
        found := WorldFind(world, LEGEND_WORLDS(), &sx, &sy)
    }
    if !found
        return LegendFail("world", "couldn't find " world " in the Legend list (read: " SubStr(worldLastRead, 1, 120) ")")
    Clk(sx, sy + 8)
    Wait(1000)
    Stale()
    if !(n := LegendClickStage(want, &read))
        return LegendFail("stage", "couldn't find Legend Stage " want " (read: " SubStr(read, 1, 120) ")")
    if n != want
        AddLog("Legend: " world " has no Stage " want " here, playing Stage " n)
    Wait(500)
    if !PadStart("Legend")
        return
    AddLog(world " Legend Stage " n " started")
    LoadStage(LegendBaseMap(world))
}

LegendFail(kind, why) {
    AddLog("Legend: " why ". Send Logs\legend_" kind "_....bmp in Discord")
    SaveDebugShot("legend_" kind)
    Clk(401, 525)                               ; Cancel
    Wait(1500)
}

; the orange button above Select World switches the list: it says "Legend Stages" on the main list
; and "Main Stages" on the Legend one. legend: the list wanted. Nothing read there = the main list
; (as before Legend Stages existed), so Infinite never stops on it
PadList(legend, &read := "") {
    loop 4 {
        read := "", bx := 0
        try {
            WinGetClientPos &ox, &oy, , , RBX
            res := OCR.FromRect(ox + 500, oy + 60, 300, 110, OcrLang(), {scale: 2, grayscale: true})
            read := res.Text
            for wd in res.Words
                if !bx && RegExMatch(wd.Text, legend ? "i)^legend" : "i)^main")
                    bx := Round(500 + wd.x + wd.w / 2), by := Round(60 + wd.y + wd.h / 2)
        }
        if !!RegExMatch(read, "i)main\s*stage") = legend
            return true
        if A_Index = 4
            break
        if bx
            Clk(bx, by)
        else
            ClosePopups()                       ; something over it
        Wait(1000)
        Stale()
    }
    return false
}

; the "Legend Stage N" buttons on the left (game x 244-336). Clicked where they are; only when the
; one wanted isn't showing is the column scrolled, towards it, with the mouse over the buttons (the
; wheel anywhere else zooms the camera). Returns the stage clicked (N, else the highest one when
; the world has fewer), 0 if none
LegendClickStage(want, &read := "") {
    prev := ""
    loop 5 {
        rows := LegendRows(&read)
        if rows.Has(want) || !rows.Count || read = prev || A_Index = 5
            break
        prev := read, low := 9
        for n in rows
            low := Min(low, n)
        ScrollAt(289, 290, low > want ? -1 : 1)
        Wait(450)
    }
    ; where to click: the button read; else where the others' spacing puts it (a player's Stage 1,
    ; bright yellow, was never read while 2 and 3 were); else, nothing read at all, its usual spot
    ; (Stage 1 at 289,240, a row every 35 px); else the highest stage (a world with fewer stages)
    step := 35, pick := want, sure := false
    if rows.Has(want)
        x := rows[want][1], y := rows[want][2], sure := true
    else if LegendGuessRow(rows, want, &x, &y) {
        AddLog("Legend: Stage " want " not read, clicking where it sits next to the others")
        sure := true
    }
    else if !rows.Count
        x := 289, y := 240 + (want - 1) * step
    else {
        seen := []
        for n in rows
            seen.Push(n)
        if !(pick := LegendPickStage(want, seen))
            return 0
        x := rows[pick][1], y := rows[pick][2], sure := true
    }
    ; the panel's title says which stage got picked: another one = moved by the rows between them
    loop 3 {
        Clk(x, y)
        got := LegendTitleStage()
        if got = pick || (!got && sure)         ; right; or the title unread after a read/guessed button: as before
            return pick
        if !got || A_Index = 3
            return 0
        y += (pick - got) * step
        if y < 200 || y > 440
            return 0
    }
    return 0
}

; the stage shown in the panel's title ("Legend Stage 3", big blue letters right of the buttons), 0 unread
LegendTitleStage() {
    Wait(400)
    try {
        WinGetClientPos &ox, &oy, , , RBX
        return LegendStageOf(OCR.FromRect(ox + 350, oy + 205, 230, 50, OcrLang(), {scale: 2, grayscale: true}).Text)
    }
    return 0
}

; where stage `want`'s button is, from two buttons read (same column, even spacing). Only when a
; higher stage was read (so it exists: a world with fewer stages plays its highest instead). False
; when fewer than two were read, their spacing is odd, or it would be off the list
LegendGuessRow(rows, want, &x, &y) {
    a := 0, b := 0, higher := false
    for n in rows {
        higher := higher || n > want
        if !a
            a := n
        else if !b
            b := n
    }
    if !b || !higher
        return false
    step := (rows[b][2] - rows[a][2]) / (b - a)
    if step < 25 || step > 100
        return false
    x := rows[a][1], y := Round(rows[a][2] + (want - a) * step)
    return y >= 160 && y <= 450
}

; the stage buttons showing: Map(N, [x, y]). Read twice, the 2nd time with the colours flipped
; (yellow letters on orange)
LegendRows(&read := "") {
    rows := Map(), read := ""
    for tf in [{scale: 2, grayscale: true}, {scale: 3, grayscale: true, invertcolors: true}] {
        try {
            WinGetClientPos &ox, &oy, , , RBX
            for ln in OCR.FromRect(ox + 100, oy + 150, 260, 310, OcrLang(), tf).Lines {
                read .= ln.Text "|"
                if (n := LegendStageOf(ln.Text)) && !rows.Has(n)
                    rows[n] := [Round(100 + ln.x + ln.w / 2), Round(150 + ln.y + ln.h / 2)]
            }
        }
    }
    return rows
}

; the mouse wheel over a list: n notches, down (+) or up (-)
ScrollAt(x, y, n) {
    MouseMove x, y
    Sleep 100
    loop Abs(n) {
        SendInput n > 0 ? "{WheelDown}" : "{WheelUp}"
        Sleep 30
    }
}

; the end of a Legend round: counted already (RecordRun), so Replay. After a win the yellow button
; can be "Next" (the next stage), so the word Replay is clicked; not seen after a win: back to the
; lobby, where the stage is picked again
LegendReplay() {
    AddLog("Legend: " (lastResult = "win" ? "won" : lastResult = "loss" ? "lost" : "round over") ", replaying")
    if ChallengeLeave()                         ; a new challenge is up: the lobby instead
        return
    Step("replaying Legend")
    if OcrFindWord(0, 300, 800, 300, "i)^replay$", &rx, &ry)
        Clk(rx, ry)
    else if lastResult = "win" {
        AddLog("Legend: no Replay button seen, back to the lobby to start Stage " LEGEND_STAGE() " again")
        BackToLobby()
        return
    } else
        ClickOpenDungeon()                      ; the yellow Replay after a loss
    Wait(800)
    t0 := A_TickCount
    while A_TickCount - t0 < 10000 {
        Stale()
        if !Det("EndScreen")
            break
        Wait(250)
    }
    if !Det("EndScreen")
        LoadStage(LegendBaseMap(LEGEND_WORLD()))
}
