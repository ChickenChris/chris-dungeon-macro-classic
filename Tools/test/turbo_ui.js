// Settings: the Turbo placing switch (Chris 16 Nov, slow PCs) under Placement speed, in Premium and Classic.
// node turbo_ui.js <macro folder> [shot dir]   (headless Chromium, the page with a demo state)
const { chromium } = require("playwright"); const fs = require("fs");
const [base, out] = process.argv.slice(2);
const demo = JSON.parse(fs.readFileSync(base + "/Tools/test/demo_state.json", "utf8").replace(/^﻿/, ""));
let fails = 0;
const check = (name, ok, detail = "") => { console.log((ok ? "PASS " : "FAIL ") + name + (ok ? "" : ": " + detail)); if (!ok) fails++; };
(async () => {
  const b = await chromium.launch();
  for (const edition of ["", "classic"]) {
    const tag = edition || "premium";
    const p = await b.newPage({ viewport: { width: 1423, height: 640 } });
    const errors = []; p.on("pageerror", (e) => errors.push(e.message));
    await p.addInitScript(() => {
      window.__sent = [];
      window.chrome = { webview: { postMessage: (m) => window.__sent.push(JSON.parse(m)), addEventListener() {} } };
    });
    await p.goto("file://" + base + "/UI/index.html"); await p.waitForTimeout(200);
    const st = JSON.parse(JSON.stringify(demo)); if (edition) st.edition = edition;
    st.cfg.placeTurbo = 0;
    await p.evaluate((s) => { try { localStorage.setItem("page", "settings"); } catch (e) {} window.ui.init(s); }, st);
    await p.waitForTimeout(250);
    const t = await p.$('#p-settings label.toggle[data-key="placeTurbo"]');
    check(tag + ": a Turbo placing switch in Settings", !!t);
    const after = await p.evaluate(() => { const s = document.querySelector("#speed"); const n = s && s.closest(".row").nextElementSibling; return n ? n.dataset.key : ""; });
    check(tag + ": right under Placement speed", after === "placeTurbo", after);
    if (t) { await t.click(); await p.waitForTimeout(150); }
    const sent = await p.evaluate(() => window.__sent);
    check(tag + ": turning it on saves placeTurbo 1", sent.some((m) => m.cmd === "set" && m.key === "placeTurbo" && (m.value === 1 || m.value === true)), JSON.stringify(sent.slice(-2)));
    if (out) await p.screenshot({ path: `${out}/turbo_${tag}.png` });
    check(tag + ": no page errors", !errors.length, errors.join("; "));
    await p.close();
  }
  await b.close();
  console.log(fails ? "FAILED " + fails : "ALL PASSED"); process.exit(fails ? 1 : 0);
})();
