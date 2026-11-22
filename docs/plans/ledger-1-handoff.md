# ledger-1 handoff (vendor commission ledger moved to Cloud Functions)

শেষ আপডেট: ২২ নভেম্বর ২০২৬, ০৩:২৫ UTC। ক, খ আর গ তিনটেই লাইভে। নতুন session এখান থেকে শুরু করতে পারে।

## কোথায় কাজ হচ্ছে

- **Branch:** `ledger-1`
- **Worktree:** `C:\FlutterProjects\cc_ledger1`
- **শুরু হয়েছে:** `audit-step-d` থেকে, তারপর `origin/seo-2` merge করা (`d163a9d`)।
- **d4ead6c এতে নেই।**
- **Push হয়নি।** `wip/audit-step1`-এ merge-ও হয়নি।
- **Commit:**
  - `4f28844` feat: ledger functions, priceCheck, vendor_private-এর balance, rules, অ্যাপের পাতা
  - `d6896c4` fix: `FieldValue` নেওয়া হয় `firebase-admin/firestore` থেকে। Functions emulator-এর `admin.firestore`-এ এটা থাকে না।
  - `4a33805` fix: dashboard-এর টাকা শুধু `vendor_private` থেকে, Withdrawable কার্ডে "Can withdraw ৳X", 360px-এ লেখা দুই লাইনে, `shortOrderId()`
  - `ae1bd0a` fix: 360px-এ লেখা আঁটে (ছোট subtitle, দোকানের নাম দুই লাইনে)
- **অন্য session:** `brand-1` (worktree `../cc_brand1`) লাইভে যাওয়ার আগে `origin/ledger-1` merge করবে। এখন থেকে প্রতিটা hosting build-এ ledger-1-এর কোড থাকতে হবে। না থাকলে vendor আর admin পাতা আবার পুরোনো হিসাবে ফিরে যাবে।

## কী হয়েছে

- **Ledger:** `commission_ledger/{orderId}_{vendorId}`। লেখে শুধু Cloud Functions (`functions/ledger/`)।
  - **`onOrderCreatedLedger`** (অর্ডার তৈরি হলে):
    - দাম আবার নেয় `products/` থেকে, variant থাকলে variant-এর দাম।
    - vendorId নেয় পণ্য থেকে।
    - হার নেয় `vendor_private.commissionPercent` থেকে (০ থাকলে ০%, কখনো বসানো না থাকলে ১০%)।
    - দাম না মিললে `priceMismatch` আর `needsReview` বসায়।
    - **সব অর্ডারে** `orders.priceCheck` লেখে: `{ok, clientTotal, serverTotal, mismatchedItems, checkedAt}`।
  - **`onOrderStatusLedger`** (status বদলালে):
    - কাজ করে শুধু `status` বা `deliveryStatus` বদলালে।
    - `delivered` (admin বা rider), `cancelled`, `returned`/`refunded` ধরে।
    - returned হলে balance ঋণাত্মক হতে পারে, তখন `debtCreated` বসে।
  - প্রতিটা ঘটনা একটা transaction-এ চলে, idempotent, শুধু সামনে এগোয়। ledger-এ `lastEventId` আর `appliedTransitions` থাকে।
  - `createVendorCommissions` আর `vendor_earnings` সরানো হয়েছে। `onOrderStatusUpdated`-এ আর কিছু বদলায়নি (snapshot test)।
- **অ্যাপ:**
  - client থেকে ledger লেখার কোড মুছে ফেলা হয়েছে (`vendor_commission_service.dart`)।
  - admin অর্ডার কার্ডে `priceCheck.ok == false` হলে লাল সতর্কবার্তা দেখায়।
  - vendor-এর Withdraw আর dashboard সব টাকার সংখ্যা নেয় শুধু `vendor_private` থেকে। ঋণ লাল রঙে দেখায়।
  - admin Payouts: payout হয় একটা transaction-এ। balance ০ বা তার কম হলে, অথবা অঙ্কের চেয়ে কম হলে, বোতাম বন্ধ থাকে। reject করলে balance-এ আর টাকা যোগ হয় না (মালিকের অনুমোদিত বদল)।
- **Rules** (লাইভ ২২ নভেম্বর ০৩:২২ UTC, ruleset `be7e9c8a…`):
  - `commission_ledger`: client-এর জন্য শুধু পড়া।
  - `priceCheck`: client কখনো বসাতে বা বদলাতে পারে না। orders-এর customer, vendor আর rider নিয়ম এখন `affectedOnly` ব্যবহার করে।
  - `vendor_private`-এর balance: client লিখতে পারে শুধু payout-এর ধাপে।
  - `vendorCommissions`: নিয়ম সরানো হয়েছে, catch-all-এর বাদের তালিকায় যোগ হয়েছে।

## লাইভে যা গেছে

| কখন (UTC) | কী | id | আগেরটা / rollback |
|---|---|---|---|
| 2026-11-21 17:24 | Firestore export (functions-এর আগে) | `gs://chalakchar-mart-backups/ledger1-fn-20261121-1723` (SUCCESSFUL, ১৯টা ডকুমেন্ট) | — |
| 2026-11-21 17:27 | Functions (`d6896c4`) | `onOrderCreatedLedger`, `onOrderStatusLedger` নতুন; `onOrderStatusUpdated` আপডেট | rollback নিচে দেখুন |
| 2026-11-22 03:15 | Hosting live (`ae1bd0a`, preview `ledger1` থেকে clone) | version `6f1f9ea547faf2d0` | `907a86861815b27e` (seo-2) |
| 2026-11-22 03:22 | Firestore export (rules-এর আগে) | `gs://chalakchar-mart-backups/ledger1-rules-20261122-0321` (SUCCESSFUL, ১৬টা ডকুমেন্ট) | — |
| 2026-11-22 03:22 | Firestore rules (`407ef43`) | ruleset `be7e9c8a-bd31-4dfd-81ea-26114d212272` | `d63b3d4b-a15c-4667-a00a-c19a6733b5ed` (ধাপ D) |

- **Preview `ledger1`:** https://chalakchar-mart--ledger1-cr0u8hep.web.app, version `6f1f9ea547faf2d0`, মেয়াদ ২৮ নভেম্বর পর্যন্ত।
- **Hash:** লাইভের `main.dart.js` = `0ba8553a…`, `main.dart.js_1.part.js` = `8d7c0692…`, preview-এর সঙ্গে হুবহু এক।
- **লাইভের ডেটা (২২ নভেম্বর ০৩:১৫ UTC):** functions deploy-এর পর কোনো অর্ডার আসেনি বা বদলায়নি। `commission_ledger`-এ ০টা ডকুমেন্ট। function-এর log-এ কোনো error নেই।
  - **প্রথম আসল অর্ডার এলে মিলিয়ে দেখতে হবে:** অর্ডারে `priceCheck` লেখা হয়েছে কি না, vendor-এর item থাকলে `commission_ledger` তৈরি হয়েছে কি না, log-এ "commission ledger" লাইন এসেছে কি না।

## Rollback

- **Hosting:**
  ```sh
  firebase hosting:clone chalakchar-mart@907a86861815b27e chalakchar-mart:live --project chalakchar-mart
  ```
  এতে ledger-1-এর পাতা চলে যায়, আর Withdraw পাতা আবার অর্ডার থেকে হিসাব শুরু করে।
- **Functions:**
  - নতুন দুটো সরাতে:
    ```sh
    firebase functions:delete onOrderCreatedLedger onOrderStatusLedger --region asia-south1 --project chalakchar-mart
    ```
  - `onOrderStatusUpdated` আগের অবস্থায় ফেরাতে: `audit-step-d` (worktree `cc_stepd`) থেকে `--only functions:onOrderStatusUpdated`।
  - এতে আবার `createVendorCommissions` চালু হবে, যেটা `vendor_earnings` লেখে।
- **Rules:** Console → Rules → History → `d63b3d4b…` → Restore।
  - অথবা `git show audit-step-d:firestore.rules > firestore.rules`, তারপর `firebase deploy --only firestore:rules`।
- **ডেটা:** export আছে `gs://chalakchar-mart-backups/ledger1-fn-20261121-1723` (bucket-এর lifecycle অনুযায়ী ৩০ দিন থাকে)।

## বাকি কাজ (এই ক্রমে)

1. ~~গ. Rules~~ **হয়ে গেছে** (২২ নভেম্বর ০৩:২২ UTC)।
   - লাইভের source আর repo-র ফাইলের sha256 এক (`5f486232…`)।
   - ওই একই ফাইলে test: rules ১১৮/১১৮, ledger trigger ১১/১১।
   - লগইন ছাড়া পড়লে `commission_ledger`, `vendorCommissions`, `vendor_private` আর `conversations`-এ 403 আসে।
   - **প্রথম আসল অর্ডার এলে মালিক মিলিয়ে দেখবেন:** অর্ডারে `priceCheck` লেখা হয়েছে কি না, আর vendor-এর item থাকলে ledger তৈরি হয়েছে কি না।
2. **Push:** `ledger-1` (২২ নভেম্বর, rules-এর পরে)। আগে গোপন ফাইল খুঁজতে হবে: `.env*`, `key.properties`, keystore, backup JSON, token।
   - `functions/.env.chalakchar-mart` আগে থেকেই repo-তে আছে। এতে কোনো secret নেই। চাইলে নিশ্চিত হতে একবার খুলে দেখে নেওয়া যায়।
3. ~~README~~ **হয়ে গেছে**: deploy টেবিলে functions, hosting আর rules-এর লাইন, "ledger-1" অংশ আর "ধাপ F" অংশ। আগে যা বাকি ছিল:
   - deploy টেবিলে functions (১৭:২৭), hosting (`6f1f9ea547faf2d0`, ০৩:১৫) আর rules-এর id ও সময়।
   - "ledger-1" অংশ।
4. **ধাপ F** (ledger-এর পরের প্রথম কাজ):
   - rules-এর `changedOnly()` আর `changedAny()` শুধু **বদলানো** key দেখে, **নতুন যোগ করা** key দেখে না।
   - `orders`-এ এটা `affectedOnly` দিয়ে ঠিক করা হয়েছে। বাকি জায়গাগুলো এখনো ঠিক হয়নি:
     - `users/{uid}`: ১৪ জায়গায়
     - `vendors/{vendorId}`: ২ জায়গায় (commission বা status-এর মতো নিষিদ্ধ key **নতুন করে যোগ** করলে আটকায় কি না, যাচাই দরকার)
     - `deliveryPartners`: ১
     - `deliveryEarnings`: ১
     - `notifications`: ১
     - helper function-এর ভেতরে আর সংজ্ঞায় ৪
   - প্রতিটার জন্য emulator-এ "নতুন key যোগ" test লিখতে হবে, তারপর `affectedKeys()`-এ বদলাতে হবে।
5. **তালিকার দুটো ছোট কাজ:**
   - vendor dashboard-এ returned বা cancelled অর্ডার এখন "Pending Orders"-এ গোনা হয়। গোনার নিয়ম `vendor_dashboard_page.dart`-এ, যেখানে status `delivered` না হলে `pending`/`processing` ধরা হয়। এগুলো আলাদা করতে হবে।
   - "You owe" কার্ডে শুধু icon আর আইকনের রঙ লাল, সংখ্যাটা (−৳90) কালো। সংখ্যাটাও লাল করতে হবে।
6. **পরে:** `wip/audit-step1`-এ merge। এটা d4ead6c নিয়ে সিদ্ধান্তের পরে। ততদিন deploy হবে `ledger-1` বা পরের branch থেকে, কখনো `wip/audit-step1` থেকে নয়।

## পরীক্ষার সরঞ্জাম

- **Emulator test:**
  - `node tools/rules-test/run.js` (rules, সঙ্গে `ledger.test.js`)
  - `node tools/rules-test/run-ledger.js` (ledger trigger, আসল transaction, ১১টা test)
  - `MOVE_TEST_NODE_MODULES` বসিয়ে দিতে হবে `functions/node_modules`-এ।
- **Functions unit test:** `functions/test/commissionLedger.test.js`
- **Dart test:** `test/vendor_balance_test.dart`, `test/order_id_test.dart`
- **Screenshot-এর পদ্ধতি** (repo-তে নেই):
  - অস্থায়ী emulator hook: `--dart-define=USE_EMULATORS=true`, `demo-chalakchar-ui` project, লগইন `?emuLogin=`।
  - emulator চালাতে হয় একটা অস্থায়ী `firebase.emu.json` আর `functions/.env.demo-chalakchar-ui` দিয়ে, ADC আড়াল করে।
  - কাজ শেষে সব সরিয়ে ফেলা হয়েছে।
  - **জানা কথা:** প্রথম একটা run-এ browser থেকে আসল Firestore আর identitytoolkit-এ একটা করে পড়ার অনুরোধ গিয়েছিল। কারণ পাওয়া যায়নি, পরে আর ঘটেনি। লেখার কোনো অনুরোধ ছিল না।
