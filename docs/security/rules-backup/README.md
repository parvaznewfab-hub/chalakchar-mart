# লাইভ rules-এর কপি

১৭ নভেম্বর ২০২৬-এ লাইভ থেকে নামানো (Firebase Rules API)।

| ফাইল | লাইভ ruleset | লাইভে গেছে |
|---|---|---|
| `firestore.rules.live-2026-11-17` | `ab0bcacc-472b-4897-a1fa-f14cff043e3b` | 2026-11-09 17:39 UTC |
| `storage.rules.live-2026-11-17` | `fc245689-b129-4212-8538-115ae1d3298b` | 2026-07-25 16:59 UTC |

তখন এই কপি আর repo-র `firestore.rules` / `storage.rules` হুবহু এক ছিল।

## Firestore rules আগের অবস্থায় ফেরানো
hosting rollback rules ফেরায় না। rules ফেরাতে:

```sh
cp docs/security/rules-backup/firestore.rules.live-2026-11-17 firestore.rules
firebase deploy --only firestore:rules --project chalakchar-mart
git checkout firestore.rules   # repo-র ফাইল আবার নতুন rules-এ
```

অথবা Firebase Console → Firestore → Rules → History থেকে ruleset
`ab0bcacc-472b-4897-a1fa-f14cff043e3b` বেছে "Restore"।
