; =====================================================================
;  The Misty Tower (Classic, from Premium's Lib\Misty.ahk; Chris 23 Nov: "Make towers for classic too but not
;  bring alt and multi account"). UPD 21.5's event. From Chris's clips (23 Nov, game area): lobby Play ->
;  "Where do you want to Play?" -> Misty Village (400,323). From where it lands: W to Flutter ("[E] Flutter",
;  E, "[View Event Tower]" 204,472: "Misty Tower (Duo)", its floors on the left, Start 401,438). Then "Join
;  Matchmaking?" Play Here / Find Match. After a floor: Return to lobby (312,121) / Next Floor (488,121)
; =====================================================================
TowerMode() => cfg.Has("mode") && cfg["mode"] = "Misty Tower"
TowerMatchOn() => cfg.Has("towerMatch") && cfg["towerMatch"]

; Play -> Misty Village, landed (its loading screen). True when it went
MistyGo() {
    before := SceneSig()
    PlayTo("misty")
    Step("lobby: waiting for the teleport to Misty Village")
    return WaitAreaTeleport(before, true)
}

; holds keys (["w"], ["s", "d"]) until found() is true (its value back), walking walkMs from when the picture
; starts to change: at night the character stood still for 5-13 s after the teleport with W held, then walked
; (Chris 23 Nov 04:47-04:49, debug_044742 / 044850 and his clip: the 6 s were over before he moved, "now you are
; just not walking"). Not moving in 12 s: false, moved false. step: short steps (ms) with a look standing still
; between, for a prompt that only shows by its NPC ("[E] Flutter" showed for about a second as he walked by her and
; the looks while walking missed it, Chris 05:10 debug_051004). Every key let go after
MistyHold(keys, found, &moved := false, step := 0, walkMs := 6000) {
    moved := false, isDown := false
    try {
        start := SceneSig(), t0 := TickNow(), t1 := 0, walked := 0
        while t1 ? walked < walkMs : TickNow() - t0 < 12000 {
            if !isDown {
                for k in keys
                    SendKeys("{" k " down}")
                isDown := true
            }
            Wait(step ? step : 250)
            walked += t1 ? (step ? step : 250) : 0
            if step {
                for k in keys
                    SendKeys("{" k " up}")
                isDown := false
                Wait(120)                       ; standing still for the look
            }
            if r := found()
                return (moved := true, r)
            if !t1 && SigDiff(SceneSig(), start) >= 10
                t1 := TickNow(), moved := true
        }
        return false
    } finally {
        if isDown
            for k in keys
                SendKeys("{" k " up}")
    }
}

; the last try of a Misty walk: Roblox rejoined first. The very first walk worked (Chris 23 Nov 04:41); once the
; tower window had been left open (04:42) W never moved him again, day or night, after every Play ("it worked
; the very first time", his 05:03 clip: standing still with W held). A fresh join gives the game's controls back
MistyRejoin(what) {
    AddLog("Misty Village: " what ", rejoining Roblox (a fresh join gets the character moving again) and walking once more")
    RejoinToLobby()
}

; Flutter's prompt on screen ("[E] Flutter", often cut: "[E] Flutte"): her name is enough, the "[E]" isn't
; always read ("E]", "(E)", "[El"). Before E her name shows nowhere else in that part of the screen; the
; banner's news ("Flutter, Demon Girl and Lovey") isn't her prompt
FlutterLookIn(txt) {
    for ln in StrSplit(txt, "`n", "`r")
        if RegExMatch(ln, "i)F[l1I|]utt") && !RegExMatch(ln, "i)demon|lovey")
            return true
    return false
}

FlutterLook() {
    try {
        WinGetClientPos &ox, &oy, , , RBX
        return FlutterLookIn(OCR.FromRect(ox, oy + 180, 800, 330, OcrLang(), {scale: 1.5, grayscale: true}).Text)
    }
    return false
}

; "[View Event Tower]" in her dialogue (once her text is written out): its first word. Not "tower" alone: the
; middle option "How does the tower work?" reaches into the area
FlutterTowerAt(&x, &y) => OcrFindWord(100, 450, 300, 45, "i)^\W*v[il1]ew$|^event$", &x, &y)

; "Misty Tower (Duo)", the tower window's title (y about 186 once it has slid in, Chris's screenshot 23 Nov).
; "Tower", not "Misty": the Misty Village stage window has that word in the same place
TowerWindowUp() => OcrFindWord(160, 172, 330, 30, "i)^tower", &x, &y)

; Misty Village, then W to Flutter, E, "[View Event Tower]": the tower window. Not reached: a fresh Play, then
; Roblox rejoined and once more
MistyToTower() {
    if TowerWindowUp()
        return true
    seen := false, still := true
    loop 3 {
        if A_Index = 3
            MistyRejoin(still ? "the character didn't move" : seen ? "Flutter's tower didn't open" : "Flutter wasn't reached")
        MistyGo()
        FocusRoblox()
        Step("Misty Village: walking to Flutter (Misty Tower)")
        got := MistyHold(["w"], FlutterLook, &moved, 300)      ; steps of 0.3 s (about 5 studs): looks by her
        still := still && !moved
        ; her prompt seen: E straight away (Chris 23 Nov 04:35: the walk stopped right at her prompt, a second
        ; read missed it and E was never pressed). Her dialogue not opening: another look and E, twice
        loop 3 {
            if !got && !(got := FlutterLook())
                break
            seen := true
            Keys("e")
            if WaitFor(() => FlutterTowerAt(&x, &y), 6000, 300) {
                FlutterTowerAt(&x, &y)
                Clk(x, y)
                if WaitFor(TowerWindowUp, 3000, 250)
                    return true
            }
            got := false
        }
    }
    if still && !seen
        AddLog("Misty Tower: the character didn't move after the teleport to Misty Village (W held, even after a rejoin). Send Logs\misty_walk_....bmp in Discord"), SaveDebugShot("misty_walk")
    else if seen
        AddLog("Misty Tower: Flutter's [View Event Tower] didn't open the tower. Send Logs\misty_tower_....bmp in Discord"), SaveDebugShot("misty_tower")
    else
        AddLog("Misty Tower: Flutter wasn't reached (W from where Misty Village lands). Send Logs\misty_walk_....bmp in Discord"), SaveDebugShot("misty_walk")
    return false
}

; a button on 21.5's end screen by its word: at the top (Return to lobby 312,121 / Replay or Next Floor
; 488,121, Chris's clips), else lower down where end screens had it before
MistyEndAt(re, &x, &y) => OcrFindWord(0, 95, 800, 55, re, &x, &y) || OcrFindWord(0, 300, 800, 300, re, &x, &y)

; ---------------------------------------------------------------- the Misty Tower mode
global towerFloor := 0          ; the floor being played (read from the tower window), 0 unknown

; the floor list's words (the tower window's left side, x 243-337 from y 228: under the title, from the locked
; floor's "Clear the floor below to unlock!" down, Chris's screenshot 23 Nov), in game coordinates
TowerWords() {
    out := []
    try {
        WinGetClientPos &ox, &oy, , , RBX
        for w in OCR.FromRect(ox + 240, oy + 228, 100, 190, OcrLang(), {scale: 2.5, grayscale: true}).Words
            out.Push({Text: w.Text, x: 240 + w.x, y: 228 + w.y, w: w.w, h: w.h})
    }
    return out
}
; the list counts down (Chris's clip): the next floor locked on top ("Clear the floor below to unlock!", no
; number), then the highest open floor. Its number (0 none read), y its button's middle
TowerFloorsIn(words, &y) {
    best := 0, y := 0
    for i, w in words {
        n := 0
        if RegExMatch(w.Text, "i)^F[l1I]oor(\d{1,3})$", &m)
            n := Integer(m[1])
        else if RegExMatch(w.Text, "i)^F[l1I]oor$") && i < words.Length && RegExMatch(words[i + 1].Text, "^\d{1,3}$")
            n := Integer(words[i + 1].Text)
        if n > best
            best := n, y := Round(w.y + w.h / 2)
    }
    return best
}
; the highest open floor clicked (the first one not cleared). Its number, 0 when none was read
TowerFloorPick() {
    global towerFloor
    n := TowerFloorsIn(TowerWords(), &y)
    if n
        Clk(290, y), towerFloor := n            ; its button (x 243-337)
    return n
}

; lobby -> Misty Village -> Flutter -> the tower -> the highest open floor -> Start (Find Match: the match)
StartTower() {
    Step("lobby: going to the Misty Tower")
    AddLog("In the lobby, going to the Misty Tower" (TowerMatchOn() ? " (Find Match)" : ""))
    Clk(400, 340), Clk(400, 390)
    CloseChat()
    if !MistyToTower()
        return
    n := TowerFloorPick()
    what := n ? "Misty Tower Floor " n : "the Misty Tower"
    Wait(400)
    Clk(401, 438)                               ; Start (where the other pads' Select is)
    Wait(1000)
    Stale()
    if TowerMatchOn() && FoolJoinUp() && FoolMatchTries(TowerToMatch, "Misty Tower") {
        if RaidWaitMatch("Misty Tower") {
            AddLog(what " matched, starting")
            LoadStage("Misty Village")
        }
        return
    }
    if !PadStart("Misty Tower", false)          ; (Play Here, or Find Match that didn't go through)
        return
    AddLog(what " started")
    LoadStage("Misty Village")
}

; Find Match again after a number that didn't go through: "Join Matchmaking?" if it's still up, else the
; tower window again and Start. True when it's up
TowerToMatch() {
    Stale()
    if FoolJoinUp()
        return true
    if !MistyToTower()
        return false
    TowerFloorPick(), Wait(400)
    Clk(401, 438)                               ; Start (where the other pads' Select is)
    Wait(1000)
    Stale()
    return FoolJoinUp()
}

; the end of a tower floor (counted already). A win: Next Floor (the top of the end screen, Chris's clip).
; A loss: Replay / Retry if the game shows one, else the lobby (the start picks the same floor again).
; Find Match: the lobby for a new match. Nothing happening after the click: the lobby
TowerNext() {
    global towerFloor
    won := lastResult = "win"
    if won
        AddLog("Misty Tower: " (towerFloor ? "Floor " towerFloor : "the floor") " cleared" (towerFloor ? ", up to Floor " towerFloor + 1 : ""))
    else
        AddLog("Misty Tower: " (towerFloor ? "Floor " towerFloor : "the floor") " " (lastResult = "loss" ? "lost" : "over") ", trying it again")
    if won && towerFloor
        towerFloor++
    if ChallengeLeave()
        return
    if TowerMatchOn() {
        AddLog("Misty Tower: back to the lobby to Find Match again")
        BackToLobby()
        return
    }
    re := won ? "i)^next$" : "i)^(replay|retry)$"
    Step(won ? "Misty Tower: the next floor" : "Misty Tower: that floor again")
    if !MistyEndAt(re, &x, &y) {
        AddLog("Misty Tower: no " (won ? "Next Floor" : "Replay / Retry") " button seen, back to the lobby")
        BackToLobby()
        return
    }
    Clk(x, y)
    Wait(800)
    if WaitFor(() => (Stale(), !Det("EndScreen") && !MistyEndAt(re, &x2, &y2)), 12000, 500) {
        LoadStage("Misty Village")
        return
    }
    AddLog("Misty Tower: the " (won ? "next floor" : "floor") " didn't start, back to the lobby")
    BackToLobby()
}
