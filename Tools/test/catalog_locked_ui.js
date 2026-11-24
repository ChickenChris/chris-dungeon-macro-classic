// Preset catalog (Premium, Chris 24 Nov, design 2026-11-24): Classic shows its rail button with the Premium tag's
// tip; a click only says where to get it, and the page doesn't change (Classic has no catalog).
// node catalog_locked_ui.js <macro folder> <shot dir>   (headless Chromium, the page with a demo state)
const { chromium } = require("playwright"); const fs = require("fs");
const [base, out] = process.argv.slice(2);
const demo = JSON.parse(fs.readFileSync(base + "/Tools/test/demo_state.json", "utf8").replace(/^﻿/, ""));
let fails = 0;
const check = (name, ok, detail = "") => { console.log((ok ? "PASS " : "FAIL ") + name + (ok ? "" : ": " + detail)); if (!ok) fails++; };

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1423, height: 640 } });
  p.errors = []; p.on("pageerror", (e) => p.errors.push(e.message));
  await p.addInitScript(() => {
    window.__sent = [];
    window.chrome = { webview: { postMessage: (m) => window.__sent.push(JSON.parse(m)), addEventListener() {} } };
  });
  await p.goto("file://" + base + "/UI/index.html"); await p.waitForTimeout(200);
  const st = JSON.parse(JSON.stringify(demo)); st.edition = "classic";
  await p.evaluate((s) => { try { localStorage.setItem("page", "dash"); } catch (e) {} window.ui.init(s); }, st);
  await p.waitForTimeout(300);
  const nav = await p.$('#rail .nav[data-page="catalog"]');
  check("the rail has a Preset catalog button", !!nav && (await nav.getAttribute("aria-label")) === "Preset catalog");
  check("  marked Premium", !!nav && (await nav.getAttribute("data-premium")) === "Preset catalog");
  check("  with its icon", !!nav && (await nav.$("svg path")) !== null);
  if (nav) await nav.click();
  await p.waitForTimeout(200);
  const t = await p.$$eval("#toasts .toast", (els) => els.map((e) => e.textContent));
  check("a click says it's Premium", t.some((s) => /Preset catalog is a Premium feature/.test(s)), t.join(" | "));
  check("  the page stays on the dashboard", await p.evaluate(() => !!document.querySelector("#p-dash.on")));
  check("  nothing asked of the macro", await p.evaluate(() => !window.__sent.some((m) => m.cmd === "catalog")));
  check("no page errors", p.errors.length === 0, p.errors.join(" | "));
  await b.close();
  console.log(fails ? "FAILED " + fails : "ALL PASSED");
  process.exit(fails ? 1 : 0);
})();
