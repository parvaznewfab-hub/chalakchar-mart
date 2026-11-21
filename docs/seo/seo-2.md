# seo-2: per-page document title (hosting only)

Branch `seo-2` = audit-step-c 5d8df70 + seo-1 (fast-forward, so the live
index.html is kept) + 707b3ef. Does NOT contain d4ead6c. Product URL,
canonical and slug code untouched.

## What changed
- `lib/services/seo_titles.dart` (new): home, policy, category (English,
  limitText 65/160) and not-found titles/descriptions, same as web/index.html
  and functions/index.js.
- `WebSeoService`: `setPageSeo` writes every page-level head tag (no product
  description/og/twitter/JSON-LD left behind); `resetPageSeo` uses the
  server's text for the path; `setCategorySeo` (real name, 404 title +
  noindex); `currentTitle` = last title set, else the server's.
- `main.dart`: `onGenerateTitle: (_) => WebSeoService.currentTitle` instead of
  the fixed `title:`, so root rebuilds (theme switch) keep the page title.
- `category_products_page.dart`: sets the category SEO only while it is the
  top route (it rebuilds behind product pages).

## Tests
New: test/seo_titles_test.dart, test/seo_titles_parity_test.dart (reads
index.html, functions/index.js, main.dart), test/seo_route_observer_test.dart.
flutter analyze: no issues. flutter test: 486 pass. functions: 664 pass.
tools/web: 9 pass.

## Preview
channel `seo2`: https://chalakchar-mart--seo2-zzsxgk3k.web.app
(version 907a86861815b27e, expires 2026-11-28)

| page | server `<title>` | document.title (360 + desktop) |
|---|---|---|
| / | ChalakChar Mart \| মোবাইল ও ল্যাপটপ পার্টস অনলাইন — ক্যাশ অন ডেলিভারি | same |
| /category/motherboard | Motherboard Price in Bangladesh \| ChalakChar Mart | same |
| /product/JerrBHpoQap1u0dHcPlA | iPhone 12/12 Pro LCD Display Screen Replacement | same |
| /about-us | About Us \| ChalakChar Mart | same |
| /cart | (index.html home title) | ChalakChar Mart, noindex |
| /login | (index.html home title) | ChalakChar Mart, noindex |

/cart and /login have no server-side SEO page; they get index.html, so the
server title is the home one. The app gives them the plain site name
(planned: private, noindex pages).

## Known limit (unchanged from before)
Back to a product page from another in-app page: the observer skips product
routes and the product page doesn't re-set its tags, so the previous page's
title stays until the product page rebuilds. Fixing it touches product SEO
code (d4ead6c area); left for after d4ead6c.

## Live
**Live since 2026-11-21 03:53:23 UTC: version `907a86861815b27e`** (owner
approved after step D rules deploy), via
`firebase hosting:clone chalakchar-mart:seo2 chalakchar-mart:live`.
Nothing else deployed (no rules, storage or functions).

Checked on live after the clone:
- served index.html and main.dart.js == seo-2 build; product, category,
  about-us, sitemap.xml, robots.txt byte-identical to before the clone.
- 360px and desktop: home, category, product, about-us document.title ==
  server `<title>`; /cart and /login "ChalakChar Mart" + noindex; no white
  screen, no horizontal scroll, #home-seo removed.
- In-app: category -> tap product card -> browser Back (360px and desktop):
  title, description, og:type/url/image, canonical back to the category's,
  product JSON-LD removed.
- Admin pages: owner checks (Google login).

From now on a hosting rollback for any other work should return to
`907a86861815b27e`.

## Rollback of seo-2
Live before seo-2: `e404b5f237649d80` (seo-1).

    firebase hosting:clone chalakchar-mart@e404b5f237649d80 chalakchar-mart:live
