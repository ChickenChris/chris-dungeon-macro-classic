"use strict";
// Chris's Dungeon Macro - the window's interface. AutoHotkey runs the macro and talks to this page:
//   page -> AHK: chrome.webview.postMessage(JSON)        (see Send)
//   AHK -> page: window.ui.<fn>(...) via ExecuteScript   (see ui below)

const host = window.chrome && window.chrome.webview;
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const send = (cmd, data = {}) => {
  const msg = JSON.stringify(Object.assign({ cmd }, data));
  if (host) host.postMessage(msg); else console.log("to AHK:", msg);
};
const icon = (name) => `<svg class="i" viewBox="0 0 24 24">${ICONS[name] || ""}</svg>`;
const esc = (t) => String(t).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

const ACCENTS = [
  ["Starlight", "#7dd3fc", "#38bdf8"], ["Petal", "#f9a8d4", "#ec4899"], ["Aurora", "#c4b5fd", "#8b5cf6"],
  ["Meadow", "#86efac", "#22c55e"], ["Ember", "#fcd34d", "#f59e0b"], ["Crimson", "#fda4af", "#f43f5e"],
];
const OLD_ACCENTS = { Purple: "Starlight", Cyan: "Starlight", Pink: "Petal", Emerald: "Meadow", Amber: "Ember" };
const PAGES = [
  ["dash", "Dashboard", "layout-dashboard"], ["units", "Units", "swords"], ["build", "Build order", "list-ordered"],
  ["spots", "Spots and walks", "map-pin"], ["dungeon", "Dungeon", "castle"], ["settings", "Settings", "settings"],
];

let S = null;              // settings + lists from AHK
let run = "idle";
let spotMap = "";
let total = 20;

// ---------------------------------------------------------------- setup
function fillIcons(root = document) {
  $$("svg[data-icon]", root).forEach((s) => { s.setAttribute("viewBox", "0 0 24 24"); s.innerHTML = ICONS[s.dataset.icon] || ""; });
}

function buildRail() {
  const rail = $("#rail");
  const btn = (id, label, ic) => `<button class="nav" data-page="${id}" aria-label="${label}">${icon(ic)}<span class="tip">${label}</span></button>`;
  rail.innerHTML = PAGES.map((p) => btn(...p)).join("") + '<div class="rail-gap"></div>' + btn("look", "Look", "palette");
  rail.addEventListener("click", (e) => { const b = e.target.closest(".nav"); if (b) showPage(b.dataset.page); });
}

function showPage(id) {
  $$(".nav").forEach((n) => n.classList.toggle("on", n.dataset.page === id));
  $$(".page").forEach((p) => p.classList.toggle("on", p.id === "p-" + id));
  try { localStorage.setItem("page", id); } catch (e) {}
  if (id === "spots") send("spots", { map: spotMap });
}

// every [data-cmd] button sends its command
document.addEventListener("click", (e) => {
  const b = e.target.closest("[data-cmd]");
  if (!b) return;
  const cmd = b.dataset.cmd;
  if (["spotPick", "spotClear", "recordWalk", "pickWalk", "testWalk", "clearWalk"].includes(cmd)) send(cmd, { map: spotMap });
  else send(cmd);
});

// drag the window by the title bar
$("#title").addEventListener("mousedown", (e) => {
  if (e.button === 0 && !e.target.closest("button")) send("drag");
});
document.addEventListener("contextmenu", (e) => { if (!e.target.closest("input, textarea")) e.preventDefault(); });

// ---------------------------------------------------------------- small controls
function setVal(key, value) {
  S.cfg[key] = value;
  send("set", { key, value });
}

// a build order you just made is meant to be used: switch "Use the build order" on with it
// Build order on (with steps): it plays the whole stage by itself and the Units tab isn't used, so
// the slots are dimmed with a note saying so. "Edit anyway" lets you change them for later.
let unitsUnlocked = false;
function unitsLockState() {
  const on = !!+S.cfg.useBuild && (S.cfg.build || []).some(isMoveStep);
  document.body.classList.toggle("build-on", on);
  // switched on with no Place / Upgrade steps (a new team, or only Ability / Buff steps): the slots still play
  const empty = !!+S.cfg.useBuild && !on;
  document.body.classList.toggle("build-empty", empty);
  document.body.classList.toggle("units-unlocked", (on || empty) && unitsUnlocked);
  $$(".unlock-btn").forEach((b) => {
    b.textContent = unitsUnlocked ? "Done" : "Edit anyway";
    b.onclick = () => { unitsUnlocked = !unitsUnlocked; unitsLockState(); };
  });
}

function buildOn() {
  if (+S.cfg.useBuild) return;
  setVal("useBuild", 1);
  $$('.toggle[data-key="useBuild"] .switch').forEach((s) => s.classList.add("on"));
  toast("Build order switched on", "good");
  unitsLockState();
}

function bindToggles() {
  $$(".toggle[data-key]").forEach((t) => {
    const sw = $(".switch", t), key = t.dataset.key;
    sw.classList.toggle("on", !!+S.cfg[key]);
    t.onclick = (e) => {
      e.preventDefault();
      const v = +S.cfg[key] ? 0 : 1;
      $$(`.toggle[data-key="${key}"] .switch`).forEach((s) => s.classList.toggle("on", !!v));   // the same switch can be on two pages
      setVal(key, v);
      if (key === "bgAnimate") applyLook();
      if (key === "useBuild") unitsLockState();
    };
  });
}

function seg(el, items, current, onPick) {
  el.innerHTML = items.map((t, i) => `<button class="${i === current ? "on" : ""}" data-i="${i}">${esc(t)}</button>`).join("");
  el.onclick = (e) => {
    const b = e.target.closest("button"); if (!b) return;
    $$("button", el).forEach((x) => x.classList.toggle("on", x === b));
    onPick(+b.dataset.i);
  };
}

function stepper(el, value, min, max, onChange, step = 1) {
  el.innerHTML = `<button aria-label="Less">${icon("minus")}</button><b>${value}</b><button aria-label="More">${icon("plus")}</button>`;
  const [dn, up] = $$("button", el), out = $("b", el);
  const set = (v) => { v = Math.max(min, Math.min(max, v)); if (v === value) return; value = v; out.textContent = v; onChange(v); };
  dn.onclick = () => set(value - step);
  up.onclick = () => set(value + step);
}

const options = (list, sel) => list.map((t, i) => `<option value="${i}" ${i === sel ? "selected" : ""}>${esc(t)}</option>`).join("");

// drag a row to reorder a list; the row moves through the list as you drag.
// onMove(from, to) gets 0-based positions when you let go
function sortable(list, onMove) {
  list._onMove = onMove;
  if (list._sortable) return;
  list._sortable = true;
  list.addEventListener("pointerdown", (e) => {
    if (e.button !== 0 || e.target.closest("button, .switch")) return;
    const item = e.target.closest(".item.drag");
    if (!item || item.parentElement !== list) return;
    e.preventDefault();
    const rows = () => [...list.children].filter((c) => c.classList.contains("item"));
    const from = rows().indexOf(item), startY = e.clientY;
    let moving = false;
    const move = (ev) => {
      if (!moving) { if (Math.abs(ev.clientY - startY) < 4) return; moving = true; item.classList.add("dragging"); list.classList.add("sorting"); }
      let before = null;
      for (const o of rows()) {
        if (o === item) continue;
        const b = o.getBoundingClientRect();
        if (ev.clientY < b.top + b.height / 2) { before = o; break; }
      }
      if (before !== item.nextElementSibling || (!before && list.lastElementChild !== item))
        before ? list.insertBefore(item, before) : list.appendChild(item);
      const lr = list.getBoundingClientRect();
      if (ev.clientY < lr.top + 24) list.scrollTop -= 10; else if (ev.clientY > lr.bottom - 24) list.scrollTop += 10;
    };
    const up = () => {
      document.removeEventListener("pointermove", move);
      document.removeEventListener("pointerup", up);
      if (!moving) return;
      item.classList.remove("dragging"); list.classList.remove("sorting");
      const to = rows().indexOf(item);
      if (to !== from) list._onMove(from, to);
    };
    document.addEventListener("pointermove", move);
    document.addEventListener("pointerup", up);
  });
}

// ---------------------------------------------------------------- pages
function renderUnits() {
  const lim = ["Max", ...Array.from({ length: 9 }, (_, i) => "Level " + (i + 1))];
  $("#slots").innerHTML = S.cfg.slots.map((s, i) => `
    <div class="pane slot ${s.on ? "" : "off"}" data-i="${i}">
      <div class="slot-top"><kbd>${i + 1}</kbd><b>Slot ${i + 1}</b><i class="switch ${s.on ? "on" : ""}" data-p="on"></i></div>
      <div class="body">
        <div class="row"><span class="lbl">Units</span><span class="stepper" data-p="count"></span></div>
        <div class="row"><span class="lbl">Priority</span><span class="stepper" data-p="prio"></span></div>
        <div class="row"><span class="lbl">Upgrade</span><i class="switch ${s.up ? "on" : ""}" data-p="up"></i></div>
        <div class="row"><span class="lbl">Until</span><select data-p="limit">${options(lim, s.limit)}</select></div>
      </div>
    </div>`).join("");
  $$(".slot").forEach((card) => {
    const i = +card.dataset.i, s = S.cfg.slots[i];
    const put = (prop, v) => { s[prop] = v; send("slot", { i: i + 1, prop, value: v }); };
    $$(".switch", card).forEach((sw) => sw.onclick = () => {
      const p = sw.dataset.p, v = s[p] ? 0 : 1;
      sw.classList.toggle("on", !!v); put(p, v);
      if (p === "on") card.classList.toggle("off", !v);
    });
    stepper($('[data-p="count"]', card), s.count, 1, S.maxCount || 6, (v) => put("count", v));
    stepper($('[data-p="prio"]', card), s.prio, 1, 6, (v) => put("prio", v));
    $('select[data-p="limit"]', card).onchange = (e) => put("limit", +e.target.value);
  });
  seg($("#segPattern"), S.patterns, Math.max(0, S.patterns.indexOf(S.cfg.pattern)), (i) => setVal("pattern", S.patterns[i]));
  seg($("#segRetries"), ["Few", "Normal", "Many", "Max"], S.cfg.retries - 1, (i) => setVal("retries", i + 1));
}

// ---------------------------------------------------------------- Element teams (Premium)
// A team per element: tabs on the Units and Build order pages, each team with its own units and build
// order. The macro sends {list: [{name, element, game}], active, def}; Classic has none (one locked tab)
const EL_COLORS = { Fire: "#ff9a1f", Aqua: "#1aa7fb", Storm: "#b9e6fe", Air: "#7dfc9a", Rose: "#ffade3", Dark: "#8f8fd6", Light: "#f9f2a0" };
const EL_ICONS = { Fire: "flame", Aqua: "droplet", Storm: "snowflake", Air: "wind", Rose: "flower", Dark: "moon", Light: "sun" };
// the game's own element symbols (cut from Anime Adventures' element list; Gomu, the game's owner, OK'd
// using them in the macro). An unknown element falls back to a drawn icon in its colour
const elIcon = (el) => EL_ICONS[el]
  ? `<img class="eimg" src="img/elements/${el}.png" alt="${el}" draggable="false">`
  : `<span class="eico" style="--ec:#aaa">${icon("sparkles")}</span>`;
function renderTeams() {
  const T = S.teams && S.teams.list && S.teams.list.length ? S.teams : { list: [{ name: "Team 1", element: "", game: 1 }], active: 1, def: 1 };
  const els = S.elements || Object.keys(EL_COLORS);
  const act = +T.active || 1, cur = T.list[act - 1] || T.list[0];
  const tabs = T.list.map((t, i) => `<button class="tteam ${i + 1 === act ? "on" : ""}" data-t="${i + 1}" title="${t.element ? esc(t.element) + " team" : "No element picked"}">`
      + (t.element ? elIcon(t.element) : "") + esc(t.name)
      + (i + 1 === +T.def ? `<span class="tdef">${icon("star")}</span>` : "")
      + (i ? `<span class="tdel" data-del="${i + 1}" title="Remove ${esc(t.name)}">${icon("x")}</span>` : "") + "</button>").join("")
    + (T.list.length < 8 ? `<button class="tteam add" data-t="add" aria-label="Add a team" title="Add a team">${icon("plus")}</button>` : "");
  $$(".teamtabs").forEach((el) => {
    el.innerHTML = tabs;
    el.onclick = (e) => {
      const d = e.target.closest("[data-del]"); if (d) return send("teamDel", { i: +d.dataset.del });
      const b = e.target.closest("[data-t]"); if (!b) return;
      if (b.dataset.t === "add") send("teamAdd"); else if (+b.dataset.t !== act) send("team", { i: +b.dataset.t });
    };
  });
  const games = Array.from({ length: 10 }, (_, i) => "Game team " + (i + 1));
  $$(".teamrow").forEach((row) => {
  row.innerHTML = `
    <input type="text" class="tname" maxlength="20" value="${esc(cur.name)}" title="The team's name" aria-label="Team name">
    <span class="lbl">Element</span>${cur.element ? elIcon(cur.element) : ""}<select data-k="element">${options(["None", ...els], cur.element ? els.indexOf(cur.element) + 1 : 0)}</select>
    <span class="lbl" title="Its row in Units &gt; Teams in the game">Loads</span><select data-k="game">${options(games, (+cur.game || 1) - 1)}</select>
    <button class="btn sm ${act === +T.def ? "acc" : ""}" data-k="default" title="Used when a room boosts none of your teams' elements">${icon("star")}${act === +T.def ? "Default" : "Make default"}</button>
    ${act > 1 ? `<button class="btn sm" data-k="del" title="Remove this team">${icon("trash-2")}</button>` : ""}`;
  $$("select", row).forEach((sel) => sel.onchange = () => {
    const k = sel.dataset.k, v = k === "element" ? (+sel.value ? els[+sel.value - 1] : "") : +sel.value + 1;
    send("teamSet", { i: act, key: k, value: v });
  });
  row.onclick = (e) => {
    const b = e.target.closest("button[data-k]"); if (!b) return;
    if (b.dataset.k === "default") send("teamSet", { i: act, key: "default", value: 1 });
    else if (b.dataset.k === "del") send("teamDel", { i: act });
  };
  const nm = $(".tname", row);
  const saveName = () => { const v = nm.value.trim(); if (v && v !== cur.name) send("teamSet", { i: act, key: "name", value: v }); else nm.value = cur.name; };
  nm.onchange = saveName;
  nm.onkeydown = (e) => { if (e.key === "Enter") nm.blur(); else if (e.key === "Escape") { nm.value = cur.name; nm.blur(); } };
  });
}

// Ability steps (Premium): {kind: "ability", slot, units (0 = all), wave, every (0 = once)}
const EVERY = [0, 1, 2, 3, 4, 5, 6, 8, 10, 15, 20, -1];     // -1: switch the ability to Auto at that wave
const everyName = (n) => n < 0 ? "turn on Auto" : n ? "again every " + n + (n == 1 ? " wave" : " waves") : "once";
// Buff steps (Premium): {kind: "buff", slot, secs, pairs}: one copy's ability every secs seconds, in
// turn; pairs (the Erwin method): 2 copies 4 s apart, the next pair when the buff (secs) runs out
const BUFF_OPTS = [[20, 0], [25, 0], [30, 0], [35, 0], [40, 0], [45, 0], [60, 0]];     // (the Erwin method has its own step kind)
const buffName = (o) => o[1] ? `Erwin method: 4 copies in pairs, 4 s apart (buff ${o[0]} s)` : `one copy every ${o[0]} s, in turn`;
const isMoveStep = (st) => st.kind !== "ability" && st.kind !== "buff";
const sideIcon = (st) => icon(st.kind === "buff" ? "sparkles" : "zap");
// the Units page's Timed abilities box: the build order's Ability steps, edited from there too
function renderAbil() {
  const el = $("#abilList"); if (!el) return;
  const list = S.cfg.build, idx = list.map((st, i) => isMoveStep(st) ? -1 : i).filter((i) => i >= 0);
  el.innerHTML = idx.length ? idx.map((i) => `<div class="item abil" data-i="${i}"><span class="num">${sideIcon(list[i])}</span><span class="txt">${esc(stepText(list[i]))}</span>
      <span class="acts"><button class="del" data-a="del" aria-label="Remove">${icon("x")}</button></span></div>`).join("")
    : '<div class="empty">No timed abilities yet. Add one below, like "Wave 13: slot 3\'s ability, 1 unit".</div>';
  el.onclick = (e) => {
    const b = e.target.closest("button[data-a]"); if (!b) return;
    list.splice(+b.closest(".item").dataset.i, 1); send("build", { steps: list }); renderBuild();
  };
  if (!$("#aSlot").options.length) {
    $("#aSlot").innerHTML = options([1, 2, 3, 4, 5, 6].map((n) => "Slot " + n), 0);
    $("#aCount").innerHTML = options(["all units", ...[1, 2, 3, 4, 5, 6].map((n) => n + (n == 1 ? " unit" : " units"))], 1);
    $("#aEvery").innerHTML = options(EVERY.map(everyName), 0);
  }
  $("#aAdd").onclick = () => {
    if (isClassic()) return toast("Timed abilities are a Premium feature. Premium is in the Chris Macros Discord", "bad");
    if (!$("#aWave").value) return toast("Pick the wave", "bad");
    const w = Math.max(1, Math.min(999, Math.round(+$("#aWave").value)));
    list.push({ kind: "ability", slot: +$("#aSlot").value + 1, count: 1, up: 0, units: +$("#aCount").value, wave: w, every: EVERY[+$("#aEvery").value] });
    send("build", { steps: list }); renderBuild();
  };
}

function stepText(st) {
  if (st.kind === "erwin") return `Erwin buff: slot ${st.slot}, 4 copies as in the video` + (st.up ? `, upgrade each ${st.up < 0 ? "to max" : st.up + (st.up == 1 ? " time" : " times")}` : "");
  if (st.kind === "buff") return `Buff rotation: slot ${st.slot}, ` + (+st.pairs ? `Erwin pairs (4 s apart, buff ${st.secs} s)` : `one copy every ${st.secs} s`);
  if (st.kind === "ability")
    return `Wave ${st.wave}: slot ${st.slot}'s ability, ${+st.units ? st.units + (st.units == 1 ? " unit" : " units") : "all units"}`
      + (+st.every < 0 ? ", switched to Auto from then" : +st.every ? `, again every ${st.every} wave${st.every == 1 ? "" : "s"}` : ", once");
  const up = st.up < 0 ? "to max" : st.up + (st.up == 1 ? " time" : " times");
  if (st.kind === "place") return `Place slot ${st.slot} ×${st.count}` + (st.up == 0 ? "" : `, upgrade each ${up}`);
  const n = +st.units || 0;
  return n ? `Upgrade ${n} unit${n == 1 ? "" : "s"} of slot ${st.slot} ${up}` : `Upgrade slot ${st.slot} ${up}`;
}

function renderBuild() {
  const list = S.cfg.build;
  const T = S.teams, team = T && T.list.length > 1 && !isFool() ? T.list[(+T.active || 1) - 1] : null;
  $("#stepTitle").textContent = (isFool() ? "Fool's Hunt steps" : "Steps") + (team ? " · " + team.name : "");
  unitsLockState();
  const el = $("#steps");
  el.innerHTML = list.length ? list.map((st, i) => `
    <div class="item drag ${isMoveStep(st) && st.kind !== "erwin" ? "" : "abil"}" data-i="${i}"><span class="grip">${icon("grip-vertical")}</span><span class="num">${st.kind === "erwin" ? icon("sparkles") : isMoveStep(st) ? i + 1 : sideIcon(st)}</span><span class="txt">${esc(stepText(st))}${st.kind === "ability" ? '<small>fires at its wave, doesn\'t wait for the steps above</small>' : st.kind === "buff" ? '<small>from the slot\'s first copy down, doesn\'t wait for the steps above</small>' : st.kind === "erwin" ? '<small>places the 4 Erwins in its turn, then keeps the 100% buff going all round</small>' : ""}</span>
      <span class="acts"><button class="del" data-a="del" aria-label="Remove">${icon("x")}</button></span>
    </div>`).join("")
    : '<div class="empty">No steps yet. Add the first one below, like "Place slot 1 ×2, upgrade each 2 times".</div>';
  // a build order that never upgrades: its units stay at level 1 for the whole round
  if (list.some(isMoveStep) && !list.some((st) => isMoveStep(st) && st.up)) el.innerHTML += '<div class="empty warn">Nothing gets upgraded with these steps. To upgrade units you already placed, add an <b>Upgrade</b> step.</div>';
  el.onclick = (e) => {
    const b = e.target.closest("button[data-a]"); if (!b) return;
    list.splice(+b.closest(".item").dataset.i, 1);
    send("build", { steps: list }); renderBuild();
  };
  sortable(el, (from, to) => { list.splice(to, 0, list.splice(from, 1)[0]); send("build", { steps: list }); renderBuild(); });
  renderAbil();
}

let bKind = 0;
function initBuilder() {
  // (a plain Buff step, one copy every N s, is still read from settings and codes; it's not offered for now)
  seg($("#bKind"), ["Place", "Upgrade", "Ability", "Erwin buff"], 0, (i) => {
    if (i >= 2 && isClassic()) { toast((i === 3 ? "Erwin buff" : "Ability") + " steps are a Premium feature. Premium is in the Chris Macros Discord", "bad"); $$("#bKind button").forEach((b, j) => b.classList.toggle("on", j === bKind)); return; }
    bKind = i; builderState();
  });
  $("#bSlot").innerHTML = options([1, 2, 3, 4, 5, 6].map((n) => "Slot " + n), 0);
  $("#bCount").innerHTML = options(Array.from({ length: S.maxCount || 6 }, (_, i) => String(i + 1)), 0);
  builderState();
  const add = (st) => {
    S.cfg.build.push(st);
    send("build", { steps: S.cfg.build }); renderBuild();
    if (isMoveStep(st)) buildOn();                 // an Ability step works with the build order off too
    const el = $("#steps"); el.scrollTop = el.scrollHeight;
  };
  $("#bAdd").onclick = () => {
    if (bKind === 3) {                      // Erwin buff: places 4 copies in the video's order and keeps the buff up
      add({ kind: "erwin", slot: +$("#bSlot").value + 1, count: 4, up: S.upValues[+$("#bUp").value] || 0, secs: 30 });
      return;
    }
    if (bKind === 2) {                      // Ability: fires at its wave, not in the line
      const w = Math.max(1, Math.min(999, Math.round(+$("#bWave").value || 0)));
      if (!$("#bWave").value) return toast("Pick the wave", "bad");
      add({ kind: "ability", slot: +$("#bSlot").value + 1, count: 1, up: 0, units: +$("#bCount").value, wave: w, every: EVERY[+$("#bUp").value] });
      return;
    }
    const up = S.upValues[+$("#bUp").value];
    if (bKind === 1 && up === 0) return toast("Pick how many times to upgrade", "bad");
    // Upgrade: how many of the slot's units ("all units" = 0), e.g. only 1 of 2 Elyssias
    const st = bKind ? { kind: "upgrade", slot: +$("#bSlot").value + 1, count: 1, up, units: +$("#bCount").value }
      : { kind: "place", slot: +$("#bSlot").value + 1, count: +$("#bCount").value + 1, up, units: 0 };
    // Place always puts down NEW units. Players used "Place slot 2 ×3, upgrade to max" to upgrade the
    // slot 2 units they had already placed, and got 3 more of them. Ask when that's likely.
    const before = S.cfg.build.findIndex((o) => o.kind === "place" && o.slot === st.slot);
    if (st.kind === "place" && before >= 0) {
      const upTxt = up < 0 ? "to max" : up ? up + (up == 1 ? " time" : " times") : "";
      return modal(`Slot ${st.slot} is already placed`,
        `<p class="muted">Step ${before + 1} already places slot ${st.slot}. A Place step always puts down <b>new</b> units, so this adds ${st.count} more.` +
        (upTxt ? ` Did you mean to upgrade the ones you placed?</p>` : `</p>`),
        upTxt ? "Upgrade them " + upTxt : "Place more", () => add(upTxt ? { kind: "upgrade", slot: st.slot, count: 1, up } : st),
        upTxt ? "Place " + st.count + " more" : "Cancel", upTxt ? () => add(st) : null);
    }
    add(st);
  };
}
function builderState() {
  // Place: how many to place (×N). Upgrade: how many of that slot's units (all, or the first N placed)
  $("#bX").style.display = bKind ? "none" : "";
  $$(".abil-only").forEach((e) => e.style.display = bKind === 2 ? "" : "none");
  $("#bCount").style.display = bKind === 3 ? "none" : "";      // Erwin buff: no count box
  const max = S.maxCount || 6;
  $("#bUp").innerHTML = bKind === 3 ? options(S.upNames, Math.max(0, S.upValues.indexOf(-1)))
    : bKind === 2 ? options(EVERY.map(everyName), 0) : options(S.upNames, 0);
  $("#bUp").title = bKind === 3 ? "Erwin buff (Commander), as in the video: places 2, uses the 1st one's ability, places the 3rd, the 2nd's ability 4 s after the 1st, places the 4th; then the 3rd when the 1st buff runs out (30 s), the 4th 4 s later, and round again: the 100% buff. Put all 4 in each other's range (Spots). Each one gets upgraded like this" : "";
  $("#bCount").innerHTML = bKind
    ? options(["all units", ...Array.from({ length: max }, (_, i) => (i + 1) + (i ? " units" : " unit"))], 0)
    : options(Array.from({ length: max }, (_, i) => String(i + 1)), 0);
  $("#bCount").title = bKind === 2 ? "How many of that slot's units use their ability (the ones that waited longest first)" : bKind ? "How many of that slot's units: all, or only the first ones placed" : "How many to place";
}
// the step list and builder over the whole page (with the team boxes the list got small)
function bigEditor(on) {
  document.body.classList.toggle("build-full", on);
  $("#bBig").innerHTML = on ? icon("check") + "Done" : icon("maximize") + "Bigger editor";
}
$("#bBig").onclick = () => bigEditor(!document.body.classList.contains("build-full"));

function renderSpotsPage() {
  $("#spotMap").innerHTML = S.maps.map((m) => `<option ${m === spotMap ? "selected" : ""}>${esc(m)}</option>`).join("");
  $("#spotMap").onchange = (e) => { spotMap = e.target.value; send("spots", { map: spotMap }); };
}

// Farm mode: one switch on the start page, one on the Dungeon page, kept in step
const MODES = ["Dungeon", "Infinity Castle", "Fool's Hunt", "Infinite", "Legend", "Portal"];
const FREE_MODES = ["Dungeon", "Legend"];   // the ones Classic has
const isInf = () => S.cfg.mode === "Infinite";
const isLegend = () => S.cfg.mode === "Legend";
const isPortal = () => S.cfg.mode === "Portal";
const isIC = () => S.cfg.mode === "Infinity Castle";
const isFool = () => S.cfg.mode === "Fool's Hunt";
function renderMode() {
  const cur = Math.max(0, MODES.indexOf(S.cfg.mode || "Dungeon"));
  const pick = (i) => {
    const wasFool = isFool();
    setVal("mode", MODES[i]);
    if (isFool() !== wasFool) swapUnitSets();
    renderMode(); if (run) setRun(run);
  };
  seg($("#segModeHome"), MODES, cur, pick);
  if (isClassic()) $$("#segModeHome button").filter((b) => !FREE_MODES.includes(MODES[+b.dataset.i])).forEach((b) => {   // Premium's modes, locked
    b.dataset.premium = MODES[+b.dataset.i]; b.dataset.tip = MODES[+b.dataset.i] + " is in Premium";
    b.insertAdjacentHTML("afterbegin", icon("lock"));
  });
  $("#modeSub").classList.toggle("open", isIC());
  $("#foolSub").classList.toggle("open", isFool());
  $("#infSub").classList.toggle("open", isInf());
  const im = $("#infMap"), maps = S.infMaps || ["Shibuya District"];
  im.innerHTML = options(maps, Math.max(0, maps.indexOf(S.cfg.infMap || "Shibuya District")));
  im.onchange = () => setVal("infMap", maps[+im.value]);
  $("#legendSub").classList.toggle("open", isLegend());
  $("#autoChallenge").classList.toggle("dim", isFool());
  $("#portalSub").classList.toggle("open", isPortal());
  const pn = $("#portalName");
  pn.value = S.cfg.portalName || "Shibuya Portal";
  pn.onchange = () => { setVal("portalName", pn.value.trim() || "Shibuya Portal"); if (run) setRun(run); };   // the alts stay in the same round: no challenges
  const lw = $("#legendWorld"), worlds = S.legendWorlds || ["Magic Hills (Elf Invasion)"];
  lw.innerHTML = options(worlds, Math.max(0, worlds.indexOf(S.cfg.legendWorld || worlds[0])));
  lw.onchange = () => { setVal("legendWorld", worlds[+lw.value]); if (run) setRun(run); };
  const ls = $("#legendStage"), stages = [1, 2, 3, 4, 5, 6].map((n) => "Stage " + n);
  ls.innerHTML = options(stages, Math.min(5, Math.max(0, (+S.cfg.legendStage || 1) - 1)));
  ls.onchange = () => { setVal("legendStage", +ls.value + 1); if (run) setRun(run); };
  seg($("#segFoolJoin"), ["Play Here", "Find Match"], +S.cfg.foolMatch ? 1 : 0, (i) => {
    setVal("foolMatch", i);
    if (i && +S.cfg.foolOwnTeam) toast("Find Match plays alone (with the freeze). Pick Play Here to use your alts");
  });
  seg($("#segIcDiff"), ["Normal", "Hard"], +S.cfg.icHard ? 1 : 0, (i) => setVal("icHard", i));
  stepper($("#icStop"), +S.cfg.icStopFloors || 0, 0, 500, (v) => setVal("icStopFloors", v));
  stepper($("#foolFreeze"), +S.cfg.foolFreeze || 80, 20, 150, (v) => setVal("foolFreeze", v), 5);
  stepper($("#foolAccounts"), +S.cfg.foolAccounts || 2, 2, 6, (v) => setVal("foolAccounts", v));
}

// in or out of Fool's Hunt: its own units and build order come in right away (the macro does the
// same swap and sends them again, so the page doesn't wait on it). The first time, Fool's Hunt
// starts with a copy of the units and an empty build order, like the macro.
function swapUnitSets() {
  const c = S.cfg;
  if (!c.otherSlots || !c.otherSlots.length) c.otherSlots = c.slots.map((s) => ({ ...s }));
  [c.slots, c.otherSlots] = [c.otherSlots, c.slots];
  [c.build, c.otherBuild] = [c.otherBuild || [], c.build];
  ui.units(c.slots, c.build, isFool() ? 20 : 6);
}

function renderDungeon() {
  $("#route").innerHTML = S.cfg.route.map((key, i) => `
    <div class="route"><span class="num">${i + 1}</span><select data-i="${i}">${options(S.roomNames, Math.max(0, S.roomKeys.indexOf(key)))}</select></div>`).join("");
  $$("#route select").forEach((sel) => sel.onchange = () => {
    const i = +sel.dataset.i; S.cfg.route[i] = S.roomKeys[+sel.value];
    send("route", { i: i + 1, key: S.cfg.route[i] });
  });
  renderMode();
  renderCurses();
  renderShop();
  renderFoolCards();
  stepper($("#skipWorst"), S.cfg.skipWorst, 0, S.curses.length, (v) => { setVal("skipWorst", v); renderCurses(); });
  const names = ["Burst", "Armor", "Chaos", "Vamparism", "Frenzy", "Eruption"];
  const chips = names.map((n) => `<button class="chip ${S.cfg.denyShrine[n] ? "on" : ""}" data-n="${n}" data-tip="${esc(SHRINE_INFO[n])}">${icon("ban")}${n}</button>`);
  chips.push(`<button class="chip ${S.cfg.denyUnknownShrine ? "on" : ""}" data-k="denyUnknownShrine" data-tip="A shrine whose curse the macro couldn't read">${icon("ban")}Unknown</button>`);
  chips.push(`<button class="chip ${S.cfg.denyAllShrines ? "on" : ""}" data-k="denyAllShrines" data-tip="Turn down every shrine, whatever its curse">${icon("ban")}Every shrine</button>`);
  $("#shrines").innerHTML = chips.join("");
  $("#shrines").onclick = (e) => {
    const c = e.target.closest(".chip"); if (!c) return;
    if (c.dataset.n) { const v = S.cfg.denyShrine[c.dataset.n] ? 0 : 1; S.cfg.denyShrine[c.dataset.n] = v; c.classList.toggle("on", !!v); send("deny", { name: c.dataset.n, value: v }); }
    else { const k = c.dataset.k, v = +S.cfg[k] ? 0 : 1; c.classList.toggle("on", !!v); setVal(k, v); }
  };
}

// ---------------------------------------------------------------- shop
const SHOP_INFO = {
  "Philosophers Stone": "Turns all current chests into rare chests (rare)", "Mask of Riches": "-50% placement and upgrade cost (rare)",
  "Golden Mushroom": "-30% placement and upgrade cost", "Golden Branch": "-15% placement and upgrade cost",
  "Genie Lamp": "+100% chest luck (rare)", "Golden Fishhook": "+40% chest luck", "Fish Hook": "+20% chest luck (Fishhook)",
  "Shimmering Moon Fragment": "+1 star remnant per chest", "Celestial Blade": "+777% true damage (rare)",
  "Archmage's Hat": "+250% magic damage", "Aures Maul": "Physical damage boost", "Magic Tome": "+100% magic damage",
  "Solar Cleaver": "+100% physical crit chance (rare)", "Mage Coat": "+50% magic damage", "Reaper Scythe": "+75% boss damage",
  "Glacial Axe": "-30% enemy speed", "Ninja Belt": "-12% attack cooldown", "Elf Bow": "+50% range", "Bow": "+20% range",
  "Headsplitter": "+75% physical damage", "Ice Dagger": "Enemies move 20% slower", "Dagger": "+15% attack",
  "Stormbringer": "-50% attack cooldown (rare, 1000 coins)", "Nimble Cloak": "-7% attack cooldown",
  "Axe": "+50% physical crit chance", "Longbow": "+30% range", "Scimitar": "+75% attack", "Sword": "+30% attack", "Speedy Boots": "-20% attack cooldown",
};
const SHOP_MAGIC = ["Archmage's Hat", "Magic Tome", "Mage Coat"], SHOP_PHYSICAL = ["Aures Maul", "Solar Cleaver", "Headsplitter", "Axe"];
const DMG = ["Magic", "Physical", "Both"];
function renderShop() {
  const list = S.cfg.shopRank || [], off = S.cfg.shopOff || (S.cfg.shopOff = {}), dmg = S.cfg.dmgType || "Both";
  const MINS = [0, 300, 600, 900, 1200];
  seg($("#segShopMin"), ["Any", "300", "600", "900", "1200"], Math.max(0, MINS.indexOf(+S.cfg.shopMinCoins)), (i) => setVal("shopMinCoins", MINS[i]));
  seg($("#segDmg"), DMG, Math.max(0, DMG.indexOf(dmg)), (i) => { S.cfg.dmgType = DMG[i]; send("set", { key: "dmgType", value: DMG[i] }); renderShop(); });
  const wrongType = (n) => (dmg === "Magic" && SHOP_PHYSICAL.includes(n)) || (dmg === "Physical" && SHOP_MAGIC.includes(n));
  const el = $("#shopList");
  el.innerHTML = list.map((n, i) => {
    const wrong = wrongType(n), on = !+off[n] && !wrong;
    return `<div class="item drag tall ${on ? "" : "dim"}" data-i="${i}"><span class="grip">${icon("grip-vertical")}</span><span class="num">${i + 1}</span>
      <span class="txt">${esc(n)}<small>${esc(wrong ? "Not your damage type" : SHOP_INFO[n] || "")}</small></span>
      <i class="switch ${on ? "on" : ""} ${wrong ? "locked" : ""}" data-n="${esc(n)}" role="switch" aria-checked="${on}" aria-label="Buy ${esc(n)}"></i></div>`;
  }).join("");
  el.onclick = (e) => {
    const sw = e.target.closest(".switch"); if (!sw || sw.classList.contains("locked")) return;
    const n = sw.dataset.n, v = +off[n] ? 0 : 1;
    off[n] = v; send("shopOff", { name: n, value: v }); renderShop();
  };
  sortable(el, (from, to) => { list.splice(to, 0, list.splice(from, 1)[0]); send("shopRank", { list }); renderShop(); });
}

// ---------------------------------------------------------------- Fool's Hunt cards
const FOOL_INFO = {
  shield: ["Enemy Shield", "+3 enemy shield, +30% AprilCoins"], regen: ["Enemy Regen", "+0.5% enemy regen, +30% AprilCoins"],
  health: ["Enemy Health", "+50% enemy health, +30% AprilCoins"], speed: ["Enemy Speed", "+25% enemy speed, +30% AprilCoins (II: +50%, +70%)"],
  yen: ["Yen", "+3000 yen right away"], range: ["Range", "+15% range for your units"],
  cooldown: ["Cooldown", "-5% attack cooldown for your units (II: -10%)"], attack: ["Attack", "+12% attack for your units (II: +25%)"],
  explosive: ["Explosive Deaths", "Enemies explode when they die (+6 range), +30% AprilCoins"], resistant: ["Resistant Enemies", "+50 enemy physical AND magic resist, +30% AprilCoins (II: +100 each, +70%)"],
  spellproof: ["Spellproof Enemies", "+75 enemy magic resist, +30% AprilCoins"], plated: ["Plated Enemies", "+75 enemy physical resist, +30% AprilCoins (II: +150, +70%)"],
  boss: ["Boss Damage", "Bosses get stronger, more AprilCoins"],
};
function renderFoolCards() {
  const list = S.cfg.foolCards || [], el = $("#foolCards");
  if (!el) return;
  el.innerHTML = list.map((k, i) => {
    const [name, info] = FOOL_INFO[k] || [k, ""];
    return `<div class="item drag tall" data-i="${i}"><span class="grip">${icon("grip-vertical")}</span><span class="num">${i + 1}</span>
      <span class="txt">${esc(name)}<small>${esc(info)}</small></span></div>`;
  }).join("");
  sortable(el, (from, to) => { list.splice(to, 0, list.splice(from, 1)[0]); send("foolCards", { list }); renderFoolCards(); });
}

// what each curse does (from the Anime Adventures wiki). Shrine curses last for the rest of the
// dungeon run and stack; room curses only last for that one room.
const SHRINE_INFO = {
  Burst: "Enemies get +100% chance to spawn with the Burst trait. Lasts the rest of the dungeon.",
  Armor: "Enemies get +100% chance to spawn with the Armor trait. Lasts the rest of the dungeon.",
  Chaos: "All curses are random. Lasts the rest of the dungeon.",
  Vamparism: "Enemies regenerate 3% health. Lasts the rest of the dungeon.",
  Frenzy: "Enemies move 50% faster. Lasts the rest of the dungeon.",
  Eruption: "Enemies explode further when they die (+24 range). Lasts the rest of the dungeon.",
};
const CURSE_INFO = {   // curses stay until the dungeon is cleared
  Flying: "+20% chance of Flying enemies (Curse of Flight). Lasts the rest of the dungeon",
  Wind: "Enemies move 25% faster. Lasts the rest of the dungeon",
  Money: "Curse of Money (-10% hoard money) and Curse of Shopping (+10% shop prices). Lasts the rest of the dungeon",
  Health: "Enemies have +80% HP ([*] Vitality: +200%). Lasts the rest of the dungeon",
  Shielding: "Enemies get +3 shield. Lasts the rest of the dungeon",
  Regen: "Enemies regenerate 1% health. Lasts the rest of the dungeon",
  Exploding: "Enemies explode further when they die: +12 range ([*] Eruption: +24). Lasts the rest of the dungeon",
};

function renderCurses() {
  const rank = S.cfg.curseRank, skip = S.cfg.skipWorst;
  $("#curses").innerHTML = rank.map((c, i) => `
    <div class="item drag sm ${i < skip ? "skip" : ""}" data-i="${i}" data-tip="${esc(CURSE_INFO[c] || "")}"><span class="grip">${icon("grip-vertical")}</span><span class="num">${i + 1}</span><span class="txt">${esc(c === "Money" ? "Shopping" : c)}</span>
      ${i < skip ? '<span class="tag">avoided</span>' : ""}
    </div>`).join("");
  sortable($("#curses"), (from, to) => { rank.splice(to, 0, rank.splice(from, 1)[0]); send("curses", { list: rank }); renderCurses(); });
}

// the Keyboard setting: [value, what the dropdown shows]
const KEYBOARDS = [["Auto", "Auto (detect it)"], ["QWERTY", "QWERTY (English and most others)"], ["AZERTY", "AZERTY (French, Belgian)"],
  ["QWERTZ", "QWERTZ (German, Swiss, Czech...)"], ["Non-Latin", "Russian, Greek, other non-Latin"]];
function renderSettings() {
  const kb = $("#kbSel");
  if (kb) {
    kb.innerHTML = options(KEYBOARDS.map((k) => k[1]), Math.max(0, KEYBOARDS.findIndex((k) => k[0] === (S.cfg.keyboard || "Auto"))));
    kb.onchange = () => setVal("keyboard", KEYBOARDS[+kb.value][0]);
  }
  $("#speed").innerHTML = options(S.speeds, S.cfg.placeSpeed - 1);
  $("#speed").onchange = (e) => setVal("placeSpeed", +e.target.value + 1);
  for (const id of ["webhook", "psLink", "showcaseName", "showcaseDiscord"]) {
    const inp = $("#" + id);
    inp.value = S.cfg[id] || "";
    inp.onchange = () => setVal(id, inp.value.trim());
  }
}

// ---------------------------------------------------------------- look
function accentOf(name) {
  name = OLD_ACCENTS[name] || name;
  return ACCENTS.find((a) => a[0] === name) || ACCENTS.find((a) => a[0] === "Crimson");
}
function renderLook() {
  const cur = accentOf(S.cfg.accent)[0];
  $("#swatches").innerHTML = ACCENTS.map(([n, c, d]) =>
    `<button class="swatch ${n === cur ? "on" : ""}" data-n="${n}" style="--sw:${c};background:linear-gradient(135deg,${c},${d})">${n}</button>`).join("");
  $("#swatches").onclick = (e) => {
    const b = e.target.closest(".swatch"); if (!b) return;
    $$(".swatch").forEach((x) => x.classList.toggle("on", x === b));
    setVal("accent", b.dataset.n); applyLook();
  };
  for (const id of ["bgOpacity", "bgBlur", "glass"]) {
    const r = $("#" + id);
    r.value = S.cfg[id];
    r.oninput = () => { S.cfg[id] = +r.value; applyLook(); };
    r.onchange = () => setVal(id, +r.value);
  }
}
function applyLook() {
  const [, c, d] = accentOf(S.cfg.accent), st = document.documentElement.style;
  st.setProperty("--acc", c); st.setProperty("--acc-deep", d);
  st.setProperty("--glass", (S.cfg.glass / 100).toFixed(2));
  // the background is a video (webm / mp4) or a picture (gif / png / jpg)
  const want = S.bgUrl || "../Images/ui/sakura.webm";
  const isVideo = /\.(webm|mp4)(\?|$)/i.test(want);
  const img = $("#bg"), vid = $("#bgv"), fr = $("#bgFreeze");
  const el = isVideo ? vid : img;
  if (el.dataset.src !== want) { el.dataset.src = want; el.src = want; }
  (isVideo ? img : vid).style.display = "none";
  if (isVideo) { img.removeAttribute("src"); delete img.dataset.src; }
  if (!isVideo) { vid.pause(); vid.removeAttribute("src"); delete vid.dataset.src; vid.load(); }
  el.style.display = "";
  for (const x of [img, vid, fr]) {
    x.style.opacity = (S.cfg.bgOpacity / 100).toFixed(2);
    x.style.filter = `blur(${S.cfg.bgBlur}px)`;
  }
  const still = !+S.cfg.bgAnimate;
  if (isVideo) {             // a video simply pauses on the current frame
    fr.style.display = "none"; img.onload = null;
    still ? vid.pause() : vid.play().catch(() => {});
  } else if (still) {        // a GIF is copied onto a canvas to keep one still frame
    const draw = () => {
      fr.width = innerWidth; fr.height = innerHeight;
      const g = fr.getContext("2d"), r = Math.max(fr.width / img.naturalWidth, fr.height / img.naturalHeight);
      const w = img.naturalWidth * r, h = img.naturalHeight * r;
      g.drawImage(img, (fr.width - w) / 2, (fr.height - h) / 2, w, h);
      fr.style.display = "block"; img.style.visibility = "hidden";
    };
    img.complete && img.naturalWidth ? draw() : (img.onload = draw);
  } else { fr.style.display = "none"; img.style.visibility = ""; img.onload = null; }
  $("#bgName").textContent = S.bgName || "Sakura";
}

// ---------------------------------------------------------------- dashboard
// the dungeon run as a bar that fills up room by room, with the boss at the end
function buildTrail() {
  const bar = $("#trail");
  bar.style.setProperty("--rooms", total);
}
function setDepth(depth) {
  const d = Math.max(0, Math.min(total, +depth || 0));
  $("#trailFill").style.width = (d / total * 100).toFixed(2) + "%";
  $(".progress .boss").classList.toggle("on", d >= total);
  $("#depthText").innerHTML = d ? `Room <em>${d}</em> of ${total}` : "";
}

const RUN_TEXT = { idle: ["Idle", "Ready to farm"], running: ["Farming", "Farming dungeons"], paused: ["Paused", "Paused"], stopping: ["Stopping", "Finishing up"], stopped: ["Stopped", "Stopped"] };
function setRun(state) {
  run = state;
  document.body.dataset.run = state;
  $("#pillText").textContent = RUN_TEXT[state][0];
  $("#heroTitle").textContent = state === "running" && isIC() ? "Climbing Infinity Castle" : state === "running" && isFool() ? "Hunting in Fool's Hunt" : state === "running" && isInf() ? "Infinite on " + (S.cfg.infMap || "Shibuya District") : state === "running" && isPortal() ? "Portals: " + (S.cfg.portalName || "Shibuya Portal") : state === "running" && isLegend() ? "Legend: " + (S.cfg.legendWorld || "Magic Hills (Elf Invasion)") + " stage " + (+S.cfg.legendStage || 1) : RUN_TEXT[state][1];
  $(".controls .btn.go").lastChild.textContent = state === "running" ? "Farming…" : state === "paused" ? "Paused" : "Start farming";
  $(".controls [data-cmd=pause]").lastChild.textContent = state === "paused" ? "Resume" : "Pause";
}

function logLine(time, msg) {
  const el = $("#log"), atEnd = el.scrollHeight - el.scrollTop - el.clientHeight < 30;
  const d = document.createElement("div");
  const t = msg.toLowerCase();
  // problems first: "Multi Roblox only works when..." was green for its "works"
  d.className = /defeat|couldn't|wouldn't|can't|didn't|doesn't|won't|failed|lost|error|disconnect|stuck|only works|send logs|not seen|no .+ seen|not found/.test(t) ? "bad"
    : /curse|shrine|skipping|denied|no preferred|paused|screenshot/.test(t) ? "warn"
    : /victory|cleared|opened|saved|works|snapped/.test(t) ? "good" : "";
  d.innerHTML = `<span>${esc(time)}</span><span title="${esc(msg)}">${esc(msg)}</span>`;
  el.appendChild(d);
  while (el.children.length > 300) el.firstChild.remove();
  if (atEnd) el.scrollTop = el.scrollHeight;
}

function toast(msg, kind = "") {
  const t = document.createElement("div");
  t.className = "toast " + kind; t.textContent = msg;
  $("#toasts").appendChild(t);
  setTimeout(() => { t.classList.add("out"); setTimeout(() => t.remove(), 350); }, 2600);
}

// ---------------------------------------------------------------- sharing
function renderAll() {
  spotMap = S.maps.includes(S.cfg.lastSpotMap) ? S.cfg.lastSpotMap : S.maps[0];
  // each part on its own: one that fails (a new feature meeting settings it didn't expect) can't take
  // the rest of the page down with it (an empty team list once left no Mode buttons and no slots)
  for (const f of [bindToggles, renderTeams, renderUnits, renderBuild, initBuilder, renderSpotsPage, renderDungeon, renderSettings, renderLook, applyLook]) {
    try { f(); } catch (e) { console.error(e); send("jsError", { msg: (f.name || "?") + ": " + (e && e.message || e) }); }
  }
}

// "AA build: P1x2u2 P6x1umax U5u2"  =  place slot 1 x2 upgrade each 2 times, place slot 6 x1 to max, upgrade slot 5 twice
function buildCode(list) {
  const up = (n) => (n < 0 ? "max" : n);
  return "AA build: " + list.map((st) => st.kind === "buff" ? `B${st.slot}s${st.secs}` + (+st.pairs ? "p" : "") : st.kind === "erwin" ? `E${st.slot}` + (st.up ? "u" + (st.up < 0 ? "max" : st.up) : "") : st.kind === "ability"
    ? `A${st.slot}w${st.wave}` + (+st.units ? "n" + st.units : "") + (+st.every < 0 ? "a" : +st.every ? "e" + st.every : "")
    : st.kind === "place"
    ? `P${st.slot}x${st.count}` + (st.up ? "u" + up(st.up) : "")
    : `U${st.slot}` + (+st.units ? "n" + st.units : "") + `u${up(st.up)}`).join(" ");
}
function parseBuildCode(text) {
  const out = [];
  const mv = /^([PU])([1-6])(?:x(\d{1,2}))?(?:n(\d{1,2}))?(?:u(max|\d{1,2}))?$/i, ab = /^A([1-6])w(\d{1,3})(?:n(\d{1,2}))?(?:e(\d{1,2})|(a))?$/i;
  for (const tok of String(text).split(/[\s,]+/)) {
    let m;
    if ((m = /^E([1-6])(?:u(max|\d{1,2}))?$/i.exec(tok))) { out.push({ kind: "erwin", slot: +m[1], count: 4, up: m[2] ? (m[2].toLowerCase() === "max" ? -1 : Math.min(10, +m[2])) : 0, secs: 30 }); continue; }
    if ((m = /^B([1-6])s(\d{2,3})(p?)$/i.exec(tok))) { out.push({ kind: "buff", slot: +m[1], count: 1, up: 0, secs: Math.max(10, Math.min(120, +m[2])), pairs: m[3] ? 1 : 0 }); continue; }
    if ((m = ab.exec(tok))) { out.push({ kind: "ability", slot: +m[1], count: 1, up: 0, wave: Math.max(1, +m[2]), units: Math.min(20, +m[3] || 0), every: m[5] ? -1 : Math.min(50, +m[4] || 0) }); continue; }
    if (!(m = mv.exec(tok))) continue;
    const kind = m[1].toUpperCase() === "P" ? "place" : "upgrade";
    const up = m[5] ? (m[5].toLowerCase() === "max" ? -1 : Math.min(10, +m[5])) : 0;
    if (kind === "upgrade" && !up) continue;
    out.push({ kind, slot: +m[2], count: kind === "place" ? Math.min(S.maxCount || 6, +m[3] || 1) : 1, up, units: kind === "upgrade" ? Math.min(20, +m[4] || 0) : 0 });
  }
  return out.slice(0, 100);
}

function modal(title, bodyHtml, okText, onOk, cancelText = "Cancel", onCancel = null) {
  $("#modal")?.remove();
  const m = document.createElement("div");
  m.id = "modal";
  m.innerHTML = `<div class="pane dialog" role="dialog" aria-label="${esc(title)}"><h3>${esc(title)}</h3>${bodyHtml}
    <div class="row end"><button class="btn" data-x="cancel">${esc(cancelText)}</button><button class="btn acc" data-x="ok">${esc(okText)}</button></div></div>`;
  document.body.appendChild(m);
  const close = () => { m.remove(); document.removeEventListener("keydown", key); };
  const key = (e) => { if (e.key === "Escape") close(); };
  document.addEventListener("keydown", key);
  m.addEventListener("click", (e) => {
    const t = e.target.closest(".toggle");
    if (t) { e.preventDefault(); $(".switch", t).classList.toggle("on"); return; }
    const b = e.target.closest("[data-x]");
    if (b && b.dataset.x === "cancel") { close(); if (onCancel) onCancel(); }
    else if (e.target === m) close();
    else if (b && b.dataset.x === "ok" && onOk(m) !== false) close();
  });
  $('[data-x="ok"]', m).focus();
}

$("#bCopy").onclick = () => {
  if (!S || !S.cfg.build.length) return toast("Add some steps first", "bad");
  send("copyText", { text: buildCode(S.cfg.build) });
  toast("Build code copied. Paste it to a friend", "good");
};
$("#bPaste").onclick = () => send("pasteBuild");

// ---------------------------------------------------------------- Classic
// Classic uses this same page. Premium's parts stay visible but locked: a gold Premium tag, greyed
// out, and a click only says where to get it (the Classic macro doesn't take those settings anyway)
const isClassic = () => !!S && S.edition === "classic";
function lockPremium() {
  const on = isClassic();
  document.body.classList.toggle("classic", on);
  if (!on) return;
  const tag = () => `<span class="prem-tag">${icon("crown")}Premium</span>`;
  $$("[data-premium]").forEach((el) => {
    $$("input, select", el).forEach((x) => { x.tabIndex = -1; x.readOnly = true; });
    if (!el.dataset.tip) el.dataset.tip = el.dataset.premium + " is in Premium";
    if (el.tagName === "BUTTON" || el.querySelector(".prem-tag")) return;
    const sw = el.matches(".toggle") && $(":scope > .switch", el), label = $(":scope > .lbl", el);
    if (sw) sw.insertAdjacentHTML("beforebegin", tag());            // a switch: the tag sits just left of it
    else if (label) label.insertAdjacentHTML("afterend", tag());    // a setting row: after its name
    else if (el.matches(".pane")) el.insertAdjacentHTML("beforeend", tag().replace("prem-tag", "prem-tag corner"));
    else el.insertAdjacentHTML("afterbegin", tag());
  });
}
// caught before anything else on the page sees it, so a locked switch, list or box never changes
for (const type of ["pointerdown", "mousedown", "click", "keydown"]) document.addEventListener(type, (e) => {
  if (!isClassic()) return;
  const p = e.target.closest && e.target.closest("[data-premium]");
  if (!p) return;
  e.preventDefault(); e.stopPropagation();
  if (type === "click") toast(`${p.dataset.premium} is a Premium feature. Premium is in the Chris Macros Discord`);
}, true);

// ---------------------------------------------------------------- called by AHK
// one shared hover tip for anything with data-tip (sits on <body> so panes can't clip it)
const HOVER_TIP = document.createElement("div");
HOVER_TIP.id = "hoverTip";
document.body.appendChild(HOVER_TIP);
document.addEventListener("mouseover", (e) => {
  const t = e.target.closest("[data-tip]");
  if (!t || !t.dataset.tip || document.body.classList.contains("dragging")) { HOVER_TIP.classList.remove("show"); return; }
  HOVER_TIP.textContent = t.dataset.tip;
  HOVER_TIP.classList.add("show");
  const r = t.getBoundingClientRect(), w = HOVER_TIP.offsetWidth, h = HOVER_TIP.offsetHeight;
  let y = r.top - h - 8;
  if (y < 6) y = r.bottom + 8;
  const x = Math.max(6, Math.min(document.documentElement.clientWidth - w - 6, r.left + r.width / 2 - w / 2));
  HOVER_TIP.style.left = x + "px"; HOVER_TIP.style.top = y + "px";
});
document.addEventListener("mousedown", () => HOVER_TIP.classList.remove("show"));

// Drag an alt's live view onto the big frame (the game area) to swap it with the main. The frame is
// Roblox showing through a hole in the page, so only its glowing edge lights up; the page keeps the
// pointer while the button is held, so letting go over the game still lands here.
const GAME = { l: 3, t: 33, r: 800, b: 630 };
function duoDrag(e) {
  const box = e.target.closest(".duo-box.live");
  if (!box || e.button !== 0) return;
  const i = +box.dataset.i, x0 = e.clientX, y0 = e.clientY;
  const over = (ev) => ev.clientX >= GAME.l && ev.clientX < GAME.r && ev.clientY >= GAME.t && ev.clientY < GAME.b;
  let moving = false;
  try { box.setPointerCapture(e.pointerId); } catch {}
  box.onpointermove = (ev) => {
    if (!moving && Math.hypot(ev.clientX - x0, ev.clientY - y0) > 8) {
      moving = true;
      box.classList.add("dragging");
      document.body.classList.add("duo-dragging");
    }
    if (moving) document.body.classList.toggle("duo-drop", over(ev));
  };
  box.onpointerup = box.onpointercancel = (ev) => {
    box.onpointermove = box.onpointerup = box.onpointercancel = null;
    box.classList.remove("dragging");
    document.body.classList.remove("duo-dragging", "duo-drop");
    if (moving && ev.type === "pointerup" && over(ev)) send("duoSwap", { i });
  };
}

window.ui = {
  init(state) {
    S = state;
    $("#ver").textContent = "v" + S.version;
    renderAll();
    lockPremium();
    buildTrail(); setDepth(0);
    (S.logs || []).forEach((l) => logLine(l[0], l[1]));
    let page = "dash"; try { page = localStorage.getItem("page") || "dash"; } catch (e) {}
    showPage(PAGES.some((p) => p[0] === page) || page === "look" ? page : "dash");
    ui.roblox(S.hasRoblox);
    document.body.classList.toggle("fool-units", (S.maxCount || 6) > 6);
    ui.duo(S.duo, S.duoOpen);      // the alt strip, when the window was already tall before the page loaded
    if (S.stats) ui.stats(S.stats);
    ui.loot(S.loot);
    setRun(S.run || "idle");
  },
  log(time, msg) { logLine(time, msg); },
  step(text) { $("#heroStep").innerHTML = text ? "<b>" + esc(text.charAt(0).toUpperCase() + text.slice(1)) + "</b>" : ""; },
  status(state) { setRun(state); },
  stats(o) {
    $("#sRuns").textContent = o.runs;
    $("#sRate").textContent = o.wins + o.losses ? Math.round(o.wins / (o.wins + o.losses) * 100) + "%" : "–";
    $("#sRooms").textContent = o.rooms;
    $("#sChests").textContent = o.chests;
    $("#sClears").textContent = o.inf ? (+o.infBest || "–") : o.ic ? o.floors : o.dungeons;
    $("#sClears").nextElementSibling.textContent = o.inf ? "Best wave" : o.ic ? "Floors" : "Dungeons";
    $("#sHour").textContent = o.perHour;
    $("#heroTime").textContent = o.elapsed ? `${o.wins} won, ${o.losses} lost. Running for ${o.elapsed}` : "";
  },
  // chest rewards since Start: [[name, count], ...], most first
  loot(list) {
    const el = $("#loot");
    if (!el) return;
    if (!el.onwheel) el.onwheel = (e) => { if (!e.deltaX) { el.scrollLeft += e.deltaY; e.preventDefault(); } };   // the wheel scrolls the row
    el.innerHTML = list && list.length
      ? list.map(([n, c]) => `<span class="chip-l">${esc(n)}<b>×${Number(c).toLocaleString()}</b></span>`).join("")
      : '<span class="loot-none">Nothing yet. What your chests give shows up here</span>';
  },
  map(name, depth, tot, floor, cleared, label, diff) {
    if (+tot && +tot !== total) { total = +tot; buildTrail(); }
    const known = name && name !== "Unknown";
    $("#mapName").textContent = known ? name : "Unknown map";
    $("#mapNote").textContent = known ? "" : "Reading the map name…";
    // Infinity Castle: the floor instead of the dungeon's room trail
    const ic = (floor !== undefined && floor !== null && floor !== "") || !!label;
    $(".progress").style.display = ic ? "none" : "";
    $(".trail-head").style.marginBottom = ic ? "0" : "";
    if (label) $("#depthText").innerHTML = label;                    // Infinite: "Wave 87 · best 120" (built by the macro)
    else if (ic) $("#depthText").innerHTML = (diff ? `<span class="diff ${diff === "Hard" ? "hard" : ""}">${esc(diff)}</span>` : "")
      + `Floor <em>${+floor > 0 ? +floor : "–"}</em>${+cleared ? ` · ${+cleared} cleared` : ""}`;
    else setDepth(depth);
  },
  toast(msg, kind) { toast(msg, kind); },
  roblox(on) { document.body.classList.toggle("has-roblox", !!on); },
  // n alt boxes (Accounts - 1), the first `open` of them have their Roblox live on top
  // the mode switched in or out of Fool's Hunt: its own units and build order (up to `max` of a unit)
  units(slots, build, max) {
    S.cfg.slots = slots; S.cfg.build = build; S.maxCount = +max || 6;
    document.body.classList.toggle("fool-units", S.maxCount > 6);
    builderState();
    renderUnits(); renderBuild();
  },
  teams(info) { S.teams = info; renderTeams(); renderBuild(); },
  duo(n, open) {
    n = +n || 0; open = +open || 0;
    document.documentElement.classList.toggle("duo", n > 0);
    if (!n) return;
    const box = $("#duoViews");
    box.classList.toggle("many", n > 1);
    box.classList.toggle("n4", n === 4); box.classList.toggle("n5", n >= 5);   // 4-5 alts: smaller, still one row
    // a live view can be dragged onto the big frame to make that alt the main (with 2-3 alts each
    // also gets a button under it; the live picture covers the box itself, so nothing shows inside)
    box.innerHTML = Array.from({ length: n }, (_, i) => i < open
      ? `<div class="duo-cell"><div class="duo-box live" data-i="${i + 1}"><span>${n > 1 ? "Alt " + (i + 1) : "Your alt's Roblox shows here"}</span></div>${
          n > 1 ? `<button class="btn sm" data-swap="${i + 1}" title="Make alt ${i + 1} the main">${icon("arrow-up-down")}${n > 3 ? "Make main" : `Make alt ${i + 1} the main`}</button>` : ""}</div>`
      : `<div class="duo-cell"><div class="duo-box empty"><div><h4>Open ${n > 1 ? "alt " + (i + 1) + "'s" : "your alt's"} Roblox</h4>
           <p>Switch on <b>Multi Roblox</b> (Fool's Hunt), open another Roblox, log in with the alt and join your private server. It shows up here by itself.</p></div></div></div>`).join("");
    box.onclick = (e) => { const b = e.target.closest("[data-swap]"); if (b) send("duoSwap", { i: +b.dataset.swap }); };
    box.onpointerdown = duoDrag;
    $("#duoTitle").textContent = n > 1 ? `Your ${n} alts` : "Your alt";
    $("#duoInfo [data-cmd=duoSwap]").hidden = n > 1;     // 2-5 alts: each view has its own button
    $("#duoAltLine").innerHTML = n > 1 ? "<b>Alts</b> are the live views on the left." : "<b>Alt</b> is the live view on the left.";
  },
  // Multi Roblox: on or off, and how many Roblox windows are open
  multi(on, count) {
    $("#multiInfo").textContent = +on
      ? `On · ${+count || 0} Roblox open. Open your alts now (same private server)`
      : "Your main and alts open at the same time. Switch on before opening Roblox";
  },
  spots(map, list, walkKind, walkText) {
    if (map !== spotMap) return;
    const el = $("#spotList");
    el.innerHTML = list.length ? list.map((p, i) => `
      <div class="item drag" data-i="${i}"><span class="grip">${icon("grip-vertical")}</span><span class="num">${i + 1}</span><span class="txt">x ${p[0]}, y ${p[1]}</span>
        <span class="acts"><button class="del" data-a="del" aria-label="Remove">${icon("x")}</button></span>
      </div>`).join("")
      : `<div class="empty">No spots for ${esc(map)}. The placement pattern does the work.</div>`;
    el.onclick = (e) => {
      const b = e.target.closest("button[data-a]"); if (!b) return;
      send("spotEdit", { map: spotMap, i: +b.closest(".item").dataset.i + 1, a: b.dataset.a });
    };
    sortable(el, (from, to) => send("spotMove", { map: spotMap, from: from + 1, to: to + 1 }));
    const w = $("#walkInfo");
    w.className = "walk " + walkKind;
    $("span", w).textContent = walkText;
  },
  // settings were imported: draw every page again (the log and dashboard stay as they are)
  refresh(state) {
    S = state;
    renderAll();
    lockPremium();
    if ($(".page.on")?.id === "p-spots") send("spots", { map: spotMap });
  },
  importAsk(from, parts) {
    const rows = parts.map((p) => `<label class="toggle" data-id="${p.id}"><span>${esc(p.label)}<small>${esc(p.detail)}</small></span><i class="switch ${p.on ? "on" : ""}"></i></label>`).join("");
    modal("Import settings", `<p class="sub">From ${esc(from)}. Your current settings are replaced for what you pick.</p><div class="list scroll" style="max-height:400px">${rows}</div>`, "Import", (m) => {
      const picked = $$(".toggle", m).filter((t) => $(".switch", t).classList.contains("on")).map((t) => t.dataset.id);
      if (!picked.length) { toast("Pick at least one thing to import", "bad"); return false; }
      send("importDo", { parts: picked });
    });
  },
  pasteBuild(text) {
    const steps = /aa build/i.test(text || "") ? parseBuildCode(text) : [];
    // no code on the clipboard (or the macro couldn't read it on this PC): a box to paste it into
    if (!steps.length) return modal("Paste a build code", `<p class="sub">Paste the code here with Ctrl+V. It starts with "AA build:"</p>
      <textarea id="codeIn" spellcheck="false" placeholder="AA build: P1x2u2 P6x1umax"></textarea>`, "Next", (m) => {
        const t = $("#codeIn", m).value;
        if (!parseBuildCode(t).length) { toast('That isn\'t a build code. It starts with "AA build:"', "bad"); return false; }
        setTimeout(() => ui.pasteBuild(/aa build/i.test(t) ? t : "AA build: " + t), 0);
      }), setTimeout(() => $("#codeIn")?.focus(), 30);
    const list = steps.map((st, i) => `<div class="item sm"><span class="num">${i + 1}</span><span class="txt">${esc(stepText(st))}</span></div>`).join("");
    const mine = S.cfg.build.length;
    modal("Use this build order?", `<p class="sub">${mine ? `It replaces your ${mine} step${mine === 1 ? "" : "s"}.` : "Your build order is empty."}</p><div class="list scroll" style="max-height:250px">${list}</div>`, "Use it", () => {
      S.cfg.build.length = 0; S.cfg.build.push(...steps);
      send("build", { steps: S.cfg.build }); renderBuild(); buildOn();
      toast(`Build order set: ${steps.length} step${steps.length === 1 ? "" : "s"}`, "good");
    });
  },
  bg(url, name) { S.bgUrl = url; S.bgName = name; applyLook(); },
  set(key, value) { S.cfg[key] = value; },
};

fillIcons();
buildRail();
send("ready");

// preview outside the macro (opening index.html in a browser)
if (!host) setTimeout(() => window.ui.init(window.DEMO || {
  version: "3.0", maps: ["Ant Kingdom", "Snowy Town", "Unknown"], patterns: ["Spiral", "Circle", "Grid", "Random"],
  roomKeys: ["Rare_Chest", "Chest", "Hoard", "Shop", "Shrine", "Boss", "None"], roomNames: ["Rare chest", "Chest", "Hoard", "Shop", "Shrine", "Boss", "(nothing)"],
  curses: ["Flying", "Wind", "Money", "Health", "Exploding", "Shielding", "Regen"], speeds: ["Super fast (1s)", "Fast (1.5s)"],
  upNames: ["no upgrades", "upgrade each 1 time", "upgrade each to max"], upValues: [0, 1, -1], hasRoblox: false,
  cfg: { slots: Array.from({ length: 6 }, (_, i) => ({ on: i < 5 ? 1 : 0, count: 2, prio: i + 1, up: 1, limit: 0 })), pattern: "Spiral", retries: 3,
    build: [], route: ["Rare_Chest", "Chest", "Shop", "Hoard", "Shrine", "Boss"], curseRank: ["Flying", "Money", "Health", "Shielding", "Regen", "Wind", "Exploding"],
    foolMatch: 0, foolOwnTeam: 0, foolFreeze: 80, foolAccounts: 2, foolCards: ["shield", "regen", "health", "speed", "yen", "range", "cooldown", "attack", "explosive", "resistant", "spellproof", "plated", "boss"], skipWorst: 5, denyShrine: { Burst: 0, Armor: 0, Chaos: 1, Vamparism: 0, Frenzy: 0, Eruption: 0 }, placeSpeed: 1, accent: "Crimson", bgOpacity: 70, bgBlur: 0, glass: 60, bgAnimate: 1 },
}), 50);
