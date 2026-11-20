# 14b ধাপ C: admin-এর জন্য পরিচয়ের কাগজ দেখা (৫ মিনিটের signed URL)

branch `audit-step-c` (worktree `C:\FlutterProjects\cc_step_c`), শুরু `audit-step-b` (a453e3a) থেকে।
d4ead6c এতে নেই, `git merge-base --is-ancestor` দিয়ে যাচাই করা।
কিছুই deploy হয়নি।

## ১. Cloud Function `getIdentityDocumentUrl(kind, ownerId, which)`

ফাইল: `functions/identity/identityDocumentUrl.js`। export আছে `functions/index.js`-এ। region asia-south1, maxInstances 2।

- **ইনপুট:**
  - `kind`: `vendor` বা `rider`।
  - `which`: vendor-এর জন্য `nidFront`, `nidBack` বা `tradeLicense`। rider-এর জন্য `nidFront` বা `nidBack`।
  - `ownerId`: vendor-এর ডকুমেন্ট id অথবা rider-এর uid। শুধু অক্ষর, সংখ্যা, `_` আর `-` চলবে।
- **অনুমতি (server-এ যাচাই হয়):** `users/{uid}` পড়া হয়। নিয়ম storage.rules-এর মতোই।
  - role বা roles-এ admin, superAdmin বা super_admin থাকলে সবসময় দেখা যায়।
  - vendor-এর কাগজ দেখতে লাগবে `vendors.view`, `vendors.edit`, `vendors.approve` বা `vendors.payouts`-এর যেকোনো একটা।
  - rider-এর কাগজ দেখতে লাগবে `delivery.view`, `delivery.approve` বা `delivery.block`-এর যেকোনো একটা।
  - account banned (`isBanned`) বা বন্ধ (`isActive: false`) থাকলে কিছুই পাওয়া যাবে না।
- **path:** client থেকে কখনো নেওয়া হয় না। client কিছু পাঠালেও উপেক্ষা হয়, test-এ এটা দেখানো আছে।
  - path পড়া হয় `vendor_private/{ownerId}` বা `delivery_partner_private/{ownerId}`-এর `*Path` field থেকে।
  - path-কে মালিকের নিজের ফোল্ডারের ভেতরে থাকতে হবে: `vendors/{ownerId}/documents/…` বা `delivery_partner_documents/{ownerId}/…`।
  - path-এ `..`, `//` বা `\` থাকলে বাতিল হয়।
- **ফল:** `{ url, expiresAt }` ফেরত আসে।
  - url হলো V4 signed URL। শুধু পড়া যায়, মেয়াদ ঠিক ৫ মিনিট।
  - কোথাও save হয় না: Firestore-এ না, log-এ না, অ্যাপে লেখা হিসেবেও দেখানো হয় না।
- **ভুলের বার্তা:** `unauthenticated`, `permission-denied`, `invalid-argument`, `not-found` (কাগজ নেই বা ফাইল নেই), `failed-precondition` (path মালিকের ফোল্ডারের বাইরে)।
- **Log:** Cloud Logging-এ যায়, বার্তা `identity document viewed`।
  - শুধু পাঁচটা field থাকে: `viewerUid`, `ownerId` (কার কাগজ, মালিকের সিদ্ধান্ত), `kind`, `which`, `at`।
  - path, URL বা কোনো ব্যক্তিগত মান থাকে না।
  - Firestore-এ log রাখা হয়নি। কারণ সেখানে রাখলে catch-all নিয়মের কারণে staff সেটা পড়তে পারত।
- **Test:**
  - `functions/test/identityDocumentUrl.test.js`: ৭টা unit test।
  - `node tools/rules-test/run-identity-doc.js`: Firestore আর Storage emulator-এ ৬টা test। শুধু signing অংশটা বদলে দেওয়া, কারণ ওটার জন্য আসল service account লাগে।

### আলাদা service account `identity-docs-viewer` (মালিক নিজে চালাবেন)

মালিকের সিদ্ধান্ত (২০ নভেম্বর): default compute account-কে signBlob-এর অনুমতি দেওয়া হবে না।
তাই `getIdentityDocumentUrl` চলবে নিজের service account দিয়ে।
কোডে `onCall({ serviceAccount: "identity-docs-viewer@chalakchar-mart.iam.gserviceaccount.com" })` বসানো আছে।
account-টা না থাকলে deploy ব্যর্থ হবে।
deploy যিনি করবেন, তাঁর account-এ `iam.serviceAccounts.actAs` লাগবে। Owner-এর এটা আছে।

```sh
# ১. account তৈরি
gcloud iam service-accounts create identity-docs-viewer \
  --display-name="Identity documents viewer (getIdentityDocumentUrl)" --project chalakchar-mart

# ২. Firestore: শুধু ডকুমেন্ট পড়া। custom role, যাতে একটাই অনুমতি আছে: datastore.entities.get।
#    এতে list, query, লেখা বা মোছা কিছুই নেই।
gcloud iam roles create identityDocsFirestoreGet --project chalakchar-mart \
  --title="Identity docs: Firestore get only" --permissions=datastore.entities.get --stage=GA

# ৩. ওপরের role-টা account-কে দেওয়া (project স্তরে)
gcloud projects add-iam-policy-binding chalakchar-mart \
  --member=serviceAccount:identity-docs-viewer@chalakchar-mart.iam.gserviceaccount.com \
  --role=projects/chalakchar-mart/roles/identityDocsFirestoreGet --condition=None

# ৪. Storage: শুধু default bucket-এ ফাইল পড়া (objectViewer)। কোন prefix, তা নিচের "Storage prefix" অংশে দেখুন।
gcloud storage buckets add-iam-policy-binding gs://chalakchar-mart.firebasestorage.app \
  --member=serviceAccount:identity-docs-viewer@chalakchar-mart.iam.gserviceaccount.com \
  --role=roles/storage.objectViewer

# ৫. signBlob: account শুধু নিজের নামে sign করতে পারবে (Token Creator, শুধু নিজের ওপর)
gcloud iam service-accounts add-iam-policy-binding identity-docs-viewer@chalakchar-mart.iam.gserviceaccount.com \
  --member=serviceAccount:identity-docs-viewer@chalakchar-mart.iam.gserviceaccount.com \
  --role=roles/iam.serviceAccountTokenCreator --project chalakchar-mart
```

- **Firestore-এর সীমা:**
  - Firestore-এর IAM collection অনুযায়ী ভাগ করা যায় না। IAM condition শুধু database-এর নাম ধরে কাজ করে।
  - তাই `datastore.entities.get`-এর মানে, id জানা থাকলে যেকোনো ডকুমেন্ট পড়া যায়।
  - তবে কোড পড়ে মাত্র তিনটে জিনিস: `users/{uid}`, `vendor_private/{id}` আর `delivery_partner_private/{id}`।
  - predefined role-এর মধ্যে সবচেয়ে ছোট হলো `roles/datastore.viewer`, কিন্তু তাতে list আর query-ও আছে। custom role তার চেয়ে ছোট।
  - "roles পড়তে যা লাগে": অনুমতি যাচাই হয় `users/{uid}` ডকুমেন্টের role, roles আর permissions field থেকে। আলাদা কোনো `roles` collection পড়া হয় না।
- **Log লেখা:** কোনো role লাগে না।
  - firebase-functions-এর logger stdout-এ লেখে, আর Cloud Run platform নিজেই সেটা Cloud Logging-এ পাঠায়।
  - `roles/logging.logWriter` ইচ্ছা করেই দেওয়া হয়নি।
  - deploy-এর পর log-এ লাইন আসছে কি না দেখা হবে। না এলে তখন এটা দেওয়া হবে।
- **Storage prefix (IAM condition):**
  - bucket `chalakchar-mart.firebasestorage.app`-এ **uniform bucket-level access বন্ধ** (পড়ে দেখা)।
  - Cloud Storage-এ IAM condition কাজ করে শুধু uniform access চালু থাকলে। তাই এখন prefix-এর condition বসানো যায় না, gcloud ভুল দেবে।
  - **বিকল্প ক (প্রস্তাবিত):** condition ছাড়াই objectViewer দেওয়া, ওপরের ৪ নম্বর কমান্ড।
    - bucket-এর বাকি অংশে আছে products, banners, categories আর vendors-এর ছবি। এগুলো এমনিতেই সবার জন্য খোলা (download link দিয়ে)।
    - account-টা বানানোই হয়েছে গোপন কাগজ পড়ার জন্য। তাই condition দিয়ে বাড়তি সুরক্ষা খুব সামান্য।
  - **বিকল্প খ:** আগে bucket-এ uniform access চালু করা, তারপর condition দেওয়া। এতে পুরোনো object-ACL বন্ধ হয়ে যায়। Firebase-এর download link আর rules আগের মতোই চলে, তবে ACL-নির্ভর কিছু থাকলে ভাঙবে। ৯০ দিনের মধ্যে আবার বন্ধ করা যায়। এটা আলাদা ঝুঁকি, আলাদা test লাগবে।
    ```sh
    gcloud storage buckets update gs://chalakchar-mart.firebasestorage.app --uniform-bucket-level-access
    gcloud storage buckets add-iam-policy-binding gs://chalakchar-mart.firebasestorage.app \
      --member=serviceAccount:identity-docs-viewer@chalakchar-mart.iam.gserviceaccount.com \
      --role=roles/storage.objectViewer \
      --condition='title=identity-docs-only,expression=resource.name.startsWith("projects/_/buckets/chalakchar-mart.firebasestorage.app/objects/vendors/") || resource.name.startsWith("projects/_/buckets/chalakchar-mart.firebasestorage.app/objects/delivery_partner_documents/")'
    ```
    - বিকল্প খ-তেও `vendors/` prefix-এর ভেতরে যা আছে, তা পুরোটাই পড়া যাবে। এখন সেখানে শুধু `vendors/{id}/documents/` আছে, ৩টা ফাইল।
- **যাচাই (মালিক চালানোর পরে, শুধু পড়া):**
  ```sh
  gcloud projects get-iam-policy chalakchar-mart --flatten=bindings --filter="bindings.members:identity-docs-viewer" --format="value(bindings.role)"
  gcloud storage buckets get-iam-policy gs://chalakchar-mart.firebasestorage.app --format=json | grep -B3 identity-docs-viewer
  gcloud iam service-accounts get-iam-policy identity-docs-viewer@chalakchar-mart.iam.gserviceaccount.com
  ```
- **rollback:** `gcloud iam service-accounts delete identity-docs-viewer@chalakchar-mart.iam.gserviceaccount.com`। custom role মুছতে: `gcloud iam roles delete identityDocsFirestoreGet --project chalakchar-mart`।

### CORS: admin-এর dialog-এ ছবি দেখানো

- **ছবি দেখানোর পদ্ধতি:** `Image.network(url)`। Flutter 3.38-এ web-এ এর default `webHtmlElementStrategy.never`।
  - মানে ছবি HTML `<img>` দিয়ে দেখানো হয় না। browser `fetch` দিয়ে byte নামায়।
  - তাই `storage.googleapis.com`-কে CORS header পাঠাতে হয়।
- **bucket-এ এখনকার CORS** (পড়ে দেখা): `[{ origin: ["*"], method: ["GET"], maxAgeSeconds: 3600 }]`।
  - অর্থাৎ CORS এখনই ঠিক আছে, signed URL থেকে ছবি দেখাতে **নতুন কিছু লাগবে না**।
  - CORS কোনো অনুমতি দেয় না। এটা শুধু ঠিক করে, browser পাতা উত্তরটা পড়তে পারবে কি না। signed URL ছাড়া ফাইল খোলে না।
- **ছোট CORS নিয়ম** (মালিকের অনুরোধে লেখা, বসানো হয়নি)। ⚠️ CORS পুরো bucket-এ খাটে, তাই এটা বসালে পুরোনো `*` নিয়ম চলে যাবে।
  - তখন অন্য preview channel (যেমন `related`, `notif`) আর localhost-এ পণ্য, banner আর category-র ছবি নাও দেখাতে পারে।
  - নতুন preview channel খুললে প্রতিবার তার origin যোগ করতে হবে।
  - এখন না বসানোর প্রস্তাব দিচ্ছি।
  ```json
  [
    {
      "origin": [
        "https://chalakcharmart.com",
        "https://chalakchar-mart.web.app",
        "https://chalakchar-mart--step-c-<HASH>.web.app"
      ],
      "method": ["GET"],
      "responseHeader": ["Content-Type"],
      "maxAgeSeconds": 300
    }
  ]
  ```
  বসাতে হলে: `gcloud storage buckets update gs://chalakchar-mart.firebasestorage.app --cors-file=cors.json`।
  ফেরাতে: একই কমান্ড, `[{"origin":["*"],"method":["GET"],"maxAgeSeconds":3600}]` দিয়ে।
  `www.chalakcharmart.com` চালু থাকলে সেটাও তালিকায় যোগ করতে হবে।

### step-c preview: OAuth client আর Auth domain

- **preview-এর ঠিকানা:** `https://chalakchar-mart--step-c-<HASH>.web.app`।
  - `<HASH>` হলো ৮ অক্ষরের একটা এলোমেলো অংশ। channel তৈরির সময় Firebase এটা বানায়, আগে থেকে জানা যায় না। যেমন step-b-র ছিল `09kqlelw`।
  - **সমাধান:** ধাপ ১-এর আগে শুধু channel তৈরি করা, কোনো ফাইল ছাড়া: `firebase hosting:channel:create step-c --expires 7d --project chalakchar-mart`।
  - এতে লাইভে কিছু বদলায় না। ঠিকানাটা এখান থেকে জানা যাবে। মালিক অনুমতি দিলে করব।
- **Google OAuth web client** (Google Cloud Console → APIs & Services → Credentials → Web client):
  - Authorized JavaScript origins: `https://chalakchar-mart--step-c-<HASH>.web.app`
  - Authorized redirect URIs: `https://chalakchar-mart--step-c-<HASH>.web.app/__/auth/handler`
- **Firebase Auth authorized domains:** `hosting:channel:deploy` এটা নিজে থেকে যোগ করে, step-b-তেও তাই হয়েছিল। না হলে Console থেকে হাতে যোগ করতে হবে।

## ২. admin পেজে কাগজ খোলা

- `lib/widgets/identity_document_dialog.dart`: callable ডেকে dialog-এ ছবি দেখায়। ছবি zoom করা যায়, আর Reload ও Close বোতাম আছে।
  - URL থাকে শুধু dialog-এর ভেতরে, কোথাও লেখা হয় না।
  - ভুল হলে সহজ বাংলা বার্তা দেখায়। কারিগরি ভাষা থাকে শুধু debugPrint-এ।
- **admin → Vendors:** কার্ডের "Trade License / NID Front / NID Back: on file" বোতামে চাপলে dialog খোলে। বোতামটা আগের মতোই `vendors.documents` অনুমতি থাকলেই দেখা যায়।
- **admin → Delivery Partners:** "Front Side / Back Side: on file" কার্ডে চাপলে dialog খোলে।
- **লক্ষ করার বিষয়:**
  - বোতাম দেখানো ঠিক হয় অ্যাপের `vendors.documents` বা `delivery` অনুমতি দিয়ে।
  - কিন্তু server মানে উপরের তালিকা।
  - কারো যদি `vendors.documents` থাকে কিন্তু `vendors.view` না থাকে, সে বোতাম দেখবে কিন্তু খুলতে পারবে না ("অনুমতি নেই")।
  - admin-এর ক্ষেত্রে এই সমস্যা নেই, কারণ admin-এর default তালিকায় দুটোই আছে।
- **Test:** `test/identity_document_dialog_test.dart`।

## ৩. এখনকার download token বাতিল

- **এখনকার অবস্থা** (২০ নভেম্বর পড়া, মান দেখা হয়নি): ৫টা ফাইলের প্রতিটিতে ১টা করে token আছে।
  - vendor-এর ৩টা: owner আগে Console থেকে revoke করেছিলেন, Console তখন নিজে থেকে নতুন token বানিয়েছে।
  - rider-এর ২টা: পুরোনো token।
- **কেন বাতিল করা দরকার:**
  - token থাকলে যার কাছে link আছে সে-ই ফাইল খুলতে পারে, কোনো লগইন ছাড়া।
  - পুরোনো link এখনো আছে `~/cc-backups/private_profiles_2026-11-20T10-15-21-735Z.json`-এ।
- **কে করবে: script দিয়ে**, `functions/scripts/revokeIdentityDocTokens.js`। Console নয়, কারণ Console-এর "Revoke" নতুন একটা token বানিয়ে দেয়।
  - script `firebaseStorageDownloadTokens` metadata key মুছে দেয়, নতুন কিছু বানায় না।
  - ফাইল বা অন্য কোনো metadata ছোঁয় না।
  - ফাইল বাছে শুধু private ডকুমেন্টের `*Path` থেকে, আর শুধু মালিকের ফোল্ডারের ভেতরের ফাইল।
  - আগে dry-run চালায়, তারপর `--apply`, তারপর নিজে আবার পড়ে যাচাই করে। কোনো token থেকে গেলে exit 3।
  - token-এর মান কখনো print বা save হয় না।
  - record হিসেবে শুধু ফাইলের নাম আর token-এর সংখ্যা রাখে: `~/cc-backups/identity_doc_tokens_removed_<সময়>.json`।
  - **মালিকের নিশ্চিত করা দরকার:** এখানে "backup" ইচ্ছা করেই রাখা হয়নি। কারণ পুরোনো token ফেরানো মানে বিপদটা ফিরিয়ে আনা।
- **emulator-এর সীমা:** Storage emulator token key কখনো মোছে না, `metadata: null` দিলেও। এটা ২০ নভেম্বর পরীক্ষা করা হয়েছে।
  - তাই emulator test দেখায়: script ঠিক ফাইলগুলোই বাছে, token print করে না, আর না মুছলে নিজের যাচাইয়ে ধরে ফেলে (exit 3)।
  - আসল GCS-এ মোছার পদ্ধতি হলো `setMetadata({ metadata: { key: null } })`, যা GCS JSON API-এর নিয়মিত পদ্ধতি। লাইভে প্রথম চালানোর পর script-এর নিজের যাচাই আর আমার আলাদা পড়া দিয়ে এটা নিশ্চিত করা হবে।
- **signed URL token ছাড়া কাজ করে কি না:**
  - signed URL যায় `storage.googleapis.com`-এ, আর যাচাই হয় service account-এর signature আর IAM দিয়ে।
  - Firebase-এর download token ব্যবহার করে `firebasestorage.googleapis.com/...?token=` link, যেটা একেবারে আলাদা পথ।
  - তাই token মুছলে signed URL-এ কোনো প্রভাব পড়ে না।
  - লাইভে নিশ্চিত করার ধাপ: token মোছার পর admin থেকে ৫টা কাগজই আবার খুলে দেখা।
  - সঙ্গে পুরোনো link (backup ফাইলে আছে) খুললে 403 আসছে কি না দেখা। শুধু HTTP code দেখা হবে, মান নয়।
- **পরে নতুন token তৈরি হতে পারে কি না:**
  - নতুন অ্যাপ কাগজের জন্য `getDownloadURL` ডাকে না।
  - পুরোনো Android build নতুন upload-এর পর ডাকতে পারে। কিন্তু Storage rules অনুযায়ী upload শুধু আবেদন খোলা থাকার সময় মালিক নিজে করতে পারেন।
  - কেউ Console-এ ফাইলটা খুললে বা "Create new access token" চাপলে নতুন token তৈরি হবে। তাই script আবার চালালে ধরা পড়বে, dry-run-এ token-এর সংখ্যা দেখাবে।

## ৪. ক্রম (প্রতিটির পরে থামা, মালিকের অনুমতি)

০. **মালিক:** `identity-docs-viewer` account আর তার অনুমতি দেবেন (উপরের ১–৫)। আমি শুধু পড়ে যাচাই করব। step-c channel আগে তৈরি করা হবে, তাতে OAuth-এর ঠিকানা জানা যাবে। CORS এখনকারটাই থাকবে, মালিক অন্য সিদ্ধান্ত না নিলে।

১. **শুধু এই function deploy**, worktree `cc_step_c` থেকে (d4ead6c ছাড়া):
   ```sh
   cd C:\FlutterProjects\cc_step_c
   firebase deploy --only functions:getIdentityDocumentUrl --project chalakchar-mart
   ```
   - অন্য কোনো function-এ হাত পড়ে না। কিছু মুছে যাওয়ার প্রশ্ন এলে উত্তর হবে "না"।
   - এই function-এ কোনো secret নেই।
   - **rollback:** `firebase functions:delete getIdentityDocumentUrl --region asia-south1 --project chalakchar-mart`। পুরোনো website এটা ডাকে না।
   - **যাচাই:** লগইন ছাড়া ডাকলে `unauthenticated` আসবে।

২. **hosting preview** `step-c`, worktree `cc_step_c` থেকে build করে:
   ```sh
   flutter clean && flutter build web --release
   firebase hosting:channel:deploy step-c --expires 7d --project chalakchar-mart
   ```
   - deploy-এর আগে `main.dart.js`-এ `getIdentityDocumentUrl` আছে কি না grep করে দেখা।

৩. **মালিক দেখবেন:** admin → Vendors-এ ৩টা কাগজ আর Delivery Partners-এ ২টা কাগজ খোলে কি না। vendor বা rider লগইন করলে admin পেজই খুলবে না।
   - আমি log-এ শুধু field-এর নাম মিলিয়ে দেখব।

৪. **hosting লাইভে:**
   - কমান্ড: `firebase hosting:clone chalakchar-mart:step-c chalakchar-mart:live`।
   - এখনকার লাইভ version `2ac61cbcad787dc7` লিখে রাখা হবে। rollback-এর জন্য এটাই ফেরানো হবে।

৫. **token বাতিল:**
   1. `node scripts/revokeIdentityDocTokens.js` চালিয়ে dry-run। প্রত্যাশিত: ৫টা ফাইল, প্রতিটিতে ১টা token।
   2. মালিকের অনুমোদন।
   3. `--apply`।
   4. যাচাই: script-এর check, আবার dry-run চালালে "No download token left", admin থেকে ৫টা কাগজ খোলে, পুরোনো link খুললে 403।

## অন্য পর্যবেক্ষণ (d4ead6c, এই branch-এ নেই)

`wip/audit-step1`-এ d4ead6c-এর `product_sources`, `product_import_keys` আর এই জাতীয় collection-এর নিজের নিয়ম আছে: `isAdmin()`।
কিন্তু catch-all `match /{document=**}`-এর বাদ দেওয়ার তালিকায় এগুলো নেই। ফলে `analytics.view` বা staff-ও supplier আর cost-এর তথ্য পড়তে পারবে।
d4ead6c deploy-এর আগে এগুলো বাদের তালিকায় যোগ করা দরকার।
