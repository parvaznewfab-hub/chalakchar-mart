#!/usr/bin/env node
// -----------------------------------------------------------------------------
// Read-only dry run of the AliExpress price/stock sync (incl. the per-variant
// refresh) against LIVE data, using the LOCAL functions code — so new sync
// logic can be reviewed before it's deployed. Writes nothing to Firestore:
// it calls runAliExpressSync({ dryRun: true }) through the env-gated
// __localAliExpressSyncDryRun hook in index.js.
//
// It does call AliExpress (product + freight lookups, same as a normal sync).
//
// Usage (Git Bash, from functions/):
//   ALIEXPRESS_APP_SECRET=$(firebase functions:secrets:access ALIEXPRESS_APP_SECRET) \
//     node scripts/aliexpressSyncDryRun.js [--out=path/report.json] [--top=10]
//       [--products=<AliExpress product id>,<id>,...]   (only these products)
//
// Credentials: firebase-admin application-default credentials (same as the
// other scripts in this folder).
// -----------------------------------------------------------------------------

process.env.CHALAKCHAR_LOCAL_SYNC_DRY_RUN = "1";

const fs = require("fs");
const path = require("path");

function arg(name, fallback) {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
}

function biggestPriceChange(product) {
  return (product.variantChanges || []).reduce(
    (max, c) => Math.max(max, Math.abs((c.newPrice || 0) - (c.oldPrice || 0))),
    0
  );
}

async function main() {
  if (!process.env.ALIEXPRESS_APP_SECRET) {
    console.error("Set ALIEXPRESS_APP_SECRET in the environment first (see usage).");
    process.exit(1);
  }
  const outPath = arg("out", path.join(process.cwd(), "aliexpress-sync-dry-run.json"));
  const top = Number(arg("top", "10")) || 10;

  // Loaded only after the env var is set so the dry-run hook is exported.
  const functions = require(path.join(__dirname, "..", "index.js"));
  if (typeof functions.__localAliExpressSyncDryRun !== "function") {
    throw new Error("Dry-run hook not exported — is CHALAKCHAR_LOCAL_SYNC_DRY_RUN set?");
  }

  const only = arg("products", "").split(",").map((s) => s.trim()).filter(Boolean);
  const result = await functions.__localAliExpressSyncDryRun(only.length ? only : null);
  if (result.dryRun !== true) throw new Error("Refusing to report: result is not a dry run.");

  const products = result.products || [];
  const synced = products.filter((p) => !p.unsaleable && p.variantSyncApplied);
  const allChanges = synced.flatMap((p) => p.variantChanges || []);
  const report = {
    generatedAt: new Date().toISOString(),
    summary: {
      productsChecked: result.totalChecked,
      productsWithVariantRefresh: synced.length,
      unsaleable: result.unsaleable,
      failed: result.failed,
      variantsChanged: allChanges.length,
      variantsPriceChanged: allChanges.filter((c) => c.oldPrice !== c.newPrice).length,
      variantsStockChanged: allChanges.filter((c) => c.oldStock !== c.newStock).length,
      variantsNoLongerOnAliExpress: synced.reduce((n, p) => n + (p.variantsMissing || []).length, 0),
      variantsUnresolvedLeftUntouched: synced.reduce((n, p) => n + (p.variantsUnresolved || []).length, 0),
      productsWithUnresolvedVariants: synced.filter((p) => (p.variantsUnresolved || []).length).length,
      variantsMatchedBy: synced.reduce((acc, p) => {
        for (const [how, n] of Object.entries(p.variantsMatchedBy || {})) acc[how] = (acc[how] || 0) + n;
        return acc;
      }, {}),
      productsWhosePriceChanges: synced.filter((p) => p.productBefore.price !== p.productAfter.price).length,
    },
    topPriceChanges: [...synced]
      .filter((p) => biggestPriceChange(p) > 0)
      .sort((a, b) => biggestPriceChange(b) - biggestPriceChange(a))
      .slice(0, top)
      .map((p) => ({
        productId: p.productId,
        name: p.name,
        sourceProductId: p.sourceProductId,
        isActive: p.isActive,
        productPrice: `${p.productBefore.price} -> ${p.productAfter.price}`,
        productStock: `${p.productBefore.stock} -> ${p.productAfter.stock}`,
        variants: (p.variantChanges || [])
          .filter((c) => c.oldPrice !== c.newPrice)
          .map((c) => ({ name: c.name, price: `${c.oldPrice} -> ${c.newPrice}`, stock: `${c.oldStock} -> ${c.newStock}`, onAliExpress: c.matched })),
      })),
    errors: result.errors,
    products,
  };

  fs.writeFileSync(outPath, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report.summary, null, 2));
  console.log(`Full report: ${outPath}`);
}

main().then(() => process.exit(0)).catch((error) => {
  console.error(error.stack || error.message || String(error));
  process.exit(1);
});
