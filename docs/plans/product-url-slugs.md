# পরিকল্পনা: প্রোডাক্ট লিংক থেকে `imp_aliexpress_…` সরানো

অবস্থা: শুধু পরিকল্পনা, কোনো কাজ হয়নি (২০২৬-১১-১৪)। পরে আলাদা কাজ হিসেবে করা হবে।

## সমস্যা
প্রোডাক্টের পাবলিক লিংক হলো `/product/{Firestore doc id}`, তাই ইমপোর্ট হওয়া প্রোডাক্টের লিংকে সাপ্লায়ারের নাম দেখা যায়:
`https://chalakcharmart.com/product/imp_aliexpress_7f8ff5113ca8bd3651b5452c93cab165`।
লিংকটা কাস্টমার দেখে, আর শেয়ার, FB/IG পোস্ট, WhatsApp, push আর চ্যাটের উত্তরেও যায়।

## মূল সিদ্ধান্ত: doc ID বদলাবে না, শুধু URL বদলাবে
Firestore-এর doc ID বহু জায়গায় রেফারেন্স হিসেবে আছে: `cart` আর `wishlist`-এর doc ID, `orders`-এর আইটেম, `reviews`, `marketing_outbox` (queueId = productId), `product_marketing_scores`, `campaign_analytics`, `notifications.data.productId`, sync (`sourceProductId` → doc ID) আর ইমপোর্টের dedupe (`marketplaceImportDocumentId`)।
ID রিনেম করলে এগুলো সব একসাথে migrate করতে হতো, আর পুরনো অর্ডার ও ইনভয়েস ভাঙার ঝুঁকি থাকত। তাই ID যেমন আছে থাকবে, শুধু **URL-এর জন্য আলাদা `urlSlug` ফিল্ড** যোগ হবে।

## URL-এর গঠন
`/product/{slug}-{code}`, যেমন `/product/netac-sata-ssd-128gb-2-5-inch-k7f3qa`
- `slug`: শুধু প্রোডাক্টের নাম থেকে বানানো, ছোট হাতের অক্ষর আর `-`, সর্বোচ্চ ~৬০ অক্ষর। **স্লাগে উৎস বা সাপ্লায়ারের কোনো চিহ্ন থাকবে না:** "aliexpress", "imp", "china" বা doc ID-র কোনো অংশ নয় (নামের মধ্যে থাকলেও বাদ যাবে)। স্লাগে থাকবে শুধু নাম আর শেষে স্থির কোড।
- `code`: doc ID-র ৬ অক্ষরের স্থির hash (base36)। এতে দুটো প্রোডাক্টের নাম এক হলেও URL আলাদা থাকে, আর নাম বদলালেও কোড একই থাকে।
- `products.urlSlug`-এ পুরো স্ট্রিং রাখা হবে, সাথে single-field index (`where urlSlug ==`)।
- **প্রোডাক্টের নাম বদলালেও `urlSlug` বদলাবে না।** অ্যাডমিন সেভ, sync, AI optimize বা ইমপোর্টের কোনোটাই বিদ্যমান `urlSlug`-এ হাত দেবে না, এতে লিংক স্থির থাকে।
- বদলাতেই হলে (শুধু অ্যাডমিন নিজে) পুরনো স্লাগ `previousSlugs` array-তে যোগ হবে আর পুরনো URL **301** দিয়ে নতুনটায় যাবে। `previousSlugs`-এর কোনো মান কখনো মোছা হবে না।

## পুরনো লিংক → 301 redirect
- `firebase.json`-এ `/product/**` আগে থেকেই `productSeo`-তে rewrite হয়। এতে কোনো বদল লাগবে না।
- `productSeo`-এর resolve ক্রম:
  1. `urlSlug == path` মিললে 200 দিয়ে স্বাভাবিক SEO HTML।
  2. `previousSlugs array-contains path` মিললে **301** দিয়ে বর্তমান slug-এ পাঠানো।
  3. path যদি কোনো doc ID হয় (পুরনো `imp_aliexpress_…` বা হাতে বানানো প্রোডাক্টের ID), আর সেই প্রোডাক্টের `urlSlug` থাকে, তাহলে **301** দিয়ে `/product/{urlSlug}`-এ পাঠানো। `urlSlug` না থাকলে 200, যাতে ব্যাকফিলের আগে কিছু না ভাঙে।
  4. কিছুই না মিললে 404 পেজ।
- 301-এ `Cache-Control: public, max-age=3600` থাকবে। query string রেখে দিতে হবে (যেমন `?ref=`)।
- আগে শেয়ার হওয়া সব লিংক (FB/IG পোস্ট, WhatsApp, push, চ্যাট) এভাবে চলতেই থাকবে।

## অ্যাপ (Flutter)
- একটা helper থাকবে, `ProductService.productPath(product)`, যা `urlSlug` থাকলে `/product/{urlSlug}` দেবে, নইলে `/product/{id}`। নিচের সব জায়গায় এটা বসাতে হবে:
  - [lib/widgets/product_card.dart](../../lib/widgets/product_card.dart)
  - [lib/pages/user/home_page.dart](../../lib/pages/user/home_page.dart)
  - [lib/pages/user/product_details_page.dart](../../lib/pages/user/product_details_page.dart) (শেয়ার লিংক)
  - [lib/services/marketing_queue_service.dart](../../lib/services/marketing_queue_service.dart) (২ জায়গা)
  - [lib/services/web_seo_service.dart](../../lib/services/web_seo_service.dart) (canonical, og:url)
- `main.dart`-এর `onGenerateRoute` → `ProductSeoLoaderPage`: আগে `urlSlug` দিয়ে খুঁজবে, না পেলে doc ID দিয়ে। doc ID দিয়ে খোলা হলে address bar-এ `replaceInPage` দিয়ে slug URL বসাবে।
- রিফ্রেশ করলে বা সরাসরি URL খুললে সার্ভারের 301 সামলাবে।

## Functions-এ যেখানে লিংক বানানো হয়
একটা `productUrl(product)` helper থাকবে (`catalog/productUrl.js`), যা এই জায়গাগুলোতে বসবে:
- `productMarketingPayload` (index.js ~L977)
- ইমপোর্টের রেসপন্স (~L2884, ~L4393)
- `productSeo`-এর canonical, og:url আর JSON-LD `url` (~L6497)
- `sitemap` (~L6836)
- [functions/messaging/replyFormatting.js](../../functions/messaging/replyFormatting.js) (চ্যাট)

helper-টা doc না পেলে ID দিয়ে বানানো পুরনো লিংকে ফিরে যাবে, আর সেটা 301-এ ঠিক হয়ে যাবে।

## ডাটা
- নতুন প্রোডাক্ট: ইমপোর্ট, অ্যাডমিন সেভ আর ভেন্ডর সেভ `urlSlug` বসাবে (শুধু নতুন প্রোডাক্টে, পরে বদলাবে না)। পুরনো অ্যাপ বিল্ডের জন্য `onProductCreated` বা price guard-এর মতো একটা সার্ভার পাহারা ফাঁকা থাকলে বসিয়ে দেবে (`lastWriteSource: "slug_guard"`, কোনো মার্কেটিং যাবে না)।
- `scripts/backfillUrlSlug.js`: আগে dry-run (slug-এর তালিকা, collision দেখানো), তারপর `--apply`। মার্কার বসাবে যাতে trigger কিছু না পাঠায়, যেমনটা price backfill-এ করা হয়।
- Firestore rules: `urlSlug` পাবলিকভাবে পড়া যায় (products-এর read এমনিতেই খোলা)। লেখা শুধু অ্যাডমিন বা সার্ভার করবে, ভেন্ডর শুধু নতুন প্রোডাক্ট তৈরির সময়।

## SEO আর sitemap-এ প্রভাব
- **sitemap:** শুধু canonical slug URL থাকবে, পুরনো ID-র URL থাকবে না।
- **canonical, og:url, JSON-LD:** সব slug URL। পুরনো URL 301 দেয়, তাই Google ধীরে ধীরে slug URL-এ চলে যাবে। কয়েক সপ্তাহ ranking একটু ওঠানামা করতে পারে।
- **Search Console:** deploy-এর পর sitemap আবার জমা দিতে হবে, আর কিছু পুরনো URL "URL Inspection" দিয়ে 301 যাচাই করতে হবে।
- **সোশ্যাল প্রিভিউ:** 301 অনুসরণ করে, তাই পুরনো পোস্টের প্রিভিউ নতুন URL-এ ঠিক থাকবে।

## ক্রম (প্রতিটা ধাপে আগে preview, production আলাদা অনুমতিতে)
1. functions: `productSeo`-এ resolve আর 301 (urlSlug ছাড়া বাকিটা আগের মতো), আর `productUrl` helper।
2. `urlSlug`-এর index, তারপর ব্যাকফিল (dry-run, তারপর `--apply`)।
3. অ্যাপ: `productPath` helper আর রাউট, তারপর hosting।
4. sitemap আর SEO-তে slug URL, তারপর Search Console।
5. যাচাই: কয়েকটা পুরনো লিংক (FB পোস্টের লিংকসহ) 301 দিয়ে ঠিক পেজে যায় কিনা; কার্ড, শেয়ার আর চ্যাটের লিংক; কার্ট আর অর্ডার আগের মতো চলে কিনা।

## ঝুঁকি
- Hash-এর ৬ অক্ষর মিলে যাওয়া (collision) প্রায় অসম্ভব, তবু ব্যাকফিল আর তৈরির সময় unique কিনা যাচাই হবে।
- একটা পুরনো অ্যাপ বিল্ড শেয়ার করলে ID দিয়ে লিংক বানাবে। সেটাও 301-এ ঠিক হয়ে যাবে, তাই সমস্যা নেই।
- `/product/{id}`-কে হার্ডকোড করে রাখে এমন বাইরের কিছু (n8n workflow, পুরনো ক্যাম্পেইন) 301-এর কারণে চলতেই থাকবে।
