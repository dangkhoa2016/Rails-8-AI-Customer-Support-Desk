// Optional browser acceptance test. Requires Playwright installed outside the Rails app.
// Never print the preview password, cookies, CSRF token, or tenant data.
const { chromium } = require("playwright");
const fs = require("fs");
const assert = require("assert/strict");

(async () => {
  const password = process.env.RAILS_PRIVATE_PREVIEW_PASSWORD;
  assert(password && password.length >= 30);
  const origin = "http://127.0.0.1:3068";
  const browser = await chromium.launch({ headless: true, args: ["--no-sandbox"] });
  const page = await browser.newPage({ viewport: { width: 1366, height: 900 } });
  const errors = [];
  page.on("pageerror", error => errors.push(error.name + ": " + error.message.slice(0, 160)));

  await page.goto(origin + "/__private_preview/sign_in");
  await page.locator("input[name=preview_password]").fill(password);
  await Promise.all([
    page.waitForURL(/\/demo\/sign_in/),
    page.locator('button[type="submit"]').click()
  ]);

  const owner = await page.locator('optgroup[label="TeamFlow Cloud"] option')
    .filter({ hasText: "Owner" }).first().getAttribute("value");
  assert(owner);
  await page.locator('select[name=membership_id]').selectOption(owner);
  await page.locator('select[name=locale]').selectOption("en");
  await Promise.all([
    page.waitForURL(origin + "/"),
    page.locator('form[action="/demo/sign_in"] input[type=submit]').click()
  ]);

  const turboReady = await page.evaluate(() => !!window.Turbo);
  const stimulusReady = await page.evaluate(() => !!window.Stimulus);
  assert(turboReady && stimulusReady, "Turbo/Stimulus JS must run in Chromium");
  await page.evaluate(() => { window.__hotwireNavigationSentinel = true; });

  await page.locator('nav a.nav-menu-link[href="/tickets"]').click();
  await page.waitForURL(origin + "/tickets");
  assert(await page.evaluate(() => window.__hotwireNavigationSentinel === true),
    "Tickets navigation caused a full page reload");
  assert(await page.locator("turbo-frame#tickets_listing").count() === 1);

  await page.locator('turbo-frame#tickets_listing select[name=status]').selectOption("open");
  await page.locator('turbo-frame#tickets_listing input[type=submit]').click();
  await page.waitForURL(/\/tickets\?/);
  assert(await page.evaluate(() => window.__hotwireNavigationSentinel === true),
    "Ticket filter caused a full reload");

  const frame = page.locator("turbo-frame#tickets_listing");
  const ticketLink = frame.locator('a[data-turbo-frame="_top"][href^="/tickets/"]').first();
  assert(await ticketLink.count() > 0, "expected at least one ticket");
  await ticketLink.click();
  await page.waitForURL(/\/tickets\/\d+$/);
  assert(await page.evaluate(() => window.__hotwireNavigationSentinel === true),
    "Ticket detail link caused a full reload");

  await page.locator('nav a.nav-menu-link[href="/customers"]').click();
  await page.waitForURL(origin + "/customers");
  assert(await page.locator("turbo-frame#customers_listing tbody tr").count() === 20);
  await page.locator('turbo-frame#customers_listing a[href*="page=2"]').click();
  await page.waitForURL(/\/customers\?.*page=2/);
  // A frame can advance browser history before the replacement DOM is complete.
  await page.waitForFunction(() => {
    const frame = document.querySelector('turbo-frame#customers_listing');
    return frame && !frame.hasAttribute('busy') && frame.textContent.includes('Page 2/');
  }, null, { timeout: 10000 });
  assert(await page.evaluate(() => window.__hotwireNavigationSentinel === true),
    "Customer pagination caused full reload");

  await page.locator('nav a.nav-menu-link[href="/knowledge_articles"]').click();
  await page.waitForURL(origin + "/knowledge_articles", { timeout: 8000 });
  const kb = page.locator("turbo-frame#kb_search_results");
  assert(await kb.count() === 1);
  await kb.locator("input[name=q]").fill("refund");
  await kb.locator("button[type=submit]").click();
  await page.waitForURL(/\/knowledge_articles\?q=/);
  assert(await page.evaluate(() => window.__hotwireNavigationSentinel === true),
    "KB search caused full reload");

  const navActive = await page.locator('nav a[aria-current=page]').getAttribute("href");
  assert.equal(navActive, "/knowledge_articles");
  // Session switch must deliberately perform a real navigation, not a Turbo cached visit.
  assert.equal(await page.locator('form[action="/demo/sign_out"]').getAttribute("data-turbo"), "false");
  await page.locator('form[action="/demo/sign_out"] button').click();
  await page.waitForURL(/\/demo\/sign_in$/);
  const reset = await page.evaluate(() => window.__hotwireNavigationSentinel === undefined);
  assert(reset, "sign-out did not reset the entire browser document");
  await page.goto(origin + "/");
  await page.waitForURL(/\/demo\/sign_in$/);
  assert.equal(await page.locator("nav a.nav-menu-link").count(), 0);

  // A new account must not inherit the previous tenant's navigation or session.
  const viewer = await page.locator('optgroup[label="NovaMart Store"] option')
    .filter({ hasText: "Viewer" }).first().getAttribute("value");
  assert(viewer);
  await page.locator('select[name=membership_id]').selectOption(viewer);
  await page.locator('select[name=locale]').selectOption("vi");
  await Promise.all([
    page.waitForURL(origin + "/"),
    page.locator('form[action="/demo/sign_in"] input[type=submit]').click()
  ]);
  const navText = await page.locator('nav').innerText();
  assert(navText.includes("NovaMart Store") && !navText.includes("TeamFlow Cloud"));
  assert.equal(await page.locator('nav a[href="/kb/ai-search"]').count(), 0);
  assert.equal(errors.length, 0, "JavaScript errors: " + errors.join(" | "));

  const result = {
    status: "PASS_CHROMIUM_REAL_HOTWIRE_NO_FULL_PAGE_RELOAD",
    origin_type: "private_loopback",
    browser: "Playwright Chromium Headless",
    turbo_loaded: turboReady,
    stimulus_loaded: stimulusReady,
    turbo_drive_tickets_no_reload: true,
    turbo_frame_tickets_filter_no_reload: true,
    turbo_tickets_detail_no_reload: true,
    turbo_frame_customers_pagination_no_reload: true,
    turbo_frame_kb_search_no_reload: true,
    active_nav_correct: true,
    signout_full_document_reload: reset,
    signed_out_page_protected: true,
    account_switch_novamart_viewer_isolated: true,
    javascript_errors: errors.length,
    business_mutations: 0,
    secrets_logged: false
  };
  console.log(JSON.stringify(result, null, 2));
  const evidencePath = process.env.HOTWIRE_EVIDENCE_OUT || "/content/rails8-hotwire-evidence-20261030/chromium-hotwire-browser.json";
  fs.mkdirSync(require("path").dirname(evidencePath), { recursive: true });
  fs.writeFileSync(evidencePath, JSON.stringify(result, null, 2) + "\n");
  await browser.close();
})().catch(error => {
  console.error("BROWSER_TEST_FAILED", error.name, error.message.slice(0, 420));
  process.exit(1);
});
