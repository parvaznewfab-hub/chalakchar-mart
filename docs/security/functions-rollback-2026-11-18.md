# 14b ধাপ A: function deploy-এর rollback (১৮ নভেম্বর ২০২৬)

`loadMarketingSettings` বদলানোর পর ১০টা function চার দলে deploy হচ্ছে। দলগুলো
আলাদা আলাদা দিনে শেষবার deploy হয়েছিল। প্রতিটা function লাইভে কোন কোড চালাচ্ছিল,
তা লাইভ source (Cloud Storage-এর `function-source.zip`) নামিয়ে মিলিয়ে দেখা হয়েছে।
প্রতিটা দলের source একটা commit-এর `functions/` ফোল্ডারের সাথে হুবহু মিলেছে।
test, scripts আর `.env` এই মেলানোয় ধরা হয়নি। তাই আলাদা করে source রাখা হয়নি।

| দল | function | লাইভে ছিল (UTC) | commit |
|---|---|---|---|
| ১ | onProductCreated, onProductStockUpdated | 2026-11-17 03:34 | `afff7c3` |
| ২ | chatWithAssistant, whatsappWebhook, messengerWebhook, instagramWebhook | 2026-11-15 10:10 | `2db1f78` |
| ৩ | onMarketingOutboxCreated, processMarketingQueueScheduled | 2026-11-14 17:39 | `d2e65dd` |
| ৪ | onWhatsAppDeliveryCreated, processWhatsAppDeliveryRetries | 2026-11-11 19:09 / 19:23 | `780f82c` |

deploy-এর মানগুলো (params) আসে `functions/.env.chalakchar-mart` থেকে। ফাইলটা git-এ
নেই। এতে আছে `ALIEXPRESS_*`, `META_WEBHOOK_VERIFY_TOKEN`, `TIKTOK_REDIRECT_URI` ইত্যাদি।
rollback-এর worktree-তে এই ফাইলটা কপি করতেই হবে। নইলে CLI মান চাইবে, অথবা ভুল মান
নিয়ে deploy হবে। `functions/.env`-এ শুধু একটা comment আছে।

## সতর্কতা
এই পুরোনো কোড চাবি পড়ে শুধু `settings/app` থেকে। চাবি সরানোর script
(`moveSocialSecrets.js --apply`) চলার **পরে** rollback করলে marketing আর
WhatsApp/Messenger/Instagram-এর উত্তর বন্ধ হয়ে যাবে। তখন rollback-এর আগে চাবি
settings/app-এ ফেরাতে হবে (script-এর backup ফাইল থেকে), অথবা rollback না করে
সমস্যাটা ঠিক করতে হবে।

## rollback কমান্ড (repo-র মূল ফোল্ডার থেকে, Git Bash)
দলের commit আলাদা worktree-তে নামিয়ে সেখান থেকে শুধু ওই function-গুলো deploy।

```sh
# দল ১
C=afff7c3; FNS=onProductCreated,onProductStockUpdated
# দল ২
C=2db1f78; FNS=chatWithAssistant,whatsappWebhook,messengerWebhook,instagramWebhook
# দল ৩
C=d2e65dd; FNS=onMarketingOutboxCreated,processMarketingQueueScheduled
# দল ৪
C=780f82c; FNS=onWhatsAppDeliveryCreated,processWhatsAppDeliveryRetries

# উপরের একটা দল বেছে তারপর:
git worktree add ../cc_rollback_$C $C
cp functions/.env.chalakchar-mart ../cc_rollback_$C/functions/   # params, not in git
(cd ../cc_rollback_$C/functions && npm ci)
(cd ../cc_rollback_$C && firebase deploy --only "functions:${FNS//,/,functions:}" --project chalakchar-mart)
git worktree remove --force ../cc_rollback_$C
```
