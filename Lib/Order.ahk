; =====================================================================
;  Order list (Premium and Classic, the same file in both)
;  Modes with a time each, played in turn (Chris 4 Nov: "2 hours of dungeons, then the Summer event for
;  2 hours, then dungeons for 2 hours", and a repeater so it goes on). It starts from the top when the
;  macro starts. A mode's time ends at a safe moment, so no round is thrown away: in the lobby, at a
;  round's end (Legend, Infinite, Infinity Castle, Portal, Summer Hunt) and after a dungeon's run.
;  Without Repeat the macro stops after the last one
; =====================================================================
global orderIdx := 0, orderSince := 0

OrderOn() => cfg.Has("orderOn") && cfg["orderOn"] && cfg.Has("order") && cfg["order"].Length

; the macro was started: the list from its top
OrderStart() {
    global orderIdx
    orderIdx := 0
    if OrderOn()
        OrderGo(1)
}

; to entry i: its mode switched on (Summer Hunt's own units and build order come in or go out with it)
OrderGo(i) {
    global orderIdx, orderSince
    e := cfg["order"][i]
    orderIdx := i, orderSince := A_TickCount
    if cfg["mode"] != e.mode {
        SetCfg("mode", e.mode)
        UI("refresh", UiState())
        try UpdateMapLabel()
    }
    AddLog("Order list " i "/" cfg["order"].Length ": " OrderModeName(e.mode) " for " OrderTime(e.mins))
}

; this mode's time is up (checked at the safe moments)
OrderDue() => OrderOn() && orderIdx >= 1 && orderIdx <= cfg["order"].Length
    && A_TickCount - orderSince >= cfg["order"][orderIdx].mins * 60000

; in the lobby: the next mode when the time's up. True when it moved on
OrderNext() {
    if !OrderDue()
        return false
    if orderIdx < cfg["order"].Length
        OrderGo(orderIdx + 1)
    else if cfg["orderRepeat"]
        OrderGo(1)
    else {
        AddLog("Order list done (" OrderTime(OrderTotal()) "), stopping")
        StopMacro()
    }
    return true
}

OrderModeName(m) => m = "Fool's Hunt" ? "Summer Hunt" : m
OrderTime(mins) => mins >= 60 ? (Mod(mins, 60) ? Format("{:.1f}", mins / 60) : mins // 60) " h" : mins " min"
OrderTotal() {
    t := 0
    for e in cfg["order"]
        t += e.mins
    return t
}

; [Order] Count=3, S1=Dungeon,120 ...
ReadOrder(modes) {
    list := []
    loop ClampInt(IniRead(cfgFile, "Order", "Count", 0), 0, 20, 0) {
        f := StrSplit(IniRead(cfgFile, "Order", "S" A_Index, ""), ",")
        if f.Length = 2 && IndexOf(modes, f[1]) && IsInteger(f[2])
            list.Push({mode: f[1], mins: ClampInt(f[2], 5, 1440, 60)})
    }
    return list
}
WriteOrder(ini) {
    ini.Set("Order", "Count", cfg["order"].Length)
    for i, e in cfg["order"]
        ini.Set("Order", "S" i, e.mode "," e.mins)
}
; the list from the page: [{mode, mins}]
SetOrder(list, modes) {
    if !(list is Array)
        return
    out := []
    for e in list
        if e is Map && IndexOf(modes, e.Get("mode", "")) && IsInteger(e.Get("mins", ""))
            out.Push({mode: e["mode"], mins: ClampInt(e["mins"], 5, 1440, 60)})
    if out.Length > 20
        out.Length := 20
    cfg["order"] := out
    SaveConfig()
}
