# পরিকল্পনা: প্রোডাক্ট লিংক থেকে `imp_aliexpress_…` সরানো, আর সাপ্লায়ারের তথ্য লুকানো

অবস্থা (২০২৬-১১-১৯): কোড কমিট হয়েছে (`wip/audit-step1`), emulator-এ লাইভ ডেটার কপিতে যাচাই হয়েছে। **Deploy বা লাইভ মাইগ্রেশন হয়নি**, মালিকের আলাদা অনুমতি লাগবে।
আগের সংস্করণ (২০২৬-১১-১৪) শুধু URL নিয়ে ছিল; মালিকের ২০২৬-১১-১৯-এর সিদ্ধান্ত অনুযায়ী এটা বদলানো হয়েছে।

## সমস্যা
1. প্রোডাক্টের পাবলিক লিংক `/product/{doc id}`, তাই ইমপোর্ট হওয়া প্রোডাক্টের লিংকে সাপ্লায়ারের নাম দেখা যায়: `/product/imp_aliexpress_7f8f…`।
2. **আরও বড় সমস্যা:** `products` যে কেউ পড়তে পারে, আর ইমপোর্ট হওয়া প্রোডাক্টের ডকে ছিল `sourceUrl` (AliExpress লিংক), `sourceProductId`, `originalPrice`, `exchangeRate`, `markupPercent`, ফ্রেইট, প্রতিটা ভ্যারিয়েন্টের `sourceSkuId` ইত্যাদি। কাস্টমারের ব্রাউজারের network response-এ এগুলো সরাসরি আসত।
3. চেকআউটে অ্যাপ `source`, `sourceProductId`, `aliExpressLink` অর্ডারের আইটেমে কপি করত। অর্ডার কাস্টমার, ভেন্ডর আর রাইডার পড়তে পারে।

## মালিকের সিদ্ধান্ত (২০২৬-১১-১৯)
1. পুরনো ১০৭টা `imp_aliexpress_*` doc ID **বদলাবে না** (কার্ট, অর্ডার, রিভিউ, মার্কেটিং এগুলোর দিকে পয়েন্ট করে)।
2. সাপ্লায়ার/খরচের সব ফিল্ড **`product_sources/{productId}`**-এ যাবে, শুধু অ্যাডমিন পড়তে/লিখতে পারবে। পাবলিক প্রোডাক্ট থেকে মুছে যাবে। **এটাই প্রথম অগ্রাধিকার।**
3. নতুন ইমপোর্ট এখন থেকে **নিরপেক্ষ (random) doc ID** পাবে।
4. ২২৬টা প্রোডাক্টেরই স্লাগ হবে, `product_slugs/{slug}` রিজার্ভেশন দিয়ে। **সাফিক্স শুধু collision হলে।**
5. একই নামের প্রোডাক্ট (Vim Bar, Coca-Cola, Radhuni Chilli ইত্যাদি) ডুপ্লিকেট নয়, আলাদা সাইজ। কিছু মোছা হবে না। নাম মিলে গেলে আগে সাইজ, সাইজও না থাকলে বা একই হলে তবেই ৪ অক্ষরের স্থির সাফিক্স।

## ১. সাপ্লায়ারের তথ্য: `product_sources`
- ফিল্ডের তালিকা: [functions/catalog/productSource.js](../../functions/catalog/productSource.js) `PRIVATE_SOURCE_FIELDS` (৩৯টা), আর ভ্যারিয়েন্টের `sourceSkuId` → `product_sources.variantSkus[variantId]`। [firestore.rules](../../firestore.rules)-এর `privateSourceFields()`-এ একই তালিকা; একটা টেস্ট দুটো মিলিয়ে দেখে।
- পাবলিক থাকে শুধু যা কাস্টমার দেখে: দাম, স্টক, `deliveryDays/MinDays/MaxDays`, আর নতুন `isImported: true` (চ্যাটবট "বিদেশ থেকে আমদানি" বলে, সাপ্লায়ারের নাম নয়)।
- সার্ভার কোড (sync, unsaleable, variant refresh, image backfill) **merged view** দেখে (প্রোডাক্ট + source record), আর লেখে `writeProduct()` দিয়ে, যা আপডেট ভাগ করে দুই জায়গায় লেখে ([productSourceStore.js](../../functions/catalog/productSourceStore.js))। মূল লজিক বদলায়নি।
- মাইগ্রেশনের আগেও নতুন কোড চলে (ফিল্ড তখনো প্রোডাক্টে থাকলে সেখান থেকে পড়ে)।
- Rules: `products`-এ কোনো ক্লায়েন্ট (অ্যাডমিন অ্যাপসহ) এই ফিল্ড বা `urlSlug`/`previousSlugs`/`urlSlugAssignedAt` বদলাতে পারে না; এগুলো শুধু Cloud Functions লেখে। অ্যাপের সব প্রোডাক্ট `set()` `merge: true` দিয়ে, তাই সাধারণ সেভে সমস্যা নেই।
- অ্যাডমিন অ্যাপ: প্রোডাক্ট ডায়ালগের "AliExpress Source" বক্স `product_sources` থেকে পড়ে। **শুধু admin/superAdmin role** পড়তে পারে; `products.edit` পারমিশনওয়ালা staff বক্সটা দেখবে না।

## ২. অর্ডার: `order_sources/{orderId}`
- কাস্টমারের অ্যাপ আর কোনো সাপ্লায়ার ফিল্ড অর্ডার বা কার্টে লেখে না।
- `onNewOrderCreated` প্রতিটা আইটেমের সোর্সিং (`sourceProductId`, `sourceSkuId`, `aliExpressLink`) `order_sources`-এ লেখে (অ্যাডমিন শুধু)। পুরনো অ্যাপ বিল্ড যদি আইটেমে ফিল্ড লেখে, trigger সেগুলো সরিয়ে দেয় (status বদলায় না, তাই `onOrderStatusUpdated` কিছু করে না)।
- অ্যাডমিন অর্ডার পেজ লিংক `order_sources` থেকে দেখায়, পুরনো অর্ডারে আইটেমের লিংক থাকলে সেটাও।

## ৩. নতুন ইমপোর্ট: নিরপেক্ষ ID
- Dedupe key: `product_import_keys/{sha256(source:sourceProductId)[0:32]}` → `productId` (অ্যাডমিন শুধু)। এটা পুরনো ID-র একই digest, তাই পুরনো ১০৭টার key মাইগ্রেশনে বসে।
- ইমপোর্টের ক্রম (একটা transaction-এ): key → পুরনো `imp_*` ID (যদি থাকে) → নতুন random ID। দুটো ইমপোর্ট একসাথে এলেও একটাই প্রোডাক্ট হয়।
- দুটো ইমপোর্ট endpoint আর search/discovery একই `saveImportedProduct()` ব্যবহার করে।

## ৪. URL স্লাগ
`/product/{urlSlug}`, যেমন `/product/coca-cola-soft-drink-refreshing-carbonated-beverage-1-ltr`। কোড: [functions/catalog/productSlug.js](../../functions/catalog/productSlug.js)।
- শুধু প্রোডাক্টের নাম থেকে: ছোট হাতের ASCII, `-`, সর্বোচ্চ ৬০ অক্ষর, শব্দের সীমায় কাটা। শুরু/শেষে "for/with/and…" থাকে না।
- **উৎস বা সাপ্লায়ারের কোনো চিহ্ন নয়:** aliexpress, ali, imp, china, cainiao, alibaba… বাদ; doc ID-র কিছু নয়।
- বাদ যায় এমন ফিলার: Fully Tested, 100% Working, 100% Original, Original, Genuine, Hot Sale, New Arrival, Fast/Free Shipping, High Quality, Brand New, AAA+++।
- `+` শুধু মডেলের নামের অংশ হলে "plus" (`S21+` → `s21-plus`, `Note 10+`); "iPhone 11+Face ID"-এর `+` শুধু বিভাজক। `&` → and, `%` → percent, `6.3''` → `6-3-inch`।
- বাংলা ইংরেজি অক্ষরে লেখা হয়; একক: কেজি→kg, গ্রাম→g, মিলি→ml, লিটার→l, পিস→pcs; বাংলা অঙ্ক → 0-9।
- **Collision** (আরেকটা প্রোডাক্টের একই স্লাগ):
  1. লম্বা কাট (৮০ পর্যন্ত), যদি তাতে আলাদা হয়;
  2. **সাইজ** (`strength` ফিল্ড: "1 ltr" → `1-ltr`, "400 ml" → `400ml`, "500gm" → `500g`);
  3. নাম যেখানে আলাদা সেই শব্দ (iPhone 11 board: `…-with-face-id` / `…-without-face-id`)। শুধু একটা বাড়তি শব্দের পার্থক্য হলে (S21 Ultra display) সেই শব্দটা যার নামে আছে সে পায় (`…-s21-ultra-5g-digitizer`), অন্যটা সাধারণ স্লাগ রাখে (মালিকের সিদ্ধান্ত ২০২৬-১১-১৯);
  4. শেষে ৪ অক্ষরের স্থির সাফিক্স (doc ID-র hash; ID নিজে নয়)।
  ব্যাকফিলে একই নামের গ্রুপের **সবাই** সাইজ পায় (শুধু পরেরটা নয়)। নতুন প্রোডাক্টের নাম হুবহু আগের কোনো প্রোডাক্টের মতো হলে খালি নামটা কখনো পায় না, সরাসরি সাইজ থেকে শুরু।
- ইউনিক: `product_slugs/{slug}` → `{productId}`, transaction-এ রিজার্ভ। রিজার্ভেশন কখনো মোছা হয় না (প্রোডাক্ট মুছলেও), যাতে পুরনো লিংক অন্য প্রোডাক্টে না যায়।
- **নাম বদলালেও `urlSlug` বদলায় না।** স্লাগ বসে: ইমপোর্টের transaction-এ, আর অ্যাপ/ভেন্ডরের নতুন প্রোডাক্টে `onProductCreated`-এ (মার্কেটিং লিংকের আগে)। এই লেখায় `urlSlugAssignedAt` স্ট্যাম্প থাকে, তাই `onProductStockUpdated` কিছু পাঠায় না।
- পরে অ্যাডমিন স্লাগ বদলাতে চাইলে: পুরনোটা `previousSlugs`-এ, পুরনো URL 301। (resolve কোড তৈরি; অ্যাডমিন UI এখনো নেই।)

## ৫. Resolve আর 301 (`productSeo` ও অ্যাপ)
`firebase.json`-এর `/product/**` → `productSeo` আগের মতো। ক্রম:
1. `urlSlug == path` → 200, প্রোডাক্ট পেজ।
2. `previousSlugs array-contains path` → **301** বর্তমান স্লাগে।
3. path কোনো doc ID (পুরনো `imp_aliexpress_…` বা অন্য প্রোডাক্টের ID) আর প্রোডাক্টের স্লাগ আছে → **301**; স্লাগ না থাকলে 200।
4. কিছু না মিললে 404 (app shell, noindex)।
- 301-এ `Cache-Control: public, max-age=3600`, query string থাকে (`?ref=fb`)।
- অ্যাপের `ProductSeoLoaderPage` একই ক্রমে খোঁজে; পুরনো key দিয়ে খুললে address bar-এ স্লাগ URL বসায়।

## ৬. যেখানে লিংক বানানো হয়
- Functions: [catalog/productUrl.js](../../functions/catalog/productUrl.js) (`productUrlFor`, `productPath`, `productPublicUrl`) → মার্কেটিং payload, ইমপোর্ট রেসপন্স, `productSeo` canonical/og:url/JSON-LD, related-products লিংক, ক্যাটাগরি পেজের JSON-LD, sitemap, চ্যাটের উত্তর।
- অ্যাপ: `ProductService.productPath/productUrl` → product card, শেয়ার, মার্কেটিং কিউ, নোটিফিকেশন, web SEO (canonical, og:url)।
- JSON-LD `sku` আর কখনো doc ID নয়: নিজস্ব `sku`, নইলে `urlSlug`।

## ৭. মাইগ্রেশন: `functions/scripts/migrateProductSources.js`
ডিফল্ট dry-run, `--apply`-এর আগে `tools/backfill/`-এ JSON ব্যাকআপ (যা মোছা বা বদলানো হবে তার পুরনো মান)। প্রতিটা প্রোডাক্ট/অর্ডার নিজের transaction-এ, আবার পড়ে। আবার চালালে শুধু বাকিটা করে।
1. প্রাইভেট ফিল্ড + `sourceSkuId` → `product_sources` (সেখানে নতুন মান থাকলে সেটাই থাকে), প্রোডাক্ট থেকে মুছে; `isImported: true`।
2. ১০৭টা import key।
3. ২২৬টা `urlSlug` + রিজার্ভেশন।
4. অর্ডারের আইটেম থেকে সাপ্লায়ার ফিল্ড → `order_sources`।
5. কার্ট আইটেম থেকে একই ফিল্ড মোছা।

লাইভ dry-run (২০২৬-১১-১৯): ১০৭ প্রোডাক্টে ফিল্ড সরানো, ২২৬ স্লাগ, ১০৭ key, ০ conflict, ৬টা অর্ডার আইটেম, ১টা কার্ট আইটেম।
Emulator-এ (লাইভ ডেটার কপি) `--apply`: ২২৬/২২৬, ৬/৬, ১/১; পরে ০টা প্রোডাক্টে প্রাইভেট ফিল্ড, ০টা স্লাগ ছাড়া।

## ৮. সাপ্লায়ারের লেখা: `functions/scripts/cleanSupplierText.js` (মালিকের সিদ্ধান্ত ২০২৬-১১-১৯)
- `description`, `overview`, `banglaDescription`, `metaDescription`: সাপ্লায়ার/উৎস দেশের নাম আছে এমন বাক্য বাদ (`mentionsSupplier`: AliExpress, China, Cainiao, Taobao, 1688, চীন), লাইন ধরে; বাকি লাইন হুবহু থাকে। পুরো অংশটাই সাপ্লায়ারের বাক্য হলে তার ছোট হেডিং ("Shipping Method")-ও যায়।
- `overviewHtml`: একই, শুধু লেখার অংশে; ট্যাগ আর ছবি অপরিবর্তিত।
- `seoTags`, `searchKeywords`: সাপ্লায়ারের নামওয়ালা এন্ট্রি বাদ। `suggestedCategory: "AliExpress"` → প্রোডাক্টের আসল `category`।
- বদলায় না: ভ্যারিয়েন্টের নাম ("… / China Mainland"; অ্যাপ দেখানোর সময় ship-from অংশ বাদ দেয়), specification (দেখানোর সময় লুকানো), অন্য seller boilerplate (দেখানোর সময় `cleanCustomerText` বাদ দেয়)।
- লাইভ dry-run: ৬৮টা প্রোডাক্ট (description ৬৫, overview ৬৬, overviewHtml ৬৬, seoTags ২৫, searchKeywords ২৫, suggestedCategory ২৫, metaDescription ২)।

## ৯. ছবি: `tools/media/migrateSupplierImages.js` (মালিকের সিদ্ধান্ত ২০২৬-১১-১৯)
- `sharp` লাগে, তাই আলাদা ফোল্ডার (`tools/media/package.json`), functions deploy-এ যায় না। চালানোর আগে `cd tools/media && npm install`।
- প্রতিটা আলাদা ছবির URL (image, imageUrl, images[], ভ্যারিয়েন্টের ছবি, `overviewHtml`-এর `<img>`): ডাউনলোড → মূল ফাইল `backups/supplier_images/{key}.{ext}` (প্রাইভেট, storage.rules default deny) → `product_images/{key}.webp` (পাবলিক, download token, ১ বছর immutable cache)। `{key}` = URL-এর sha256-এর প্রথম ২৪ hex; পাথে প্রোডাক্ট ID বা সাপ্লায়ারের নাম নেই।
- alicdn সব সময় WebP পাঠায় (URL `.jpg` হলেও, Accept header যাই হোক), তাই "মূল ফাইল" = alicdn যা দেয়। আগে থেকেই WebP আর ≤১৬০০px হলে বাইট হুবহু রাখা হয় (আবার lossy encode করলে মান কমে); বাকিগুলো WebP-তে রূপান্তর, সর্বোচ্চ ১৬০০px চওড়া।
- তারপর প্রোডাক্টের সব ফিল্ডে পুরনো URL → নতুন URL (`og:image` এখান থেকেই আসে)। URL map `tools/backfill/`-এ, মাঝপথে থামলে আবার চালালে বাকিটা করে।
- লাইভ dry-run: ১০৭টা প্রোডাক্ট, ১৩০৪টা আলাদা ছবি, মোট ৯২.৬ MB, সবগুলো পাওয়া যায়। Emulator-এ পুরো চালানো: ১৩০৪/১৩০৪, ৯২.৬ → ৮৮.৭ MB, ০টা ব্যর্থ।
- অর্ডার আর কার্ট আইটেমের `image` ফিল্ড এখনো পুরনো URL রাখতে পারে (কাস্টমার নিজের অর্ডারে দেখে)। মালিক চাইলে আলাদা ধাপ।

## ১০. স্ক্রিপ্টের লেখা আর trigger
সব মাইগ্রেশন লেখায় স্ট্যাম্প থাকে (`urlSlugAssignedAt` বা `systemWriteAt`), যাতে `onProductStockUpdated` কিছু না করে। দরকার কারণ ইমপোর্ট হওয়া প্রোডাক্টে `lowStockAlerted` ফিল্ড নেই: স্টক ≤ ৫ থাকলে যেকোনো লেখায় অ্যাডমিনের কাছে "Low Stock" নোটিফিকেশন যেত। `systemWriteAt` rules-এ server-owned।

## ১১. Sitemap-এ ৮৩টা কেন (১৯৬টা active)
বাগ নয়। বাকি ১১৩টা প্রোডাক্টের ক্যাটাগরি `categories/`-এ নেই (Cooking ৪৮, Home & Cleaning ১৫, Fruits & Vegetables ১৫, Beverages ১০, Grocery ৯, LPG ৬, Other ৫, Watches ২, Popular/Food Items/Baby food ১টা করে)। শপও এগুলো দেখায় না (`isShopVisibleProduct`), তাই sitemap শপের সাথেই মেলে (audit D1, সিদ্ধান্ত বাকি)। একটা পার্থক্য ঠিক করা হয়েছে: sitemap আগে `approvalStatus` দেখত না; এখন শপের মতোই `isActive === true` আর `approved` লাগে (আজকের ডেটায় সংখ্যা একই, ৮৩)।

## ১২. লোকাল যাচাই (deploy ছাড়া)
- `flutter build web --release --pwa-strategy=none --dart-define=USE_FIREBASE_EMULATORS=true -o <abs>/build/web_emulator`: অ্যাপ Firestore emulator (127.0.0.1:8080) পড়ে। `tools/web/finalize_web_build.js` এমন build deploy করতে দেয় না (`useFirestoreEmulator("127.0.0.1",8080)` থাকলে predeploy ব্যর্থ)।
- Firestore + Storage emulator-এ লাইভ ডেটার কপি (settings/app_secrets আর অর্ডারের ব্যক্তিগত তথ্য ছাড়া), তিনটা মাইগ্রেশন `--apply`, তারপর firebase.json-এর মতো rewrite করা লোকাল সার্ভার (`productSeo`/`sitemap` in-process) আর headless Chrome দিয়ে স্ক্রিনশট + network log।

## ক্রম (প্রতিটা ধাপে আলাদা অনুমতি)
1. functions deploy (নতুন কোড মাইগ্রেশনের আগে-পরে দুইভাবেই চলে) + Firestore rules deploy। (storage.rules বদলায়নি।)
2. **লাইভে যেকোনো `--apply`-এর আগে পুরো Firestore export:** asia-south1-এ একটা ব্যাকআপ বাকেট (এখন নেই; একমাত্র সাধারণ বাকেট US-CENTRAL1-এ, ডেটাবেস asia-south1-এ) — `gcloud storage buckets create gs://chalakchar-mart-firestore-backups --location=asia-south1 --project chalakchar-mart`, তারপর `gcloud firestore export gs://chalakchar-mart-firestore-backups/2026-11-<dd>-pre-supplier-migration --project chalakchar-mart`। পাথ মালিককে জানানো হবে, শেষ হওয়া (`gcloud firestore operations list`) যাচাই করে তবেই apply।
3. লাইভ মাইগ্রেশন, এই ক্রমে, প্রতিটা dry-run → অনুমতি → `--apply`: `migrateProductSources.js` → `cleanSupplierText.js` → `tools/media/migrateSupplierImages.js`।
4. hosting (অ্যাপ)। শুধু `wip/audit-step1` থেকে, নিজস্ব preview channel আগে।
5. Search Console-এ sitemap আবার জমা; কয়েকটা পুরনো লিংক (FB পোস্টেরটাসহ) URL Inspection-এ 301 যাচাই।
6. যাচাই: কার্ড, শেয়ার, চ্যাটের লিংক; কার্ট, চেকআউট, অ্যাডমিন অর্ডার পেজের AliExpress লিংক; sync একবার; কয়েকটা প্রোডাক্টে ছবি Storage থেকে।

## যা এখনো বাকি
- **ভ্যারিয়েন্ট ID:** ১০৭টা প্রোডাক্টের ৮১৭টা ভ্যারিয়েন্টের `id`/`variantId` = AliExpress SKU নম্বর। মালিকের সিদ্ধান্ত (২০২৬-১১-১৯): বদলানো হবে না।
- পুরনো ১০৭টা doc ID (`imp_aliexpress_…`) সিদ্ধান্ত অনুযায়ী থাকছে: URL, HTML, meta, sitemap-এ আর আসে না, কিন্তু অ্যাপের Firestore network traffic-এ (প্রোডাক্ট ডকের নাম, কার্ট/অর্ডারের `productId`) দেখা যায়।
- `specifications`-এ "Origin: Mainland China" (১০৭) আর ৫টায় "Aliexpress Standard Shipping": দেখানোর সময় লুকানো, ডেটায় আছে।
- অর্ডার/কার্ট আইটেমের পুরনো `image` URL (উপরে ৯)।
- অ্যাডমিনের স্লাগ বদলানোর UI (`previousSlugs`)।
- `products.edit` পারমিশনওয়ালা staff AliExpress বক্স/লিংক দেখবে না — মালিক ঠিক আছে বলেছেন।
