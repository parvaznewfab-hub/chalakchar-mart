# seo-3: Google indexing (SSR content, one indexable rule, server-only robots)

Branch `seo-3` (worktree `../cc_seo3`), from `step-g` (live base: seo-1, seo-2,
brand-1, ledger-1, steps C–G; not d4ead6c). Status: committed, NOT deployed.

## What changed

- `functions/seo/` — productSeo, pageSeo, homeSeo, sitemap now live here
  (functions/index.js only wires them).
  - `indexable.js`: `isProductIndexable` = the shop rule
    (lib/utils/shop_visibility.dart, no needsReview); `isCategoryIndexable` =
    switched on + ≥1 shown product. SSR and sitemap use the same helpers.
    Live 2026-11-27: 83 products (= live sitemap), 3 categories.
  - Status rules: shown → 200 index; hidden product / empty category → 200
    noindex; missing → 404 noindex; Firestore error or 8 s timeout → 503 +
    Retry-After 120, no robots meta, `no-store`.
  - Category: h1, Bengali intro, up to 100 `<a href="/product/ID">name — ৳price</a>`
    (“থেকে” for a price range, as the cards), subcategory `?sub=` links,
    BreadcrumbList Home → category.
  - Product: h1 full name, title = full name (an import's cut-short
    metaTitle is ignored), entities decoded then escaped once, price/stock/
    delivery days, "বিদেশ থেকে আমদানি", specs table (origin rows hidden),
    template summary, breadcrumb + visible link to the real category, one
    Product JSON-LD with offers (BDT, availability, transit days).
  - Policy pages: full text from `functions/seo/policyTexts.js`, generated
    from lib/pages/user/policy_texts.dart by `tools/seo/sync_policy_texts.js`
    (a test fails when they differ). Owner approval of the "DRAFT" text is
    pending.
  - Sitemap: indexable URLs only; lastmod from data (no "today"); policy pages
    `POLICY_LAST_MODIFIED`.
- Client: never writes robots (setRobots removed; route observer, category
  not-found and product page no longer touch it); no client JSON-LD; product
  title same rule as the server. `/login`, `/cart` noindex via firebase.json
  `X-Robots-Tag`. Dart tests guard both rules.
- web/index.html: the home SEO text stays after Flutter's first frame (only
  the loading logo is removed). Checked with screenshots: Flutter view covers
  it, no scroll.

## Findings

- `/` is the static index.html: Hosting serves a real file before rewrites, so
  the `/` → homeSeo rewrite never runs (also noted in seo-1.md).
- The `index.html` → `app.html` idea: commit 0cf3229 (2026-07-13) added `/` →
  homeSeo and changed the `**` fallback to `/app.html`, but no script ever
  renamed index.html (no other commit in any branch mentions app.html). Deep
  links then hit Hosting's 404 (commit 277003c, 2026-07-25, put the fallback
  back to /index.html). So `/` never reached homeSeo.
- 2026-11-21 noindex on /category/computer-accessories: server answered 200
  index (one active category, no duplicates). Most likely cause: seo-2's
  client `setCategorySeo(exists:false)` (live from 2026-11-21 03:53 UTC) set
  noindex when the first Firestore snapshot came back empty in Google's
  renderer, and nothing reset it.

## Deploy (each step needs the owner's go)

1. Firestore export. Done: `gs://chalakchar-mart-backups/seo3-fn-20261127-0550`
   (full database, SUCCESSFUL 05:51:01 UTC, 970 documents, ~4.1 MB).
2. `firebase deploy --only functions:productSeo,functions:pageSeo,functions:homeSeo,functions:sitemap`
   from `seo-3`. Rollback: the same four from `step-g`.
3. Hosting build (flutter clean; build --release --pwa-strategy=none) to
   channel `seo3`; owner checks; headless check of rendered robots and the
   /login, /cart header (the hosting emulator sends no headers at all).
4. Clone `seo3` → live. Rollback: clone the previous live version.
