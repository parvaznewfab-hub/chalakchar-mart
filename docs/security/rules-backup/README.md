# লাইভ rules-এর কপি

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
