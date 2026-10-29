; =====================================================================
;  Auto challenge (Premium and Classic, the same file in both)
;  A new Challenge comes up every half hour on the clock (:00 and :30). With the switch on, the
;  macro plays each one once and goes back to farming: in the lobby it goes first; Legend, Infinite
;  and Infinity Castle leave for it at a round's end; a dungeon is always finished first; never in
;  Fool's Hunt (the alts have to stay in the same round). From Chris's clips (game area): Areas
;  (764,475) -> Challenges (302,413) -> walk left to the door -> "Join Matchmaking?" Play Here ->
;  Start ("You have already cleared this challenge!" over it -> Cancel). The round ends with Next,
;  reward popups, then "Return to lobby" at the top (400,121)
; =====================================================================
global challengeOn := false      ; a challenge round is being played

; the half hour a time is in (seconds since 1970, UTC, / 1800), counted from 2 minutes past: a PC
; clock a little ahead (or the game a little late) still showed the old, already cleared challenge,
; and the new one was then skipped
ChallengeSlot(stamp := A_NowUTC) => (DateDiff(stamp, "19700101000000", "Seconds") - 120) // 1800

; in the lobby: no challenge round is being played any more (a disconnect, leaving by hand or a
; Stop / Start in the middle of one left it set, and the next farming round was taken for its end:
; a dungeon was thrown away). Then: is a new one due?
ChallengeLobby() {
    global challengeOn
    challengeOn := false
    return ChallengeDue()
}

ChallengeDue() {
    if challengeOn || !cfg.Has("autoChallenge") || !cfg["autoChallenge"]
        return false
    if cfg.Has("mode") && cfg["mode"] = "Fool's Hunt"
        return false
    return ChallengeSlot() != (cfg.Has("challengeSlot") ? cfg["challengeSlot"] : 0)
}

; lobby -> the challenge's pad -> Play Here -> Start. The half hour counts as played from here on,
; whatever happens (no retry loop)
StartChallenge() {
    global challengeOn
    cfg["challengeSlot"] := ChallengeSlot()
    SaveConfig()
    Step("lobby: going to the challenge")
    AddLog("A new challenge is up, playing it once")
    Clk(400, 340), Clk(400, 390)
    CloseChat()
    if !ChallengeWalk()
        return ChallengeFail("entry", "couldn't reach the challenge's door (no Join Matchmaking)")
    Clk(330, 325)                               ; Play Here
    ; "You have already cleared this challenge! No extra rewards will be awarded." over Start
    ; (played by hand this half hour): Cancel, nothing to win
    loop 6 {
        Wait(500)
        if OcrFindWord(150, 420, 500, 70, "i)^already$", &ax, &ay) {
            AddLog("Challenge already cleared this half hour (no rewards), back to farming")
            Clk(401, 525)                       ; Cancel
            Wait(1000)
            return ChallengeStepOff()
        }
    }
    if !PadStart("Challenge", false)            ; (it pressed Cancel)
        return ChallengeStepOff()
    challengeOn := true
    AddLog("Challenge started")
    LoadStage()
}

; Areas -> Challenges, then left (A) until "Join Matchmaking?" shows. Twice at most
ChallengeWalk() {
    loop 2 {
        before := SceneSig()
        Clk(764, 475)                           ; Areas
        Wait(700)
        Clk(302, 413)                           ; Challenges
        Step("waiting for the teleport")
        WaitAreaTeleport(before)
        FocusRoblox()
        Step("walking to the challenge")
        SendKeys("{a down}")
        sig0 := SceneSig(), nudged := false
        loop 32 {                               ; 8 s
            Wait(250)
            Stale()
            if FoolJoinUp()
                break
            ; not walking after 2 s (the first A can be lost right after a teleport): click into
            ; the game and press A again, once
            if A_Index = 8 && !nudged && SigDiff(SceneSig(), sig0) < 20 {
                nudged := true
                SendKeys("{a up}")
                Clk(400, 470)
                Wait(200)
                SendKeys("{a down}")
            }
        }
        SendKeys("{a up}")
        Wait(300)
        if FoolJoinUp()
            return true
    }
    return false
}

; a step off the challenge's door after Cancel, so "Join Matchmaking?" doesn't come back
ChallengeStepOff() {
    SendKeys("{d down}")
    Wait(1000)
    SendKeys("{d up}")
}

ChallengeFail(kind, why) {
    AddLog("Challenge: " why ". Back to farming. Send Logs\challenge_" kind "_....bmp in Discord")
    SaveDebugShot("challenge_" kind)
}

; the top "Return to lobby" button's words, read with the usual mistakes ("Iobby", "lobby.")
LobbyWordRe() => "i)^\W*(return|[l1i|]obb[yv])\W*$"

; the end of a challenge round (already counted at Next): reward popups tapped away, then the
; "Return to lobby" button at the top. 150 tries (2-3 minutes), then the usual way back. Still a
; challenge until the lobby shows (a Stop / Start on the reward popups carries on from there)
ChallengeEnded() {
    global challengeOn
    AddLog("Challenge " (lastResult = "win" ? "won" : lastResult = "loss" ? "lost" : "over") ", back to farming")
    Step("challenge over: back to the lobby")
    loop 150 {
        Stale()
        if Det("Lobby")
            return (challengeOn := false)
        if Det("Next")
            ClickDet("Next", 0, -40, 5000)
        else if OcrFindWord(300, 95, 200, 55, LobbyWordRe(), &lx, &ly)
            Clk(lx, ly)                         ; "Return to lobby" at the top
        else
            Clk(560, 560)                       ; reward popups
        Wait(600)
    }
    if BackToLobby()
        challengeOn := false
}

; at the end of a Legend / Infinite / Infinity Castle round: a challenge due -> the lobby (it goes
; first there) instead of Replay. True if it left
ChallengeLeave() {
    if !ChallengeDue()
        return false
    AddLog("A new challenge is up, back to the lobby for it")
    BackToLobby()
    return true
}
