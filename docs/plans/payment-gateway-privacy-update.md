# নোট: পেমেন্ট gateway যোগ হলে privacy policy আপডেট

অবস্থা: নোট (লেখা হয়েছে ২০২৬-১১-২৭, seo-3-এর সময়)।

২০২৬-১১-২৭ পর্যন্ত কোডে কোনো পেমেন্ট gateway API নেই। রিফান্ড হাতে
bKash/Nagad নম্বরে পাঠানো হয়, তাই privacy policy-র "তথ্য শেয়ার" অংশে
পেমেন্ট সেবাদাতার নাম নেই।

bKash, Nagad বা অন্য কোনো পেমেন্ট gateway API যোগ হলে:

1. `lib/pages/user/policy_texts.dart` → `kPrivacyPolicyNoHealth` → "তথ্য শেয়ার"
   অংশে সেবাদাতার নাম আর কী তথ্য যায় (অর্ডার নম্বর, টাকার পরিমাণ, ফোন নম্বর
   ইত্যাদি, কোড দেখে) যোগ করা।
2. "সর্বশেষ হালনাগাদ" তারিখ বদলানো।
3. `node tools/seo/sync_policy_texts.js` চালানো, আর
   `functions/seo/handlers.js`-এর `POLICY_LAST_MODIFIED` একই তারিখ করা।
4. মালিকের অনুমোদন নিয়ে `pageSeo` function আর hosting deploy।
