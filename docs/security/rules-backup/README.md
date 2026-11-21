# লাইভ rules-এর কপি

> **কোথা থেকে deploy করতে হবে** (মালিকের নিয়ম, ২০ নভেম্বর ২০২৬): d4ead6c (product sources আর slugs) নিয়ে সিদ্ধান্ত না হওয়া পর্যন্ত
> **rules আর hosting deploy হবে শুধু `audit-step-c` থেকে** (worktree `C:\FlutterProjects\cc_step_c`), **`wip/audit-step1` থেকে কখনো নয়।**
> কারণ `wip/audit-step1`-এ d4ead6c আছে। সেখানকার `firestore.rules`-এ লাইভে না যাওয়া product নিয়ম আছে, আর hosting-এ আছে d4ead6c-এর কোড।
> তা ছাড়া d4ead6c deploy-এর আগে `product_sources` আর `product_import_keys` catch-all-এর বাদের তালিকায় যোগ করা বাধ্যতামূলক।
> functions-ও শুধু নাম ধরে (`--only functions:<name>`) deploy হবে, `audit-step-c` থেকে।

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
