# seo-3: Google indexing (SSR content, one indexable rule, server-only robots)

Branch `seo-3` (worktree `../cc_seo3`), from `step-g` (live base: seo-1, seo-2,
brand-1, ledger-1, steps C–G; not d4ead6c). Status: LIVE 2026-11-27 —
functions 05:54 UTC, hosting 06:25 UTC (version d9aabec1a0fd54c3). Pushed,
not merged. Later hosting builds must include seo-3 (and seo-1, seo-2).

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
   Done 2026-11-27 05:54:46 UTC (commit 43d185a). Live checks: SSR h1/links/
   text as in the emulator; sitemap 91 URLs (83 products, 3 categories), all
   200 + index; hidden products (draft, health_removed) 200 + noindex,
   X-Robots-Tag, not in sitemap; logs 05:54–06:05: no WARNING/ERROR, no 5xx
   (pageSeo 200×15, 404×3 = test URL /category/doesnotexist; productSeo
   200×87; sitemap 200×1).
3. Hosting build (flutter clean; build --release --pwa-strategy=none) to
   channel `seo3`; owner checks; headless check of rendered robots and the
   /login, /cart header (the hosting emulator sends no headers at all).
   Done 2026-11-27 06:09 UTC: https://chalakchar-mart--seo3-m19onqq4.web.app
   (expires 2026-12-04), main.dart.js sha256 85dc5bbf2c526da5 (live
   e19a1cbdea039de8). Firebase adds `X-Robots-Tag: noindex` to every
   preview-channel response (old stepg channel too), so the /login, /cart
   header can only be checked on live after the clone. Rendered (8 s after
   first frame): robots index on all 5 real pages, 404 page noindex; product
   page exactly 1 Product JSON-LD. Bug test with firestore.googleapis.com
   blocked: live (old client) computer-accessories/mobile-parts → "Page not
   found" + noindex; seo3 → index + real title. Slow 3G: both index (~85 s).
4. Clone `seo3` → live. Rollback: clone the previous live version.
   Done 2026-11-27 06:25:48 UTC: live = version d9aabec1a0fd54c3.
   **Rollback target (live before seo-3): bd482832093239e5** (step G) —
   `firebase hosting:clone chalakchar-mart@bd482832093239e5 chalakchar-mart:live --project chalakchar-mart`.

## Final result (live, 2026-11-27 06:29 UTC)

- live main.dart.js sha256 85dc5bbf2c526da5 (= seo3 build).
- X-Robots-Tag: `/login`, `/cart` → `noindex, nofollow`; `/category/doesnotexist`
  → `noindex` (404); none on `/`, `/about-us`, both categories, the product,
  `/sitemap.xml`, `main.dart.js`, or chalakchar-mart.web.app.
- Rendered (Googlebot UA, 8 s after first frame):

  | URL | robots | h1 | links | DOM text | Product JSON-LD |
  |---|---|---|---|---|---|
  | / | index | 1 | 7 | 384 (was 0) | 0 |
  | /about-us | index | 1 | 5 | 965 | 0 |
  | /category/computer-accessories | index | 1 | 11 | 1012 | 0 |
  | /category/mobile-parts | index | 1 | 61 | 6966 | 0 |
  | /product/imp_aliexpress_d85… | index | 1 | 20 | 2712 | 1 |
  | /category/doesnotexist (404) | noindex | 0 | 0 | 0 | 0 |

  Product title: full name + " | ChalakChar Mart".
- Firestore blocked (firestore.googleapis.com aborted):
  /category/computer-accessories stays `index, follow` with its real title
  (before: "Page not found" + noindex).
- Sitemap: 91 URLs (83 products, 3 categories, 4 policy, home), all 200 +
  index.
- App: /cart (guest: "Your cart is empty"), /admin (guest: "Admin access
  denied"), /login open with 0 console errors. Logged-in admin check: by the
  owner (no credentials in this session).
- Function logs 05:54–06:29 UTC: no WARNING/ERROR, no 5xx.

## After release

- Search Console: inspect + request indexing for /category/computer-accessories,
  /about-us and a few products; resubmit sitemap.xml.
- Later steps: (ক) "/" served by homeSeo (separate step);
  docs/plans/updated-at-real-changes.md; docs/plans/payment-gateway-privacy-update.md.
