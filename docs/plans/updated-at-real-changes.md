# পরের কাজ: `updatedAt` শুধু আসল পরিবর্তনে বাড়বে

অবস্থা: নোট, শুরু হয়নি (লেখা হয়েছে ২০২৬-১১-২৭, seo-3-এর সময়)।

## সমস্যা

- sitemap-এর `lastmod` এখন প্রোডাক্টের আসল `updatedAt` থেকে আসে (seo-3)।
- কিন্তু AliExpress sync (`syncAliExpressProduct`, `aliexpressScheduledSync` /
  `aliexpressSyncAllProducts`, functions/index.js) প্রতিবার চললেই
  `updatedAt: serverTimestamp()` লেখে — দাম, স্টক বা লেখা না বদলালেও।
- ফলে প্রায় সব imported প্রোডাক্টের `updatedAt`, আর তাই home ও category-র
  `lastmod`, প্রতিদিন "আজ" দেখায়। Google এতে `lastmod`-কে কম বিশ্বাস করে।

## যা করতে হবে

1. sync-এ আগের আর নতুন মান তুলনা করা: দাম (`price`, `mrp`, variant দাম), স্টক
   (`stock`, variant স্টক, in-stock অবস্থা), কন্টেন্ট (`name`, `images`,
   `specifications`, `description`/`overview`, variant নাম/ছবি), category।
2. এগুলোর কোনোটা বদলালেই শুধু `updatedAt` বাড়ানো। sync-এর সময় আলাদা ফিল্ডে
   থাকবে (`lastSyncedAt`, `lastPriceSyncAt`, `lastStockSyncAt` আগে থেকেই আছে)।
3. অন্য যেসব জায়গা প্রোডাক্টে `updatedAt` লেখে (delivery estimate sync,
   variant refresh, price guard, marketing flags, backfill script) সেগুলো একই
   নিয়মে দেখা: শুধু marketing/সিস্টেম ফিল্ড বদলালে `updatedAt` না।
4. test: একই data দিয়ে দুবার sync → `updatedAt` বদলায় না; দাম বদলালে বদলায়।

## খেয়াল

- অ্যাপ বা অন্য কোড `updatedAt` দিয়ে কিছু সাজায় বা ফিল্টার করে কিনা আগে দেখতে
  হবে (যেমন admin তালিকা, marketing "দাম কমেছে" নিয়ম)।
- deploy নিয়ম আগের মতো: Firestore export আর মালিকের অনুমতি, function নাম ধরে।
