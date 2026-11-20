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
  - শুধু চারটে field থাকে: `viewerUid`, `kind`, `which`, `at`।
  - path, URL বা কোনো ব্যক্তিগত মান থাকে না।
  - **প্রস্তাব:** কার কাগজ দেখা হলো সেটাও রাখা, অর্থাৎ `ownerId`। এটা কোনো মান নয়, শুধু একটা id। মালিক বললে এক লাইনে যোগ করা যাবে।
  - Firestore-এ log রাখা হয়নি। কারণ সেখানে রাখলে catch-all নিয়মের কারণে staff সেটা পড়তে পারত।
- **Test:**
  - `functions/test/identityDocumentUrl.test.js`: ৭টা unit test।
  - `node tools/rules-test/run-identity-doc.js`: Firestore আর Storage emulator-এ ৬টা test। শুধু signing অংশটা বদলে দেওয়া, কারণ ওটার জন্য আসল service account লাগে।

### signBlob-এর অনুমতি (মালিক দেবেন, আমি দিইনি)

- Functions চলে `1036870421759-compute@developer.gserviceaccount.com` দিয়ে। এটা default, অন্য কোনো account বসানো নেই।
- service account key ছাড়া signed URL বানাতে admin SDK IAM `signBlob` ব্যবহার করে। এর জন্য ওই account-এর **নিজের ওপর** `iam.serviceAccounts.signBlob` অনুমতি লাগে।
- **এখন অনুমতিটা নেই।**
  - account-টার নিজের IAM policy খালি।
  - project-এ এর আছে শুধু `roles/editor`, আর Editor-এ signBlob নেই (যাচাই করা)।
  - `iamcredentials.googleapis.com` চালু আছে।
- এটা ছাড়া callable `internal` ভুল দেবে, আর অ্যাপে দেখাবে "কাগজটা খোলা যায়নি"।
- **যা দিতে হবে**, শুধু এই account-এর ওপর, পুরো project-এ নয়:

  ```sh
  gcloud iam service-accounts add-iam-policy-binding 1036870421759-compute@developer.gserviceaccount.com \
    --member=serviceAccount:1036870421759-compute@developer.gserviceaccount.com \
    --role=roles/iam.serviceAccountTokenCreator --project chalakchar-mart
  ```

  এতে compute account-এ চলা সব function নিজের নামে sign করতে পারবে। ওদের Editor role আগে থেকেই আছে, তাই নতুন ঝুঁকি সামান্য।
- **পরিচ্ছন্ন বিকল্প:** এই function-এর জন্য আলাদা একটা service account।
  - role লাগবে: Firestore পড়া, Storage-এ `objects.get`, আর নিজের ওপর Token Creator।
  - এটা তালিকার কম-অগ্রাধিকারের কাজের সঙ্গে মেলে: "Functions-এর জন্য আলাদা কম-ক্ষমতার service account"।
  - তখন `onCall({ serviceAccount: "…" })` যোগ করতে হবে।

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

০. **মালিক:** উপরের IAM binding দেবেন। অথবা আলাদা service account বেছে নেবেন।

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
