// -----------------------------------------------------------------------------
// Is a product (or a search/import query) a medicine / health product?
//
// ChalakChar Mart no longer sells health products (Play Store Health apps
// declaration: "My app doesn't provide any health features"). Used by:
//   - scripts/hideHealthProducts.js (find and hide existing ones),
//   - the import denylist (aliexpressSearchImport, chat fallback, n8n import),
//   - chat replies (no medicine advice).
//
// Note on fields: `strength` holds the pack size on groceries ("1 kg",
// "500 ml") and `generic`/`manufacturer` are filled on some groceries
// ("Sugar", "Fresh"), so those fields alone don't mark a medicine; a medicine
// unit in strength ("500 MG") or a medicine dosage form in type does.
//
// Pure: no Firestore.
// -----------------------------------------------------------------------------

function text(value) {
  return String(value ?? "").toLowerCase();
}

// Prescription medicine signals.
// "tablet" is NOT here: in a parts shop it is mostly a device ("Galaxy Tab
// tablet LCD"); it only counts with a dose (TABLET_WITH_DOSE) or as the
// product's dosage-form `type`. "napa" is also "Napa leather".
const RX_TERMS = [
  "capsule", "capsules", "syrup", "injection", "injectable", "ointment",
  "eye drop", "eye drops", "ear drop", "inhaler", "suppository", "antibiotic", "ciprofloxacin",
  "amoxicillin", "azithromycin", "metformin", "omeprazole", "esomeprazole", "paracetamol", "ace plus",
  "bactin", "insulin", "prescription", "rx only", "pharmaceutical", "pharma",
  "ট্যাবলেট", "ক্যাপসুল", "সিরাপ", "ইনজেকশন", "অ্যান্টিবায়োটিক", "ওষুধ", "ঔষধ", "প্রেসক্রিপশন",
];
// OTC / health products and medical devices.
const HEALTH_TERMS = [
  "oral rehydration", "orsaline", "ors", "saline", "vitamin", "multivitamin", "supplement", "protein powder",
  "whey", "collagen", "omega 3", "fish oil", "probiotic", "first aid", "bandage", "antiseptic", "savlon", "dettol",
  "sanitary napkin", "sanitary pad", "pregnancy test", "thermometer", "blood pressure", "bp machine", "glucometer",
  "glucose meter", "oximeter", "nebulizer", "nebuliser", "stethoscope", "hearing aid", "condom", "medical",
  "health & wellness", "pharmacy", "herbal medicine", "ayurvedic", "homeopathic", "homeopathy",
  "স্যালাইন", "ভিটামিন", "সাপ্লিমেন্ট", "ফার্স্ট এইড", "থার্মোমিটার", "ডাক্তার", "ফার্মেসি",
];
// Words that look medical but, in this catalog, describe groceries/parts.
const FALSE_FRIENDS = ["herbal drink", "for cooking and health", "healthy", "health cooking"];

const MEDICINE_DOSE = /\b\d+(?:\.\d+)?\s*(mg|mcg|µg|iu|ml\/|mg\/ml)\b/i;
// "tablet" + a dose, either order, close together ("napa 500mg tablet").
const TABLET_WITH_DOSE = /\b(tablet|tablets|tab)\b.{0,20}\d+(?:\.\d+)?\s*(mg|mcg)\b|\b\d+(?:\.\d+)?\s*(mg|mcg)\b.{0,20}\b(tablet|tablets|tab)\b/i;
const MEDICINE_TYPES = /^(tablet|capsule|syrup|injection|suspension|ointment|drop|drops|inhaler|cream|gel|powder for suspension)s?$/i;

const LATIN = /^[ -~]+$/;

// Latin-script terms match whole words only ("ors" must not match
// "protectors"); Bangla terms match as substrings (they take case endings).
function termIn(haystack, term) {
  const t = term.trim();
  if (!LATIN.test(t)) return haystack.includes(t);
  const escaped = t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(^|[^a-z0-9])${escaped}($|[^a-z0-9])`).test(haystack);
}

function includesAny(haystack, terms) {
  return terms.find((t) => termIn(haystack, t)) || null;
}

/**
 * Classifies a product: { group: "rx" | "otc" | "unsure" | null, reasons: [] }.
 * null = not a health product.
 */
function classifyHealthProduct(product) {
  const name = text(product?.name);
  const category = text(product?.category);
  const type = text(product?.type).trim();
  const strength = text(product?.strength);
  const generic = text(product?.generic);
  const haystack = ` ${[name, category, type, generic, text(product?.banglaTitle)].join(" ")} `;
  const reasons = [];

  if (category === "pharmacy" || category === "medicine" || category === "medicines") reasons.push(`category:${category}`);
  if (MEDICINE_TYPES.test(type)) reasons.push(`type:${type}`);
  if (MEDICINE_DOSE.test(strength)) reasons.push(`strength:${strength}`);
  const rx = includesAny(haystack, RX_TERMS);
  if (rx) reasons.push(`term:${rx}`);
  if (TABLET_WITH_DOSE.test(haystack)) reasons.push("tablet+dose");
  if (reasons.length) return { group: "rx", reasons };

  const falseFriend = includesAny(haystack, FALSE_FRIENDS);
  const health = includesAny(haystack, HEALTH_TERMS);
  if (health && !falseFriend) return { group: "otc", reasons: [`term:${health.trim()}`] };
  if (health && falseFriend) return { group: "unsure", reasons: [`term:${health.trim()}`, `but:${falseFriend}`] };

  // Nutrition drinks / baby formula: food, but often sold as health products.
  if (/\b(nutrition|nutritional|baby formula|infant formula|horlicks|complan|glucerna)\b/.test(haystack)) {
    return { group: "unsure", reasons: ["nutrition drink / formula"] };
  }
  return { group: null, reasons: [] };
}

/**
 * True when a search/import query asks for medicine, supplements or medical
 * devices (import denylist). Uses the same term lists.
 */
function isHealthQuery(query) {
  const q = ` ${text(query)} `;
  return Boolean(includesAny(q, RX_TERMS) || includesAny(q, HEALTH_TERMS) || MEDICINE_DOSE.test(q)
    || TABLET_WITH_DOSE.test(q)
    || /\b(medicine|medicines|drug|drugs|doctor|doctors|pill|pills)\b/.test(q));
}

module.exports = { classifyHealthProduct, isHealthQuery, RX_TERMS, HEALTH_TERMS };
