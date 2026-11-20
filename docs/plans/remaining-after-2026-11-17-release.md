# বাকি কাজ — ১৭ নভেম্বর ২০২৬-এর লাইভ রিলিজের পর

## লাইভে কী আছে (17 Nov 2026, 03:34 UTC)
- hosting আর ১৩টা function, commit `afff7c3` (branch `wip/notifications`, worktree `c:\FlutterProjects\chalakchar_mart_notif`)।
- function-গুলো: aliexpressBackfillVariantImages, aliexpressDiscoverProducts, aliexpressImportByUrl, aliexpressProductDetails, aliexpressScheduledSync, aliexpressSearchImport, aliexpressSyncAllProducts, importAliExpressProduct, onOrderStatusUpdated, onProductCreated, onProductStockUpdated, productSeo, resolveProductCategory।
- ইচ্ছা করে দেওয়া হয়নি: `aliexpressScheduledDiscover`। deploy করলে বন্ধ রাখা Scheduler আবার চালু হয়ে যাবে।
- এতে আছে: নোটিফিকেশন (চাপলে খোলে, বাংলা, মোবাইলে ঘণ্টা, পছন্দের অপশন), লগইন (নিজের হোস্টে authDomain, F4 ঠিক, COOP, account linking, বাংলা error), Play-র permission ঠিক করা, My Orders আর Track Order বাংলায়, Related products, seller-text filter।

## লাইভে গেছে, ১৭ নভেম্বর ২০২৬
- **04:18 UTC:** hosting আর `productSeo`, commit `cfb3c87`। এতে seller-text ফিল্টার। release `1794889137159000`, version `839ee55692e46666`। আগেরটা ছিল `2e00227653efefe9`।
- **16:14 UTC:** শুধু hosting, commit `ed6859a` (`53a9e36`, `fd1be87`, `ed6859a`)। release `1794932050383000`, version `847c033e7daffde8`। rollback: `firebase hosting:clone chalakchar-mart@839ee55692e46666 chalakchar-mart:live`।
  - সার্চ, সাজেশন, vendor shop, marketplace, category পেজ আর হোমের category সারি এখন একটাই নিয়ম মানে (`lib/utils/shop_visibility.dart`)।
  - সাজেশন সব দেখানোযোগ্য পণ্যের মধ্যে খোঁজে। vendor shop-এ "আরও দেখুন"। category-র তালিকা ১০ মিনিট cache-এ থাকে।
  - AliExpress import-এর সিদ্ধান্ত এখন শুধু সার্ভারের তালিকা দিয়ে হয়।
  - লাইভে যাচাই: খালি সার্চে 83, "motorola" সাজেশন আসে, category পেজ 52 / 25 / 6, `/category/cooking` খুললে "not found", পণ্যের পেজ খোলে।

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

## মালিকের সিদ্ধান্ত (১৭ নভেম্বর ২০২৬)
- **19:** এখনকার নিয়ম থাকবে। সার্চের শব্দ কোনো লুকানো পণ্যের সাথে মিললেও "মিলেছে" ধরা হবে, তাই AliExpress import চলবে না।

## 14b নিরাপত্তা: ধাপ A-র পরে বাকি (মালিক, ১৭ নভেম্বর)
- মালিক Meta-র নতুন চাবি বানানোর (rotate) পর `loadMarketingSettings`-এর
  fallback সরানো: function তখন শুধু `settings/app_secrets` পড়বে, settings/app
  থেকে না। (`functions/settings/socialSecrets.js`, `lib/utils/social_secrets.dart`)
- deliveryEarnings লেখা আর rider-এর মোট আয় ও COD বাকি বাড়ানো function-এ সরানো।
  এখন rider-অ্যাপ নিজে লেখে, rules যাচাই করে। পরে করা হবে।
- জেনেবুঝে নেওয়া সিদ্ধান্ত: staff (পণ্যের কাজ) আর অর্ডার বদলাতে পারবেন না।
  দরকার হলে তাঁকে `orders.edit` বা `orders.confirm` অনুমতি দিতে হবে।
- ধাপ B: vendors আর deliveryPartners-এর সবার দেখার তথ্য আর গোপন তথ্য আলাদা করা।
  ধাপ C: ছবির লিংকের বদলে path রাখা, আর পুরোনো download token বাতিল করা।
- rider-অ্যাপ (`delivery_partner_dashboard_page.dart`, `_createEarning`): ধাপ ৪
  (মোট আয় যোগ) হয়ে ৫ (চিহ্ন) হারালে "Sync earning" ধাপ ৪-এ আটকে যায়, চিহ্ন বসে
  না। rules দুবার যোগ হতে দেয় না, কিন্তু অ্যাপের উচিত `deliveryPartners.
  lastSyncedOrderId == orderId` হলে ধাপ ৪ বাদ দিয়ে সরাসরি ৫ করা। আর ধাপ ৪
  হারানোর পর অন্য ডেলিভারি sync হয়ে গেলে আগেরটা আর যোগ হয় না (কম গোনা,
  `partnerSynced:false` থেকে যায়)। admin-এ "যোগ না হওয়া আয়" তালিকা দরকার।
  দুটোই আসল সমাধান হলো লেখাটা function-এ সরানো।

## দল ১-এর পরে সবার আগে (মালিক, ১৮ নভেম্বর)
1. **chat লুকানো পণ্যও দেখায়।** `fetchCandidateProductsForChat` (functions/index.js)
   শুধু `isActive` দেখে, `isShopVisibleProduct` দেখে না। ফলে লুকানো category-র পণ্যও
   উত্তরে আসতে পারে। দোকানের একই নিয়ম লাগাতে হবে, emulator বা unit test সহ।
2. **chat থেকে AliExpress import।** কোনো পণ্য না মিললে chat ওই কথাগুলো দিয়ে
   `aliexpressSearchImport` ডাকে, লগইন ছাড়া, server-এর axios থেকে।
   - ১৮ নভেম্বর নিজের মেশিনে চালিয়ে দেখা: "ডেলিভারি চার্জ কত?", "দোকান কখন খোলা
     থাকে?", "আপনাদের দোকান কোথায়?" chat থেকে পাঠানো হয়। কিন্তু server ইংরেজি
     পণ্যের শব্দ না পেয়ে বাদ দেয় (`no_english_terms`), তাই আসলে import হয় না।
     ইংরেজি সাধারণ প্রশ্ন ("where is your shop", "shop open time") আংশিক মেলে বলে
     পাঠানোই হয় না।
   - গত ৩০ দিনে chat থেকে ৩টা import হয়েছে, সবকটা এখনকার query-চেক বসানোর আগে:
     ১১ নভেম্বর ১টা (০টা পণ্য), ১৪ নভেম্বর ২টা। দ্বিতীয় দিনের একটায় ০টা পণ্য, অন্যটা
     বাংলা প্রশ্ন থেকে ৫টা পণ্য, পাঁচটাই এখন দোকানে লুকানো:
     `imp_aliexpress_050b41d6…`, `…a9acb95d…`, `…12d75d08…`, `…b5cc78b2…`, `…0344343d…`।
   - deploy ছাড়া বন্ধ করার উপায় নেই। settings-এ কোনো flag নেই। rate-limit-এর মান ০
     দিলে আগের মানে ফিরে যায়। Cloud Run-এ বন্ধ করলে search পেজের import-ও বন্ধ হবে।
     chat-এর সব import একই server IP থেকে আসে, তাই ঘণ্টায় ১২টার বেশি হয় না।
   - সমাধান: chat-এর import আলাদা flag-এ রাখা (যেমন `importSettings.chatImportEnabled`,
     না থাকলে বন্ধ), অথবা [TODO 1d] অনুযায়ী in-process আর প্রতি গ্রাহকের সীমা।
3. ছোট ভুল: "delivery charge?" লিখলে "charge" শব্দে charger-এর ৩টা পণ্য উত্তরে আসে।

## দল ২-তে যোগ (মালিক, ১৮ নভেম্বর)
- rules-এ `ownsVendorProduct` function-টা লেখাই নেই (`firestore.rules`, products-এর
  update আর delete)। ফলে vendor নিজের পণ্য বদলাতে বা মুছতে পারে না। কোথায় কোথায়
  ব্যবহার হয় দেখা, function লেখা, আর emulator test।
- লুকানো category-র পণ্যের লিংকে (যেমন Home&Cleaning) spinner ঘুরতেই থাকে।
  "পণ্যটি এখন পাওয়া যাচ্ছে না" দেখানো উচিত। productSeo/SEO-তেও একই জিনিস দেখা।
- Node runtime upgrade, দরকার হলে। এখন সব function `nodejs22`, `engines.node` 22
  (দেখা হয়েছে ১৮ নভেম্বর)।
- **admin-এর জন্য সতর্কতা (অ্যাপ ঠিক না হওয়া পর্যন্ত):** rider-এর আয়ে "যোগ হয়নি"
  চিহ্ন (`partnerSynced:false`) ভুল হতে পারে। ধাপ ৩ আর ৪ সফল হয়ে ৫ হারালে আয়টা
  আসলে মোট আয়ে যোগ হয়ে গেছে, কিন্তু চিহ্ন দেখায় "যোগ হয়নি"। তাই admin চিহ্ন
  দেখে হাতে যোগ করবেন না। আগে rider-এর `totalEarning`, `codDue` আর
  `lastSyncedOrderId` মিলিয়ে নেবেন।
- `socialApi.whatsappBroadcastNumbers` (১টা নম্বর, ১৩ অক্ষর) এখন settings/app-এ সবার
  জন্য খোলা। এটা ব্যক্তিগত নম্বর বা গ্রাহক তালিকা হলে app_secrets-এ সরানো দরকার,
  সঙ্গে function-এর কোডও বদলাতে হবে। মালিক পরে ঠিক করবেন।
- WhatsApp, Messenger আর Instagram-এর webhook-এ ১৮ নভেম্বরের আগের ৩০ দিনে একটাও
  request আসেনি, Meta-র GET যাচাইও না। Meta app publish আর webhook subscription
  দেখা দরকার (মালিকের "পরে" তালিকার Meta app Publish-এর সাথে)।
- `marketing_outbox`-এ ২৩টা `partial_failed` (মূল status `completed`, তাই scheduler
  আর চেষ্টা করে না)। কোন চ্যানেলে আর কেন ব্যর্থ, শুধু পড়ে দেখা
  (`channelResults`, `lastError`)। মালিক পরে দেখবেন। (১৮ নভেম্বরের হিসাব: মোট ১০২টা,
  সব completed; posted ৩৯, not_requested ৪০, partial_failed ২৩।)


## তালিকায় যোগ (মালিক, ১৯ নভেম্বর)
- Admin Settings পেজের লেখায় "saved under settings/app" কথাটা বদলাতে হবে (`lib/pages/admin/app_settings_page.dart:2149`, d7d6761)। চাবি এখন
  `settings/app_secrets`-এ থাকে।
- chat-এর উত্তরে "অর্ডার করুন" বোতামের কথা বলা হয়, কিন্তু সাইটে বোতামের নাম
  "Buy Now" আর "Add to Cart"। উত্তরের লেখা সাইটের সাথে মেলাতে হবে।
- Google OAuth Web client-এ preview channel "secrets"-এর ঠিকানা
  (`chalakchar-mart--secrets-23qyz1jj.web.app`) হাতে যোগ করা হয়েছে। channel মুছে
  ফেলার সময় OAuth client থেকেও এটা সরাতে হবে।

## লাইভ hosting, ১৯ নভেম্বর ২০২৬ (14b ধাপ A)
- **16:06 UTC:** preview channel "secrets" হুবহু লাইভে clone করা হয়েছে
  (`firebase hosting:clone chalakchar-mart:secrets chalakchar-mart:live`)। build
  worktree `../cc_deploy_d7d6761`-এর, commit `d7d6761`। release `1795104383279000`,
  version `5718e9fbf1f0afea`। আগেরটা ছিল `847c033e7daffde8`।
  rollback: `firebase hosting:clone chalakchar-mart@847c033e7daffde8 chalakchar-mart:live`।
- লাইভ hosting এখন d7d6761-এ। d4ead6c এখনো লাইভে যায়নি। পরের hosting deploy HEAD
  থেকে করলে এটা চলে যাবে, তাই সেটা আলাদা সিদ্ধান্ত।

## 14b ধাপ A-র পরে: social চাবি (মালিক, ১৯ নভেম্বর)
১৯ নভেম্বর 16:29 UTC-তে `moveSocialSecrets.js --apply` চলেছে। চাবি এখন শুধু
`settings/app_secrets.socialApi`-এ আছে। backup রাখা আছে `~/cc-backups`-এ, মালিক নিজে মুছবেন।
এখন rules ফেরাতে হলে শুধু `firestore.rules.rollback-keep-secrets` ব্যবহার করতে হবে। function
rollback করলে আগে চাবি settings/app-এ ফেরাতে হবে
([functions-rollback-2026-11-18.md](../security/functions-rollback-2026-11-18.md))।

- **admin-এর social চাবি save শক্ত করা।** অগ্রাধিকার: দল ১-এর সাথে।
  এখনকার সমস্যা: admin পেজ খুললেই token-এর পুরো মান দেখায়
  (`app_settings_page.dart:345-354`)। ঘর ফাঁকা রেখে save করলে app_secrets-এ খালি মান লেখা হয়,
  ফলে চাবি মুছে যায় (`:437-445`)।
  1. admin-only callable `adminSaveSocialSecrets`:
     - server-এ দেখবে ডাকা লোকটার `settings.edit` অনুমতি আছে কি না।
     - শুধু জানা key নেবে (`SECRET_SOCIAL_API_KEYS`)।
     - ফাঁকা বা না-পাঠানো key বাদ দেবে, তাই পুরোনো মান থেকে যাবে।
     - মোছার জন্য আলাদা স্পষ্ট flag, যেমন `clear: ["whatsappAccessToken"]`।
     - log-এ শুধু key-র নাম আর সময়, কোনো মান না।
  2. callable `adminSocialSecretsStatus`: প্রতিটা key-র শুধু "বসানো আছে/নেই", চাইলে শেষ বদলের সময়।
     কোনো মান ফেরত দেবে না।
  3. admin পেজ:
     - app_secrets আর সরাসরি পড়বে না।
     - token-এর ঘর সবসময় ফাঁকা থাকবে, পাশে লেখা "বসানো আছে/নেই"।
     - নতুন মান লিখলেই শুধু সেটা `adminSaveSocialSecrets`-এ পাঠাবে।
     - settings/app-এর save থেকে token পুরো আলাদা থাকবে।
  4. rules: `settings/app_secrets`-এ client থেকে লেখা বন্ধ (`write: if false`)। শুধু function লিখবে।
     client-এর পড়াও বন্ধ করা যায়।
  5. পরীক্ষা: emulator-এ দেখা—ফাঁকা পাঠালে মান থেকে যায় কি না, customer বা অনুমতি ছাড়া admin ডাকলে
     বাতিল হয় কি না, status বা কোনো উত্তরে মান আসে না কি না। তারপর নিজস্ব preview channel-এ চোখে দেখা।
- **`app_secrets.socialApi.tiktokClientSecret` পুরোনো field।** TikTok-এর আসল কাজ চলে Secret Manager-এর
  `TIKTOK_CLIENT_SECRET` দিয়ে। এই field শুধু `apiReady.tiktok` হিসাবে কাজে লাগে
  (`functions/index.js:202`)। `apiReady.tiktok` এই field-এর ওপর নির্ভর না করে Secret Manager-এ secret
  আছে কি না তার ওপর নির্ভর করবে। তারপর field-টা মোছা (dry-run আর backup আগে)। সঙ্গে Flutter-এর
  `kSecretSocialApiKeys` আর rules-এর `secretSocialApiKeys` থেকেও সরানো।

## Meta token বদলানো আর WhatsApp (মালিক, ১৯ নভেম্বর)
- **Meta token এখন:**
  - Facebook আর Instagram: ChalakChar Automation-এর Page token।
  - WhatsApp: ChalakChar Automation-এর System user token।
  - দুটোরই মেয়াদ Never। পুরোনো token বাতিল (Debugger-এ Valid: False)।
  - চাবি আছে শুধু `settings/app_secrets.socialApi`-এ। settings/app-এ কোনো চাবি নেই
    (১৯ নভেম্বর 18:14 আর 18:37 UTC-এর save-এর পর যাচাই করা)।
- **WhatsApp marketing আসলে কাউকে যায় না।**
  - WhatsApp opt-in করা user (`users.whatsappOptIn == true`) এখন ০ জন।
  - তবু admin-এ "queued" দেখায়: ১৯ নভেম্বরের আগের ৭ দিনে ২৯টা item, সবকটায় `eligibleCount 0`,
    `queuedCount 0`। কোড: `enqueueDynamicWhatsAppDeliveries`, `functions/index.js`।
  - `whatsapp_deliveries`-এ কখনো একটাও ডকুমেন্ট তৈরি হয়নি।
  - করণীয়: "queued" দেখানোর আগে `eligibleCount` দেখা, ০ হলে আলাদা status, যেমন
    "no_recipients"। আর opt-in নেওয়ার ব্যবস্থা অ্যাপে কোথায় আছে বা নেই, সেটা খোঁজা।
- **`whatsappWebhook`-এ ১৯ নভেম্বরের আগের ৭ দিনে একটাও request আসেনি** (৩০ দিনেও না, উপরে দেখুন)।
  এটা "Meta app publish আর webhook subscription দেখা" কাজের সাথে যুক্ত।

## TikTok: বন্ধ (মালিকের সিদ্ধান্ত, ১৯ নভেম্বর)
TikTok এখন চালু হবে না। তাই secret বদলানো, deploy বা worktree কিছুই করা হয়নি। পরে চালু করলে নিচের কাজগুলো আগে করতে হবে।
- **Secret Manager-এর `TIKTOK_CLIENT_SECRET` version 1 ভুল।** এতে ৩২ অক্ষরের মানটা পরপর ৪ বার লেখা,
  মোট ১২৮ অক্ষর। সম্ভবত এজন্যই TikTok কখনো connect হয়নি।
  - `tiktok_connections` ০টা।
  - `tiktok_oauth_states`-এ ৩টা চেষ্টা, শুধু ১০-১১ জুলাই ২০২৬-এর।
- **নতুন version বসানো:** `gcloud secrets versions add TIKTOK_CLIENT_SECRET --data-file=- --project chalakchar-mart`
  দিয়ে। secret paste করে Ctrl+D দিতে হবে।
  - `firebase functions:secrets:set` ব্যবহার করা যাবে না। এটা শেষে "destroy the stale version?" জিজ্ঞেস করে,
    আর default উত্তর হ্যাঁ। হ্যাঁ দিলে পুরোনো version চিরতরে মুছে যায়।
  - পুরোনো version পরে শুধু disable করা হবে, destroy না।
- **secret কোন version-এ বাঁধা থাকবে, তা ঠিক হয় deploy-এর সময়।** firebase CLI তখনকার latest version
  বেঁধে দেয়। কোডে (`functions/tiktok/config.js:6`) কোনো version লেখা নেই।
  - তাই নতুন version বসানোর পর চারটা function আবার deploy করতে হবে: `tiktokOAuthCallback`,
    `tiktokTokenRefreshSweep`, `tiktokDisconnect`, `tiktokWebhook`।
  - লাইভে এগুলো চলছে `780f82c`-এর কোডে। এদের `tiktok/` ফোল্ডার d7d6761-এর সাথে হুবহু এক।
- **`tiktokConfirmPublish`, `tiktokGetCreatorInfo` আর `tiktokPublishJobsSweep` token refresh করে, কিন্তু এদের সাথে
  secret বাঁধা নেই।** এরা `ensureFreshAccessToken` ডাকে
  (`tiktok/tokenRefresh.js` → `TIKTOK_CLIENT_SECRET.value()`)। token-এর মেয়াদ ১০ মিনিটের কম থাকলে refresh
  ব্যর্থ হবে। সমাধান: এই তিনটার options-এ `secrets: [TIKTOK_CLIENT_SECRET]` যোগ করা।
- **TikTok অটোমেশন বন্ধ (১৯ নভেম্বর)।** কারণ:
  - TikTok-এর Content Sharing Guidelines নিজের অ্যাকাউন্টে আপলোড করার utility টুল গ্রহণ করে না।
  - audit ছাড়া সব পোস্ট private থাকে।
  - মালিক TikTok portal-এ client secret reset করেছেন। নতুন secret কোথাও বসানো হয়নি।
  - ভবিষ্যতে চাইলে Upload (draft/inbox) পদ্ধতি দেখা যাবে, Direct Post না।
- **`app_secrets.socialApi.tiktokClientSecret` মোছা।** এটা পুরোনো field, আর এর মান ফাঁস হয়েছিল।
  - মোছার আগে dry-run আর backup।
  - সাথে `apiReady.tiktok`-এর নির্ভরতা ঠিক করা (`functions/index.js:202`, এখন এই field দেখে)।
  - Flutter-এর `kSecretSocialApiKeys` আর rules-এর `secretSocialApiKeys` থেকেও নাম সরানো।
- **Marketing Center-এ TikTok পরিষ্কার করা।**
  - ১৯ নভেম্বরে `settings/app.marketingDefaults.tiktok` এখনো true ছিল।
  - `products.marketingChannels.tiktok == true` এমন পণ্য ৯টা। admin-এর পণ্যের ফর্ম এই মানটাই আবার পাঠায়, global switch দেখে না।
  - `marketing_outbox`-এ `channels.tiktok == true` ৫২টা: ৫০টা `skipped_missing_credentials`, ২টা `skipped_not_implemented`। সবকটার status completed।
  - `tiktok_publish_jobs` ০টা।
  - সিদ্ধান্ত লাগবে: পণ্যের TikTok চিহ্ন false করা হবে কি না, পুরোনো item কীভাবে দেখানো হবে, আর admin-এ TikTok-এর ঘর লুকানো হবে কি না।
- **চারটা TikTok function রাখা হবে না মোছা হবে, সিদ্ধান্ত পরে।**
  - চারটা: `tiktokOAuthCallback`, `tiktokTokenRefreshSweep`, `tiktokDisconnect`, `tiktokWebhook`।
  - বাকি TikTok function-গুলোর (মোট ১১টা) সিদ্ধান্তও এর সাথে।
  - Secret Manager-এর version 1 disable বা destroy করা যাবে শুধু function মোছার পরে। নইলে deploy আর নতুন instance ভাঙবে (বিস্তারিত ১৯ নভেম্বরের রিপোর্টে)।

## ধাপ B-এর সিদ্ধান্ত আর নতুন কাজ (মালিক, ২০ নভেম্বর)
- **উঁচু অগ্রাধিকার: commission ledger customer অ্যাপ থেকে না লিখে function-এ নেওয়া।** কোনো vendor-এর পণ্য
  চালুর আগে এটা বাধ্যতামূলক।
  - এখন `cart_page.dart:576` থেকে customer-এর অ্যাপ `VendorCommissionService.createOrderCommissionLedger`
    ডাকে। এটা `vendorCommissions` আর vendor-এর টাকার field লিখতে চায়।
  - rules customer-কে এটা লিখতে দেয় না, আর error চুপচাপ গিলে ফেলা হয়। তাই vendor-এর পণ্য বিক্রি হলেও
    হিসাব তৈরি হবে না। (২০ নভেম্বরে vendor-এর পণ্য ০টা।)
- **মোবাইল অ্যাপে ন্যূনতম version যাচাই (force update)।** এখন না।
- ধাপ B-এর সিদ্ধান্ত:
  - দোকানের পেজে ব্যক্তিগত phone বা address দেখানো হবে না।
  - মূল `vendors` ডকুমেন্টে নতুন public field `shopArea`: শুধু এলাকা বা জেলা, vendor নিজে লিখবে, ঐচ্ছিক।
    থাকলে দোকানের পেজে দেখাবে, না থাকলে কিছু না।
  - যোগাযোগের জায়গায় দেখাবে ChalakChar support।
  - `ownerName` আর `commissionPercent` গোপন।
- **লগইনের সময় platform (web, android) আর অ্যাপের version `users` ডকুমেন্টে লেখা।** force update-এর কাজের সাথে।
  এখন `auth_service.dart:307, 327` শুধু `lastLoginAt` লেখে। ফলে কে কোন platform বা version থেকে আসে, জানা যায় না।
- **সবশেষের `match /{document=**}` read rule আলাদা করে দেখা।** analytics.view বা staff role থাকলে এই rule প্রায় সব
  collection পড়তে দেয়। ধাপ B-তে এটা বদলানো হচ্ছে না, শুধু নতুন private collection আর `vendorWithdrawRequests` বাদ
  যাচ্ছে।
  - নিজস্ব match নেই, তাই staff শুধু এই rule দিয়েই পড়তে পারে। লাইভ collection (২০ নভেম্বরের সংখ্যা):
    `analytics_daily` (১১), `conversations` (৭, গ্রাহকের chat), `delivery_logs` (১), `marketplace_connections` (১),
    `rateLimits` (২৩), `searchImportLog` (৪৮), `system_locks` (২), `whatsappProcessedMessages` (১)।
  - কোডে নাম আছে কিন্তু লাইভে ডেটা নেই: `commissionLedger`, `messages`, `order_sources`, `product_sources`,
    `recommendation_signals`, `reviews`, `vendor_earnings`। এর মধ্যে `order_sources` আর `product_sources`-এর নিজস্ব
    match d4ead6c-এ আছে।
  - আর যেসব collection-এর নিজস্ব match আছে, সেখানে এই rule "বাড়তি অনুমতি" হিসেবে যোগ হয়। কারণ Firestore rules-এ
    যেকোনো একটা allow মিললেই পড়া যায়। ফলে staff role সব collection পড়তে পারে, এই rule-এ যেগুলো বাদ দেওয়া হয়নি।
- **vendor-এর কাগজের token (২০ নভেম্বর):** মালিক console থেকে vendor-এর ৩টা ফাইলের পুরোনো token বাতিল করেছেন।
  vendor ডকুমেন্টের লিংক এখন 403। console নিজে থেকে প্রতিটায় একটা নতুন token বানিয়েছে, যেটা কোথাও লেখা নেই।
  rider-এর ২টা ফাইলে এখনো পুরোনো token আছে, ধাপ C-তে বাতিল হবে।
- **Settings-এ "default commission %" ঘর** (মালিক, ২০ নভেম্বর)। নতুন vendor-এর শুরুর হার এখন কোডে লেখা ১০%
  (`kDefaultVendorCommissionPercent`, audit-step-b-এর `lib/utils/private_profile_fields.dart`)। এটা admin থেকে ঠিক করা
  যাবে। প্রতিটা vendor-এর হার মালিক নিজে admin → Vendors → Edit থেকে বসাবেন। এই ঘর ধাপ B-তে আছে, আর ০% বসালে ০%-ই থাকে।
- **পুরোনো অ্যাপে Profile → "Seller request" চুপচাপ ব্যর্থ হয়।** `profile_page.dart:234` থেকে
  `AuthService.requestSellerAccount` ডাকা হয়, কিন্তু কোনো try/catch নেই।
  - ব্যর্থ হলে dialog খোলা থাকে, কোনো বার্তা দেখায় না।
  - ধাপ B-এর rules লাইভে গেলে পুরোনো অ্যাপে এটা সবসময় ব্যর্থ হবে, কারণ ফোন আর ঠিকানা মূল ডকুমেন্টে যায়।
  - নতুন কোডেও try/catch নেই। পরের Android build-এর আগে বাংলা error বার্তা যোগ করা দরকার।
  - আর vendor বা rider-এর আবেদন ব্যর্থ হলে কারিগরি ভাষায় লাল snackbar দেখায়
    ("Submit failed: [cloud_firestore/permission-denied] …")। এটা সহজ বাংলায় করা দরকার।

## তালিকায় যোগ (মালিক, ২০ নভেম্বর, ধাপ B চলাকালীন)

- **কম অগ্রাধিকার:** Cloud Functions-এর জন্য কম ক্ষমতার আলাদা একটা service account তৈরি করা, আর default compute account থেকে `Editor` সরিয়ে দেওয়া।
  - কারণ: project-স্তরের `Editor` থাকায় compute, App Engine আর cloudservices account `gs://chalakchar-mart-backups`-সহ সব bucket পড়তে পারে। `firebase-adminsdk-fbsvc`-এর `storage.admin`-ও একই কাজ করে।
  - backup bucket-এর জন্য IAM deny policy এখন লাগবে না (মালিকের সিদ্ধান্ত)। soft-delete-এর ৭ দিন থাকবে।
- **কম অগ্রাধিকার:** rider Faruk-এর NID নম্বর আর দুটো NID ফাইল test মান, আসল NID নেই। Faruk আসল rider হলে আসল কাগজ নিতে হবে, নইলে test অ্যাকাউন্ট হিসেবে চিহ্নিত করতে হবে।

## d4ead6c deploy-এর আগে বাধ্যতামূলক (মালিক, ২০ নভেম্বর)

- `product_sources` আর `product_import_keys` (আর d4ead6c-এর বাকি admin-only collection) catch-all `match /{document=**}`-এর বাদের তালিকায় যোগ করা।
  - এগুলো বাদ না দিলে `analytics.view` বা যেকোনো staff role supplier আর cost-এর তথ্য পড়তে পারবে।
  - এর জন্য emulator test লাগবে।
- **নিয়ম:** d4ead6c নিয়ে সিদ্ধান্ত না হওয়া পর্যন্ত rules আর hosting deploy হবে শুধু `audit-step-c` থেকে, `wip/audit-step1` থেকে না। বিস্তারিত `docs/security/rules-backup/README.md`-এ (audit-step-c)।
- **পরে (কম অগ্রাধিকার):** default bucket `chalakchar-mart.firebasestorage.app`-এ uniform bucket-level access চালু করা, তারপর `identity-docs-viewer`-এর objectViewer-এ prefix condition বসানো (`vendors/` আর `delivery_partner_documents/`)।
  - আগে দেখতে হবে কোনো কিছু object-ACL-এর ওপর নির্ভর করে কি না।
  - এটা ৯০ দিনের মধ্যে আবার বন্ধ করা যায়।
