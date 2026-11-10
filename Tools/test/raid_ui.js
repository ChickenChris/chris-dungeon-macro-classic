// The Mode row's Raid button and its World / Raid dropdowns, in Premium and Classic.
// node raid_ui.js <macro folder> <shot dir>   (headless Chromium, the page with a demo state)
const { chromium } = require("playwright"); const fs = require("fs");
const [base, out] = process.argv.slice(2);
const demo = JSON.parse(fs.readFileSync(base + "/Tools/test/demo_state.json", "utf8").replace(/^﻿/, ""));
let fails = 0;
const check = (name, ok, detail = "") => { console.log((ok ? "PASS " : "FAIL ") + name + (ok ? "" : ": " + detail)); if (!ok) fails++; };
const WORLDS = ["Ant Kingdom (Midnight)", "Sacred Planet", "Strange Town", "Ruined City (The Menace)", "Cursed Festival",
  "Future City (Tyrant)", "Storm Hideout", "Future City", "Nightmare Train", "Sand Village"];

async function open(b, edition, cfg = {}) {
  const p = await b.newPage({ viewport: { width: 1423, height: 640 } });
  p.errors = []; p.on("pageerror", (e) => p.errors.push(e.message));
  await p.addInitScript(() => {
    window.__sent = [];
    window.chrome = { webview: { postMessage: (m) => window.__sent.push(JSON.parse(m)), addEventListener() {} } };
  });
  await p.goto("file://" + base + "/UI/index.html"); await p.waitForTimeout(200);
  const st = JSON.parse(JSON.stringify(demo));
  st.cfg.mode = "Dungeon"; Object.assign(st.cfg, cfg); st.raidWorlds = WORLDS; if (edition) st.edition = edition;
  await p.evaluate((s) => { try { localStorage.setItem("page", "dash"); } catch (e) {} window.ui.init(s); }, st);
  await p.waitForTimeout(200);
  return p;
}
const raidBtn = (p) => p.evaluateHandle(() => [...document.querySelectorAll("#segModeHome button")].find((b) => b.textContent.trim() === "Raid"));

(async () => {
  const b = await chromium.launch();
  for (const edition of ["", "classic"]) {
    const tag = edition || "premium";
    const p = await open(b, edition);
    const btn = await raidBtn(p);
    check(tag + ": a Raid button in the mode row", !!(await btn.evaluate((x) => !!x)));
    check(tag + ": Raid isn't locked", await btn.evaluate((x) => x && !x.dataset.premium));
    check(tag + ": the raid panel is closed in Dungeon mode", !(await p.evaluate(() => document.querySelector("#raidSub")?.classList.contains("open"))));
    await btn.evaluate((x) => x && x.click()); await p.waitForTimeout(250);
    let sent = await p.evaluate(() => window.__sent);
    check(tag + ": picking it sets the mode", sent.some((m) => m.cmd === "set" && m.key === "mode" && m.value === "Raid"));
    check(tag + ": its panel opens", await p.evaluate(() => !!document.querySelector("#raidSub")?.classList.contains("open")));
    const worlds = await p.evaluate(() => [...(document.querySelector("#raidWorld")?.options || [])].map((o) => o.textContent));
    check(tag + ": every raid world in the list", JSON.stringify(worlds) === JSON.stringify(WORLDS), worlds.join(", "));
    check(tag + ": Sacred Planet picked at first", await p.evaluate(() => document.querySelector("#raidWorld")?.selectedOptions[0]?.textContent) === "Sacred Planet");
    const acts = await p.evaluate(() => [...(document.querySelector("#raidAct")?.options || [])].map((o) => o.textContent));
    check(tag + ": raids 1 to 5", acts.join(",") === "Raid 1,Raid 2,Raid 3,Raid 4,Raid 5", acts.join(","));
    await p.evaluate(() => { const s = document.querySelector("#raidWorld"); s.value = "4"; s.dispatchEvent(new Event("change")); });
    await p.evaluate(() => { const s = document.querySelector("#raidAct"); s.value = "2"; s.dispatchEvent(new Event("change")); });
    sent = await p.evaluate(() => window.__sent);
    check(tag + ": the world is saved", sent.some((m) => m.cmd === "set" && m.key === "raidWorld" && m.value === "Cursed Festival"));
    check(tag + ": the raid is saved as a number", sent.some((m) => m.cmd === "set" && m.key === "raidAct" && m.value === 3));
    const legendOpen = await p.evaluate(() => document.querySelector("#legendSub")?.classList.contains("open"));
    check(tag + ": the Legend panel stays closed", !legendOpen);
    // the mode row still fits with 7 buttons (nothing wraps or spills out of it)
    const fit = await p.evaluate(() => {
      const row = document.querySelector("#segModeHome"), r = row.getBoundingClientRect();
      const bs = [...row.querySelectorAll("button")].map((x) => x.getBoundingClientRect());
      return { n: bs.length, oneLine: bs.every((x) => Math.abs(x.top - bs[0].top) < 2), inside: bs.every((x) => x.left >= r.left - 1 && x.right <= r.right + 1),
        clipped: [...row.querySelectorAll("button")].some((x) => x.scrollWidth > x.clientWidth + 1) };
    });
    check(tag + ": the mode row holds its buttons on one line", fit.oneLine && fit.inside && !fit.clipped, JSON.stringify(fit));
    check(tag + ": no page errors", !p.errors.length, p.errors.join(" | "));
    await p.screenshot({ path: `${out}/raid_${tag}.png`, clip: { x: 0, y: 0, width: 1423, height: 300 } });
    await p.close();
  }
  // a saved raid world and raid come back picked
  const p = await open(b, "", { mode: "Raid", raidWorld: "Storm Hideout", raidAct: 4 });
  check("saved settings shown: Storm Hideout, raid 4", await p.evaluate(() => document.querySelector("#raidWorld").selectedOptions[0].textContent === "Storm Hideout"
    && document.querySelector("#raidAct").selectedOptions[0].textContent === "Raid 4"));
  await b.close();
  console.log(fails ? "FAILED " + fails : "ALL PASSED");
  process.exit(fails ? 1 : 0);
})();
