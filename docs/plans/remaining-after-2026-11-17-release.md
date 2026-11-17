# বাকি কাজ — ১৭ নভেম্বর ২০২৬-এর লাইভ রিলিজের পর

## লাইভে কী আছে (17 Nov 2026, 03:34 UTC)
- hosting আর ১৩টা function, commit `afff7c3` (branch `wip/notifications`, worktree `c:\FlutterProjects\chalakchar_mart_notif`)।
- function-গুলো: aliexpressBackfillVariantImages, aliexpressDiscoverProducts, aliexpressImportByUrl, aliexpressProductDetails, aliexpressScheduledSync, aliexpressSearchImport, aliexpressSyncAllProducts, importAliExpressProduct, onOrderStatusUpdated, onProductCreated, onProductStockUpdated, productSeo, resolveProductCategory।
- ইচ্ছা করে দেওয়া হয়নি: `aliexpressScheduledDiscover`। deploy করলে বন্ধ রাখা Scheduler আবার চালু হয়ে যাবে।
- এতে আছে: নোটিফিকেশন (চাপলে খোলে, বাংলা, মোবাইলে ঘণ্টা, পছন্দের অপশন), লগইন (নিজের হোস্টে authDomain, F4 ঠিক, COOP, account linking, বাংলা error), Play-র permission ঠিক করা, My Orders আর Track Order বাংলায়, Related products, seller-text filter।

## প্রথমে করতে হবে
1. **`wip/audit-step1` এগিয়ে আনা।** এই branch লাইভের চেয়ে পিছিয়ে আছে, শেষ commit `0f16c45`। লাইভ চলছে `afff7c3`-এ। এখান থেকে deploy করলে আজকের সব বদল লাইভ থেকে হারিয়ে যাবে।
   - `afff7c3`-এ `wip/audit-step1`-এর সবকিছু আছে, তাই শুধু fast-forward করলেই হবে: `git merge --ff-only wip/notifications`।
   - ১৭ নভেম্বর permission check এটা আটকে দিয়েছিল। মালিকের অনুমতি নিয়ে করতে হবে।
   - main tree-তে related সেশনের অসমাপ্ত কাজ আছে (`functions/catalog/customerText.js`, `lib/utils/customer_text.dart`, `test/fixtures/seller_text_cases.json`)। আগে ওই সেশনের commit হোক, অথবা আগে ff, তারপর ওদের commit।
2. **Related সেশনের "বাকি লেখা ছাঁকা" commit:** এলে merge করতে হবে। `functions/index.js`-এর require লাইনে conflict হলে সব require থাকবে, আর বদলানো লাইনের নতুন রূপটা নেওয়া হবে।
3. **লাইভে মালিক নিজে দেখবেন** (headless browser-এ লগইন করা যায় না): chalakcharmart.com-এ Google লগইন, "আমার অর্ডার", লগইন অবস্থায় মোবাইলের ঘণ্টা। হোম আর প্রোডাক্ট পেজ (Related সহ) ৩৬০px-এ দেখা হয়ে গেছে, ঠিক আছে।
4. **Play Console আপডেট:**
   - Advertising ID declaration: "No"।
   - Data safety: Location, Device IDs, App activity, Photos কোনোটাই নেই।
   - runtime permission শুধু Notification।
   - ফলে AD_ID, READ_MEDIA আর FB app events সব বন্ধ।

## পরের ধাপ D (অ্যাডমিন)
- live audit-এর admin item B–F আর D1-এর তালিকা। uncategorized grocery আর Horlicks `x33Sx3Va0LktpfnHo1qe` নিয়ে সিদ্ধান্ত।
- needsReview একসাথে মোছা:
  1. লাইভে যে পণ্যগুলো দোকানে দেখায় অথচ `needsReview:true` আছে, তার তালিকা মালিককে দেখানো।
  2. অনুমতির পর dry-run আর backup, তারপর একবারে `needsReview:false` করা, `lastWriteSource` দিয়ে, যাতে কোনো marketing বা নোটিফিকেশন না যায়।
  3. Admin-এ "Mark reviewed" বাটন।
- E2 (needsReview-এর সাথে)।

## পরে (মালিকের তালিকা, এখন নয়)
- Meta অ্যাপ Publish, তারপর Facebook linking পরীক্ষা। linking-এর কোড তৈরি আছে।
- ফার্মেসির লেখা ছাড়া নতুন লোগো, মালিক বানাবেন। বদলাতে হবে:
  - `assets/images/{app_logo,app_icon,logo,chalakchar_mart_logo}.png`
  - Android mipmap আর foreground (`flutter_launcher_icons`)
  - iOS AppIcon
  - `web/favicon.png`, `web/icons/*` (maskable সহ)
  - og:image: `Icon-512` থেকে আসে
  - Play Store-এর 512 আইকন আর 1024×500 feature graphic
- `www.chalakcharmart.com`-এর redirect। এখন এই ঠিকানা খোলে না। চালু হলে OAuth redirect URI-তেও যোগ করতে হবে।
- Splash: Android-এ শুধু সাদা, iOS-এর LaunchImage খালি।
- একরঙা notification icon।

## সিদ্ধান্ত বাকি
- Firestore PITR চালু করা: `gcloud firestore databases update --database="(default)" --enable-pitr`। খরচ কম, ডাটাবেস ছোট।
- Data Access audit log, শুধু Data Write। চাইলে exclusion দিয়ে শুধু `notifications` আর `orders` রাখা।
- স্থায়ী নিয়ম: যেকোনো delete-এর আগে dry-run আর backup।

## গুছিয়ে রাখা
- `chalakchar_mart_notif` worktree আর `wip/notifications` branch ff-এর পরে মুছে ফেলা যায়।
- পুরনো hosting চ্যানেল: notif, related, preview, release (প্রতিটার মেয়াদ ৭ দিন)।

## পরে করার তালিকা (মালিক, ১৭ নভেম্বর; এখন কিছু নয়)
- [x] **সার্চে AliExpress import-এর race** (ঠিক হয়েছে, ১৭ নভেম্বর, ভাগ ১: এখন শুধু সার্ভারের তালিকা দিয়ে গোনা হয়): সার্চ পেজ প্রথমে Firestore-এর নিজের cache থেকে আংশিক তালিকা পায় (`fromCache`)। সেটা দিয়েই "কিছু মিলল কি না" গোনা হয় ([search_page.dart](../../lib/pages/user/search_page.dart), `_handleSettledQuery`)। ফলে লুকানো grocery-র সাথে মেলে এমন শব্দেও ("gas") মাঝে মাঝে import চলে যায়। সমাধান: `snapshot.metadata.isFromCache` হলে গোনা পিছিয়ে দেওয়া।
- সার্চ শব্দের ভেতরে খোঁজে ("rice" লিখলে "price" আসে)। শব্দের শুরু থেকে মেলানো দরকার।
- সার্চ কার্ডে সবচেয়ে কম দামের variant দেখায় (যেমন ৳2,599), কিন্তু পণ্যের পেজে সবচেয়ে দামি variant বাছাই থাকে (৳13,668)। পেজ খুললে কার্ডের দামের variant-টাই বাছাই থাকা উচিত।
- Overview-তে seller-এর after-sales কথা থেকে যায় ("you cannot use it to apply for after-sales service", "100% working well")।
- ছবির ভেতরের লেখা ("Fast Ship in 24 Hours") লেখার ফিল্টার ধরতে পারে না।
- grocery-র ১১৩টা পণ্য ডেটায় `isActive:false` করা হবে কি না, মালিক পরে জানাবেন।
- ChalakChar Mart-এর vendorId `super_admin`, `vendors`-এ কোনো ডকুমেন্ট নেই, তাই vendor shop "Vendor shop not found" দেখায়।
- marketplace section (`MarketplaceHomeSection`) কোথাও বসানো নেই, `/marketplace` route-ও নেই। রাখা হবে না মোছা হবে, সিদ্ধান্ত পরে।
- category পেজের সাব-ক্যাটাগরি গণনা (`liveProductCountsBySubcategory`) এখনো শুধু isActive আর approved দেখে, isShopVisibleProduct দেখে না। এখন পার্থক্য নেই (এমন লুকানো পণ্য ০টা)।
