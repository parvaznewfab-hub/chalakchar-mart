# Subcategory progress

Last updated: 2026-11-14

## Data model (for reference)
- Subcategories: top-level `subcategories` collection, parent link `categoryId`
  (category doc id). Fields: `name`, `slug`, `normalizedName`, `priority`,
  `isActive`, `status`, `image`/`imageUrl`.
- Products: `subcategoryId` (subcategory doc id).
- "Live" product = `isActive == true` and `approvalStatus == 'approved'`.

## Done (2026-11-14) — committed, NOT deployed
| Commit | What |
|---|---|
| `c1e23e0` | Category page chip row ("All" + subcategories, priority then name, `?sub={slug}` with pushState/back/forward); shared `CategorySidebar` on home + desktop category page (expand/collapse, highlight); subcategories cached once per session; category page streams no longer re-subscribe on every tap; admin badge "N live · M total" + live count per subcategory row |
| `2f094d5` | AI category suggestion no longer silently clears the subcategory: kept when the category is the same; on a real change a snack + "Subcategory will be removed" confirm on save |
| `58529e6` | Sidebar hides subcategories with 0 live products (same rule as chips); counts via cached `count()` per subcategory |

Verified with real data in headless Chrome (desktop 1440px and mobile 360px):
chip counts, chip → products, filters with chips, no-subcategory category,
mobile scroll, sidebar expand/collapse/highlight, direct `?sub=` link,
back/forward, 0 extra Firestore requests per chip/filter tap.

## Firestore data changes (2026-11-14)
- `Mobile Parts › Motherboard & Mainboard` (`FLBc3w9o9IeMQP5QGzI0`) set
  `isActive: false`, `status: inactive` (not deleted). Top-level "Motherboard"
  category is the home for boards.
- Backfill: `subcategoryId` written on 46 Mobile Parts products (only that
  field): Display & Digitizer 42, USB Charging port board 4. Rollback = delete
  `subcategoryId` on the ids in the backup JSON kept from the run.
  Result (live): All 53 · Display & Digitizer 41 · USB Charging port board 5.
- New subcategory `Mobile Parts › Flex Cable & Connector`
  (`sE4gPp3kqOW2suDwUV7n`, slug `flex-cable-connector`, active, 0 products —
  hidden on the site until products are assigned).

## Waiting for approval
Assign to **Flex Cable & Connector** (only `subcategoryId` will be written):

| productId | live | name |
|---|---|---|
| imp_aliexpress_0e59d480de8646baad731b1283e200cb | yes | Motherboard Mainboard LCD Flex Cable For Huawei Nova 2… |
| imp_aliexpress_3032838ff4d232c439b3a801646ec82e | yes | Main Flex Cable For Samsung S23 S22 S21 S20… |
| imp_aliexpress_4e555a41d4d913fba9e51f3293229a77 | yes | 10Pcs/Lot For Samsung Tab A 10.1 … Main board Motherboard Connector LCD Display Flex Cable |
| imp_aliexpress_508b55cd1d6ad292a44df817655473cf | no | Main Board Motherboard LCD Display Connector Flex Cable For HuaWei Nova 4… |
| imp_aliexpress_526659ff5d1475874c22b62fad9fef94 | yes | 5pcs For Samsung A21 A31 A41 … Main Board Motherboard Connector Ribbon Flex Cable |
| imp_aliexpress_730d22355bf7ecabe0e231f75ca98123 | yes | 2Pcs 56 60 Pins LCD FPC Plug Connector Mainboard Flex Connector… |
| imp_aliexpress_c5e1a4617214e9785011c716e76621e8 | yes | Wi-Fi Signal Antenna Main Board Connector Motherboard Flex Cable For Samsung Note 10… |
| imp_aliexpress_fd14508f5cedcd56137433c83395eec8 | no | Motherboard Main Board Connector Board Flex Cable For Huawei Nova 5i… |

Not touched:
- `imp_aliexpress_82ef3a01837f195aae33a1d3463d570f` — **FLAG**: HP Probook laptop
  motherboard, admin will move it out of Mobile Parts.
- `imp_aliexpress_d3c7e8edfbf1119cfcb716f0289f43bd` — spudger tool, stays
  without a subcategory.

## AI category suggestions (uncommitted, not deployed)
- Audit (read-only): 116 of 215 products — all live — use category names
  that don't exist (Cooking 48, Home & Cleaning 15, Fruits & Vegetables 15,
  Beverages 10, Grocery 9, LPG 6, Other 5, Pharmacy 2, Watches 2, 4 single)
  and have no `categoryId`. No subcategory mismatches. The Netac SSD is
  correctly in Computer Accessories; "Storage Devices"
  (`xmKKqehdkhkQgSyG40jv`) is an inactive/pending category the AliExpress
  importer auto-created 2026-11-13 21:44 UTC, with 0 products. Fix plan
  waits for the owner's decision (needs new categories, none of the 3
  existing fit).
- AI optimize now only proposes active categories/subcategories (backend
  prompt + match, `functions/category/aiTaxonomy.js`; client match,
  `lib/utils/ai_taxonomy_match.dart`). Unmatched → "মিল পাওয়া যায়নি —
  বর্তমানটাই থাকবে". Category change needs a checkbox (off by default);
  the old resolver call that could auto-create categories is gone.
- Backend part takes effect only after deploying `aiOptimizeProduct` and
  `aiProductFromImage`; until then the "matched" path can't be reached on
  localhost (old prompt always answers e.g. "Electronics").

## TODO / open
- Deploy the three commits above (not deployed yet).
- Category page queries `category == name`; renaming a category empties its
  page. Should query by `categoryId`.
- 2f094d5 (AI subcategory fix) passed analyzer but was not exercised in the
  running admin UI (needs an admin login).
