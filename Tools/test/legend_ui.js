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
    await p.screenshot({ path: `${out}/legend_${tag}.png`, clip: { x: 0, y: 0, width: 1423, height: 300 } });
    check(tag + ": no page errors", !p.errors.length, p.errors.join("; "));
    await p.close();
  }
  await b.close();
  console.log(fails ? "FAILED " + fails : "ALL PASSED");
  process.exit(fails ? 1 : 0);
})();
