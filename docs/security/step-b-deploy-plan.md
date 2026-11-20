# 14b ধাপ B: deploy-এর ক্রম

এই ফাইলে শুধু পরিকল্পনা। প্রতিটা ধাপ চলবে মালিকের অনুমতির পরে।

ক্রম (মালিক, ২০ নভেম্বর): ১ → ২ → ২ক → ৫ → ৬। Android release আলাদাভাবে, keystore পাওয়া গেলে।

সব কমান্ড চলবে worktree `C:\FlutterProjects\cc_step_b`-এর মূল ফোল্ডার থেকে, Git Bash-এ, branch `audit-step-b`-এ।
এই branch d7d6761 থেকে খোলা, তাই d4ead6c এতে নেই। শুরুর আগে নিশ্চিত হতে:
`git merge-base --is-ancestor d4ead6c HEAD` চালালে exit code 1 আসতে হবে।

আজকের লাইভ অবস্থা (২০ নভেম্বর ২০২৬):

| কী | লাইভে | কোথা থেকে |
|---|---|---|
| hosting | version `5718e9fbf1f0afea` | d7d6761 |
| Firestore rules | `c34bd793-1b54-472a-96bd-375352ac8f85` | |
| Storage rules | `fc245689-b129-4212-8538-115ae1d3298b` | |

- Storage-এর সেবা আগে থেকেই Firestore পড়তে পারে। কারণ লাইভ storage.rules-এ `firestore.get` আর `firestore.exists` চালু আছে,
  আর `service-1036870421759@gcp-sa-firebasestorage.iam.gserviceaccount.com`-এর
  `roles/firebaserules.firestoreServiceAgent` role আছে।
- তাই Storage rules deploy করার সময় নতুন কোনো অনুমতি দিতে হবে না। CLI যদি তবু
  "grant the role?" জিজ্ঞেস করে, Yes দিলে কোনো ক্ষতি নেই, কারণ role-টা আগে থেকেই আছে।

---

## ধাপ ১: preview channel `step-b`, শুধু পড়ার পরীক্ষা, লাইভ rules যেমন আছে তেমনই

```sh
git merge-base --is-ancestor d4ead6c HEAD; echo $?      # 1 আসতে হবে
flutter clean && flutter pub get
flutter build web --release
firebase hosting:channel:deploy step-b --expires 7d --project chalakchar-mart
# predeploy নিজে চালায়: node tools/web/finalize_web_build.js build/web
```

- **লগইন করতে হলে** Google OAuth Web client-এ preview-এর ঠিকানা যোগ করতে হবে, "secrets" channel-এর মতোই।
  channel মুছে ফেলার সময় ঠিকানাটাও সরাতে হবে।
- **যা দেখবেন:**
  - দোকানের পেজ: ফোন আর ঠিকানা নেই, support কার্ড আছে।
  - admin vendors আর riders পেজ: তথ্য আসে মূল ডকুমেন্টের পুরোনো কপি থেকে, কারণ লাইভ rules private ডকুমেন্ট পড়তে দেয় না।
    কোড এটা "private ডকুমেন্ট নেই" ধরে নেয়, কোনো error দেখায় না।
  - কাগজের বোতামে "on file" দেখায়।
- **⚠ এই ধাপে কিছু save করবেন না:** vendor বা rider-এর আবেদন, admin Edit, payout কিছুই না।
  - preview লাইভ ডেটাই ব্যবহার করে। লাইভ rules-এ private লেখা বাতিল হবে, ফলে মূল অংশ লেখা হবে আর private অংশ হবে না।
- **rollback:** `firebase hosting:channel:delete step-b --project chalakchar-mart`। লাইভে কোনো প্রভাব নেই।
- **কী ভাঙতে পারে:** কিছু না। ওয়েবসাইট আর অ্যাপ যেমন আছে তেমনই থাকে।

## ধাপ ২: Firestore আর Storage rules লাইভে (একসাথে), তারপর preview-তে save পরীক্ষা, তারপর hosting লাইভে

```sh
node tools/rules-test/run.js && node tools/rules-test/run-storage.js   # সব test পাস করতে হবে
firebase deploy --only firestore:rules,storage --project chalakchar-mart
# নতুন ruleset id দুটো docs/security/rules-backup/README.md-এর টেবিলে লেখা হবে
```

এরপর preview `step-b`-এ save-এর পরীক্ষা। এবার লেখা হবে আসল ডেটায়, তাই আপনার অনুমতি নিয়ে শুধু এগুলো:
- admin → vendor Edit-এ শুধু `shopArea` বা commission বদলে save করা।
- vendor_private আর delivery_partner_private-এ ডেটা দেখা যায় কি না দেখা।

সব ঠিক থাকলে hosting লাইভে:

```sh
firebase hosting:clone chalakchar-mart:step-b chalakchar-mart:live --project chalakchar-mart
```

- **rollback:**
  - hosting: `firebase hosting:clone chalakchar-mart@5718e9fbf1f0afea chalakchar-mart:live`
  - Firestore rules: Console → Firestore → Rules → History → `c34bd793…` → Restore।
    এটা চলবে শুধু ধাপ ৫-এর script চলার **আগে**।
  - Storage rules: `cp docs/security/rules-backup/storage.rules.live-2026-11-17 storage.rules && firebase deploy --only storage --project chalakchar-mart && git checkout storage.rules`
- **rules deploy থেকে hosting লাইভ পর্যন্ত (কয়েক মিনিট), পুরোনো ওয়েবসাইট (d7d6761):**
  - নতুন vendor বা rider আবেদন, Profile-এর seller অনুরোধ, vendor withdraw: সব বাতিল।
  - admin-এর vendor Edit-এ ফোন বা payout বদলালে বাতিল। না বদলালে চলে।
  - বাকি সব আগের মতো।
- **staff-এর ছবি দেখা:** যেসব staff-এর vendor বা rider-এর অনুমতি নেই, তারা NID বা trade license-এর ফাইল আর পড়তে পারবে না।
  rider-এর ছবি এখনো পুরোনো token-সহ লিংক দিয়ে খোলে, যতক্ষণ না ধাপ C-তে token বাতিল হয়।
- **পুরোনো অ্যাপ** (Play-তে এখন যে build আছে): নিচের "পুরোনো অ্যাপ" টেবিলের "ধাপ ২ থেকে ৫" কলাম।

## ধাপ ২ক: vendor আর rider-কে জানানো (ধাপ ২-এর পরপরই)

- মালিক দুজনকে জানাবেন: নতুন Android অ্যাপ আসা পর্যন্ত vendor-এর প্রোফাইল, আবেদন আর withdraw **ওয়েবসাইট থেকে**
  (chalakcharmart.com) করতে হবে। পুরোনো অ্যাপে এগুলো ব্যর্থ হবে (নিচের টেবিল)।
- rider-এর dashboard, আয় আর COD sync পুরোনো অ্যাপেই চলে, তাই rider-এর কিছু বদলাতে হবে না।
- কোনো কমান্ড নেই। rollback-ও নেই।

## ধাপ ৫: script, ধাপ ২ক-এর পরে (Play release-এর জন্য অপেক্ষা নয়), আগে dry-run, তারপর মালিকের অনুমোদন, তারপর `--apply`, তারপর যাচাই

শুরুর শর্ত: মালিক vendor আর rider-কে website ব্যবহারের কথা জানিয়ে বলবেন। তার আগে কিছু শুরু হবে না।
প্রতিটি `--apply` আলাদা অনুমোদনে চলবে। প্রতিটা উপধাপের পর থেমে রিপোর্ট দিতে হবে। রিপোর্টে কোনো মান লেখা যাবে না, শুধু key-এর নাম আর দৈর্ঘ্য।
সব কমান্ড চলবে `C:\FlutterProjects\cc_step_b`-এ, Git Bash-এ। script চলবে `functions/` থেকে।
`firebase-admin` লাগলে কমান্ডের আগে `NODE_PATH=C:/FlutterProjects/chalakchar_mart/functions/node_modules` যোগ করতে হবে, অথবা `functions/`-এ `npm ci` চালাতে হবে।

### ক. Firestore export

- **কোথায় যাবে:** `gs://chalakchar-mart-backups`। bucket-টা তৈরি হয়েছে 2026-11-20, অঞ্চল asia-south1।
  - uniform access আর public access prevention চালু।
  - lifecycle নিয়ম: ৩০ দিন পর object নিজে থেকে মুছে যায়। তারপর আরও ৭ দিন soft-delete অবস্থায় থাকে। এটা GCS-এর default নিয়ম।
  - bucket-এর IAM-এ আছে শুধু project owner আর Firestore service agent। agent-এর role `roles/storage.legacyBucketWriter`।
- **কমান্ড:**
  ```sh
  STAMP=$(date -u +%Y%m%d-%H%M)
  gcloud firestore export gs://chalakchar-mart-backups/step-b-$STAMP \
    --collection-ids=vendors,deliveryPartners,vendor_private,delivery_partner_private,users \
    --project chalakchar-mart
  ```
- **সফল হলো কি না কীভাবে বুঝব:**
  - কমান্ডটা শেষ না হওয়া পর্যন্ত অপেক্ষা করে (`--async` ছাড়া)। শেষে operation-এর বিবরণ দেখায়। সেখানে `operationState: SUCCESSFUL` থাকতে হবে।
  - পরে আবার দেখতে চাইলে: `gcloud firestore operations list --project chalakchar-mart --limit=3`
  - `gcloud storage ls -r gs://chalakchar-mart-backups/step-b-$STAMP/` চালালে `step-b-$STAMP.overall_export_metadata` ফাইল আর `all_namespaces/...` ফোল্ডার দেখাবে।
  - এর কোনোটা না মিললে থামতে হবে। বাকি উপধাপ শুরু হবে না।

### খ. vendor-এর পুরোনো `ownerName` মোছা (`clearPublicOwnerName.js`)

- **কারণ:** `vendors/{id}.ownerName`-এ পুরোনো ভুল মান আছে। ঠিক মান আছে `vendor_private`-এ। এটা না মুছলে গ-এর script CONFLICT ধরে থেমে যাবে।
- **নিয়ম:**
  - script মোছে শুধু ওই একটা key।
  - `vendor_private`-এ ownerName না থাকলে বা খালি থাকলে মোছে না (exit 2)।
  - মোছার আগে backup রাখে: `~/cc-backups/clear_public_ownerName_<সময়>.json`। ফরম্যাট movePrivateProfiles-এর backup-এর মতোই।
  - transaction-এর ভেতরে আবার মিলিয়ে দেখে, তারপর মোছে। শেষে আবার পড়ে যাচাই করে।
  - দ্বিতীয়বার চালালে "Nothing to do" দেখায়।
  - এর test: `node tools/rules-test/run-move-script.js` (emulator), আর `functions/test/clearPublicOwnerName.test.js`।
- **কমান্ড:**
  ```sh
  cd functions
  node scripts/clearPublicOwnerName.js vmcQG3naz6RGutEiiiWZNBhz4Dm2            # dry-run
  # -> মালিকের অনুমোদন
  node scripts/clearPublicOwnerName.js vmcQG3naz6RGutEiiiWZNBhz4Dm2 --apply
  ```
- **dry-run-এ যা প্রত্যাশিত:**
  - `plan: delete (vendor_private already has ownerName)`
  - `Dry run: would delete vendors/vmcQ….ownerName`
- **যাচাই:**
  - script শেষে `Done.` দেখাবে।
  - `node scripts/movePrivateProfiles.js` (dry-run) চালালে আর CONFLICT থাকবে না।
- **rollback:**
  ```sh
  node scripts/restorePrivateProfiles.js --from-backup ~/cc-backups/clear_public_ownerName_<সময়>.json            # dry-run
  node scripts/restorePrivateProfiles.js --from-backup ~/cc-backups/clear_public_ownerName_<সময়>.json --apply
  ```

### গ. গোপন মান সরানো (`movePrivateProfiles.js`)

- **কমান্ড:**
  ```sh
  node scripts/movePrivateProfiles.js            # dry-run: id, key-এর নাম, দৈর্ঘ্য
  # -> মালিকের অনুমোদন
  node scripts/movePrivateProfiles.js --apply    # backup: ~/cc-backups/private_profiles_<সময়>.json
  ```
- **dry-run-এ যা প্রত্যাশিত (2026-11-20-এর পড়া অনুযায়ী):** ২টা ডকুমেন্ট বদলাবে।
  - **vendor:** phone, email, address, note আর payoutAccount যাবে private-এ। আগে থেকেই একই মান থাকলে আবার লেখা হবে না।
  - **vendor-এর ৩টা link** (nidFront, nidBack, tradeLicense) `*Path` হয়ে যাবে। link-গুলো মুছে যাবে।
  - **rider:** `delivery_partner_private` এখন খালি। nidNumber, nidFrontPath, nidBackPath, address আর email লেখা হবে।
  - **rider-এর মূল ডকুমেন্ট থেকে সরবে:** nidFrontUrl, nidBackUrl আর note।
  - কোনো CONFLICT থাকবে না।
- **যাচাই:**
  - script শেষে `No private key left in vendors or deliveryPartners` দেখাবে। না দেখালে exit 3।
  - dry-run আবার চালালে `Nothing to move` দেখাবে।
  - লগইন ছাড়া `vendors/<id>` পড়লে কোনো গোপন key-এর নাম থাকবে না। `vendor_private/<id>` আর `delivery_partner_private/<id>` পড়লে 403 আসবে।

### ঘ. লাইভে চোখে দেখা (chalakcharmart.com, কিছু save না করে)

- **admin → Vendors:**
  - দোকান "Abdullah Pharmacy" দেখাবে।
  - Edit খুললে owner name, ফোন, ঠিকানা, payout আর commission ১০ দেখাবে।
  - ৩টা কাগজ "on file" দেখাবে। ধাপ ৫-এর আগে এগুলো link থেকে আসত, এখন path থেকে আসে।
- **admin → Delivery Partners:** rider-এর NID নম্বর, ঠিকানা আর ২টা NID কাগজ "on file" দেখাবে।
- **vendor লগইন → My Shop / dashboard:** balance আর commission আগের মতোই দেখাবে।
- **vendor লগইন → Withdraw:** payout account দেখাবে, "Please add payout account first" দেখাবে না। request জমা দেওয়া হবে না।
- **দোকানের পেজ (লগইন ছাড়া):** ফোন আর ঠিকানা দেখাবে না। ChalakChar support-এর যোগাযোগ দেখাবে।
- **rider লগইন → dashboard:** আয়, COD আর অর্ডার আগের মতোই দেখাবে।
- **সব জায়গায়:** browser console-এ permission-denied থাকবে না।

### ঙ. rollback (ধাপ ৫-এর পরে শুধু এভাবে)

- **মানগুলো মূল ডকুমেন্টে ফেরানো:**
  ```sh
  node scripts/restorePrivateProfiles.js --from-backup ~/cc-backups/private_profiles_<সময়>.json            # dry-run
  node scripts/restorePrivateProfiles.js --from-backup ~/cc-backups/private_profiles_<সময়>.json --apply
  ```
  - এতে পুরোনো link-সহ মান ফেরে। private ডকুমেন্ট যেমন আছে তেমন থাকে।
  - backup না থাকলে `--from-private` দিয়ে চালানো যায়, তবে তাতে link ফেরে না।
  - মূল ডকুমেন্টে ভিন্ন মান থাকলে script কিছু লেখার আগেই থেমে যায় (exit 2)।
  - `ownerName`-ও ফেরাতে হলে খ-এর backup দিয়ে আলাদাভাবে চালাতে হবে।
- **rules ফেরানো: শুধু এই ফাইল দিয়ে।**
  ```sh
  cp docs/security/rules-backup/firestore.rules.rollback-step-b firestore.rules
  firebase deploy --only firestore:rules --project chalakchar-mart
  git checkout firestore.rules
  ```
  `rollback-keep-secrets`, `live-2026-11-17` বা Console-এর পুরোনো কোনো ruleset ব্যবহার করা যাবে **না**। কারণ সেগুলোতে private collection-এর কোনো নিয়ম নেই। তাই catch-all-এর মাধ্যমে যেকোনো staff role সেগুলো পড়তে পারে।
- **ক্রম:**
  1. আগে মান ফেরানো (restore)।
  2. তারপর rules ফেরানো।
  3. দরকার হলে hosting ফেরানো: `firebase hosting:clone chalakchar-mart@5718e9fbf1f0afea chalakchar-mart:live --project chalakchar-mart`। কারণ rollback-step-b-তে private collection বন্ধ, তাই নতুন website private থেকে কিছু পড়তে পারে না।
- **শেষ উপায়:** `gcloud firestore import gs://chalakchar-mart-backups/step-b-<STAMP> --collection-ids=vendors,deliveryPartners,vendor_private,delivery_partner_private,users --project chalakchar-mart`।
  - এতে export-এর পরে লেখা একই id-র ডকুমেন্ট আগের অবস্থায় ফিরে যায়।
  - export-এর পরে নতুন তৈরি হওয়া ডকুমেন্ট মোছে না।
- **প্রভাব:**
  - নতুন website আর নতুন অ্যাপে কিছু বদলায় না, কারণ এরা private থেকেই পড়ে।
  - পুরোনো অ্যাপের জন্য নিচের টেবিলের "ধাপ ৫-এর পরে" কলাম দেখুন।

## ধাপ ৬: rules-এর দ্বিতীয় ধাপ

এখন মূল ডকুমেন্টে আর পুরোনো কপি নেই, তাই:
- মূল `vendors` আর `deliveryPartners`-এ গোপন key-এর জন্য "আগের মতো বা ফাঁকা" ছাড় তুলে দেওয়া। এর জায়গায় সোজা নিয়ম:
  `!request.resource.data.keys().hasAny(...)`। এতে expression-ও কম লাগে।
- `vendor_private`-এ মালিক আর পুরোনো লিংকের key লিখতে পারবে না: `nidFront`, `nidBack`, `tradeLicense`।
- rider-এর retry rule থাকবে, এর দরকার আছে।

```sh
node tools/rules-test/run.js       # নতুন test-সহ
firebase deploy --only firestore:rules --project chalakchar-mart
```

- **rollback:** Console History থেকে ধাপ ২-এর ruleset-এ Restore। এটা নিরাপদ, কারণ ওই ruleset-ও private ডকুমেন্ট বন্ধ রাখে।
- **প্রভাব:** এই ধাপে কোনো কপি বাকি থাকে না। তাই পুরোনো অ্যাপের "আগের মতো" মান পাঠানো save-ও বাতিল হবে,
  যেমন খোলা থাকা পুরোনো admin form। পুরোনো অ্যাপের জন্য ধাপ ৫-এর টেবিলই খাটে।

---

## আলাদা কাজ: Android release (keystore পাওয়া গেলে, ধাপ ৫-এর জন্য অপেক্ষা নয়)

মালিকের সিদ্ধান্ত (২০ নভেম্বর): ধাপ ৫ Play release-এর জন্য অপেক্ষা করবে না। keystore পাওয়া গেলে নিচের ক, খ আলাদাভাবে হবে।

### ক. audit-step-b থেকে নতুন Android release build, তারপর Play-তে জমা

**আগে যা লাগবে** (এখন repo-তে নেই):
1. **upload keystore** (`.jks`) আর `android/key.properties`। এতে থাকে storePassword, keyPassword, keyAlias আর storeFile।
   - এটা git-এ রাখা যাবে না।
   - Play App Signing চালু থাকলে Play Console-এ যে upload key নিবন্ধিত আছে, সেই key-ই লাগবে।
     হারিয়ে গেলে Play Console → App integrity → "Request upload key reset"।
2. `android/app/build.gradle.kts` এখন `android/key.properties` থেকে release-এর signing পড়ে (audit-step-b)।
   ফাইলটা না থাকলে বা কোনো ঘর ফাঁকা থাকলে release build থেমে যায়, স্পষ্ট বার্তা দেয়, debug key দিয়ে আর সই হয় না
   (পরীক্ষা করা হয়েছে: `flutter build apk --release` → "Release signing is not configured…")।
   key.properties আর `*.jks` `.gitignore`-এ আছে।
3. **version:** pubspec-এ এখন `1.0.0+1`, যেটা প্রথম commit থেকে কখনো বদলায়নি।
   - নতুন versionCode অবশ্যই Play-তে এখনকার versionCode-এর চেয়ে বড় হতে হবে। মান দেখতে হবে Play Console → App bundle explorer-এ।
   - উদাহরণ: `--build-name=1.0.1 --build-number=<Play-এর এখনকার versionCode + 1>`।

```sh
flutter clean && flutter pub get
flutter test                       # সব পাস করতে হবে
flutter build appbundle --release --build-name=1.0.1 --build-number=<N>
# ফল: build/app/outputs/bundle/release/app-release.aab -> Play Console -> Internal testing -> তারপর Production
```

- **rollback:** Play-তে আগের release-এ ফেরা যায় না। ভুল থাকলে নতুন versionCode দিয়ে ঠিক করা build জমা দিতে হবে।
  তবে staged rollout থামানো যায়।
- **প্রভাব:** কিছু না, যতক্ষণ না ব্যবহারকারী update করছেন। Play-এর review-এ কয়েক ঘণ্টা থেকে কয়েক দিন লাগতে পারে।

### খ. Play-তে নতুন অ্যাপ এলে মালিক vendor আর rider-কে update করাবেন

- দুজনে অ্যাপ খুলে লগইন করবেন।
- নতুন অ্যাপ এখনো platform বা version লেখে না, এটা তালিকায় আছে। তাই update হয়েছে কি না নিশ্চিত হতে হবে
  দুজনের কাছে জিজ্ঞেস করে। Play Store-এ অ্যাপের পাতায় "Update" বোতাম না থাকলে update হয়ে গেছে।

---

## পুরোনো অ্যাপ: কে কী দেখবে

Play-তে এখন কোন build আছে তা repo থেকে জানা যায় না। নিচের টেবিল ধরে নিয়েছে যে Play-এর অ্যাপে ধাপ B-এর আগের কোড চলছে।

| পেজ | ধাপ ২ থেকে ৫-এর মধ্যে | ধাপ ৫-এর পরে, update না করলে | ব্যবহারকারী কী দেখেন |
|---|---|---|---|
| **vendor-এর আবেদন** | নতুন আবেদন বাতিল হয়, কারণ ফোন আর payout মূল ডকুমেন্টে যায়। কাগজ Storage-এ আগেই উঠে যায়, তাই অনাথ ফাইল থেকে যায়। approved vendor-এর ফর্ম এমনিতেই বন্ধ | ফর্মে ফোন, ঠিকানা আর payout ফাঁকা, কাগজ "missing" দেখায়। save বাতিল | লাল snackbar: "Submit failed: [cloud_firestore/permission-denied] …"। ভুলটা দেখা যায়, তবে কারিগরি ভাষায় |
| **rider-এর আবেদন** | বাতিল, কারণ NID মূল ডকুমেন্টে যায়। ছবি Storage-এ আগেই উঠে যায় | একই | লাল snackbar: "Submit failed: …" |
| **vendor dashboard** | চলে। balance মূল ডকুমেন্ট থেকে আসে (লাইভ vendor-এর ০) | balance আর commission ০ বা ফাঁকা দেখায়, তবে ভাঙে না | চুপচাপ ভুল সংখ্যা (আজ ০, তাই একই দেখায়) |
| **vendor withdraw** | request বাতিল, কারণ `vendorPhone` আর `vendorEmail` আর রাখা যায় না | "Please add payout account first", কারণ payout মূল ডকুমেন্টে আর নেই | ধাপ ২-৫-এ লাল snackbar "Withdraw failed: …", ধাপ ৫-এর পরে ওই বার্তা |
| **rider dashboard** | চলে | চলে। টাকা আর নাম মূল ডকুমেন্টেই থাকে | — |
| **rider-এর আয় আর COD sync** | চলে (`validRiderMoneySync` বদলায়নি) | চলে | — |
| **Profile → seller অনুরোধ** | বাতিল, কারণ ফোন, ঠিকানা আর commission মূল ডকুমেন্টে যায় | একই | **চুপচাপ ব্যর্থ।** `requestSellerAccount`-এ try/catch নেই, তাই dialog খোলা থাকে, কিছুই দেখায় না |
| admin পেজ (অ্যাপে) | চলে, পুরোনো কপি থেকে | NID, ফোন আর payout ফাঁকা | — |
| দোকানের পেজ, পণ্য, cart | চলে | চলে। পুরোনো অ্যাপ দোকানের পেজে ফোন আর ঠিকানা খোঁজে, পায় না, তাই কিছু দেখায় না | — |
