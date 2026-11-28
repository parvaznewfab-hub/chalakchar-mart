# লাইভ rules-এর কপি

> **কোথা থেকে deploy করতে হবে** (মালিকের নিয়ম, ২০ নভেম্বর ২০২৬): d4ead6c (product sources আর slugs) নিয়ে সিদ্ধান্ত না হওয়া পর্যন্ত
> **rules আর hosting deploy হবে শুধু `audit-step-c` থেকে** (worktree `C:\FlutterProjects\cc_step_c`), **`wip/audit-step1` থেকে কখনো নয়।**
> কারণ `wip/audit-step1`-এ d4ead6c আছে। সেখানকার `firestore.rules`-এ লাইভে না যাওয়া product নিয়ম আছে, আর hosting-এ আছে d4ead6c-এর কোড।
> তা ছাড়া d4ead6c deploy-এর আগে `product_sources` আর `product_import_keys` catch-all-এর বাদের তালিকায় যোগ করা বাধ্যতামূলক।
> functions-ও শুধু নাম ধরে (`--only functions:<name>`) deploy হবে, `audit-step-c` থেকে।
>
> **২১ নভেম্বর থেকে:** Firestore rules যাবে `audit-step-d` থেকে (worktree `C:\FlutterProjects\cc_stepd`)। এটা `audit-step-c`-এর ওপর তৈরি, তাই d4ead6c এতে নেই।
> hosting-এর মালিকানা এখন SEO session-এর (branch `seo-1`, অন্য worktree)।
> ২১ নভেম্বর ০৩:১৩ UTC-তে লাইভ ছিল `e404b5f237649d80`। ০৩:৫৩:২৩ UTC-তে লাইভে এসেছে `907a86861815b27e`, এটা seo2 preview-এর version।
> ধাপ D থেকে এটা আসেনি, ধাপ D শুধু rules deploy করেছে। hosting rollback-এর লক্ষ্য SEO session ঠিক করবে, `caec3ea7c1d3fd7e`-এ নয়।
> ধাপ D-তে hosting, storage বা functions কিছুই deploy হবে না।

১৭ নভেম্বর ২০২৬-এ লাইভ থেকে নামানো (Firebase Rules API)।

| ফাইল | লাইভ ruleset | লাইভে গেছে |
|---|---|---|
| `firestore.rules.live-2026-11-17` | `ab0bcacc-472b-4897-a1fa-f14cff043e3b` | 2026-11-09 17:39 UTC |
| `storage.rules.live-2026-11-17` | `fc245689-b129-4212-8538-115ae1d3298b` | 2026-07-25 16:59 UTC |

তখন এই কপি আর repo-র `firestore.rules` / `storage.rules` হুবহু এক ছিল।

## Firestore rules আগের অবস্থায় ফেরানো
hosting rollback rules ফেরায় না।

**কোন ফাইল দিয়ে:**
- চাবি সরানোর script (`functions/scripts/moveSocialSecrets.js --apply`) চলার
  **আগে**: `firestore.rules.live-2026-11-17`।
- script চলার **পরে**: সবসময় `firestore.rules.rollback-keep-secrets`।
  পুরোনো rules-এ `settings/{docId}` সবাই লগইন ছাড়া পড়তে পারত। তাই পুরোনো
  ফাইল ফেরালে `settings/app_secrets`-এর চাবিও খোলা হয়ে যাবে। এই ফাইলটা
  পুরোনো rules-ই, শুধু `app_secrets`-এ তালা দেওয়া (emulator test:
  `node tools/rules-test/run.js docs/security/rules-backup/firestore.rules.rollback-keep-secrets`)।

```sh
cp docs/security/rules-backup/firestore.rules.rollback-keep-secrets firestore.rules
firebase deploy --only firestore:rules --project chalakchar-mart
git checkout firestore.rules   # repo-র ফাইল আবার নতুন rules-এ
```

Console থেকে ruleset `ab0bcacc-472b-4897-a1fa-f14cff043e3b` "Restore" করা চলবে
শুধু script চলার আগে।

## 14b ধাপ A-র deploy
| কখন (UTC) | ruleset | আগেরটা |
|---|---|---|
| 2026-11-17 17:29 | `230c48c3-5441-4f8c-b723-904407f211b9` | `ab0bcacc-472b-4897-a1fa-f14cff043e3b` |
| 2026-11-18 03:11 (rider sync-এর দুবার যোগ বন্ধ, `3c0bc1e`) | `c34bd793-1b54-472a-96bd-375352ac8f85` | `230c48c3-5441-4f8c-b723-904407f211b9` |

শুধু শেষ deploy-টা ফেরাতে (চাবি সরানোর script চলার আগে বা পরে, দুই অবস্থাতেই নিরাপদ):
Console → Firestore → Rules → History → `230c48c3…` → Restore।

## 14b ধাপ B (vendor আর rider-এর গোপন তথ্য): rollback
ধাপ B-তে vendor আর rider-এর গোপন তথ্য মূল ডকুমেন্ট থেকে সরে যায় দুটো আলাদা collection-এ:
- vendor-এর ফোন, ইমেইল, ঠিকানা, NID আর trade license-এর লিংক, payout account, commission আর balance যায়
  `vendor_private/{vendorId}`-এ।
- rider-এর NID, ঠিকানা আর ইমেইল যায় `delivery_partner_private/{uid}`-এ।

এই সরানোর কাজটা করে `functions/scripts/movePrivateProfiles.js --apply`।

**কোন ফাইল দিয়ে ফেরানো যাবে:**
- **ধাপ B-এর rules লাইভে যাওয়ার আগে:** এই অংশ খাটে না। উপরের ধাপ A-এর নিয়ম মানতে হবে।
- **ধাপ B-এর rules লাইভে, কিন্তু সরানোর script এখনো চলেনি:**
  - Console → Firestore → Rules → History থেকে ধাপ B-এর আগের ruleset-এ Restore করা যায়।
  - ধাপ A-এর লাইভ ruleset ছিল `c34bd793-1b54-472a-96bd-375352ac8f85`। ধাপ B deploy হলে নিচের টেবিলে সঠিক id লেখা হবে।
  - নিরাপদ বিকল্প হিসেবে `firestore.rules.rollback-step-b` ব্যবহার করা যায়।
- **সরানোর script চলার পরে (2026-11-20 10:15 UTC থেকে):** ফেরানো যাবে শুধু দুটো ruleset-এ:
  - **ধাপ ৬ বাতিল করতে:** ধাপ ২-এর ruleset `c1dedc27-106c-42fa-a55a-bff96182ec15`-এ ফিরতে হবে। এর কপি আছে `firestore.rules.live-step-b-2` ফাইলে (commit `4800640`, লাইভের সঙ্গে হুবহু মেলানো)।
    এই ruleset-এ মূল ডকুমেন্টে গোপন key-এর মান খালি থাকতে পারে, বা আগের মান অপরিবর্তিত থাকতে পারে। নতুন মান লেখা যায় না।
    ```sh
    cp docs/security/rules-backup/firestore.rules.live-step-b-2 firestore.rules
    firebase deploy --only firestore:rules --project chalakchar-mart
    git checkout firestore.rules
    ```
    বিকল্প: Console → Firestore → Rules → History → `c1dedc27…` → Restore। এটা ছাড়া Console থেকে অন্য কোনো ruleset Restore করা যাবে না।
  - **পুরো ধাপ B বাতিল করতে:** আগে `restorePrivateProfiles.js` চালাতে হবে, তারপর `firestore.rules.rollback-step-b` deploy করতে হবে।
    পুরো ক্রম `docs/security/step-b-deploy-plan.md`-এর ধাপ ৫ঙ-তে আছে।
  - **`firestore.rules.rollback-keep-secrets` আর `firestore.rules.live-2026-11-17` তখন আর কখনো ব্যবহার করা যাবে না।** Console-এর
    History থেকে ধাপ B-এর আগের কোনো ruleset Restore করাও চলবে না।
  - কারণ: পুরোনো সব rules-এ `vendor_private` আর `delivery_partner_private`-এর কোনো match নেই। তাই সবশেষের
    `match /{document=**}` দিয়ে analytics.view বা staff role-এর যে কেউ NID, ফোন আর payout account পড়তে পারবে।
    emulator-এ এটা দেখানো হয়েছে: পুরোনো লাইভ rules-এ analyst `vendor_private` পড়তে পারে (200)।
  - `firestore.rules.rollback-step-b` হলো ধাপ B-এর আগের লাইভ rules (`c34bd793`, commit `d7d6761`), শুধু এই তিনটা বদলসহ:
    - `vendor_private` আর `delivery_partner_private` সবার জন্য বন্ধ, admin আর superAdmin-এর জন্যও।
      function বা admin SDK পড়তে পারে।
    - সবশেষের match-এ এই দুটো আর `vendorWithdrawRequests` বাদ।
    - বাকি সব ধাপ B-এর আগের মতো। এর মধ্যে আছে vendor-এর নিজের দোকান save করতে না পারার ভুলটাও
      (ধাপ B-তে `canAnyOf` দিয়ে ঠিক হয়েছে, rollback-এ ফিরে আসে)।
  - এই ফাইল দিয়ে ফেরালে অ্যাপ থেকে কেউ গোপন তথ্য দেখবে না। তাই admin-এর vendor আর rider পেজে ফোন, NID আর
    payout ফাঁকা দেখাবে। তথ্য ফেরাতে হলে script-এর backup থেকে আলাদা কাজ লাগবে।
  - emulator test: `node tools/rules-test/run.js docs/security/rules-backup/firestore.rules.rollback-step-b`। এতে
    `tools/rules-test/rollback_b.test.js` চলে: ১৩ রকম ভূমিকার কেউ private পড়তে বা লিখতে পারে না।

```sh
cp docs/security/rules-backup/firestore.rules.rollback-step-b firestore.rules
firebase deploy --only firestore:rules --project chalakchar-mart
git checkout firestore.rules   # repo-র ফাইল আবার নতুন rules-এ
```

**Storage rules:** ধাপ B-এ `storage.rules`-ও বদলায়। NID আর trade license-এর ফাইল আগে যেকোনো staff role পড়তে
পারত, এখন পারবে শুধু মালিক আর যাদের অনুমতি আছে। Storage rollback করা যায় `storage.rules.live-2026-11-17` দিয়ে।
তাতে আবার যেকোনো staff role ফাইলগুলো পড়তে পারবে, তবে লগইন ছাড়া বা customer কেউ পারবে না। storage-এর test:
`node tools/rules-test/run-storage.js`।

```sh
cp docs/security/rules-backup/storage.rules.live-2026-11-17 storage.rules
firebase deploy --only storage --project chalakchar-mart
git checkout storage.rules
```

| কখন (UTC) | কী | ruleset | আগেরটা |
|---|---|---|---|
| 2026-11-20 07:33 UTC (`4800640`) | Firestore, ধাপ B | `c1dedc27-106c-42fa-a55a-bff96182ec15` | `c34bd793-1b54-472a-96bd-375352ac8f85` |
| 2026-11-20 07:33 UTC (`4800640`) | Storage, ধাপ B | `2ce1afb0-379e-4ad8-82e3-206be53d8a01` | `fc245689-b129-4212-8538-115ae1d3298b` |
| 2026-11-20 09:28 UTC (`4800640`, preview `step-b` থেকে clone) | Hosting live, ধাপ B | version `2ac61cbcad787dc7` | version `5718e9fbf1f0afea` |
| 2026-11-20 10:39 UTC (`b6a44df`) | Firestore, ধাপ B ধাপ ৬ (মূল ডকুমেন্টে কোনো গোপন key নয়) | `cea420b6-9bc7-408e-8f36-e8bb9261277c` | `c1dedc27-106c-42fa-a55a-bff96182ec15` |
| 2026-11-20 13:33 UTC (`4e90295`) | Function `getIdentityDocumentUrl` (নতুন; account `identity-docs-viewer`) | — | ছিল না |
| 2026-11-20 14:06 UTC (`4e90295`, preview `step-c` থেকে clone) | Hosting live, ধাপ C | version `caec3ea7c1d3fd7e` | version `2ac61cbcad787dc7` |
| 2026-11-21 03:53 UTC (`3e71922`, branch `audit-step-d`) | Firestore, ধাপ D (শুধু server-এর collection বন্ধ) | `d63b3d4b-a15c-4667-a00a-c19a6733b5ed` | `cea420b6-9bc7-408e-8f36-e8bb9261277c` |
| 2026-11-21 17:27 UTC (`d6896c4`, branch `ledger-1`) | Functions: `onOrderCreatedLedger` আর `onOrderStatusLedger` নতুন, `onOrderStatusUpdated` আপডেট | — | নতুন দুটো ছিল না |
| 2026-11-22 03:15 UTC (`ae1bd0a`, preview `ledger1` থেকে clone) | Hosting live, ledger-1 | version `6f1f9ea547faf2d0` | version `907a86861815b27e` |
| 2026-11-22 03:22 UTC (`407ef43`, branch `ledger-1`) | Firestore, ledger-1 | `be7e9c8a-bd31-4dfd-81ea-26114d212272` | `d63b3d4b-a15c-4667-a00a-c19a6733b5ed` |
| 2026-11-24 15:52 UTC (`7446f36`, branch `brand-1`, preview `brand1` থেকে clone) | Hosting live, brand-1 (নতুন লোগো, সবুজ রং, favicon 48×48; ledger-1-এর কোডসহ) | version `784e6fe0f776880e` | version `6f1f9ea547faf2d0` |
| 2026-11-24 17:46 UTC (`4c7faf7`, branch `step-f`) | Firestore, ধাপ F (`affectedKeys`, staff-এর ১০০০-সীমা) | `700f57c7-1ebf-41d5-9b8a-4acd8a029b96` | `be7e9c8a-bd31-4dfd-81ea-26114d212272` |
| 2026-11-25 03:56 UTC (`93d2402`, branch `step-g`) | Firestore, ধাপ G (`cashCheck` client লিখতে পারে না) | `438c4999-aa60-440c-aad1-5acd04e03d69` | `700f57c7-1ebf-41d5-9b8a-4acd8a029b96` |
| 2026-11-25 03:59 UTC (`93d2402`, branch `step-g`) | Functions, ধাপ G: নতুন `onOrderCreatedCash`, `onOrderStatusCash` (শুধু এই দুটো) | তৈরি | (ছিল না) |
| 2026-11-25 03:59 UTC (`93d2402`, branch `step-g`, preview `stepg` থেকে clone) | Hosting live, ধাপ G (cart থেকে points লেখা বাদ, admin-এর লাল সতর্কবার্তা) | version `bd482832093239e5` | version `784e6fe0f776880e` |
| 2026-11-27 06:25 UTC (branch `seo-3`, preview `seo3` থেকে clone; বিবরণ `docs/seo/seo-3.md`) | Hosting live, seo-3 (functions `productSeo`, `pageSeo`, `homeSeo`, `sitemap` ০৫:৫৪ UTC) | version `d9aabec1a0fd54c3` | version `bd482832093239e5` |
| 2026-11-27 18:34 UTC (`f4082fa`, branch `step-h`) | Firestore, ধাপ H (reviews শুধু পড়া; referrals-এ client-এর লেখা বন্ধ; `referralCount`; rating-এর ঘর) | `fa5f0e22-cc67-4abc-92c2-d21caad63af0` | `438c4999-aa60-440c-aad1-5acd04e03d69` |
| 2026-11-27 18:42 UTC (`f4082fa`, branch `step-h`) | Functions, ধাপ H: নতুন `submitProductReview`, `deleteProductReview`, `onProductReviewWritten`, `approveReferral`, `rejectReferral`; আপডেট `applyReferralReward`; মোছা `onProductReviewCreated` | — | step-g-এর `applyReferralReward` আর `onProductReviewCreated` |
| 2026-11-27 19:02 UTC (`05702f5`, branch `step-h`, preview `steph` থেকে clone) | Hosting live, ধাপ H (review আর referral-এর পাতা, admin Settings-এর dropdown ঠিক; seo-1/2/3, ledger-1, brand-1 আর ধাপ G-র কোড সহ) | version `1ef9e5dcd524900a` | version `d9aabec1a0fd54c3` |

brand-1-এর hosting ফেরাতে: `firebase hosting:clone chalakchar-mart@6f1f9ea547faf2d0 chalakchar-mart:live --project chalakchar-mart`।
এতে ledger-1-এর পাতা থেকে যায়, শুধু লোগো আর রং আগের মতো হয়।

ধাপ F-এর rules ফেরাতে: `docs/security/rules-backup/firestore.rules.live-be7e9c8a` ফাইলটা `firestore.rules`-এ বসিয়ে `firebase deploy --only firestore:rules`, অথবা console-এ ruleset `be7e9c8a-bd31-4dfd-81ea-26114d212272` আবার release। deploy-এর আগে export: `gs://chalakchar-mart-backups/stepf-rules-20261124-174314` (SUCCESSFUL, ১৭:৪৪ UTC)। লাইভ ruleset-এর sha256 `20b67d56…` = branch-এর ফাইল।

ধাপ H ফেরাতে (উল্টো ক্রমে):
- **functions:**
  - `../cc_stepg` (origin/step-g) থেকে: `firebase deploy --only functions:applyReferralReward,functions:onProductReviewCreated --project chalakchar-mart`।
  - তারপর: `firebase functions:delete submitProductReview deleteProductReview onProductReviewWritten approveReferral rejectReferral --region asia-south1 --project chalakchar-mart`।
  - মনে রাখার বিষয়: পুরোনো `applyReferralReward` আবার `settings/referral` পড়বে, তাই auto-approve আবার কার্যত চালু হবে।
- **hosting** (সবার আগে ফেরাতে হবে): `firebase hosting:clone chalakchar-mart@d9aabec1a0fd54c3 chalakchar-mart:live --project chalakchar-mart`। এতে seo-3 থেকে যায়।
  - মনে রাখার বিষয়: এতে admin Settings পাতা আবার ভেঙে যাবে (`roundingMode` = `"round"`), আর admin পাতা pending referral আবার চিনবে না।
- **rules:** `git show origin/step-g:firestore.rules > firestore.rules`, তারপর `firebase deploy --only firestore:rules --project chalakchar-mart` আর `git checkout firestore.rules`। অথবা Console → Rules → History → `438c4999…` → Restore।
- **deploy-এর আগের export:**
  - rules: `gs://chalakchar-mart-backups/steph-rules-20261127-1833` (SUCCESSFUL, ৯৬৫টা ডকুমেন্ট)।
  - functions: `gs://chalakchar-mart-backups/steph-fn-20261127-1839` (SUCCESSFUL, ৯৬৫টা ডকুমেন্ট)।
- **লাইভে যাচাই:**
  - লাইভ ruleset-এর sha256 `b5b6c626…` = branch-এর ফাইল।
  - লগইন ছাড়া reviews (list আর query) → 200; referrals → 403।
  - `onProductReviewWritten` ACTIVE (`document.v1.written`) হওয়ার পরেই `onProductReviewCreated` মোছা হয়েছে।
  - লগইন ছাড়া `submitProductReview` আর `approveReferral` → 401 UNAUTHENTICATED।
  - function-এর সংখ্যা ৫৯ থেকে ৬৩।
  - **hosting:**
    - preview `steph` (https://chalakchar-mart--steph-g042ixnx.web.app, ১৮:৫৭ UTC, মেয়াদ ৪ ডিসেম্বর) থেকে লাইভে ১৯:০২:৪০ UTC-তে clone।
    - export `gs://chalakchar-mart-backups/steph-hosting-20261127-1852` (SUCCESSFUL, ৯৬৫টা ডকুমেন্ট)।
    - `main.dart.js` (`dfcd337c…`), `main.dart.js_1.part.js` (`37bf8a73…`) আর `flutter_bootstrap.js` (`96043038…`): build, preview আর লাইভ (chalakcharmart.com) তিন জায়গাতেই হুবহু এক।
    - build-এ emulator-এর কোনো চিহ্ন নেই।
    - seo-3-এর অবস্থা আগের মতোই আছে:
      - `www` থেকে মূল ঠিকানায় 301।
      - `/sitemap.xml` 200, ৯১টা URL।
      - X-Robots-Tag: `/login` আর `/cart`-এ `noindex, nofollow`, `/category/doesnotexist`-এ 404 আর `noindex`, `/`, `/about-us` আর category-তে কিছু নেই।

ধাপ G ফেরাতে (উল্টো ক্রমে): hosting `firebase hosting:clone chalakchar-mart@784e6fe0f776880e chalakchar-mart:live --project chalakchar-mart`; functions `firebase functions:delete onOrderCreatedCash onOrderStatusCash --region asia-south1`; rules `firestore.rules.live-700f57c7` বসিয়ে `firebase deploy --only firestore:rules`। deploy-এর আগে export: `gs://chalakchar-mart-backups/stepg-rules-20261125-035525` (SUCCESSFUL, ০৩:৫৬ UTC)। লাইভ ruleset-এর sha256 `eb09b8aa…` = branch-এর ফাইল। functions deploy-এর ঠিক আগে Cash খরচ হওয়া অর্ডার ০টা (মোট ৭টা)। hosting-এর পরে লাইভ আর preview-এর `main.dart.js`, `main.dart.js_1.part.js`, `flutter_bootstrap.js` হুবহু এক; home, category, product, login, admin-এ console error ০; দুই function-এর log-এ warning বা error নেই।

Hosting ফেরাতে:
- ধাপ C-এর আগের অবস্থায় (ধাপ B): `firebase hosting:clone chalakchar-mart@2ac61cbcad787dc7 chalakchar-mart:live --project chalakchar-mart`।
- ধাপ B-এর আগের অবস্থায়: `firebase hosting:clone chalakchar-mart@5718e9fbf1f0afea chalakchar-mart:live --project chalakchar-mart`।
  - সতর্কতা: এই পুরোনো website নতুন rules-এ vendor/rider আবেদন, withdraw আর seller request জমা দিতে পারে না।

Function সরাতে: `firebase functions:delete getIdentityDocumentUrl --region asia-south1 --project chalakchar-mart`।
এতে admin-এর কাগজ খোলা বন্ধ হয়ে যায়, বাকি সব আগের মতো চলে।

## 14b ধাপ C: সম্পূর্ণ (২০ নভেম্বর ২০২৬)

- **IAM (১৩:৩০ UTC-র আশেপাশে):** service account `identity-docs-viewer` তৈরি হয়েছে, মালিকের অনুমোদনে। এর অনুমতি:
  - custom role `identityDocsFirestoreGet` (শুধু `datastore.entities.get`)।
  - default bucket-এ `storage.objectViewer`, condition ছাড়া।
  - নিজের ওপর `iam.serviceAccountTokenCreator`।
  - default compute account-এ কিছু যোগ হয়নি।
- **Function:** `getIdentityDocumentUrl` চলে ১৩:৩৩ UTC থেকে, `identity-docs-viewer` দিয়ে।
  - preview-এ ৫টা কাগজই খুলেছে।
  - লাইভে vendor Trade License খুলেছে ১৪:০৯ UTC-তে। rider Front খুলেছে ১৪:৩৬ UTC-তে, token মোছার পরে।
  - log-এ থাকে শুধু viewerUid, ownerId, kind, which আর at। কোনো path বা URL নেই।
- **Hosting live:** version `caec3ea7c1d3fd7e`, ১৪:০৬ UTC।
- **Download token বাতিল:** ১৪:৩৩ UTC-তে `functions/scripts/revokeIdentityDocTokens.js --apply` চলেছে।
  - vendor-এর ৩টা আর rider-এর ২টা কাগজ, মোট ৫টা ফাইলের প্রতিটিতে ১টা করে token ছিল। এখন ০টা।
  - script-এর নিজের যাচাই আর আবার dry-run, দুটোতেই "No download token left" এসেছে।
  - পুরোনো link-এর 403 আলাদা করে খোলা হয়নি। token ০ থাকাকেই যথেষ্ট প্রমাণ ধরা হয়েছে (মালিকের সিদ্ধান্ত)। কারণ backup ফোল্ডারটা মালিক ইচ্ছা করে মুছেছেন।
  - token-এর মান কোথাও print বা save করা হয়নি। পুরোনো token ফেরানোর কোনো উপায় ইচ্ছা করেই রাখা হয়নি।
- **আবার দেখার উপায়:** `node scripts/revokeIdentityDocTokens.js` (dry-run) চালালে কোনো কাগজে নতুন token তৈরি হয়েছে কি না দেখা যায়। যেমন কেউ Console-এ ফাইল খুলে "Create new access token" চাপলে।
- **বাকি (তালিকায়):**
  - bucket-এ uniform access চালু করে prefix condition বসানো।
  - rider Faruk-এর test কাগজ।

## 14b ধাপ D: শুধু server-এর collection বন্ধ (লাইভ ২১ নভেম্বর ২০২৬, ০৩:৫৩ UTC)

- **Export:** `gs://chalakchar-mart-backups/step-d-20261121-0351`। ০৩:৫২:০২ UTC-তে শেষ, SUCCESSFUL, ১০১টা ডকুমেন্ট।
  - এতে আছে ছয়টা collection আর `messages`।
  - bucket-এর lifecycle অনুযায়ী ৩০ দিন পর নিজে থেকে মুছে যাবে।
- **Deploy:** `firebase deploy --only firestore:rules`, `cc_stepd` থেকে (commit `3e71922`), ০৩:৫৩:৩২ UTC-তে।
  - আগের ruleset ছিল `cea420b6-9bc7-408e-8f36-e8bb9261277c`, এখন `d63b3d4b-a15c-4667-a00a-c19a6733b5ed`।
  - hosting, storage বা functions কিছুই deploy হয়নি।
- **লাইভে যাচাই:**
  - ০৩:৫৪:৩১ UTC-তে customer অ্যাপের AI chat-এ (`chatWithAssistant`, লগইন ছাড়া guestId দিয়ে) একটা সাধারণ প্রশ্ন পাঠানো হয়েছে। HTTP 200 এসেছে, উত্তর এসেছে।
  - `conversations`-এ নতুন thread তৈরি হয়েছে, তাতে customer আর bot-এর ২টা বার্তা লেখা হয়েছে। অর্থাৎ functions আগের মতোই লিখতে পারে।
  - লগইন ছাড়া `conversations`, `marketplace_connections` আর `rateLimits` পড়তে গেলে 403 আসে।
  - admin-এর পাতাগুলো মালিক নিজে দেখবেন। WhatsApp-এর পরীক্ষাও মালিক নিজে করবেন।
- **AliExpress token: বদলানো হবে না** (মালিকের সিদ্ধান্ত, ২১ নভেম্বর ২০২৬)।
  - কারণ: যে ৩টা account token পড়তে পারত (superAdmin, admin আর staff), সবগুলোই বিশ্বস্ত।
  - ধাপ D-র rules দিয়ে ফাঁকটা বন্ধ হয়েছে।
  - নতুন token নেওয়ার পদ্ধতি নিচে লেখা আছে, পরে কখনো লাগলে কাজে আসবে।

**কী বদলেছে (শুধু `firestore.rules`):** ছয়টা collection-এর জন্য নিজের নিয়ম যোগ হয়েছে, `allow read, write: if false`। একই সঙ্গে catch-all `match /{document=**}`-এর বাদের তালিকাতেও এগুলো যোগ হয়েছে:

| collection | কী আছে | কে লেখে বা পড়ে |
|---|---|---|
| `conversations` আর `{id}/messages` | AI সহকারী আর WhatsApp-এর আলাপ, customer-এর নাম, WhatsApp নম্বর, বার্তা | শুধু functions (`upsertConversation`, `writeConversationMessage`, `getRecentConversationMessages`) |
| `marketplace_connections` | AliExpress-এর OAuth `accessToken` আর `refreshToken` | শুধু functions |
| `rateLimits` | প্রতিটি IP-র counter (id-তে IP ঠিকানা) | শুধু functions (`searchImportRateLimit`) |
| `whatsappProcessedMessages` | WhatsApp message id, দুবার না চালানোর জন্য | শুধু functions (`whatsapp/dedupe`) |
| `delivery_logs` | order, rider আর customer-এর id, মোট টাকা | শুধু functions |
| `searchImportLog` | search import-এর query আর অপেক্ষায় থাকা user id | শুধু functions |

- **যাচাই:** ২১ নভেম্বর কোডে খুঁজে দেখা হয়েছে, কোনো অ্যাপ (customer, vendor, rider বা admin) এগুলো পড়ে না।
  - `conversations` customer-vendor বা customer-rider chat নয়। অ্যাপে এমন কোনো chat নেই।
  - customer-এর AI chat HTTP দিয়ে `chatWithAssistant` function ডাকে, Firestore সরাসরি পড়ে না।
- **আগে কী হতো:** catch-all-এর কারণে staff আর `analytics.view` এগুলো পড়তে পারত। AliExpress-এর token-ও এর মধ্যে ছিল।
- **এখন:** superAdmin আর admin-সহ কোনো client role পড়তে বা লিখতে পারে না। Cloud Functions (admin SDK) আগের মতোই চলে।
- **ধরা হয়নি:** `system_locks` আর `analytics_daily` (মালিকের সিদ্ধান্ত, ধাপ E-তে)।
- **Test:** `tools/rules-test/step_d.test.js`।
  - ৭টা path-এর প্রতিটিতে ১০টা role দিয়ে পরীক্ষা হয়: লগইন ছাড়া, ২ জন customer, vendor, rider, staff, ২ জন staff permission-ওয়ালা, admin আর superAdmin।
  - কেউ get, list, create, update বা delete করতে পারে না।
  - ধাপ C-এর rules-এ এই test চালালে ঠিক ৮টা test ব্যর্থ হয়, মানে test-গুলো আসল ফাঁকটাই ধরে।
- **rollback:** ধাপ C-এর rules-এ ফেরা, অর্থাৎ ruleset `cea420b6-9bc7-408e-8f36-e8bb9261277c`।
  - Console → Firestore → Rules → History থেকে Restore, অথবা:
    ```sh
    git show audit-step-c:firestore.rules > firestore.rules
    firebase deploy --only firestore:rules --project chalakchar-mart
    git checkout firestore.rules
    ```
  - ধাপ D-র বদল শুধু নতুন বন্ধ করা নিয়ম, data বদলায় না। তাই ফেরানো নিরাপদ।
  - তবে মনে রাখতে হবে: ফেরালে staff আবার AliExpress-এর token পড়তে পারবে।

### AliExpress token নতুন করে নেওয়া (দরকার হলে; ২১ নভেম্বর সিদ্ধান্ত: এখন বদলানো হবে না)

- **নতুন token নেওয়ার ধাপ:**
  1. `https://chalakcharmart.com/api/aliexpress/start` (function `aliexpressOAuthStart`)-এ import API key দিয়ে GET পাঠাতে হয়: header `x-import-api-key: <key>` অথবা `Authorization: Bearer <key>`।
  2. উত্তরে একটা `authorizationUrl` আসে, ১৫ মিনিট কাজ করে, `force_auth=true` সহ।
  3. browser-এ সেটা খুলে AliExpress seller account দিয়ে অনুমতি দিতে হয়।
  4. callback (`aliexpressOAuthCallback`) `/auth/token/security/create` দিয়ে নতুন access আর refresh token এনে `marketplace_connections/aliexpress`-এ লিখে দেয়।
- **পুরোনো token বাতিল হয় কি না:** কোডে কোনো revoke ডাক নেই।
  - নতুন token আসে আলাদা করে, পুরোনোটা নিজে নিজে বাতিল হয় কি না তা AliExpress-এর নিয়মের ওপর নির্ভর করে। এটা repo বা কোড থেকে নিশ্চিত করা যায় না।
  - নিশ্চিত হতে চাইলে AliExpress Open Platform-এর app console-এ authorized session বা app secret দেখতে হবে।
  - সবচেয়ে নিশ্চিত উপায় হলো app secret বদলানো। কিন্তু তাতে `ALIEXPRESS_APP_SECRET` secret আর functions deploy-ও বদলাতে হয়, তাই এটা আলাদা কাজ।
- AliExpress discovery এখন বন্ধ আছে। refresh token-এর মেয়াদও নির্দিষ্ট, শেষ হলে আবার হাতে reconnect করতে হয় (memory-র পুরোনো নোট)।

## ledger-1: vendor commission ledger (লাইভ ২১–২২ নভেম্বর ২০২৬)

পুরো বিবরণ আর বাকি কাজের তালিকা আছে `docs/plans/ledger-1-handoff.md`-এ।

- **Functions** (২১ নভেম্বর ১৭:২৭ UTC):
  - `onOrderCreatedLedger` প্রতিটা অর্ডারে `priceCheck` লেখে। vendor-এর item থাকলে `commission_ledger/{orderId}_{vendorId}` তৈরি করে, দাম `products/` থেকে আবার মিলিয়ে।
  - `onOrderStatusLedger` চলে delivered, cancelled আর returned/refunded হলে, একটা transaction-এ, idempotent।
  - **এর আগের export:** `gs://chalakchar-mart-backups/ledger1-fn-20261121-1723`।
- **Hosting** (২২ নভেম্বর ০৩:১৫ UTC): version `6f1f9ea547faf2d0`। এতে আছে client-এর ledger কোড সরানো, vendor পাতার টাকা `vendor_private` থেকে, আর payout-এ ০-এর নিয়ম।
- **Rules** (২২ নভেম্বর ০৩:২২ UTC): ruleset `be7e9c8a-bd31-4dfd-81ea-26114d212272`।
  - `commission_ledger`: পড়তে পারে vendor নিজে, staff আর admin। client-এর লেখা বন্ধ।
  - `priceCheck`: client বসাতে পারে না।
  - `vendor_private`-এর balance: client লিখতে পারে শুধু payout-এর ধাপে।
  - `vendorCommissions`: বন্ধ।
  - **এর আগের export:** `gs://chalakchar-mart-backups/ledger1-rules-20261122-0321`।
  - লাইভের ruleset-এর source আর repo-র `firestore.rules`-এর sha256 এক (`5f486232…`)।
  - **ওই একই ফাইলে test:** rules ১১৮/১১৮, ledger trigger ১১/১১।
  - **লগইন ছাড়া পড়লে:** `commission_ledger`, `vendorCommissions`, `vendor_private` আর `conversations`-এ 403 আসে। `vendors` পড়া যায় (200)।
- **Rollback:**
  - **rules:** Console → Rules → History → `d63b3d4b…` → Restore। অথবা `git show audit-step-d:firestore.rules > firestore.rules`, তারপর `firebase deploy --only firestore:rules`।
  - **hosting:** `firebase hosting:clone chalakchar-mart@907a86861815b27e chalakchar-mart:live --project chalakchar-mart`।
  - **functions:** `firebase functions:delete onOrderCreatedLedger onOrderStatusLedger --region asia-south1`। তারপর `onOrderStatusUpdated` আবার deploy করতে হবে `audit-step-d` থেকে।
  - **শুধু rules ফেরালে কী হয়:** client আবার `vendor_private`-এর balance লিখতে পারবে, আর `priceCheck` বসাতে পারবে।

## 14b ধাপ F (ledger-এর পরের প্রথম কাজ): `changedOnly` / `changedAny`-এর ফাঁক

- **সমস্যা:** `changedOnly()` আর `changedAny()` দেখে শুধু `diff().changedKeys()`, অর্থাৎ শুধু বদলানো key। **নতুন যোগ করা key এরা দেখে না।** ফলে নিষিদ্ধ কোনো key আগে না থাকলে client সেটা নতুন করে যোগ করতে পারে।
- `orders`-এ ledger-1 এটা `affectedOnly()` দিয়ে ঠিক করেছে।
- **বাকি জায়গা** (২২ নভেম্বর গোনা):
  - `users/{uid}`: ১৪
  - `vendors/{vendorId}`: ২
  - `deliveryPartners`: ১
  - `deliveryEarnings`: ১
  - `notifications`: ১
  - helper function-এর সংজ্ঞা আর ভেতরে: ৪
- **কাজ:**
  1. প্রতিটা নিয়মের জন্য emulator-এ "নিষিদ্ধ key নতুন করে যোগ" test লেখা।
  2. `affectedKeys()`-এ বদলানো।
  3. ১০০০-expression সীমা মাথায় রাখা, একটা নিয়মে diff একবারই।

### ধাপ F: তদন্ত আর কোড (২৪ নভেম্বর, branch `step-f`, worktree `../cc_stepf`)

- **শুরুর মিল:** লাইভ ruleset `be7e9c8a`-এর source আর branch-এর `firestore.rules` হুবহু এক (sha256 `cc0ba46a…`, CRLF সমেত)। লাইভের কপি রাখা আছে `firestore.rules.live-be7e9c8a`-এ।
- **ফাঁকটা আরও বড়:** `changedKeys()` নতুন যোগ করা key-ও দেখে না, **মুছে ফেলা key-ও দেখে না।**
- **লাইভে খোলা ছিল** (emulator-এ যাচাই করা, `be7e9c8a`-তে):
  - customer নিজের প্রোফাইলে `permissions` যোগ করে staff-এর ক্ষমতা পায়। এরপর vendor_private-এর ব্যাংক বা bKash পড়তে পারে।
  - যে customer-এর ডকুমেন্টে `vendorId` নেই, সে অন্য vendor-এর id বসায়। এরপর সেই vendor-এর `payoutAccount` বদলাতে পারে।
  - users.edit staff একজন customer-কে `permissions` দিতে পারে।
  - block করা staff বা customer নিজের `isBanned` আর `isActive` মুছে ফেলতে পারে।
  - rider নিজের `codDue`, `withdrawnAmount`, `lastSyncedOrderId`, `lastEarningSyncedAt` মুছতে পারে।
  - `vendorStatus`, `isVendor` আর rider-এর তিনটা key কোনো নিষিদ্ধ তালিকাতেই ছিল না।
  - vendor, earning আর notification-এ বাড়তি key যোগ বা মোছা যেত।
- **লাইভে গোনা** (২৪ নভেম্বর, শুধু পড়া, কোনো মান দেখা হয়নি):
  - ৮ জন user, তাদের ৩ জন staff। ৫ জনের `permissions` নেই, সবার `vendorId` আছে।
  - staff নয় অথচ `permissions` আছে: ০ জন, অর্থাৎ ফাঁক ব্যবহারের চিহ্ন নেই।
  - অন্য vendor-এর `vendorId`: ০। একজনের `vendorId` তার নিজের uid, কিন্তু সেই vendor ডকুমেন্ট নেই, যা অসম্পূর্ণ আবেদন।
  - `isBanned` বা `isActive` নেই এমন staff: ০।
  - vendor ১টা, তার সব key আছে।
  - rider ১ জন, শুধু `lastSyncedOrderId` নেই। এখনো sync হয়নি, তাই এটা স্বাভাবিক।
  - ChalakChar Cash ব্যবহার হওয়া অর্ডার: ০।
- **ঠিক করা:**
  - `changedOnly` আর `changedAny`-এর বদলে `affectedOnly` আর `affectedAny` (`affectedKeys()`)। orders-এর নিজস্ব copy বাদ গেছে, `changedKeys` আর কোথাও নেই।
  - customer আর users.edit staff-এর নিষিদ্ধ তালিকায় যোগ: `vendorStatus`, `isVendor`, `isDeliveryPartner`, `deliveryPartnerStatus`, `deliveryPartnerId`।
  - role-বদলের তালিকায় rider-এর তিনটা key। admin-এর rider অনুমোদন এগুলো লেখে।
  - admin Notifications পাতার জন্য সরু নিয়ম: admin বা superAdmin নিজের ডকুমেন্টে শুধু notifications.*-এর ৬টা permission যোগ করতে পারবে, কিছু মুছতে পারবে না।
  - seller-link নিয়মে `sellerStatus` না থাকলে আর error হয় না।
  - **১০০০-expression সীমা:** users.block, wallet.edit, users.permissions, users.edit আর vendor অনুমোদনে `can()`-এর বদলে `canAnyOf()`। role-বদলের নিয়ম users-এর শুরুতে সরানো হয়েছে। আগে block, points, permission আর staff-এর vendor বা rider অনুমোদনের user-sync লাইভেও আটকে যেত।
- **test:** `tools/rules-test/step_f.test.js`, ২৭টা।
  - ১৪টা আক্রমণ, যোগ আর মোছা দুটোই। এর মধ্যে ১৩টা `be7e9c8a`-তে সফল হয়, যা ফাঁকের প্রমাণ। বাকি একটা সেখানে শুধু ১০০০-সীমার কারণে আটকাত।
  - ১৩টা অ্যাপের আসল লেখা।
  - আগের ১১৮টা test: নতুন rules-এ ১১৮/১১৮, `be7e9c8a`-তেও ১১৮/১১৮।
  - `step_f.test.js` (২৭): নতুন rules-এ ২৭/২৭। `be7e9c8a`-এর কপিতে নতুন rules-এর প্রত্যাশা দিয়ে চালালে ১৯টা ব্যর্থ, ৮টা পাস। ব্যর্থ ১৯টা: ১৩টা আক্রমণ সফল হয়; ৫টা staff-এর কাজ ১০০০-সীমায় আটকায় (block, wallet, permission, rider আর vendor অনুমোদন); ১টা হলো admin Notifications-এর নিয়ম, যেখানে আগে থেকে permissions থাকা admin আটকায়। নকশা অনুযায়ী "ফাঁক খোলা" প্রত্যাশা দিয়ে চালালে `be7e9c8a`-তে ২৭/২৭ পাস।
- **লাইভে:** ২৪ নভেম্বর ১৭:৪৬ UTC, ruleset `700f57c7-1ebf-41d5-9b8a-4acd8a029b96`।

## 14b ধাপ G (ধাপ F-এর পরেই): ChalakChar Cash-এর points কাটা server-এ

- **সমস্যা:** cart (`cart_page.dart`, অর্ডারের পরে) customer নিজের `users.points`-এ `increment(-x)` লেখে। কিন্তু rules customer-কে `points`-এ লিখতে দেয় না। তাই অর্ডারে ছাড় হয়, অথচ points কাটে না।
- লাইভে ২৪ নভেম্বর পর্যন্ত এমন অর্ডার ০টা।
- **কাজ:**
  - points কাটা Cloud Function-এ নেওয়া: অর্ডার তৈরির trigger, idempotent, অর্ডারের `chalakCharCashUsed` দেখে।
  - client `points`-এ কখনো লিখবে না। rules যেমন আছে তেমনই থাকবে।
  - হাতে থাকা points-এর চেয়ে বেশি ছাড় নেওয়া হলে কী হবে, সেটা ঠিক করতে হবে।

### ধাপ G: তদন্ত আর কোড (২৫ নভেম্বর, branch `step-g`, worktree `../cc_stepg`)

- **তদন্তে আরও যা পাওয়া গেছে** (লাইভ rules `700f57c7`-এ emulator দিয়ে যাচাই):
  - cart-এর points কমানো আটকায়, অথচ অর্ডার আগেই তৈরি হয়ে যায়। তাই customer "Order failed" দেখে, আর আবার চেষ্টা করলে দ্বিতীয় অর্ডার পড়ে।
  - rules অর্ডারের মোট অঙ্ক দেখে না: ৫০ points নিয়ে ৫০০০ টাকা Cash দাবি বা `grandTotal` ১ টাকা, দুটোই তৈরি হয়ে যায়।
  - priceCheck শুধু item-এর দাম মেলায়। `grandTotal`, coupon, Cash আর delivery charge কেউ মেলায় না।
  - settings-এর `maxAbdCashRedeem` আর `enableAbdCash` save হয়, কিন্তু কোথাও মানা হয় না।
  - cancel বা return হলে Cash ফেরতের কোনো ব্যবস্থা ছিল না।
- **লাইভে গোনা** (২৫ নভেম্বর, শুধু পড়া):
  - `points` > ০ এমন user: ০ জন, মোট ৮ জনের মধ্যে।
  - Cash খরচ হওয়া অর্ডার: ০টা, মোট ৭টার মধ্যে।
  - wallet_logs: ০টা। review: ০টা।
  - referral: ১টা, status `approved`। কিন্তু wallet_logs ০টা আর কারও points নেই, তাই এটা function-এর auto-approve পথে আসেনি।
  - `settings/app`: `maxAbdCashRedeem` ১০০, `enableAbdCash` true।
  - ৭টা অর্ডারেই client-এর subtotal দিয়ে `grandTotal`-এর সূত্র মেলে। server-এর দাম দিয়ে মেলানো যায় শুধু priceCheck থাকা ১টায় (`M5esc8i0zvOC5RYWaWj9`), সেটাও মেলে। বাকি ৬টা ledger-1-এর আগের, তাদের priceCheck নেই।
- **কোড:**
  - `functions/cash/cashCheck.js` (pure) আর `cashTriggers.js`।
  - নতুন trigger `onOrderCreatedCash` আর `onOrderStatusCash`।
  - **প্রতিটা অর্ডারে** `cashCheck` লেখা হয়:
    - Cash: চালু আছে কি না, এক অর্ডারে সর্বোচ্চ টাকা, points আর পণ্যের দাম − coupon মেলায়। সব মিললে points কাটে আর `wallet_logs/cash_redeem_{id}` লেখে। না মিললে কিছু কাটে না, শুধু `ok: false` আর কারণ।
    - মোট: `grandTotal = server-এর subtotal − coupon − Cash + delivery`। server-এর subtotal নেওয়া হয় products থেকে, priceCheck-এর মতোই। না মিললে `totalOk: false`, সঙ্গে দুটো অঙ্ক।
  - cancel বা returned হলে একবারই ফেরত দেয় (`wallet_logs/cash_refund_{id}`, `cashCheck.refundedAt`), আর পরে আবার কাটে না।
  - rules: অর্ডার তৈরির সময় client `cashCheck` লিখতে পারে না, staff-এর update-ও `cashCheck`-এ হাত দিতে পারে না। নিয়মটা priceCheck-এর মতো।
  - cart: points কমানোর লাইন সরানো হয়েছে, settings-এর চালু/বন্ধ আর সীমা মানা হয় (`lib/utils/chalakchar_cash.dart`)।
  - admin-এর অর্ডার কার্ডে লাল সতর্কবার্তা: "মোট দাম মেলে না: customer ৳X, হিসাবে ৳Y। rider পাঠানোর আগে দেখুন।" আর "ChalakChar Cash কাটা হয়নি…" (`lib/widgets/cash_check_warning.dart`)।
- **test:**
  - function-এর unit test ১২টা।
  - emulator test ১১টা (`node tools/rules-test/run-cash.js`): কাটা, সীমা, দুবার চলা, একসঙ্গে দুটো অর্ডার, cancel আর return-এ একবার ফেরত।
  - rules-এর `step_g.test.js` ৮টা। লাইভের কপি `firestore.rules.live-700f57c7`-এ নতুন rules-এর প্রত্যাশা দিয়ে চালালে ২টা আক্রমণ সফল হয়, যা ফাঁকের প্রমাণ। নতুন rules-এ দুটোই আটকায়।
  - Dart test ৭টা।
- **deploy-এর ক্রম:** rules → functions → hosting, প্রতিটার আগে export।

## 14b ধাপ H: review-এর reward আর admin-এর referral অনুমোদন

### ধাপ H: তদন্ত আর কোড (২৫–২৭ নভেম্বর, branch `step-h`, worktree `../cc_steph`)

- **শুরুর মিল:** লাইভ ruleset `438c4999`-এর source আর branch-এর `firestore.rules` হুবহু এক (sha256 `eb09b8aa…`)। লাইভের কপি `firestore.rules.live-438c4999` শুধু লোকাল, commit হয়নি (`.git/info/exclude`)। কপিটা দরকার হলে Rules API থেকে আবার নামানো যায়; `git show origin/step-g:firestore.rules`-এর সঙ্গেও এটা হুবহু এক।
- **branch:** `step-h` তৈরি হয়েছে `origin/step-g` থেকে, তারপর `origin/seo-3`-এ fast-forward করা হয়েছে। কারণ ২৭ নভেম্বর লাইভ hosting `d9aabec1a0fd54c3` (seo-3) step-g-এর ঠিক ওপরে বানানো। seo-3 বাদ দিলে SEO পিছিয়ে যেত। d4ead6c এতে নেই।

**তদন্তে যা পাওয়া গেছে** (লাইভ rules `438c4999`-এ emulator দিয়ে যাচাই):

- **review পড়াও বন্ধ ছিল,** শুধু লেখা না। customer আর guest review-এর তালিকা দেখতে পেত না। "আগে review দিয়েছি কি না" যাচাই error দিত, তাই সবাই দেখত "Review option will be available after product received"।
- **client review-এ `userEmail` লিখত।** client নিজেই পণ্যের rating-এর গণনা বাড়াত, আর `onProductReviewCreated`-ও গুনত, ফলে দুবার গোনার ঝুঁকি ছিল। ক্রেতা কি না সেটা পণ্যের **নাম** মিলিয়েও ধরা হতো।
- **যেকোনো লগইন করা user নিজের জন্য referral তৈরি করতে পারত,** যেকোনো status আর reward অঙ্ক দিয়ে (যেমন `Pending` আর ১০০০০ টাকা, যাতে admin অনুমোদন দেয়)।
- **referral-এর settings দুই জায়গায় ছিল।** function পড়ত `settings/referral` থেকে, অথচ admin পাতা লিখত `settings/app`-এ। `settings/referral`-এ `autoApprove` নেই, তাই কার্যত সব referral নিজে থেকেই approved হতো।
- **admin-এর পাতা function-এর লেখা referral চিনত না।** পাতা খুঁজত `'Pending'` আর `refereeId`, তাই Approve বোতাম কখনো দেখাত না। Dashboard আর Analytics-ও বড় হাতের `'Pending'`/`'Approved'` গুনত।
- **১০০০-expression-এর সীমা:**
  - `referrals` পড়ার নিয়মে চারটা `can()` ছিল। role `admin` আর শুধু `wallet.edit` থাকা staff তাই সীমায় আটকে তালিকাই পড়তে পারত না।
  - এই কাজে `referralCount` নিষিদ্ধ তালিকায় যোগ করার পর admin Notifications-এর নিয়মও সীমা ছাড়াচ্ছিল।
- **customer নিজের `referralCount` বদলাতে পারত,** আর profile তৈরির সময় যেকোনো মান বসাতে পারত। users.edit staff-ও পারত।
- **যেকোনো customer নিজের uid-কে `vendorId` বসিয়ে `products`-এ নতুন পণ্য তৈরি করতে পারে,** বানানো rating আর `status: approved` সমেত। vendor-ও নতুন পণ্যে rating বসাতে পারত। rating-এর অংশ এই ধাপে বন্ধ হয়েছে; ভুয়া পণ্য তৈরির বড় ফাঁকটা আলাদা কাজ (নিচে "জানা ঝুঁকি")।
- **লাইভের অনাথ referral:** function-এর auto-approve পথে তৈরি, ২০২৬-০৬-২২-এ, git ইতিহাসের আগে। দুজন user-ই Auth আর `users` থেকে মুছে গেছে। মালিকের সিদ্ধান্তে এতে হাত দেওয়া হয়নি।

**মালিকের সিদ্ধান্ত (২৭ নভেম্বর):**

- review দিতে পারবে শুধু যাচাই করা ক্রেতা: নিজের অর্ডার, status delivered/received/completed, আর item-এ এই `productId`। নামের মিল ধরা হবে না।
- points প্রতি পণ্যে একবার। Asia/Dhaka সময়ের এক দিনে সর্বোচ্চ ৫টা review-এ points যাবে। অঙ্ক নেওয়া হবে `settings/app.reviewReward` থেকে, না থাকলে ২।
- customer নিজের review বদলাতে পারবে, তাতে আর points পাবে না। review মুছতে পারবে শুধু admin, আর ইতিমধ্যে দেওয়া points থেকে যাবে।
- review-এ শুধু প্রথম নাম থাকবে, email কোথাও থাকবে না।
- referral অনুমোদন আর বাতিল হবে callable দিয়ে, `wallet.edit` অথবা super admin লাগবে।
- settings-এর মূল জায়গা `settings/app`, না থাকলে `settings/referral`। auto-approve শুধু `true` থাকলেই চালু।

**কোড:**

- **Functions** (`functions/reviews/productReviews.js`, `functions/referrals/referrals.js`):
  - `submitProductReview` (callable):
    - যাচাই করে: লগইন, rating ১ থেকে ৫-এর পূর্ণসংখ্যা, comment trim করার পর ১০০০ অক্ষরের বেশি নয় (code point হিসাবে), আর server-এ যাচাই করা ক্রেতা।
    - নতুন review হলে একই transaction-এ দেয়: `points` আর `totalEarnings`, `wallet_logs/review_{productId}_{uid}`, আর দিনের গণনা `review_reward_days/{uid}_{YYYY-MM-DD}`।
    - এটা নতুন collection। এতে শুধু function লেখে, catch-all-এ client-এর লেখা বন্ধ।
    - review বদলালে শুধু rating, comment আর `updatedAt` বদলায়।
  - `deleteProductReview` (callable): শুধু admin বা super admin পারে।
  - `onProductReviewWritten`: `onProductReviewCreated`-এর জায়গায় এসেছে। তৈরি, বদল আর মোছা, সব ক্ষেত্রে rating আবার হিসাব করে, একটা transaction-এ। মোছা পণ্য নতুন করে তৈরি করে না।
  - `approveReferral` / `rejectReferral` (callable):
    - শুধু pending থেকে বদলানো যায়, বড়-ছোট হাতের অক্ষরে তফাত না করে।
    - অঙ্ক নেয় referral ডকুমেন্ট থেকে। লেখে `approvedBy`/`approvedAt` অথবা `rejectedBy`/`rejectedAt`।
    - user মুছে গেলে `user_missing` দেয়। নিজের referral নিজে অনুমোদন করা যায় না।
  - **auto পথ আর হাতে অনুমোদন এখন একই credit ব্যবহার করে:**
    - referrer পায় points, totalEarnings আর `referralCount + 1`। referee পায় points আর totalEarnings।
    - `wallet_logs`-এর id দুই পথে এক, তাই points একবারই যায়।
    - **আগে এখানে অমিল ছিল:** পুরোনো admin batch referee-কে `totalEarnings` দিত না, wallet_logs লিখত না, আর status লিখত `'Approved'`।
  - `applyReferralReward`:
    - পড়ে `settings/app` থেকে, কোনো key না থাকলে `settings/referral` থেকে। দুই ডকুমেন্টে নাম আলাদা: `referralReward` বনাম `referrerReward`।
    - `referralAutoApprove` শুধু `true` হলে auto-approve চালু হয়।
    - status লেখে ছোট হাতে। referral বন্ধ থাকলে কিছুই লেখে না।
- **rules:**
  - `products/{id}/reviews`: পড়তে পারে সবাই, client কোনো লেখা করতে পারে না।
  - `referrals`: client-এর create, update আর delete বন্ধ। পড়ার permission আগের মতোই, শুধু `canAnyOf` দিয়ে লেখা।
  - `referralCount` এখন customer-এর নিজের update-এ বন্ধ, users.edit staff-এর জন্যও বন্ধ, আর profile তৈরির সময় শুধু ০।
  - staff ছাড়া কেউ নতুন পণ্যে বা পণ্য বদলের সময় চারটা rating-এর ঘর লিখতে পারে না।
  - admin Notifications-এর নিয়ম users-এর role-বদলের নিয়মের ঠিক পরে সরানো হয়েছে, ১০০০-সীমার কারণে। নিয়মের ক্রমে মানে বদলায় না।
- **অ্যাপ:**
  - **পণ্যের পাতা:**
    - review যায় callable দিয়ে। নিজের review দেখা যায় আর বদলানো যায়।
    - ১০০০ অক্ষর গোনা হয় function-এর মতোই। লাল সতর্কবার্তা দেখায় আর ১০০১-এ Submit বন্ধ থাকে।
    - "Verified buyer" চিহ্ন দেখায়, লম্বা নাম "…" দিয়ে কাটা হয়, admin-এর জন্য মোছার বোতাম থাকে।
    - client আর review, points, rating বা email লেখে না।
  - **admin settings:**
    - Approve আর Reject callable ডাকে। error বাংলায় দেখায় কার্ডের ভেতরে আর snackbar-এ।
    - `referredUserId` পড়ে, না থাকলে `refereeId`। মুছে যাওয়া user লাল লেখায় দেখায়।
    - নতুন দুটো ঘর: "Review Reward" আর "Auto-approve Referrals", দুটোই `settings/app`-এ save হয়।
    - পুরোনো batch-এর কোড মুছে দেওয়া হয়েছে।
    - referrer বা referee মুছে গেলে কার্ডে Approve শুরু থেকেই বন্ধ, পাশে কারণ লেখা থাকে; Reject চালু থাকে (`6650e34`)। user-এর তথ্য পড়া শেষ না হওয়া পর্যন্তও Approve বন্ধ থাকে। server-এর `user_missing` যাচাই আগের মতোই আছে।
  - **Dashboard আর Analytics:** status গোনে বড়-ছোট হাতের অক্ষরে তফাত না করে।

**test** (সব পাস):

- **rules:** `node tools/rules-test/run.js`।
  - নতুন rules-এ ১৭৯/১৭৯। এর মধ্যে `step_h.test.js` ২৬টা।
  - `firestore.rules.live-438c4999`-এ "আগের অবস্থা"-র প্রত্যাশা দিয়ে চালালেও ১৭৯/১৭৯:
    - ৮টা আক্রমণ সফল হয়: নিজের জন্য referral তৈরি (দুই রকম), users.edit দিয়ে referral বদল, super admin-এর client থেকে referral মোছা, `referralCount` বাড়ানো, মোছা আর তৈরির সময় বসানো, ভুয়া rating-সহ পণ্য তৈরি।
    - customer আর guest review পড়তে পারে না।
    - admin আর `wallet.edit` staff referral-এর তালিকা পড়তে পারে না।
- **emulator-এ function:** `node tools/rules-test/run-steph.js` ২৩/২৩। এতে আছে:
  - ক্রেতা নয়, pending অর্ডার, নামে মেলে কিন্তু productId-এ মেলে না।
  - প্রথমবার points, বদলালে না।
  - ৬ নম্বর review-এ points নেই; Dhaka-র মধ্যরাতের পরে আবার points।
  - একসঙ্গে দুটো review-এ ঠিক ৫টা পুরস্কার।
  - `reviewReward` অঙ্ক।
  - admin-এর মোছা, আর মোছার পরে নতুন review-এ points না পাওয়া।
  - trigger-এ তৈরি, বদল আর মোছার পরে গড়; মোছা পণ্য তৈরি না হওয়া।
  - `applyReferralReward`: pending, auto, বন্ধ।
  - approve: permission, দ্বিতীয়বার, auto পথে আগে দেওয়া points, একসঙ্গে দুটো approve, মুছে যাওয়া user, নিজের referral।
- **আগের emulator test:** cash ১১/১১, ledger ১১/১১।
- **functions-এর unit test:** ৭১৮/৭১৮।
- **Dart test:** ৫১৬/৫১৬, `flutter analyze`-এ বদলানো ফাইলে কোনো সমস্যা নেই।
- **screenshot:** worktree-র `screenshots/step-h/`-এ ৪২টা (৩৬০px আর ১৩৬৬px), commit হয়নি।
  - তোলা হয়েছে লোকাল emulator build দিয়ে, demo project `demo-chalakchar-ui`-এ। একটা অস্থায়ী emulator hook ছিল, commit হয়নি, কাজ শেষে সরানো হয়েছে।
  - browser থেকে Firestore, Auth, Functions বা নিজের ডোমেইনে কোনো লাইভ অনুরোধ যায়নি (block করা ছিল আর log দেখা হয়েছে)। বাইরে গেছে শুধু gstatic-এর CanvasKit, font আর Firebase JS SDK, আর Google Sign-In-এর script।
  - কোনো preview channel deploy হয়নি।

**index:** নতুন কোনো composite index লাগে না।

- `orders where userId ==` চলে single-field index-এ।
- review-এর তালিকা (`orderBy createdAt`, একটা subcollection) চলে single-field index-এ।
- দিনের সীমা গোনা হয় একটা নির্দিষ্ট id-র ডকুমেন্টে, কোনো query লাগে না।

**জানা ঝুঁকি / বাকি:**

- **পণ্য return হলে review-এর points ফেরত যায় না।** review-ও থেকে যায়। admin review মুছলেও points থাকে (মালিকের সিদ্ধান্ত)।
- **`settings/referral.maxRewardPerUser` কোথাও ব্যবহার হয় না।** (লাইভে মান ০।)
- **`referralFirstOrderRewarded`** শুধু auto পথে লেখা হয়, কোথাও পড়া হয় না।
- **ভুয়া পণ্য তৈরি:** `vendorProductCreateOwner`-এ `data.vendorId == request.auth.uid` থাকায় যেকোনো লগইন করা user পণ্য তৈরি করতে পারে।
  - এতে vendor কি না, দেখা হয় না।
  - নিজের পণ্য বদলানোর নিয়মে `ownsVendorProduct()` আছে, যা কোথাও সংজ্ঞায়িত নয়, আর এটা ১০০০-সীমায়ও আটকায়। ফলে লাইভে vendor নিজের পণ্য বদলাতে পারে না।
  - এ দুটো আলাদা কাজ, মালিকের সিদ্ধান্ত লাগবে।
- **লম্বা প্রথম নাম** server-এ ৪০ অক্ষরে কাটা হয়, আর পাতায় এক লাইনে "…" দিয়ে।
- **`ReferralService.updateReferralSettings`** (`settings/referral` লেখে) কেউ ডাকে না। রেখে দেওয়া হয়েছে।

**admin Settings পাতা ভাঙা ছিল** (মালিকের পাওয়া, ২৭ নভেম্বর; ঠিক করা `a25786b`):

- **কারণ:** লাইভে `settings/app.importSettings.roundingMode` = `"round"` (শুধু পড়ে দেখা)।
  - মানটা বসিয়েছে `functions/scripts/roundPricesToTaka.js` (`e42022d`, ১৫ নভেম্বর)। এটাই দোকানের "পুরো টাকা, .৫ হলে ওপরে" নিয়ম, আর server (`applyImportPriceRule`) এই মান চেনে।
  - কিন্তু admin-এর "Price Rounding" dropdown-এ ছিল শুধু `none`/`00`/`99`।
  - Flutter-এর DropdownButton মান তালিকায় ঠিক একবার না পেলে assert করে। তাই debug build-এ লাল error আসে, release build-এ পাতা ধূসর বা ফাঁকা দেখায়।
  - **লাইভের admin Settings পাতা তাই ১৫ নভেম্বর থেকেই ভাঙা।** ধাপ H-এর hosting এটা ঠিক করবে।
  - 9a32684-এ এটা ঠিক হয়নি। তখনকার screenshot-এর demo ডেটায় `importSettings` ছিল না, তাই ডিফল্ট `none` দেখিয়েছিল আর সমস্যা ধরা পড়েনি।
- **সমাধান:**
  - `"round"` এখন আসল বিকল্প: "Whole taka, nearest (.5 up)"।
  - পাতার চারটা dropdown-ই (Price Rounding, Default Audience, Default Publish Time, referral-এর Status) চলে `SafeDropdownField` দিয়ে:
    - একই value দুবার থাকলে একটাই রাখে।
    - অচেনা মান হলে কিছু নির্বাচিত দেখায় না ("Choose…"), নিচে লেখে "অজানা মান: <মান>"।
  - save-এর সময় এই তিনটা ঘর লেখা হয় শুধু মান বৈধ হলে। অচেনা মান থাকলে ঘরটা লেখাই হয় না, তাই Firestore-এ আগের মান থাকে (merge write)।
- **test:** `test/safe_dropdown_test.dart` ৭টা। এর একটা দেখায় যে সাধারণ DropdownButtonFormField-এ `"round"` দিলে হুবহু মালিকের দেখা assert-টাই আসে।
- **screenshot:** `11-*` (৩৬০ আর ১৩৬৬)। অবস্থা তিনটা:
  - লাইভের মতো (`round`)
  - ঘর নেই (ডিফল্ট `none`)
  - অচেনা মান (`ceil_to_5`, আর audience `vip_only`)
  - console-এ error ০।

### ধাপ H: deploy-এর পরিকল্পনা (অনুমতির অপেক্ষায়; এখনো কিছু deploy হয়নি)

সব command চলবে `../cc_steph` থেকে (branch `step-h`)। প্রতিটা ধাপের আগে export নিতে হবে, আর প্রতিটা ধাপের পরে লাইভে যাচাই করতে হবে। ক্রম: rules → functions → hosting।

1. **Rules**
   - export: `gcloud firestore export gs://chalakchar-mart-backups/steph-rules-<YYYYMMDD-HHMM> --project chalakchar-mart`
   - deploy: `firebase deploy --only firestore:rules --project chalakchar-mart`
   - rollback: ruleset `438c4999-aa60-440c-aad1-5acd04e03d69` (Console → Rules → History → Restore), অথবা `git show origin/step-g:firestore.rules > firestore.rules`, তারপর deploy আর `git checkout firestore.rules`।
   - **পুরোনো hosting-এর সঙ্গে নিরাপদ:** client থেকে review লেখা আগেই বন্ধ ছিল, client কখনো referral তৈরি করে না, আর পুরোনো admin batch আগেও আটকাত।
   - যাচাই:
     - লাইভের source-এর sha256 = branch-এর ফাইল।
     - লগইন ছাড়া `products/<id>/reviews` list → 200 (খালি)।
     - লগইন ছাড়া `referrals` → 403।
     - admin পাতা খোলে।
     - customer-এর নিজের নাম বদলানো চলে।
2. **Functions**
   - export: `gs://chalakchar-mart-backups/steph-fn-<YYYYMMDD-HHMM>`
   - deploy: `firebase deploy --only functions:submitProductReview,functions:deleteProductReview,functions:onProductReviewWritten,functions:approveReferral,functions:rejectReferral,functions:applyReferralReward --project chalakchar-mart`
   - তারপর: `firebase functions:delete onProductReviewCreated --region asia-south1 --project chalakchar-mart`। নতুন trigger চালু হওয়ার পরে মুছতে হবে। মাঝের সময়ে দুটো trigger একই হিসাব লিখবে, তাতে ক্ষতি নেই।
   - **এখান থেকেই auto-approve বন্ধ হয়ে যায়,** কারণ `settings/app`-এ `referralAutoApprove` নেই। hosting আসার আগ পর্যন্ত নতুন referral pending থাকবে।
   - rollback:
     - `cc_stepg` (origin/step-g) থেকে `firebase deploy --only functions:applyReferralReward,functions:onProductReviewCreated`।
     - তারপর `firebase functions:delete submitProductReview deleteProductReview onProductReviewWritten approveReferral rejectReferral --region asia-south1`।
   - যাচাই: log-এ error নেই; callable লগইন ছাড়া ডাকলে `unauthenticated` আসে। লাইভ ডেটায় review বা referral লেখা হবে না।
3. **Hosting**
   - build: `flutter clean && flutter build web --release`। কোনো `--dart-define` নয়। এই build-এ seo-1, seo-2, seo-3, ledger-1, brand-1, ধাপ G আর ধাপ H আছে।
   - আগে preview: `firebase hosting:channel:deploy steph --expires 7d`।
   - preview-এর `main.dart.js`-এ grep: `submitProductReview` আর `approveReferral` থাকবে, `emuLogin` আর `USE_EMULATORS` থাকবে না।
   - তারপর: `firebase hosting:clone chalakchar-mart:steph chalakchar-mart:live --project chalakchar-mart`
   - rollback: `firebase hosting:clone chalakchar-mart@d9aabec1a0fd54c3 chalakchar-mart:live --project chalakchar-mart` (seo-3)।
     - **`bd482832093239e5`-এ নয়:** সেটা seo-3-এর আগের version, তাতে ফিরলে SEO পিছিয়ে যাবে।
   - যাচাই:
     - পণ্যের পাতার Reviews ট্যাব guest আর customer-এর জন্য খোলে, console error নেই।
     - wallet.edit বা super admin-এর admin পাতায় referral-এর তালিকা আর Approve দেখা যায়।
     - settings-এ নতুন দুটো ঘর আছে।
     - লাইভ আর preview-এর `main.dart.js` হুবহু এক।
   - এরপর মালিক ঠিক করবেন `reviewReward` আর auto-approve-এর মান।

## 14b ধাপ H2: products-এর rules, vendor-এর পরিচয় আর পণ্যের ছবি

### ধাপ H2: তদন্ত আর কোড (২৮ নভেম্বর, branch `step-h2`, worktree `../cc_steph2`)

- **শুরুর মিল:**
  - branch `step-h2` তৈরি `origin/step-h` (`9b3a76e`) থেকে, d4ead6c নেই।
  - লাইভ Firestore ruleset `fa5f0e22` = branch-এর `firestore.rules` (sha256 `b5b6c626…`)।
  - লাইভ Storage ruleset `2ce1afb0` = branch-এর `storage.rules` (sha256 `7ae2db76…`)।
  - লাইভ Firestore rules-এর কপি `firestore.rules.live-fa5f0e22` শুধু লোকালে, commit হয়নি।

**তদন্তে যা পাওয়া গেছে** (লাইভ rules-এর কপিতে emulator দিয়ে প্রমাণিত, `step_h2.test.js` আর `storage_h2.test.js`):

- **ভুয়া পণ্য:**
  - guest বাদে যেকোনো লগইন করা user approved আর live পণ্য তৈরি করতে পারত।
  - এর মধ্যে আছে customer, rider, pending বা suspended vendor, আর শুধু `products.view` থাকা staff।
  - নিজের uid দিয়েই শুধু নয়; অন্য vendor-এর বা দোকানের নিজের (`super_admin`) নামেও পারত।
  - commission, featured, sponsored, marketing-এর লেখা আর SEO-র ঘরও নিজের ইচ্ছামতো বসাতে পারত।
  - কারণ `vendorProductCreateOwner()` দেখত শুধু `data.vendorId == request.auth.uid` (বা owner-এর ঘর), vendor কি না দেখত না।
- **এর ফল:**
  - দোকান, SSR আর sitemap-এ ভুয়া পণ্য দেখাত।
  - `onProductCreated` সর্বোচ্চ ১০০০ জন customer-কে push পাঠাত, আর `marketing_outbox` বানাত।
  - লাইভের ইতিহাসে `cloud_function_product_created` সারিতে `facebook: posted`, `instagram: posted`, `whatsapp: queued` দেখা যায়। অর্থাৎ caption নিজে লিখে দোকানের page-এ post করানো যেত।
- **vendor নিজের পণ্য বদলাতে, লুকাতে বা মুছতে পারত না:** `ownsVendorProduct()` কোথাও সংজ্ঞায়িত ছিল না।
- **`products.status` থাকা staff দাম আর rating-ও বদলাতে পারত।**
- **`users.vendorId`:**
  - customer নিজের profile-এ এই ঘর বসাতে পারত।
  - ফলে Firestore-এ নিজেকে vendor দেখাতে পারত। সেই vendor-এর `vendor_private` পড়া, payout চাওয়া (নিজের `payoutAccount` দিয়ে), অর্ডার আর notification দেখা যেত।
  - Storage-এও নিজেকে vendor দেখাতে পারত।
- **pending vendor আবেদন দখল:** যে কেউ `vendors/{V}`-এর `ownerId` নিজের নামে বদলে দিতে পারত।
- **Storage:**
  - "vendor" (যার মধ্যে ভুয়া `users.vendorId` থাকা customer-ও পড়ে) দোকানের `products/` আর `product_images/`-এর যেকোনো ছবির ওপর লিখতে পারত।
  - যেকোনো customer `vendor_products/{নিজের uid}/`-এ ছবি রাখতে পারত, যা সবাই দেখতে পারে।
- **লাইভের ডেটা** (শুধু পড়া, ২৮ নভেম্বর):
  - ২২১টা পণ্য, সবগুলোর `vendorId = 'super_admin'`।
  - vendor ১টা (approved), তার পণ্য ০টা।
  - rating-এর ঘর সব ০, সন্দেহজনক কিছু নেই।
  - **এই ফাঁক দিয়ে কেউ কিছু বসায়নি।**

**মালিকের সিদ্ধান্ত (২৮ নভেম্বর):**

1. approved পণ্যে দাম, stock আর variant সরাসরি বদলানো যাবে। নাম, ছবি বা category বদলালে পণ্য আবার pending হবে, আর rules সেটা বাধ্য করবে।
   - আমি overview-কেও এই তালিকায় রেখেছি, কারণ এটাও দোকানে দেখানো লেখা।
2. vendor পণ্য মুছতে পারবে না, শুধু লুকাতে পারবে।
3. `products.status` শুধু status-এর ঘরে সীমিত।
4. vendor-এর পণ্য অনুমোদিত হলেও নিজে থেকে marketing বা push হবে না।
5. `onProductCreated`-এ কে লিখেছে তা দেখার সুরক্ষা।
6. Storage-এ `products/` আর `product_images/`-এ শুধু staff লিখবে। vendor লিখবে শুধু `vendor_products/{নিজের V}/`-এ।
7. vendor-এর পণ্য তৈরি চালু থাকবে, pending দিয়ে।

সঙ্গে বাড়তি তিনটা:
- client `users.vendorId` বসাতে পারবে না।
- vendor-এর ছবি শুধু নিজের ফোল্ডারের।
- ওষুধ-আমলের ঘর বাদ।
- CSV/JSON-এর জন্য `products.bulk` আর `products.edit` দুটোই লাগবে।
- পুরোনো `admin_panel_page` সরানো।

**কোড:**

- **Firestore rules** (`8ae6d70`):
  - **vendor-এর পরিচয়:** এখন দেখা হয় `vendors/{V}` ডকুমেন্ট থেকে (`ownerId`, `status`, `isActive`), helper `ownsVendorDoc` আর `ownsApprovedVendor`। `users.vendorId`-এর ওপর আর কোথাও ভরসা নেই: `vendor_private`, withdraw, অর্ডার পড়া, `vendor_notifications`, পণ্য।
  - **পণ্য তৈরি:** `products.edit`-ওয়ালা staff, অথবা approved vendor-এর নিজের নতুন পণ্য।
    - ঘরের অনুমোদিত তালিকা (hasOnly), যাতে ওষুধ-আমল, marketing, SEO, commission বা rating-এর ঘর নেই।
    - `approvalStatus == 'pending'`, আর সব প্রকাশের ঘর false।
    - owner-এর ঘর = নিজে।
    - ছবি শুধু `https://firebasestorage.googleapis.com/v0/b/chalakchar-mart.firebasestorage.app/o/vendor_products%2F{V}%2F…`, সর্বোচ্চ ৮টা।
    - variant-এ শুধু `name`/`price`/`mrp`/`stock`, সর্বোচ্চ ১২টা।
  - **পণ্য বদলানো:**
    - `products.edit`: সব।
    - `products.status`: শুধু status-এর ঘর।
    - vendor:
      - নিজের পণ্যে নিজের ঘর।
      - কখনো approve বা publish করতে পারে না।
      - নাম, ছবি, category বা overview বদলালে পণ্য pending আর লুকানো হবে।
      - approved না হলে পণ্য লুকানোই থাকে।
  - **মোছা:** শুধু `products.delete` (superAdmin সহ)।
  - **users:**
    - client `vendorId` লিখতে পারে না।
    - তৈরির সময় `sellerStatus` শুধু `none`/`new`/`pending`/`submitted`, আর `vendorStatus`/`isVendor` থাকে না।
  - **vendors:** owner `ownerId`/`userId` বদলাতে পারে না।
- **Storage rules:**
  - `products/` আর `product_images/`: শুধু staff।
  - `vendor_products/{V}/`: শুধু approved আর চালু vendor-এর owner।
- **Functions** (`8647a7e`):
  - নতুন `onProductCreatedChecked` (`onDocumentCreatedWithAuthContext`), `onProductCreated`-এর জায়গায়।
    - স্বয়ংক্রিয় marketing চলে শুধু function, import বা script (service account), অথবা অ্যাপের staff (admin, superAdmin, owner, `products.edit`)-এর লেখা দোকানের পণ্যে।
    - vendor-এর পণ্যে কখনো নয়।
  - `onProductStockUpdated`: vendor-এর পণ্যে customer-দের wishlist push বন্ধ।
  - নিয়মটা আছে `functions/products/productMarketingGuard.js`-এ।
- **অ্যাপ** (`9d6d6f4`, `5543eb5`):
  - **vendor-এর "My Products":**
    - ওষুধ-আমলের ঘর নেই।
    - সাদামাটা variant।
    - ৮টা ছবি আর ১২টা variant-এর সীমা।
    - update হয় `vendorProductUpdate` দিয়ে (`lib/utils/vendor_product_rules.dart`)।
    - মোছার বোতাম নেই।
    - rules বাতিল করলে বাংলায় error।
  - **ধরা পড়া দুটো পুরোনো bug:**
    - stock সবসময় ০ লেখা হতো (controller-এর লেখা না পড়ে controller যোগ করা হতো)।
    - category resolver-এর `categoryId` শুধু দাম বদলেও পণ্যকে pending করে দিত।
  - আবেদনের পাতা আর `requestSellerAccount` আর `users.vendorId` লেখে না।
  - CSV/JSON-এর জন্য `products.bulk` আর `products.edit` দুটোই লাগে।
  - `admin_panel_page.dart` আর `admin_button_page.dart` সরানো।

**test:**
- rules: `node tools/rules-test/run.js`
  - নতুন rules-এ ২২৫/২২৫। এর মধ্যে আগের ১৭৯টা; তাদের দুটো নতুন সিদ্ধান্ত অনুযায়ী বদলানো (`step_f`-এর আবেদনের link, `step_h`-এর vendor payload)।
  - লাইভের কপি `fa5f0e22`-এ ২১৪/২১৪, যেখানে আক্রমণগুলো সফল হয় আর vendor-এর নিজের বদল আটকায়।
- Storage: `node tools/rules-test/run-storage.js` ১৭/১৭।
- function-এর emulator test: `run-steph2.js` ৪/৪। unit test ৪/৪।
- `step_h2.test.js` আর `storage_h2.test.js` প্রত্যাশা বাছে rules ফাইলের sha256 দেখে।
- **শেষ run (২৮ নভেম্বর):**
  - rules ২২৫/২২৫, লাইভের কপি ২১৪/২১৪, Storage ১৭/১৭।
  - emulator: H ২৩/২৩, H2 ৪/৪, cash ১১/১১, ledger ১১/১১।
  - functions-এর unit test ৭২২/৭২২, Dart ৫৩২/৫৩২।
  - `flutter analyze lib test` পরিষ্কার।
- vendor-এর save-এর error এখন dialog-এর ভেতরে দেখায় (`df80840`)। আগে SnackBar ফোনে dialog-এর নিচে ঢাকা পড়ত।
- screenshot: `screenshots/step-h2/`, ৩৬০ আর ১৩৬৬ মাপে, md5 সব আলাদা।

**জানা কথা:**
- লাইভে একজন user-এর `vendorId` তার নিজের uid, অথচ vendor ডকুমেন্ট নেই (ধাপ F-এ গোনা)। নতুন rules-এ এর কোনো প্রভাব নেই, কারণ ভরসা এখন `vendors` ডকুমেন্টের ওপর।
- ধাপ E-র catch-all আগের মতোই।

### ধাপ H2: deploy-এর পরিকল্পনা (অনুমতির অপেক্ষায়; কিছুই deploy হয়নি)

চারটা আলাদা deploy, এই ক্রমে। প্রতিটার আগে `gcloud firestore export gs://chalakchar-mart-backups/steph2-<ধাপ>-<YYYYMMDD-HHMM> --project chalakchar-mart` (SUCCESSFUL না হওয়া পর্যন্ত এগোনো যাবে না)। সব command `../cc_steph2` থেকে।

1. **Firestore rules**
   - deploy: `firebase deploy --only firestore:rules --project chalakchar-mart`
   - rollback: ruleset `fa5f0e22-cc67-4abc-92c2-d21caad63af0` (Console → Rules → History → Restore), অথবা `git show origin/step-h:firestore.rules > firestore.rules`, deploy, তারপর `git checkout firestore.rules`।
   - **hosting আসার আগ পর্যন্ত:**
     - পুরোনো অ্যাপের vendor আবেদন `users.vendorId` লিখতে গিয়ে আটকাবে (vendors ডকুমেন্ট save হবে, users-এরটা নয়)।
     - পুরোনো vendor পাতা নতুন পণ্যে ওষুধ-আমলের ঘর পাঠায়, তাই সেটাও আটকাবে।
     - লাইভে vendor-এর পণ্য ০টা আর আবেদন খুব কম, তাই hosting তাড়াতাড়ি পরে দেওয়া ভালো।
   - যাচাই:
     - লাইভ source-এর sha256 = branch।
     - লগইন ছাড়া products পড়া 200।
     - admin-এর Products আর Vendor Products পাতা খোলে।
     - লাইভ source-এর কপিতে emulator suite পাস।
2. **Storage rules**
   - deploy: `firebase deploy --only storage --project chalakchar-mart`
   - rollback: ruleset `2ce1afb0-379e-4ad8-82e3-206be53d8a01`, অথবা `git show origin/step-h:storage.rules > storage.rules`, deploy, তারপর `git checkout storage.rules`।
   - যাচাই: লাইভ source-এর sha256 = branch; পণ্যের একটা ছবি লগইন ছাড়া 200।
3. **Functions**
   - deploy: `firebase deploy --only functions:onProductCreatedChecked,functions:onProductStockUpdated --project chalakchar-mart`
   - নতুন trigger ACTIVE হলে: `firebase functions:delete onProductCreated --region asia-south1 --project chalakchar-mart`
   - মাঝের কয়েক মিনিটে দুটো trigger-ই চলবে। সে সময় admin নতুন পণ্য না বানালেই দুবার marketing-এর ঝুঁকি নেই।
   - rollback:
     - `../cc_steph` (origin/step-h) থেকে `firebase deploy --only functions:onProductCreated,functions:onProductStockUpdated`।
     - তারপর `firebase functions:delete onProductCreatedChecked --region asia-south1`।
   - যাচাই: function-এর log-এ error নেই, ACTIVE, event `document.v1.created`।
4. **Hosting**
   - `flutter clean && flutter build web --release` (কোনো `--dart-define` নয়)।
   - preview: `firebase hosting:channel:deploy steph2 --expires 7d`।
   - `main.dart.js`-এ grep: emulator-এর চিহ্ন নেই, vendor পাতার নতুন বাংলা লেখা আছে।
   - তারপর `firebase hosting:clone chalakchar-mart:steph2 chalakchar-mart:live`।
   - rollback: `firebase hosting:clone chalakchar-mart@1ef9e5dcd524900a chalakchar-mart:live --project chalakchar-mart`।
   - যাচাই: লাইভ = preview (sha256); www থেকে 301; sitemap ৯১টা URL; X-Robots আগের মতো।

## 14b ধাপ I: অর্ডার তৈরি function দিয়ে

- ধাপ G-এর পরেও coupon আর delivery charge client-এর দেওয়া অঙ্কই থাকে। `cashCheck` শুধু সূত্র মেলায়, coupon বৈধ কি না আর delivery charge ঠিক কি না দেখে না।
- **কাজ:**
  - অর্ডার তৈরি একটা callable function-এ নেওয়া। function দাম, coupon (বৈধতা, মেয়াদ, ব্যবহারের সীমা), delivery charge (ঠিকানা থেকে), Cash আর মোট অঙ্ক নিজে হিসাব করে লিখবে।
  - client সরাসরি `orders`-এ create করতে পারবে না।

## পরের ছোট কাজের দফা (brand-1-এর পরে; মালিক, ২৪ নভেম্বর)

এখন করা হয়নি। পরের দফায় একসঙ্গে করতে হবে, তারপর preview।

- **vendor dashboard-এর বাকি নীল আর teal:** brand-এর রঙে বদলাতে হবে।
  - উপরের banner-এর gradient `#0F766E`, `#0891B2`, `#2563EB`।
  - কার্ডের `#2563EB` (Products) আর `#0D9488` (Withdrawable)।
  - এগুলো আছে `lib/pages/vendor/vendor_dashboard_page.dart`-এ। brand-1-এর রং বদলের তালিকায় এগুলো ছিল না।
- **Withdraw পাতা:** payout account-এর বাক্সের `Colors.blue.shade50` বদলে brand-এর হালকা রং (`vendor_withdraw_page.dart`)।
- **লগইন পাতা:** ফোন নম্বরের ঘর card-এর ভেতরের কিনারা ছাড়িয়ে যায়, ডান দিকে কাটা দেখায়। desktop আর 360px দুটোতেই।
- **লগইন পাতা, 360px:** card মাঝখানে বসাতে হবে, এখন একটু উপরে বসে।
- ledger-1-এর বাকি দুটো ছোট কাজও এর সঙ্গে করা যায়:
  - vendor dashboard-এ returned বা cancelled অর্ডার "Pending Orders"-এ গোনা হয়।
  - "You owe"-এর সংখ্যাটা লাল করতে হবে।
- **admin Delivery Partners পাতা** (ধাপ F যাচাইয়ের সময় মালিকের পাওয়া, ২৫ নভেম্বর):
  - কাগজের তথ্য (NID ইত্যাদি) লোড হওয়ার আগে কয়েক সেকেন্ড "not uploaded" দেখায়। লোড হওয়ার সময় "লোড হচ্ছে" দেখানো উচিত।
  - সবুজ বারে "Partners" আর "Withdraws" ট্যাবের লেখা প্রায় দেখা যায় না, রং বদলাতে হবে।
- **মালিকের নতুন তালিকা** (ধাপ H-এর পরে, ২৭ নভেম্বর; এখনো ঠিক করা হয়নি):
  - customer হোম পাতার ওপরের অংশ হালকা বেগুনি। সবুজ brand-এর রঙে বদলাতে হবে।
  - Profile-এ এলাকা না থাকলে "-> ->" দেখায়। "Not set" দেখানো উচিত।
  - Profile-এ role-এর ট্যাগ কাঁচা "DELIVERYPARTNER" দেখায়। পড়ার মতো নাম চাই।
  - Cart পাতার ওপরের অংশ status bar-এর নিচে ঢুকে যায়, কারণ SafeArea নেই।
  - পণ্যের পাতার ছবির সারিতে কিছু ছবি ফাঁকা সাদা দেখায়। সম্ভবত ভাঙা লিংক।
  - "Mobile parts" সারিতে SSD দেখায়। ক্যাটাগরির ভুল হতে পারে।
  - admin Dashboard লোডের প্রথম প্রায় ১৫ সেকেন্ড সব ঘরে ০ দেখায়। তখন লোড হওয়ার চিহ্ন দেখানো উচিত।
  - admin Dashboard-এর কার্ডে লেখা আর টাকার অঙ্ক কেটে যায় ("৳52…")।
  - admin Products-এর খোঁজার ঘরে ওষুধের আমলের লেখা "generic, manufacturer" রয়ে গেছে।
- **ধাপ H-এর screenshot দেখে মালিকের তালিকা** (২৮ নভেম্বর; এখনো ঠিক করা হয়নি):
  - review-এর তালিকায় লম্বা লেখা ৫–৬ লাইনের পর "আরও পড়ুন" দিয়ে গুটিয়ে রাখা।
  - desktop footer-এ bKash/Nagad/Card দেখায়, কিন্তু এগুলো চালু নেই।
  - wallet-এ "Total Earned"-এর অঙ্কের আগে ৳ নেই।
  - 360px-এ পণ্যের পাতার "Add To Cart" দুই লাইনে ভাঙে।
  - 360px-এ admin Settings-এর "Review Reward (first review, verified buyer)" লেবেল কাটা পড়ে।

## জরুরি (ধাপ I-এর আগে, আলাদা ধাপে): ভুয়া পণ্য আর vendor-এর নিজের পণ্য বদলানো

> **অবস্থা (২৮ নভেম্বর):** ধাপ H2-এ কোড, rules আর test হয়েছে (branch `step-h2`)। এখনো deploy হয়নি। উপরের "ধাপ H2" অংশ দেখুন।

- **ভুয়া পণ্য:** `vendorProductCreateOwner()`-এ `data.vendorId == request.auth.uid` আছে। তাই যেকোনো লগইন করা user নিজের uid-কে `vendorId` বসিয়ে `products`-এ পণ্য তৈরি করতে পারে, `status: approved` বা `isActive: true` সমেত।
  - এতে vendor কি না, দেখা হয় না।
  - লাইভ `438c4999`-এ emulator দিয়ে যাচাই করা।
  - ধাপ H শুধু rating-এর চারটা ঘর বন্ধ করেছে। পণ্য তৈরি এখনো খোলা।
- **vendor নিজের পণ্য বদলাতে পারে না:** products-এর update আর delete নিয়মে `ownsVendorProduct()` আছে, কিন্তু function-টা `firestore.rules`-এ কোথাও সংজ্ঞায়িত নয়। নিয়মটা ১০০০-expression-এর সীমাতেও আটকায়। ফলে লাইভে vendor নিজের পণ্য বদলাতে বা মুছতে পারে না।
- **কাজ:**
  1. পণ্য তৈরি শুধু অনুমোদিত vendor-এর জন্য (`isVendor()` বা vendor ডকুমেন্টের `status == approved`), নিজের `vendorId` দিয়ে।
  2. নতুন পণ্য সবসময় pending বা unpublished থাকবে, admin অনুমোদন দেবে।
  3. `ownsVendorProduct()` লেখা, আর vendor কোন ঘর বদলাতে পারবে তার তালিকা।
  4. emulator test।
  5. লাইভে খোঁজা: কোনো customer আগে এমন পণ্য বানিয়েছে কি না (`vendorId` = কোনো customer-এর uid)।


## পরের কাজ: ৭৪টা পণ্য `needsReview: true` হয়েও লাইভে (এখন হাত দেওয়া হবে না)

- ২৮ নভেম্বর লাইভে গোনা (শুধু পড়া):
  - ২২১টা পণ্যের মধ্যে ৭৪টা `needsReview: true`, অথচ `isActive`, `isPublished` আর `isVisible` তিনটাই true।
  - আরও ১৬টা `needsReview: true` আর `isActive: false`।
- `needsReview` স্বয়ংক্রিয় marketing আটকায়, কিন্তু দোকান, SSR আর sitemap-এ দেখানো আটকায় না।
- আগের পরিকল্পনা (memory "needsReview bulk clear"):
  1. তালিকা বানানো।
  2. মালিকের অনুমোদন।
  3. `lastWriteSource` দিয়ে একসঙ্গে বাতিল করা, যাতে marketing না চলে।
  4. admin-এ "Mark reviewed" বোতাম।
- প্রতিটা লেখার আগে dry-run আর backup।

## 14b ধাপ E (পরে): catch-all-কে "অনুমোদিত তালিকা" বানানো

- **এখনকার নকশা:** catch-all staff আর `analytics.view`-কে **সব** collection পড়তে দেয়, শুধু একটা বাদের তালিকা ছাড়া।
  - Firestore-এ যেকোনো একটা নিয়ম অনুমতি দিলেই পড়া যায়। তাই যেসব collection-এর নিজের কড়া নিয়ম আছে, সেগুলোও staff-এর জন্য খুলে যায়।
  - যেমন `users`, `orders`, `addresses`, `cart`, `wallet_logs`, `user_marketing_profiles`, `tiktok_oauth_states` (নিজের নিয়মে `false`)।
  - নতুন কোনো collection যোগ হলে সেটাও আপনাআপনি খুলে যায়।
- **ধাপ E-র কাজ:**
  1. staff আর `analytics.view` আসলে কোন পাতায় কোন collection পড়ে, তার তালিকা করা: admin dashboard, analytics, orders ইত্যাদি।
  2. catch-all বাদ দিয়ে শুধু সেই collection-গুলোর নিজের নিয়মে `can('analytics.view')` বা নির্দিষ্ট permission দেওয়া।
  3. প্রতিটি role-এর জন্য emulator test লেখা।
  4. `system_locks` আর `analytics_daily`-এর জন্য স্পষ্ট নিয়ম লেখা।
  5. d4ead6c-এর `product_sources` আর `product_import_keys` এই তালিকার বাইরে রাখা।
- **emulator-এ পাওয়া একটা বিষয়:** যে collection শুধু catch-all দিয়ে খোলা, সেখানে list query (`runQuery`) emulator-এ `request.path`-এর error দিয়ে বাতিল হয়। get কাজ করে। ধাপ D-র আগেও এমনই ছিল। লাইভে এমন হয় কি না, ধাপ E-তে দেখতে হবে।
