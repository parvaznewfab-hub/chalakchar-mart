# seo-1: home page SEO (hosting only)

Branch `seo-1`, base `audit-step-c` 5d8df70 (does NOT contain d4ead6c).
Only `web/index.html` changed. No rules, storage or functions.

## What changed
- viewport meta, Bengali title/description, og:site_name; meta keywords removed
- JSON-LD Organization + WebSite (same @id as productSeo/homeSeo)
- crawlable `<main id="home-seo">` (h1, intro, category + policy links),
  removed on Flutter's `flutter-first-frame` event
- og:image still Icon-512 until the owner provides a 1200x630 banner

## Preview
- channel `seo1`: https://chalakchar-mart--seo1-ylaq8fyi.web.app (version e404b5f237649d80, expires 2026-11-28)

## Live
**Live since 2026-11-21 03:13:36 UTC: version `e404b5f237649d80`** (owner approved),
via `firebase hosting:clone chalakchar-mart:seo1 chalakchar-mart:live`.
Nothing else deployed (no rules, storage or functions).

Checked on live after the clone: new title, Bengali description, viewport,
valid JSON-LD (Organization, WebSite); served index.html == seo-1 build;
product/category/about-us/sitemap.xml/robots.txt byte-identical to before
the clone; at 360px home, product, /cart and /login render (no white
screen, no horizontal scroll, #home-seo removed after Flutter's first
frame). www.chalakcharmart.com has no DNS record (existing issue, not checked).

From now on a hosting rollback for any other work should return to
`e404b5f237649d80`, not `caec3ea7c1d3fd7e`.

## Rollback of seo-1
Live before seo-1: version `caec3ea7c1d3fd7e` (step C, released 2026-11-20 14:06 UTC).

    firebase hosting:clone chalakchar-mart@caec3ea7c1d3fd7e chalakchar-mart:live

## Why the "/" -> homeSeo rewrite never runs
Firebase Hosting serves an existing static file before it looks at rewrites.
`/` resolves to `build/web/index.html`, which always exists, so the `"/"`
rewrite to `homeSeo` in firebase.json is never reached; every visit to `/`
gets the static index.html. Same for any other route: `**` -> /index.html.
Making homeSeo serve `/` would need index.html renamed out of the public
dir (and the `**` rewrite pointed at the new name), which would make the
home page depend on a function cold start. Not done here; static
index.html now carries the same SEO data.

## Follow-ups (not in this branch)
- After Flutter starts, the app sets document.title back to "ChalakChar Mart"
  (MaterialApp `title:` in lib/main.dart:386); align it with the new title (lib change).
- Soft 404s, category body links, breadcrumb category URL, brand on imported
  products, truncated titles, sitemap lastmod, canonical on 404: functions.
- www.chalakcharmart.com DNS + redirect: Firebase Console.
