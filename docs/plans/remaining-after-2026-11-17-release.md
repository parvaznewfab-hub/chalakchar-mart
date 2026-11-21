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

## Android release-এর প্রথম কাজ (মালিক, ২১ নভেম্বর ২০২৬)
Android release-এর প্রথম কাজ: package-এর নাম com.chalakcharmart.abdullahpharmacy
থেকে বদলানো, Firebase-এ নতুন Android অ্যাপ, SHA, Google আর Facebook লগইন।
অ্যাপ কখনো Play Store-এ প্রকাশ হয়নি, তাই নাম বদলানো যায়। brand-1 branch-এ
বদলানো হয়নি।

এখনকার অবস্থা (brand-1, ২১ নভেম্বর দেখা):
- আসল Android package (`applicationId` আর `namespace`) এখনই
  `com.chalakcharmart.chalakchar_mart`। Firebase-এর Android অ্যাপ
  (`1:1036870421759:android:6504de8a…`) আর `google-services.json`-ও এই নামে, একটা
  SHA-1 সহ।
- `com.chalakcharmart.abdullahpharmacy` আছে শুধু অব্যবহৃত
  `android/app/src/main/kotlin/com/chalakcharmart/abdullahpharmacy/MainActivity.kt`-এ
  (Initial commit থেকে; manifest-এর `.MainActivity` namespace ধরে
  `chalakchar_mart`-এরটা চালায়) আর linux-এর নামে।
- তাই আগে ঠিক করতে হবে: `com.chalakcharmart.chalakchar_mart` রাখা হবে, নাকি নতুন
  কোনো নাম (Play Store-এ প্রথম প্রকাশের পর আর বদলানো যাবে না)।

নাম বদলালে যা যা বদলাতে হবে:
- `android/app/build.gradle.kts`: `namespace` আর `applicationId`।
- `android/app/src/main/kotlin/com/chalakcharmart/<নাম>/MainActivity.kt`: ফোল্ডার আর
  `package` লাইন। অব্যবহৃত `abdullahpharmacy/MainActivity.kt` মুছে ফেলা।
- `android/app/google-services.json`: Firebase-এ নতুন নামে Android অ্যাপ যোগ করে
  নতুন ফাইল।
- `lib/firebase_options.dart`: `android`-এর `appId` (`flutterfire configure` দিয়ে)।
- Firebase-এ নতুন অ্যাপে debug, release আর Play App Signing-এর SHA-1 ও SHA-256।
  Google লগইনের OAuth Android client নতুন package আর SHA দিয়ে।
- Facebook লগইন: Meta app-এর Android settings-এ নতুন package, class name
  (`<নাম>.MainActivity`) আর key hash। `res/values/strings.xml`-এর
  `facebook_app_id` আর `facebook_client_token` একই থাকে।
- `linux/CMakeLists.txt` (`BINARY_NAME`, `APPLICATION_ID`) আর
  `linux/runner/my_application.cc` (জানালার শিরোনাম "abdullahpharmacy")।
- iOS আলাদা: bundle id `com.chalakcharmart.chalakcharMart`
  (`ios/Runner.xcodeproj/project.pbxproj`, `lib/firebase_options.dart`)।
- পরে পরীক্ষা: FCM notification, Google আর Facebook লগইন, ফোন OTP (Play Integrity /
  SHA), release build।

