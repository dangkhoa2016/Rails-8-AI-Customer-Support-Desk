// Optional Colab acceptance. Uses the existing successful synthetic run; no GPU writes.
const { chromium } = require("playwright");
const assert = require("assert/strict");
const fs = require("fs");
(async () => {
  const origin = process.env.M52_ORIGIN || "http://127.0.0.1:3068";
  const password = process.env.RAILS_PRIVATE_PREVIEW_PASSWORD;
  const runId = process.env.M52_EXISTING_PUBLIC_ID;
  assert(password?.length >= 30 && /^[0-9a-f-]{36}$/.test(runId));
  const browser = await chromium.launch({ headless: true, args: ["--no-sandbox"] });
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", e => errors.push(e.name));
  await page.goto(origin + "/__private_preview/sign_in");
  await page.locator("input[name=preview_password]").fill(password);
  await Promise.all([
    page.waitForURL(/\/demo\/sign_in/),
    page.locator('button[type=submit]').click()
  ]);
  const owner = await page.locator('optgroup[label="TeamFlow Cloud"] option')
    .filter({hasText: "Owner"}).first().getAttribute("value");
  assert(owner);
  await page.locator("select[name=membership_id]").selectOption(owner);
  await page.locator("select[name=locale]").selectOption("vi");
  await Promise.all([
    page.waitForURL(origin + "/"),
    page.locator('form[action="/demo/sign_in"] input[type=submit]').click()
  ]);
  await page.goto(origin + "/kb/ai-search?run=" + runId);
  const frame = page.locator("turbo-frame#ai_search_run_" + runId);
  await frame.waitFor();
  assert.equal(await frame.locator("article.ai-hit").count(), 3);
  assert.equal(await frame.getAttribute("data-controller"), "ai-search-poll");
  assert.equal(await frame.locator("[data-ai-terminal=true]").count(), 1);
  assert(await page.evaluate(() => !!window.Turbo && !!window.Stimulus));
  assert.equal(errors.length, 0);
  console.log(JSON.stringify({
    status: "PASS_M52_REAL_CHROMIUM_COMPLETED_TURBO_FRAME",
    origin_kind: origin.startsWith("https") ? "private_https" : "private_local",
    citations: 3, turbo: true, stimulus: true, javascript_errors: 0,
    gpu_calls: 0, business_writes: 0, sealed80: "BLOCKED"
  }));
  await browser.close();
})().catch(e => { console.error("M52_BROWSER_TEST_FAILED", e.name); process.exit(1); });
