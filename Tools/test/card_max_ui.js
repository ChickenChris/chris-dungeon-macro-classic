// Summer Hunt cards: a max per round on each enemy card (RNG / The Grinch 23 Nov: "if 400% never take hp again
// for that run, add hard limits for each card"; Chris: "Max % per run"). A small box on each enemy card in the
// list (Enemy Health max 400%), none on your own buffs; typing in it saves foolMax; empty is no max.
// node card_max_ui.js <macro folder> <shot dir>   (headless Chromium, the page with a demo state)
const { chromium } = require("playwright"); const fs = require("fs");
const [base, out] = process.argv.slice(2);
const demo = JSON.parse(fs.readFileSync(base + "/Tools/test/demo_state.json", "utf8").replace(/^﻿/, ""));
let fails = 0;
const check = (name, ok, detail = "") => { console.log((ok ? "PASS " : "FAIL ") + name + (ok ? "" : ": " + detail)); if (!ok) fails++; };
const ENEMY = ["shield", "regen", "health", "speed", "explosive", "resistant", "spellproof", "plated", "gale", "updraft", "boss"];
const BUFF = ["yen", "range", "cooldown", "attack", "grounded", "slow"];

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1423, height: 900 } });
  p.errors = []; p.on("pageerror", (e) => p.errors.push(e.message));
  await p.addInitScript(() => {
    window.__sent = [];
    window.chrome = { webview: { postMessage: (m) => window.__sent.push(JSON.parse(m)), addEventListener() {} } };
  });
  await p.goto("file://" + base + "/UI/index.html"); await p.waitForTimeout(200);
  const st = JSON.parse(JSON.stringify(demo));
  st.cfg.foolCards = ["shield", "regen", "health", "speed", "yen", "range", "cooldown", "attack", "grounded", "slow", "explosive", "resistant", "spellproof", "plated", "gale", "updraft", "boss"];
  st.cfg.foolMax = { health: 400 };
  await p.evaluate((s) => { try { localStorage.setItem("page", "dungeon"); } catch (e) {} window.ui.init(s); }, st);
  await p.waitForTimeout(400);
  const rows = await p.evaluate(() => [...document.querySelectorAll("#foolCards .item")].map((r) => {
    const i = r.querySelector("input.cmax-in"), rb = r.getBoundingClientRect(), ib = i && i.getBoundingClientRect();
    return { name: r.querySelector(".txt").childNodes[0].textContent.trim(), key: r.dataset.key, box: !!i, value: i ? i.value : null,
      unit: i ? (r.querySelector(".cmax").textContent || "").trim() : "", inside: !!ib && ib.right <= rb.right + 1 && ib.width > 20 && ib.height > 10 };
  }));
  check("17 cards in the list", rows.length === 17, rows.length);
  const by = Object.fromEntries(rows.map((r) => [r.key, r]));
  check("a max box on every enemy card", ENEMY.every((k) => by[k] && by[k].box), ENEMY.filter((k) => !(by[k] && by[k].box)).join(","));
  check("  none on your own buffs (yen, range, cooldown...)", BUFF.every((k) => by[k] && !by[k].box), BUFF.filter((k) => by[k] && by[k].box).join(","));
  check("  inside its row, big enough to type in", ENEMY.every((k) => by[k] && by[k].inside), JSON.stringify(rows.filter((r) => r.box && !r.inside)));
  check("Enemy Health shows its saved max: 400 %", by.health && by.health.value === "400" && /%/.test(by.health.unit), JSON.stringify(by.health));
  check("  Enemy Shield is a number (+3 shield), no %", by.shield && by.shield.value === "" && !/%/.test(by.shield.unit), JSON.stringify(by.shield));
  const type = async (k, v) => { try { await p.fill(`#foolCards .item[data-key="${k}"] input.cmax-in`, v, { timeout: 2000 });
    await p.press(`#foolCards .item[data-key="${k}"] input.cmax-in`, "Tab"); } catch (e) {} await p.waitForTimeout(150); };
  await type("speed", "100");
  let sent = await p.evaluate(() => window.__sent.filter((m) => m.cmd === "foolMax"));
  check("typing 100 on Enemy Speed saves foolMax speed 100", sent.some((m) => m.key === "speed" && m.value === 100), JSON.stringify(sent));
  await type("health", "");
  sent = await p.evaluate(() => window.__sent.filter((m) => m.cmd === "foolMax"));
  check("emptied: no max (0)", sent.some((m) => m.key === "health" && m.value === 0), JSON.stringify(sent));
  const sub = await p.evaluate(() => document.querySelector("#foolCards").closest(".pane").querySelector("p.sub").textContent);
  check("the pane says what the max does", /max/i.test(sub) && /round/i.test(sub), sub);
  check("no page errors", p.errors.length === 0, p.errors.join(" | "));
  if (out) await p.locator("#foolCards").screenshot({ path: out + "/card_max.png" });
  await b.close();
  console.log(fails ? "FAILED " + fails : "ALL PASSED");
  process.exit(fails ? 1 : 0);
})();
