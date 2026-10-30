// The Mode row's Legend button and its World / Stage dropdowns, in Premium and Classic.
// node legend_ui.js <macro folder> <shot dir>   (headless Chromium, the page with a demo state)
const { chromium } = require("playwright"); const fs = require("fs");
const [base, out] = process.argv.slice(2);
const demo = JSON.parse(fs.readFileSync(base + "/Tools/test/demo_state.json", "utf8").replace(/^﻿/, ""));
let fails = 0;
const check = (name, ok, detail = "") => { console.log((ok ? "PASS " : "FAIL ") + name + (ok ? "" : ": " + detail)); if (!ok) fails++; };
const WORLDS = ["Magic Hills (Elf Invasion)", "Spirit Invasion", "Space Center", "Fabled Kingdom (Generals)",
  "Ruined City (Midnight)", "Virtual Dungeon (Bosses)", "Dungeon Throne", "Rain Village"];

async function open(b, edition) {
  const p = await b.newPage({ viewport: { width: 1423, height: 640 } });
  p.errors = []; p.on("pageerror", (e) => p.errors.push(e.message));
  await p.addInitScript(() => {
    window.__sent = [];
    window.chrome = { webview: { postMessage: (m) => window.__sent.push(JSON.parse(m)), addEventListener() {} } };
  });
  await p.goto("file://" + base + "/UI/index.html"); await p.waitForTimeout(200);
  const st = JSON.parse(JSON.stringify(demo));
  st.cfg.mode = "Dungeon"; st.legendWorlds = WORLDS; if (edition) st.edition = edition;
  await p.evaluate((s) => { try { localStorage.setItem("page", "dash"); } catch (e) {} window.ui.init(s); }, st);
  await p.waitForTimeout(200);
  return p;
}
const legendBtn = (p) => p.evaluateHandle(() => [...document.querySelectorAll("#segModeHome button")].find((b) => b.textContent.trim() === "Legend"));

(async () => {
  const b = await chromium.launch();
  for (const edition of ["", "classic"]) {
    const tag = edition || "premium";
    const p = await open(b, edition);
    const btn = await legendBtn(p);
    check(tag + ": a Legend button in the mode row", !!(await btn.evaluate((x) => !!x)));
    check(tag + ": Legend isn't locked", await btn.evaluate((x) => x && !x.dataset.premium));
    if (edition) check("classic: Infinite is still locked", await p.evaluate(() =>
      [...document.querySelectorAll("#segModeHome button")].find((x) => x.textContent.trim() === "Infinite").dataset.premium === "Infinite"));
    check(tag + ": the Legend panel is closed in Dungeon mode", !(await p.evaluate(() => document.querySelector("#legendSub")?.classList.contains("open"))));
    await btn.evaluate((x) => x && x.click()); await p.waitForTimeout(250);
    const sent = await p.evaluate(() => window.__sent);
    check(tag + ": picking it sets the mode", sent.some((m) => m.cmd === "set" && m.key === "mode" && m.value === "Legend"));
    check(tag + ": its panel opens", await p.evaluate(() => !!document.querySelector("#legendSub")?.classList.contains("open")));
    const worlds = await p.evaluate(() => [...(document.querySelector("#legendWorld")?.options || [])].map((o) => o.textContent));
    check(tag + ": the 8 worlds in the game's order", JSON.stringify(worlds) === JSON.stringify(WORLDS), JSON.stringify(worlds));
    const stages = await p.evaluate(() => [...(document.querySelector("#legendStage")?.options || [])].map((o) => o.textContent));
    check(tag + ": stages 1 to 6", stages.length === 6 && stages[0] === "Stage 1" && stages[5] === "Stage 6", JSON.stringify(stages));
    await p.evaluate(() => { const s = document.querySelector("#legendWorld"); if (s) { s.value = "4"; s.dispatchEvent(new Event("change")); } });
    await p.evaluate(() => { const s = document.querySelector("#legendStage"); if (s) { s.value = "2"; s.dispatchEvent(new Event("change")); } });
    const sent2 = await p.evaluate(() => window.__sent);
    check(tag + ": the world is saved", sent2.some((m) => m.cmd === "set" && m.key === "legendWorld" && m.value === "Ruined City (Midnight)"));
    check(tag + ": the stage is saved as a number", sent2.some((m) => m.cmd === "set" && m.key === "legendStage" && m.value === 3));
    // Auto challenge: one switch on the Mode panel, free in Classic, greyed in Fool's Hunt
    const ac = '.modebar .toggle[data-key="autoChallenge"]';
    check(tag + ": an Auto challenge switch on the Mode panel", await p.evaluate((q) => !!document.querySelector(q), ac));
    check(tag + ": Auto challenge isn't locked", await p.evaluate((q) => { const t = document.querySelector(q); return !!t && !t.closest("[data-premium]"); }, ac));
    await p.evaluate((q) => document.querySelector(q)?.click(), ac); await p.waitForTimeout(100);
    check(tag + ": switching it on is saved", (await p.evaluate(() => window.__sent)).some((m) => m.cmd === "set" && m.key === "autoChallenge" && m.value === 1));
    check(tag + ": not greyed outside Fool's Hunt", !(await p.evaluate((q) => document.querySelector(q)?.classList.contains("dim"), ac)));
    if (!edition) {
      await p.evaluate(() => [...document.querySelectorAll("#segModeHome button")].find((x) => x.textContent.trim() === "Fool's Hunt").click());
      await p.waitForTimeout(150);
      check("premium: greyed in Fool's Hunt", await p.evaluate((q) => !!document.querySelector(q)?.classList.contains("dim"), ac));
      await legendBtn(p).then((h) => h.evaluate((x) => x.click())); await p.waitForTimeout(150);
    }
    // Infinity Castle: free in Classic too (Chris), with its Normal / Hard and Stop after
    const icb = await p.evaluateHandle(() => [...document.querySelectorAll("#segModeHome button")].find((b) => b.textContent.trim() === "Infinity Castle"));
    check(tag + ": Infinity Castle isn't locked", await icb.evaluate((x) => !!x && !x.dataset.premium && !x.querySelector("svg")));
    await p.evaluate(() => { window.__sent = []; }); await icb.evaluate((x) => x.click()); await p.waitForTimeout(150);
    check(tag + ": picking Infinity Castle sets the mode and opens its panel", (await p.evaluate(() => window.__sent)).some((m) => m.cmd === "set" && m.key === "mode" && m.value === "Infinity Castle")
      && await p.evaluate(() => !!document.querySelector("#modeSub")?.classList.contains("open")));
    await p.evaluate(() => $$("#segIcDiff button")[1].click()); await p.waitForTimeout(50);
    check(tag + ": Hard is saved", (await p.evaluate(() => window.__sent)).some((m) => m.cmd === "set" && m.key === "icHard" && m.value === 1));
    if (edition) check("classic: Fool's Hunt is still locked", await p.evaluate(() => [...document.querySelectorAll("#segModeHome button")].find((b) => b.textContent.trim() === "Fool's Hunt")?.dataset.premium === "Fool's Hunt"));
    await legendBtn(p).then((h) => h.evaluate((x) => x.click())); await p.waitForTimeout(150);
    // Portal mode: Premium only (locked in Classic), a name box
    const portal = await p.evaluateHandle(() => [...document.querySelectorAll("#segModeHome button")].find((b) => b.textContent.trim() === "Portal"));
    check(tag + ": a Portal button in the mode row", await portal.evaluate((x) => !!x));
    if (edition) check("classic: Portal is locked", await portal.evaluate((x) => !!x && x.dataset.premium === "Portal"));
    else {
      await portal.evaluate((x) => x && x.click()); await p.waitForTimeout(200);
      check("premium: picking Portal sets the mode", (await p.evaluate(() => window.__sent)).some((m) => m.cmd === "set" && m.key === "mode" && m.value === "Portal"));
      check("premium: the Portal panel opens with a name box", await p.evaluate(() => !!document.querySelector("#portalSub")?.classList.contains("open") && !!document.querySelector("#portalName")));
      await p.evaluate(() => { const i = document.querySelector("#portalName"); if (i) { i.value = "  Namek Portal "; i.dispatchEvent(new Event("change")); } });
      check("premium: the name is saved, trimmed", (await p.evaluate(() => window.__sent)).some((m) => m.cmd === "set" && m.key === "portalName" && m.value === "Namek Portal"));
      // Multi Roblox: a switch on the Fool's Hunt panel
      await p.evaluate(() => [...document.querySelectorAll("#segModeHome button")].find((x) => x.textContent.trim() === "Fool's Hunt").click());
      await p.waitForTimeout(150);
      check("premium: a Multi Roblox switch on the Fool's Hunt panel", await p.evaluate(() => !!document.querySelector('#foolSub .toggle[data-key="multiRoblox"]')));
      await p.evaluate(() => document.querySelector('#foolSub .toggle[data-key="multiRoblox"]')?.click()); await p.waitForTimeout(100);
      check("premium: switching Multi Roblox on is sent", (await p.evaluate(() => window.__sent)).some((m) => m.cmd === "set" && m.key === "multiRoblox" && m.value === 1));
      await p.screenshot({ path: `${out}/fool_panel.png`, clip: { x: 803, y: 32, width: 620, height: 200 } });
      await legendBtn(p).then((h) => h.evaluate((x) => x.click())); await p.waitForTimeout(150);
    }
    await p.screenshot({ path: `${out}/legend_${tag}.png`, clip: { x: 0, y: 0, width: 1423, height: 300 } });
    // the Erwin buff step in the build order (Premium): slot + upgrades, in the share code, a step in the line
    await p.evaluate(() => { window.__sent = []; });
    const kinds = await p.evaluate(() => $$("#bKind button").map((b) => b.textContent.trim()));
    check(tag + ": the build order's step kinds: Place, Upgrade, Ability, Erwin buff, Wenda buff, Wait for yen", JSON.stringify(kinds) === JSON.stringify(["Place", "Upgrade", "Ability", "Erwin buff", "Wenda buff", "Wait for yen"]), JSON.stringify(kinds));
    await p.evaluate(() => $$("#bKind button")[3].click()); await p.waitForTimeout(100);
    if (edition) check("classic: Erwin buff steps are locked", await p.evaluate(() => $$("#bKind button")[3].classList.contains("on") === false));
    else {
      const eu = await p.evaluate(() => ({ count: getComputedStyle($("#bCount")).display, up: $("#bUp").selectedOptions[0].textContent }));
      check("premium: Erwin buff: the slot and the upgrades (to max picked), no count box", eu.count === "none" && /max/i.test(eu.up), JSON.stringify(eu));
      await p.evaluate(() => { $("#bSlot").value = "1"; $("#bAdd").click(); }); await p.waitForTimeout(100);
      const es = await p.evaluate(() => { const m = window.__sent.filter((m) => m.cmd === "build").pop(); return m && m.steps[m.steps.length - 1]; });
      check("premium: added as {kind: erwin, slot 2, 4 copies, to max}", !!es && es.kind === "erwin" && es.slot === 2 && es.count === 4 && es.up === -1, JSON.stringify(es));
      check("premium: the step reads 'Erwin buff: slot 2, 4 copies as in the video, upgrade each to max', golden with its sparkle", await p.evaluate(() => $$("#steps .item").some((it) => /^Erwin buff: slot 2, 4 copies as in the video, upgrade each to max/.test($(".txt", it).textContent) && it.classList.contains("abil") && !!$(".num svg", it))));
      check("premium: in the share code as E2umax, and read back", await p.evaluate(() => buildCode(S.cfg.build).includes("E2umax") && parseBuildCode("E2umax E3u2").some((x) => x.kind === "erwin" && x.slot === 2 && x.up === -1) && parseBuildCode("E3u2")[0].up === 2));
      await p.evaluate(() => { window.__sent = []; $$("#bKind button")[4].click(); $("#bSlot").value = "2"; $("#bAdd").click(); }); await p.waitForTimeout(100);
      const ws = await p.evaluate(() => { const m = window.__sent.filter((m) => m.cmd === "build").pop(); return m && m.steps[m.steps.length - 1]; });
      check("premium: Wenda buff added as {kind: wenda, slot 3, 4 copies, to max}", !!ws && ws.kind === "wenda" && ws.slot === 3 && ws.count === 4 && ws.up === -1, JSON.stringify(ws));
      check("premium: it reads 'Wenda buff: slot 3, ...', golden, 'places the 4 Wendas'", await p.evaluate(() => $$("#steps .item").some((it) => /^Wenda buff: slot 3, 4 copies as in the video/.test($(".txt", it).textContent) && /4 Wendas/.test($(".txt", it).textContent) && it.classList.contains("abil"))));
      check("premium: Wenda in the share code as W3umax, and read back", await p.evaluate(() => buildCode(S.cfg.build).includes("W3umax") && parseBuildCode("W3umax")[0].kind === "wenda" && parseBuildCode("W3umax")[0].slot === 3 && parseBuildCode("E2u2")[0].kind === "erwin" && parseBuildCode("E2u2")[0].up === 2));
      // Wait for yen (Chris): just an amount, a numbered step in the line, Y2500 in the share code
      await p.evaluate(() => { window.__sent = []; $$("#bKind button")[5].click(); }); await p.waitForTimeout(100);
      const yv = await p.evaluate(() => ({ yen: getComputedStyle($("#bYen")).display, slot: getComputedStyle($("#bSlot")).display, up: getComputedStyle($("#bUp")).display }));
      check("premium: Wait for yen: only the yen box", yv.yen !== "none" && yv.slot === "none" && yv.up === "none", JSON.stringify(yv));
      await p.evaluate(() => { $("#bYen").value = "2500"; $("#bAdd").click(); }); await p.waitForTimeout(100);
      const ys = await p.evaluate(() => { const m = window.__sent.filter((m) => m.cmd === "build").pop(); return m && m.steps[m.steps.length - 1]; });
      check("premium: added as {kind: yen, amount 2500}", !!ys && ys.kind === "yen" && ys.amount === 2500, JSON.stringify(ys));
      check("premium: it reads 'Wait until you have 2,500 yen', numbered in the line", await p.evaluate(() => $$("#steps .item").some((it) => /^Wait until you have 2,500 yen/.test($(".txt", it).textContent) && !it.classList.contains("abil") && /^\d+$/.test($(".num", it).textContent))));
      check("premium: in the share code as Y2500, and read back", await p.evaluate(() => buildCode(S.cfg.build).includes("Y2500") && parseBuildCode("Y2500 P1x2")[0].kind === "yen" && parseBuildCode("Y2500")[0].amount === 2500));
      await p.evaluate(() => $$("#bKind button")[1].click()); await p.waitForTimeout(50);
      check("premium: back on Upgrade the slot and upgrade boxes show again", await p.evaluate(() => getComputedStyle($("#bSlot")).display !== "none" && getComputedStyle($("#bYen")).display === "none"));
      // its own timings (Lunoc): 2nd after / 3rd after boxes, saved and in the share code
      check("premium: Erwin / Wenda show their 2nd after / 3rd after boxes (4 and 30)", await p.evaluate(() => { $$("#bKind button")[4].click(); return getComputedStyle($("#bGap")).display !== "none" && +$("#bGap").value === 4 && +$("#bSecs").value === 30; }));
      await p.evaluate(() => { window.__sent = []; $("#bSlot").value = "2"; $("#bGap").value = "6"; $("#bSecs").value = "25"; $("#bAdd").click(); }); await p.waitForTimeout(100);
      const wt = await p.evaluate(() => { const m = window.__sent.filter((m) => m.cmd === "build").pop(); return m && m.steps[m.steps.length - 1]; });
      check("premium: added with gap 6 and 25 s", !!wt && wt.kind === "wenda" && wt.gap === 6 && wt.secs === 25, JSON.stringify(wt));
      check("premium: it reads '..., 2nd after 6 s, 3rd after 25 s'", await p.evaluate(() => $$("#steps .item").some((it) => /2nd after 6 s, 3rd after 25 s/.test($(".txt", it).textContent))));
      check("premium: in the share code as W3umaxs25g6, read back; plain codes keep 4 and 30", await p.evaluate(() => buildCode(S.cfg.build).includes("W3umaxs25g6") && parseBuildCode("W3umaxs25g6")[0].gap === 6 && parseBuildCode("W3umaxs25g6")[0].secs === 25 && parseBuildCode("E2umax")[0].gap === 4 && parseBuildCode("E2umax")[0].secs === 30));
      check("premium: the boxes hide on Place", await p.evaluate(() => { $$("#bKind button")[0].click(); return getComputedStyle($("#bGap")).display === "none"; }));
      check("premium: an older Buff step still reads and shows", await p.evaluate(() => parseBuildCode("B5s30")[0].kind === "buff" && stepText({ kind: "buff", slot: 5, secs: 30 }) === "Buff rotation: slot 5, one copy every 30 s"));
      check("premium: the Until box still saves", await p.evaluate(() => { const s = document.querySelector('.slot[data-i="4"] select[data-p="limit"]'); s.value = "2"; s.dispatchEvent(new Event("change")); return window.__sent.some((m) => m.prop === "limit" && m.value === 2); }));
      await p.evaluate(() => $$("#bKind button")[0].click());
    }
    // "Use the build order" with no Place / Upgrade steps: the slots still play, and a note says so
    const notes = await p.evaluate(async () => {
      const shown = (sel) => getComputedStyle(document.querySelector(sel)).display !== "none";
      const keep = [S.cfg.useBuild, S.cfg.build];
      S.cfg.useBuild = 1; S.cfg.build = [{ kind: "buff", slot: 5, count: 1, up: 0, secs: 30, pairs: 1 }]; unitsLockState();
      const empty = [shown(".build-note.empty-note"), shown(".build-note:not(.empty-note)"), document.body.classList.contains("build-on")];
      S.cfg.build = [{ kind: "place", slot: 1, count: 2, up: 0, units: 0 }]; unitsLockState();
      const full = [shown(".build-note.empty-note"), shown(".build-note:not(.empty-note)"), document.body.classList.contains("build-on")];
      S.cfg.useBuild = keep[0]; S.cfg.build = keep[1]; unitsLockState();
      return JSON.stringify([empty, full]);
    });
    check(tag + ": build order on with no Place steps: the 'no steps' note; with steps: the usual note", notes === JSON.stringify([[true, false, false], [false, true, true]]), notes);
    const dim = await p.evaluate(async () => {
      const keep = [S.cfg.useBuild, S.cfg.build];
      S.cfg.useBuild = 1; S.cfg.build = []; unitsLockState();
      const a = getComputedStyle($("#slots")).pointerEvents === "none";
      document.querySelector(".empty-note .unlock-btn").click();
      const b = getComputedStyle($("#slots")).pointerEvents !== "none";
      document.querySelector(".empty-note .unlock-btn").click();
      S.cfg.useBuild = 0; unitsLockState();
      const c = getComputedStyle($("#slots")).pointerEvents !== "none";
      S.cfg.useBuild = keep[0]; S.cfg.build = keep[1]; unitsLockState();
      return [a, b, c].join();
    });
    check(tag + ": build order on and empty: the slots are greyed too, Edit anyway opens them, off: normal", dim === "true,true,true", dim);
    // Activity colours: a problem is red even when it has a "good" word in it ("only works when ...")
    const cls = (m) => p.evaluate((m) => { window.ui.log("09:00:00", m); const l = document.querySelector("#log").lastElementChild; return l ? l.className : "?"; }, m);
    for (const [m, want] of [["Multi Roblox only works when it's on before Roblox opens: close every Roblox window, then switch it on", "bad"],
        ["Portal: no Shibuya Portal seen in your items, looking once more", "bad"],
        ["Legend: couldn't find Legend Stage 1 (read: ...). Send Logs\\legend_stage_....bmp in Discord", "bad"],
        ["Saved a screenshot of it: Logs\\legend_stage_....bmp", "warn"],
        ["Victory on Snowy Town in 13m 04s", "good"], ["Dungeon cleared!", "good"], ["Opened 4 chests", "good"],
        ["Skipping Chest room (curse of Health)", "warn"], ["Placed slot 4  (1/3)", ""]])
      check(tag + `: '${m.slice(0, 40)}' is ${want || "plain"}`, (await cls(m)) === want, await cls(m));
    check(tag + ": no page errors", !p.errors.length, p.errors.join("; "));
    await p.close();
  }
  await b.close();
  console.log(fails ? "FAILED " + fails : "ALL PASSED");
  process.exit(fails ? 1 : 0);
})();
