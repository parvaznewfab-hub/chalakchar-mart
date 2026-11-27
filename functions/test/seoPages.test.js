const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const html = require("../seo/html");
const idx = require("../seo/indexable");
const pages = require("../seo/pages");
const handlers = require("../seo/handlers");
const { guard, SeoUnavailableError } = require("../seo/catalog");

// ---------------------------------------------------------------------------
// Tiny Firestore fake: collection().where(==).select().limit().get(),
// doc().get(); `fail` makes every read reject, `hang` never resolve.
// ---------------------------------------------------------------------------
function fakeDb(collections, { fail = false, hang = false } = {}) {
  const read = (value) => {
    if (hang) return new Promise(() => {});
    if (fail) return Promise.reject(new Error("14 UNAVAILABLE: backend down"));
    return Promise.resolve(value);
  };
  const snapOf = (entries) => ({
    empty: entries.length === 0,
    docs: entries.map(([id, data]) => ({ id, data: () => ({ ...data }) })),
    forEach(fn) { this.docs.forEach(fn); },
  });
  const query = (name, filters = []) => ({
    where: (field, op, value) => query(name, [...filters, [field, value]]),
    select: () => query(name, filters),
    limit: () => query(name, filters),
    orderBy: () => query(name, filters),
    get: () => read(snapOf(Object.entries(collections[name] || {})
      .filter(([, d]) => filters.every(([f, v]) => d[f] === v)))),
  });
  return {
    collection: (name) => ({
      ...query(name),
      doc: (id) => ({
        get: () => {
          const data = (collections[name] || {})[id];
          return read({ exists: Boolean(data), id, data: () => (data ? { ...data } : undefined) });
        },
      }),
    }),
  };
}

function fakeRes() {
  const res = { headers: {}, statusCode: 0, body: "" };
  res.set = (k, v) => { res.headers[k.toLowerCase()] = v; return res; };
  res.status = (s) => { res.statusCode = s; return res; };
  res.send = (b) => { res.body = b; return res; };
  return res;
}

const quietLogger = { warn() {}, error() {}, info() {} };
const ts = (iso) => ({ toDate: () => new Date(iso) });

const P = (extra = {}) => ({
  name: "iPhone 12 LCD Display", category: "Mobile Parts", isActive: true, approvalStatus: "approved",
  price: 2399, stock: 3, createdAt: ts("2026-11-01T00:00:00Z"), updatedAt: ts("2026-11-20T00:00:00Z"), ...extra,
});

const catalogData = () => ({
  categories: {
    mp: { name: "Mobile Parts", isActive: true, priority: 1, updatedAt: ts("2026-11-14T00:00:00Z") },
    ca: { name: "Computer Accessories", isActive: true, priority: 2 },
    empty: { name: "Motherboard", isActive: true, priority: 3 },
    off: { name: "Storage Devices", isActive: false },
  },
  subcategories: {
    disp: { name: "Display & Digitizer", slug: "display-digitizer", categoryId: "mp", isActive: true },
    merged: { name: "Old", categoryId: "mp", isActive: true, mergedInto: "disp" },
  },
  products: {
    a: P({ subcategoryId: "disp" }),
    imp_aliexpress_x: P({
      name: '6.6&quot; LCD For Samsung A14 &amp; A14 5G', metaTitle: '6.6" LCD For Samsung A14',
      deliveryMinDays: 11, deliveryMaxDays: 26, importedAt: ts("2026-11-02T00:00:00Z"),
      specifications: [{ name: "Origin", value: "Mainland China" }, { name: "Brand Name", value: "AUMOOK" }, { name: "Ships From", value: "AliExpress" }],
      needsReview: true,
    }),
    ssd: P({ name: "Netac SSD 256GB", category: "Computer Accessories" }),
    draft: P({ approvalStatus: "draft" }),
    hidden: P({ hiddenReason: "health_removed" }),
    invisible: P({ isVisible: false }),
    offCat: P({ category: "Storage Devices" }),
    noCat: P({ category: "Cooking" }),
    inactive: P({ isActive: false }),
  },
  settings: { app: { supportPhone: "01343845018" } },
});

async function run(handler, url, data = catalogData(), opts = {}) {
  const res = fakeRes();
  await handlers[handler]({ path: url, url }, res, { db: fakeDb(data, opts), logger: quietLogger, deadlineMs: opts.deadlineMs || 1000 });
  return res;
}

const robotsMeta = (body) => (body.match(/<meta name="robots" content="([^"]*)"/) || [])[1];

// ---------------------------------------------------------------------------
// Entity escaping
// ---------------------------------------------------------------------------

test("escText/escAttr: stored entities are decoded, then escaped exactly once", () => {
  assert.equal(html.escText('6.6&quot; A &amp; B <x>'), '6.6" A &amp; B &lt;x&gt;');
  assert.equal(html.escText('6.6" A & B'), '6.6" A &amp; B');
  assert.equal(html.escAttr('6.6&quot; it&#39;s'), "6.6&quot; it&#39;s");
  assert.equal(html.escAttr('6.6" it\'s'), "6.6&quot; it&#39;s");
  assert.ok(!html.escText("&amp;quot;").includes("&amp;quot;") || html.escText("&amp;quot;") === "&amp;quot;");
});

test("product page: <title> and <h1> carry the full name, no double escape, no '...'", async () => {
  const res = await run("productSeo", "/product/imp_aliexpress_x");
  assert.equal(res.statusCode, 200);
  const title = res.body.match(/<title>([^<]*)<\/title>/)[1];
  assert.equal(title, '6.6" LCD For Samsung A14 &amp; A14 5G | ChalakChar Mart');
  assert.ok(!res.body.includes("&amp;quot;"));
  assert.ok(!res.body.includes("&amp;amp;"));
  assert.match(res.body, /<h1>6\.6" LCD For Samsung A14 &amp; A14 5G<\/h1>/);
  assert.match(res.body, /<meta property="og:title" content="6\.6&quot; LCD For Samsung A14 &amp; A14 5G \| ChalakChar Mart">/);
  const ld = JSON.parse(res.body.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
  const product = ld["@graph"].find((n) => n["@type"] === "Product");
  assert.equal(product.name, '6.6" LCD For Samsung A14 & A14 5G');
});

// ---------------------------------------------------------------------------
// Indexable rule (same as lib/utils/shop_visibility.dart)
// ---------------------------------------------------------------------------

test("isProductIndexable is the shop rule; needsReview does not matter", () => {
  const d = catalogData();
  const active = idx.activeCategoryNames(Object.values(d.categories));
  const shown = Object.entries(d.products).filter(([, p]) => idx.isProductIndexable(p, active)).map(([id]) => id).sort();
  assert.deepEqual(shown, ["a", "imp_aliexpress_x", "ssd"]);
  assert.equal(idx.isProductIndexable({ ...P(), isActive: "true" }, active), false, "isActive must be true, not truthy");
});

test("isCategoryIndexable: switched on and at least one shown product", () => {
  assert.equal(idx.isCategoryIndexable({ isActive: true }, 1), true);
  assert.equal(idx.isCategoryIndexable({ isActive: true }, 0), false);
  assert.equal(idx.isCategoryIndexable({ isActive: false }, 5), false);
  assert.equal(idx.isCategoryIndexable({}, 5), false, "missing isActive is off, like the app");
});

test("findActiveCategoryBySlug ignores switched-off duplicates", () => {
  const cats = [{ name: "Toys", isActive: false, priority: 0 }, { name: "Toys", isActive: true, priority: 5, id: "on" }];
  assert.equal(idx.findActiveCategoryBySlug(cats, "toys").id, "on");
  assert.equal(idx.findActiveCategoryBySlug(cats, "nope"), null);
});

// ---------------------------------------------------------------------------
// Status codes: 200 / 200+noindex / 404 / 503
// ---------------------------------------------------------------------------

test("category page: h1, intro, product links with price, subcategory links, breadcrumb", async () => {
  const res = await run("pageSeo", "/category/mobile-parts");
  assert.equal(res.statusCode, 200);
  assert.equal(robotsMeta(res.body), "index, follow");
  assert.equal(res.headers["x-robots-tag"], undefined);
  assert.match(res.body, /<h1>Mobile Parts<\/h1>/);
  assert.match(res.body, /ক্যাটাগরিতে এখন ২টি পণ্য আছে/);
  assert.match(res.body, /<a href="\/product\/a">iPhone 12 LCD Display — ৳2,399<\/a>/);
  assert.match(res.body, /<a href="\/category\/mobile-parts\?sub=display-digitizer">Display &amp; Digitizer \(১\)<\/a>/);
  assert.ok(!res.body.includes('href="/product/draft"'));
  assert.ok(!res.body.includes('href="/product/hidden"'));
  const ld = JSON.parse(res.body.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
  const crumbs = ld["@graph"].find((n) => n["@type"] === "BreadcrumbList").itemListElement;
  assert.deepEqual(crumbs.map((c) => c.item), ["https://chalakcharmart.com/", "https://chalakcharmart.com/category/mobile-parts"]);
});

test("category: switched on but empty → 200 + noindex; unknown/off → 404 + noindex", async () => {
  const empty = await run("pageSeo", "/category/motherboard");
  assert.equal(empty.statusCode, 200);
  assert.equal(robotsMeta(empty.body), "noindex, follow");
  assert.equal(empty.headers["x-robots-tag"], "noindex");
  for (const url of ["/category/doesnotexist", "/category/storage-devices", "/category/beverages"]) {
    const res = await run("pageSeo", url);
    assert.equal(res.statusCode, 404, url);
    assert.equal(robotsMeta(res.body), "noindex, follow", url);
  }
});

test("Firestore error → 503 + Retry-After, never 404 and never noindex", async () => {
  const cases = [
    ["pageSeo", "/category/mobile-parts"],
    ["pageSeo", "/about-us"],
    ["productSeo", "/product/a"],
    ["homeSeo", "/"],
  ];
  for (const [handler, url] of cases) {
    const res = await run(handler, url, catalogData(), { fail: true });
    assert.equal(res.statusCode, 503, url);
    assert.equal(res.headers["retry-after"], handlers.RETRY_AFTER_SECONDS, url);
    assert.equal(res.headers["x-robots-tag"], undefined, url);
    assert.equal(robotsMeta(res.body), undefined, `${url}: no robots meta at all`);
    assert.ok(!/noindex/i.test(res.body), url);
    assert.equal(res.headers["cache-control"], "no-store", url);
  }
  const sm = await run("sitemap", "/sitemap.xml", catalogData(), { fail: true });
  assert.equal(sm.statusCode, 503);
  assert.equal(sm.headers["retry-after"], handlers.RETRY_AFTER_SECONDS);
});

test("Firestore timeout → 503 (deadline), not a hung request or a 404", async () => {
  const res = await run("productSeo", "/product/a", catalogData(), { hang: true, deadlineMs: 30 });
  assert.equal(res.statusCode, 503);
  await assert.rejects(guard(new Promise(() => {}), "x", 10), SeoUnavailableError);
});

test("product: missing → 404 noindex; hidden → 200 noindex; shown → 200 index", async () => {
  const missing = await run("productSeo", "/product/nope");
  assert.equal(missing.statusCode, 404);
  assert.equal(robotsMeta(missing.body), "noindex, follow");
  const hidden = await run("productSeo", "/product/draft");
  assert.equal(hidden.statusCode, 200);
  assert.equal(robotsMeta(hidden.body), "noindex, nofollow");
  assert.equal(hidden.headers["x-robots-tag"], "noindex, nofollow");
  const shown = await run("productSeo", "/product/a");
  assert.equal(robotsMeta(shown.body), "index, follow");
});

test("product: price ৳, stock, delivery, import label, specs, category link, offers; no supplier name", async () => {
  const res = await run("productSeo", "/product/imp_aliexpress_x");
  const body = res.body.split("<body>")[1];
  assert.match(body, /দাম: <strong>৳2,399<\/strong>/);
  assert.match(body, /স্টক: স্টকে আছে/);
  assert.match(body, /ডেলিভারি: আনুমানিক ১১–২৬ দিন/);
  assert.match(body, /<li>বিদেশ থেকে আমদানি<\/li>/);
  assert.match(body, /<tr><th>Brand Name<\/th><td>AUMOOK<\/td><\/tr>/);
  assert.ok(!/Origin|Mainland|China/i.test(body), "origin rows are hidden");
  const visibleText = body.replace(/<script[\s\S]*?<\/script>/g, "").replace(/<[^>]+>/g, " ").replace(/href="[^"]*"/g, "");
  assert.ok(!/ali\s*express/i.test(visibleText), "supplier never named in visible text");
  assert.match(body, /<a href="\/category\/mobile-parts">আরও Mobile Parts দেখুন<\/a>/);
  const ld = JSON.parse(res.body.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
  const product = ld["@graph"].find((n) => n["@type"] === "Product");
  assert.equal(product.offers.price, "2399.00");
  assert.equal(product.offers.priceCurrency, "BDT");
  assert.equal(product.offers.availability, "https://schema.org/InStock");
  assert.deepEqual([product.offers.shippingDetails.deliveryTime.transitTime.minValue, product.offers.shippingDetails.deliveryTime.transitTime.maxValue], [11, 26]);
  const crumbs = ld["@graph"].find((n) => n["@type"] === "BreadcrumbList").itemListElement;
  assert.equal(crumbs[1].item, "https://chalakcharmart.com/category/mobile-parts");
  assert.ok(!/ali\s*express/i.test(JSON.stringify(product).replace(/imp_aliexpress_x/g, "")));
});

test("productTitle: an import's cut-short metaTitle gives way to the full name", () => {
  assert.equal(pages.productTitle({ name: "A very long name here", metaTitle: "A very long" }), "A very long name here | ChalakChar Mart");
  assert.equal(pages.productTitle({ name: "iPhone 12 LCD", metaTitle: "iPhone 12 LCD Display" }), "iPhone 12 LCD Display");
});

// ---------------------------------------------------------------------------
// Policy pages
// ---------------------------------------------------------------------------

test("policy pages: full text, <h1>, contacts from settings", async () => {
  for (const url of ["/about-us", "/privacy-policy", "/terms-conditions", "/return-policy"]) {
    const res = await run("pageSeo", url);
    assert.equal(res.statusCode, 200, url);
    assert.equal((res.body.match(/<h1>/g) || []).length, 1, url);
    const text = res.body.split("<body>")[1].replace(/<style[\s\S]*?<\/style>/g, "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");
    assert.ok(text.length > 800, `${url}: ${text.length} chars`);
  }
  const about = await run("pageSeo", "/about-us");
  assert.match(about.body, /01343845018/);
  assert.ok(!about.body.includes("01975838764"));
});

// ---------------------------------------------------------------------------
// Sitemap
// ---------------------------------------------------------------------------

test("sitemap: only indexable URLs, every one answers 200 + index; lastmod from data", async () => {
  const res = await run("sitemap", "/sitemap.xml");
  assert.equal(res.statusCode, 200);
  const locs = [...res.body.matchAll(/<loc>https:\/\/chalakcharmart\.com([^<]*)<\/loc>/g)].map((m) => m[1]);
  assert.deepEqual(locs.filter((l) => l.startsWith("/product/")).sort(), ["/product/a", "/product/imp_aliexpress_x", "/product/ssd"]);
  assert.deepEqual(locs.filter((l) => l.startsWith("/category/")).sort(), ["/category/computer-accessories", "/category/mobile-parts"]);
  for (const loc of locs.filter((l) => l !== "/")) {
    const handler = loc.startsWith("/product/") ? "productSeo" : "pageSeo";
    const page = await run(handler, loc);
    assert.equal(page.statusCode, 200, loc);
    assert.equal(robotsMeta(page.body), "index, follow", loc);
  }
  const today = new Date().toISOString().slice(0, 10);
  const lastmods = [...res.body.matchAll(/<lastmod>([^<]*)<\/lastmod>/g)].map((m) => m[1]);
  assert.ok(!lastmods.includes(today) || today === "2026-11-20", "no 'today' dates");
  assert.match(res.body, /<loc>https:\/\/chalakcharmart\.com\/about-us<\/loc>\n {4}<lastmod>2026-11-15<\/lastmod>/);
  assert.match(res.body, /<loc>https:\/\/chalakcharmart\.com\/category\/mobile-parts<\/loc>\n {4}<lastmod>2026-11-20<\/lastmod>/);
});

test("sitemap: a product without dates gets no lastmod (never today)", () => {
  const xml = pages.renderSitemap({
    categories: [{ name: "Mobile Parts", isActive: true }],
    products: [{ id: "x", ...P({ createdAt: null, updatedAt: null }) }],
    activeCategoriesLower: new Set(["mobile parts"]),
    policyLastModified: null,
  });
  assert.ok(!xml.includes("<lastmod>"));
});

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

test("home: newest shown products as links, at most 20", () => {
  const products = Array.from({ length: 25 }, (_, i) => ({ id: `p${i}`, ...P({ name: `Part ${i}`, createdAt: ts(`2026-11-${String(i + 1).padStart(2, "0")}T00:00:00Z`) }) }));
  products.push({ id: "hid", ...P({ hiddenReason: "x", createdAt: ts("2026-12-01T00:00:00Z") }) });
  const body = pages.renderHomePage({ categories: [{ name: "Mobile Parts", isActive: true }], products, activeCategoriesLower: new Set(["mobile parts"]) });
  const links = [...body.matchAll(/href="\/product\/([^"]+)"/g)].map((m) => m[1]);
  assert.equal(links.length, 20);
  assert.equal(links[0], "p24");
  assert.ok(!links.includes("hid"));
  assert.match(body, /<h1>/);
});

// ---------------------------------------------------------------------------
// Policy text copy stays in sync with the app
// ---------------------------------------------------------------------------

test("policyTexts.js is the current copy of lib/pages/user/policy_texts.dart", () => {
  const sync = require("../../tools/seo/sync_policy_texts");
  if (!fs.existsSync(sync.DART_FILE)) return; // functions/ deployed alone
  const expected = sync.buildJs(fs.readFileSync(sync.DART_FILE, "utf8"));
  assert.equal(fs.readFileSync(sync.JS_FILE, "utf8").replace(/\r\n/g, "\n"), expected, "run: node tools/seo/sync_policy_texts.js");
});

test("POLICY_LAST_MODIFIED is not older than the policy texts' last commit", () => {
  const dart = path.resolve(__dirname, "..", "..", "lib", "pages", "user", "policy_texts.dart");
  let lastCommit = "";
  try {
    lastCommit = execFileSync("git", ["log", "-1", "--format=%cs", "--", dart], { encoding: "utf8" }).trim();
  } catch (_) {
    return; // no git here
  }
  if (!lastCommit) return;
  assert.ok(handlers.POLICY_LAST_MODIFIED >= lastCommit, `update POLICY_LAST_MODIFIED to ${lastCommit}`);
});

test("price label: 'থেকে' when variants differ in price, like the product cards", () => {
  const variants = [{ price: 1829, stock: 5 }, { price: 1921, stock: 5 }];
  const html = pages.renderProductPage({ product: { id: "v", ...P({ variants }) }, indexable: true });
  assert.match(html, /দাম: <strong>৳1,829 থেকে<\/strong>/);
  assert.match(pages.productLinkItem({ id: "v", ...P({ variants }) }), /— ৳1,829 থেকে<\/a>/);
  assert.match(pages.productLinkItem({ id: "s", ...P() }), /— ৳2,399<\/a>/);
});
