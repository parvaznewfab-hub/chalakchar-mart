// -----------------------------------------------------------------------------
// Server-rendered HTML for crawlers: category, product and policy pages, and
// the sitemap. The app is Flutter Web (CanvasKit), so this first HTML is the
// only text a search engine can read; Flutter draws over it after load.
//
// Pure: callers pass the Firestore data in (functions/seo/handlers.js).
// test/seo_titles_parity_test.dart reads POLICY_PAGE_SEO and the category
// title/description lines below: the app sets the same titles.
// -----------------------------------------------------------------------------

const {
  cleanText, plainText, limitText, escText, escAttr, jsonLd, seoSlug, taka,
} = require("./html");
const { isProductIndexable, isSubcategoryActive, subcategorySlug } = require("./indexable");
const { productDisplayPrice, productDisplayMrp, hasPriceRange } = require("../catalog/displayPrice");
const { mentionsSupplier, isHiddenSpecification, cleanCustomerText } = require("../catalog/customerText");
const POLICY_TEXTS = require("./policyTexts");

const BASE_URL = "https://chalakcharmart.com";
const SITE_NAME = "ChalakChar Mart";
const DEFAULT_IMAGE = `${BASE_URL}/icons/Icon-512.png`;
const MAX_CATEGORY_LINKS = 100;

// Opened early so the first Firestore/image/canvaskit requests skip the
// DNS + TLS setup.
const APP_SHELL_PRECONNECTS = [
  "https://www.gstatic.com",
  "https://firestore.googleapis.com",
  "https://firebasestorage.googleapis.com",
  "https://ae01.alicdn.com",
].map((href) => `<link rel="preconnect" href="${href}" crossorigin>`).join("\n  ");

const POLICY_PAGE_SEO = {
  "/about-us": {
    title: "About Us | ChalakChar Mart",
    description: "ChalakChar Mart — চালাকচর বাজার, মনোহরদী, নরসিংদীর অনলাইন শপ। মোবাইল ও ল্যাপটপ পার্টস, কম্পিউটার এক্সেসরিজ ও দৈনন্দিন পণ্য, ক্যাশ অন ডেলিভারিতে সারা দেশে।",
  },
  "/privacy-policy": {
    title: "Privacy Policy | ChalakChar Mart",
    description: "ChalakChar Mart কোন তথ্য সংগ্রহ করে, কীভাবে ব্যবহার ও সুরক্ষিত রাখে, এবং আপনার তথ্য দেখা, সংশোধন বা মুছে ফেলার অনুরোধ যেভাবে করবেন।",
  },
  "/terms-conditions": {
    title: "Terms & Conditions | ChalakChar Mart",
    description: "ChalakChar Mart-এ অর্ডার, দাম, পেমেন্ট, ডেলিভারি, পণ্যের সামঞ্জস্য ও অ্যাকাউন্ট ব্যবহারের শর্তাবলী।",
  },
  "/return-policy": {
    title: "Return & Refund Policy | ChalakChar Mart",
    description: "পণ্য ফেরত, রিপ্লেসমেন্ট, ওয়ারেন্টি ও রিফান্ডের নিয়ম — মোবাইল ও ল্যাপটপ পার্টস হাতে পেয়ে কী করবেন এবং কখন রিপ্লেসমেন্ট পাবেন।",
  },
  "/data-deletion": {
    title: "Data Deletion | ChalakChar Mart",
    description: "ChalakChar Mart অ্যাকাউন্ট ও ব্যক্তিগত তথ্য মুছে ফেলার অনুরোধ যেভাবে করবেন।",
  },
};

const FOOTER_LINKS = [
  ["/", "Home"],
  ["/about-us", "About Us"],
  ["/return-policy", "Return & Refund Policy"],
  ["/terms-conditions", "Terms & Conditions"],
  ["/privacy-policy", "Privacy Policy"],
];

const BN_DIGITS = "০১২৩৪৫৬৭৮৯";
const bn = (n) => String(n).replace(/\d/g, (d) => BN_DIGITS[d]);

// Seen only until Flutter draws over it (slow phones, crawlers): a quiet,
// readable page rather than raw default-styled text.
const PAGE_STYLE = `<style>
    .seo-page{max-width:960px;margin:24px auto;padding:0 16px;font:15px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#333}
    .seo-page h1{font-size:22px;line-height:1.35;margin:8px 0 12px}
    .seo-page h2{font-size:16px;margin:20px 0 8px}
    .seo-page ul{padding-left:18px;margin:0}
    .seo-page li{padding:2px 0}
    .seo-page a{color:#1f7f99;text-decoration:none}
    .seo-page table{border-collapse:collapse;width:100%}
    .seo-page th,.seo-page td{border-bottom:1px solid #e5e7eb;padding:6px 8px;text-align:left;vertical-align:top}
    .seo-page th{width:38%;font-weight:600;color:#555}
    .seo-crumbs{font-size:13px;color:#666}
    .seo-footer{margin-top:28px;font-size:13px}
    .seo-footer a{margin-right:12px}
  </style>`;

// -----------------------------------------------------------------------------
// Shell
// -----------------------------------------------------------------------------

function renderShell({
  title, description, canonical, robots = "index, follow", image = DEFAULT_IMAGE,
  ogType = "website", jsonLdGraph = null, bodyHtml = "", extraHead = "",
}) {
  const ld = jsonLdGraph ? `  <script type="application/ld+json">${jsonLd(jsonLdGraph)}</script>\n` : "";
  return `<!DOCTYPE html>
<html lang="bn">
<head>
  <base href="/">
  <meta charset="UTF-8">
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">

  <title>${escText(title)}</title>
  <meta name="description" content="${escAttr(description)}">
  <meta name="robots" content="${escAttr(robots)}">

  <meta property="og:site_name" content="${SITE_NAME}">
  <meta property="fb:app_id" content="996213106661804">
  <meta property="og:title" content="${escAttr(title)}">
  <meta property="og:description" content="${escAttr(description)}">
  <meta property="og:type" content="${escAttr(ogType)}">
  <meta property="og:url" content="${escAttr(canonical)}">
  <meta property="og:image" content="${escAttr(image)}">
${extraHead}
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escAttr(title)}">
  <meta name="twitter:description" content="${escAttr(description)}">
  <meta name="twitter:image" content="${escAttr(image)}">

  <link rel="canonical" href="${escAttr(canonical)}">
  <link rel="apple-touch-icon" href="icons/Icon-192.png">
  <link rel="icon" type="image/png" href="favicon.png">
  <link rel="manifest" href="manifest.json">
  ${APP_SHELL_PRECONNECTS}
${ld}</head>
<body>
${bodyHtml ? `  ${PAGE_STYLE}\n  <main class="seo-page">\n${bodyHtml}  </main>\n` : ""}  <script src="flutter_bootstrap.js" async></script>
</body>
</html>`;
}

function footerHtml() {
  return `    <nav class="seo-footer" aria-label="Site">${FOOTER_LINKS.map(([href, label]) => `<a href="${href}">${escText(label)}</a>`).join("")}</nav>\n`;
}

function crumbsHtml(items) {
  // items: [{ name, href? }]; last one is the current page (no link).
  const parts = items.map((it, i) => (it.href && i < items.length - 1)
    ? `<a href="${escAttr(it.href)}">${escText(it.name)}</a>`
    : `<span>${escText(it.name)}</span>`);
  return `    <nav class="seo-crumbs" aria-label="Breadcrumb">${parts.join(" › ")}</nav>\n`;
}

function breadcrumbLd(id, items) {
  return {
    "@type": "BreadcrumbList",
    "@id": id,
    "itemListElement": items.map((it, i) => ({
      "@type": "ListItem",
      "position": i + 1,
      "name": it.name,
      "item": it.url,
    })),
  };
}

const ORGANIZATION_LD = {
  "@type": "Organization",
  "@id": `${BASE_URL}/#organization`,
  "name": SITE_NAME,
  "url": BASE_URL,
  "logo": DEFAULT_IMAGE,
};

const WEBSITE_LD = {
  "@type": "WebSite",
  "@id": `${BASE_URL}/#website`,
  "url": BASE_URL,
  "name": SITE_NAME,
  "publisher": { "@id": `${BASE_URL}/#organization` },
};

// -----------------------------------------------------------------------------
// Product fields
// -----------------------------------------------------------------------------

function num(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function productPrice(product) {
  return productDisplayPrice(product);
}

/** "৳1,829", or "৳1,829 থেকে" when variants differ in price (as the cards). */
function priceLabel(product) {
  const price = taka(productPrice(product));
  if (!price) return "";
  return hasPriceRange(product.variants) ? `${price} থেকে` : price;
}

function productStock(product) {
  const direct = num(product.stock || 0);
  if (direct > 0) return direct;
  if (Array.isArray(product.variants)) {
    return product.variants.reduce((sum, v) => sum + num(v?.stock || 0), 0);
  }
  return 0;
}

/** Brought in from abroad after the order (marketplace import). */
function isImportedProduct(product) {
  return cleanText(product.id).startsWith("imp_") ||
    Boolean(cleanText(product.sourceProductId)) ||
    Boolean(product.importedAt);
}

function toDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  if (typeof value === "number") return new Date(value > 20000000000 ? value : value * 1000);
  const n = Number(value);
  if (Number.isFinite(n) && String(value).trim() !== "") return new Date(n > 20000000000 ? n : n * 1000);
  const d = new Date(String(value));
  return Number.isNaN(d.getTime()) ? null : d;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const shortDate = (d) => `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;

/**
 * Delivery time in words, from the same fields and in the same order as the
 * app (lib/utils/product_delivery_resolver.dart), but as a day count so a
 * cached page stays true. "" when the product has none.
 */
function deliveryText(product) {
  const exact = toDate(product.estimatedDeliveryDate);
  if (exact) return `আনুমানিক ${shortDate(exact)}`;
  const min = product.deliveryMinDays;
  const max = product.deliveryMaxDays;
  if (min != null && max != null && num(max) >= 0 && String(max).trim() !== "") {
    const a = Math.round(num(min));
    const b = Math.round(num(max));
    return a === b || a <= 0 ? `আনুমানিক ${bn(b)} দিন` : `আনুমানিক ${bn(a)}–${bn(b)} দিন`;
  }
  const maxDate = toDate(product.estimatedDeliveryMaxDate);
  if (maxDate) return `আনুমানিক ${shortDate(maxDate)}`;
  const minDate = toDate(product.estimatedDeliveryMinDate);
  if (minDate) return `আনুমানিক ${shortDate(minDate)}`;
  const text = plainText(product.estimatedDeliveryText);
  if (text && !mentionsSupplier(text)) return text;
  if (product.deliveryDays != null && String(product.deliveryDays).trim() !== "" && num(product.deliveryDays) >= 0) {
    return `আনুমানিক ${bn(Math.round(num(product.deliveryDays)))} দিন`;
  }
  return "";
}

/** Transit days for the JSON-LD offer: the product's own range, else 1–5. */
function transitDays(product) {
  const min = Math.round(num(product.deliveryMinDays));
  const max = Math.round(num(product.deliveryMaxDays));
  if (max > 0) return { min: Math.max(0, Math.min(min, max)), max };
  const days = Math.round(num(product.deliveryDays));
  if (days > 0) return { min: days, max: days };
  return { min: 1, max: 5 };
}

/** Name/value rows the app shows (same filter: no origin/supplier rows). */
function specificationRows(product) {
  const specs = Array.isArray(product.specifications) ? product.specifications : [];
  const out = [];
  for (const spec of specs) {
    if (!spec || typeof spec !== "object") continue;
    const name = plainText(spec.name);
    const value = plainText(spec.value);
    if (!name || !value) continue;
    if (isHiddenSpecification(name, value)) continue;
    out.push([name, value]);
  }
  return out;
}

function productBrand(product) {
  const brand = plainText(product.brand || product.manufacturer);
  if (!brand || mentionsSupplier(brand) || /^(none|no brand|generic|n\/a)$/i.test(brand)) return "";
  return brand;
}

/**
 * The page <title>. An admin-written metaTitle wins; an imported one that
 * is only the name cut short (60 characters, no "...") gives way to the
 * full name, so the title is never a truncated name.
 */
function productTitle(product) {
  const name = plainText(product.name) || "Product";
  const meta = plainText(product.metaTitle);
  if (meta && !name.startsWith(meta)) return meta;
  return `${name} | ${SITE_NAME}`;
}

/** Short Bengali description built from the product's fields (no AI). */
function productSummary(product, { categoryName, subcategoryName, price, mrp, stock, delivery, imported }) {
  const name = plainText(product.name) || "পণ্যটি";
  const brand = productBrand(product);
  const where = subcategoryName ? `${categoryName} › ${subcategoryName}` : categoryName;
  const parts = [];
  parts.push(`${name} — ChalakChar Mart-এর ${where || "অনলাইন শপ"} ক্যাটাগরির পণ্য${brand ? `, ব্র্যান্ড ${brand}` : ""}।`);
  if (price > 0) {
    const label = priceLabel(product);
    parts.push(mrp > price
      ? `দাম ${label} (আগের দাম ${taka(mrp)})।`
      : `দাম ${label}।`);
  }
  const variants = Array.isArray(product.variants) ? product.variants.length : 0;
  if (variants > 1) parts.push(`${bn(variants)}টি অপশন থেকে বেছে নিতে পারবেন।`);
  parts.push(stock > 0 ? "পণ্যটি এখন অর্ডার করা যাচ্ছে।" : "পণ্যটি এই মুহূর্তে স্টকে নেই।");
  if (imported) {
    parts.push(`পণ্যটি অর্ডারের পর বিদেশ থেকে আমদানি করে পাঠানো হয়${delivery ? `; ডেলিভারি ${delivery}` : ""}।`);
  } else if (delivery) {
    parts.push(`ডেলিভারি ${delivery}।`);
  }
  parts.push("সারা বাংলাদেশে হোম ডেলিভারি ও ক্যাশ অন ডেলিভারি। অর্ডারের আগে মডেল মিলিয়ে নিতে WhatsApp-এ যোগাযোগ করুন।");
  return parts.join(" ");
}

function firstProductImage(product) {
  if (Array.isArray(product.images)) {
    for (const image of product.images) {
      const url = cleanText(image);
      if (url.startsWith("http")) return url;
    }
  }
  const imageUrl = cleanText(product.imageUrl || product.image);
  if (imageUrl.startsWith("http")) return imageUrl;
  return DEFAULT_IMAGE;
}

function youtubeVideoId(product) {
  const raw = cleanText(product.videoUrl || product.youtubeUrl || product.youtubeLink || product.videoLink || product.youtubeVideoId);
  if (!raw) return "";
  if (/^[a-zA-Z0-9_-]{11}$/.test(raw)) return raw;
  try {
    const url = new URL(raw);
    const host = url.hostname.toLowerCase();
    const parts = url.pathname.split("/").filter(Boolean);
    if (host.includes("youtu.be")) return parts[0] || "";
    if (host.includes("youtube.com") || host.includes("youtube-nocookie.com")) {
      const v = url.searchParams.get("v");
      if (v) return v;
      for (const marker of ["embed", "shorts", "live"]) {
        const i = parts.indexOf(marker);
        if (i !== -1 && parts.length > i + 1) return parts[i + 1];
      }
    }
  } catch (_) {
    // not a URL
  }
  return "";
}

function isoDate(value) {
  const d = toDate(value);
  return d && !Number.isNaN(d.getTime()) ? d.toISOString().slice(0, 10) : "";
}

function productKeywords(product) {
  const list = [
    ...(Array.isArray(product.searchKeywords) ? product.searchKeywords : []),
    ...(Array.isArray(product.seoTags) ? product.seoTags : []),
    product.name, product.category, productBrand(product), SITE_NAME, "online shopping Bangladesh",
  ];
  return [...new Set(list.map((k) => plainText(k).toLowerCase()).filter((k) => k && !mentionsSupplier(k)))]
    .slice(0, 20).join(", ");
}

// -----------------------------------------------------------------------------
// Product page
// -----------------------------------------------------------------------------

/**
 * [product] (with id), its [category] doc (or null), its [subcategory] doc
 * (or null), [indexable] from isProductIndexable, [relatedHtml] (links,
 * may be ""), [reviews] (JSON-LD Review list).
 */
function renderProductPage({ product, category = null, subcategory = null, indexable, relatedHtml = "", reviews = [] }) {
  const productId = product.id;
  const productUrl = `${BASE_URL}/product/${encodeURIComponent(productId)}`;
  const name = plainText(product.name) || "Product";
  const categoryName = plainText(category?.name || product.category);
  const categorySlug = seoSlug(categoryName);
  const categoryUrl = categorySlug ? `${BASE_URL}/category/${categorySlug}` : `${BASE_URL}/`;
  const subcategoryName = subcategory && isSubcategoryActive(subcategory) ? plainText(subcategory.name) : "";
  const price = productPrice(product);
  const mrp = productDisplayMrp(product);
  const stock = productStock(product);
  const delivery = deliveryText(product);
  const imported = isImportedProduct(product);
  const summary = productSummary(product, { categoryName, subcategoryName, price, mrp, stock, delivery, imported });
  const specs = specificationRows(product);
  const image = firstProductImage(product);
  const videoId = youtubeVideoId(product);
  const brand = productBrand(product) || SITE_NAME;
  const title = productTitle(product);
  // Seller text can name the supplier/origin: those sentences never reach
  // the page meta (cleanCustomerText).
  const description = limitText(
    plainText(cleanCustomerText(product.metaDescription)) ||
      plainText(cleanCustomerText(product.overview)) ||
      summary,
    155
  );
  const robots = indexable ? "index, follow" : "noindex, nofollow";
  const transit = transitDays(product);

  const productLd = {
    "@type": "Product",
    "@id": `${productUrl}#product`,
    "name": name,
    "image": [image],
    "description": summary,
    "sku": productId,
    "category": categoryName || undefined,
    "brand": { "@type": "Brand", "name": brand },
    "offers": {
      "@type": "Offer",
      "url": productUrl,
      "priceCurrency": "BDT",
      "price": price.toFixed(2),
      "availability": stock > 0 ? "https://schema.org/InStock" : "https://schema.org/OutOfStock",
      "itemCondition": "https://schema.org/NewCondition",
      "shippingDetails": {
        "@type": "OfferShippingDetails",
        "shippingRate": { "@type": "MonetaryAmount", "value": "60", "currency": "BDT" },
        "shippingDestination": { "@type": "DefinedRegion", "addressCountry": "BD" },
        "deliveryTime": {
          "@type": "ShippingDeliveryTime",
          "handlingTime": { "@type": "QuantitativeValue", "minValue": 0, "maxValue": 1, "unitCode": "DAY" },
          "transitTime": { "@type": "QuantitativeValue", "minValue": transit.min, "maxValue": transit.max, "unitCode": "DAY" },
        },
      },
      "hasMerchantReturnPolicy": {
        "@type": "MerchantReturnPolicy",
        "applicableCountry": "BD",
        "returnPolicyCategory": "https://schema.org/MerchantReturnFiniteReturnWindow",
        "merchantReturnDays": 7,
        "returnMethod": "https://schema.org/ReturnByMail",
        "returnFees": "https://schema.org/FreeReturn",
      },
      "seller": { "@id": `${BASE_URL}/#organization` },
    },
  };
  if (videoId) {
    productLd.video = {
      "@type": "VideoObject",
      "name": name,
      "description": summary,
      "thumbnailUrl": [`https://img.youtube.com/vi/${videoId}/hqdefault.jpg`],
      "embedUrl": `https://www.youtube.com/embed/${videoId}`,
      "contentUrl": `https://www.youtube.com/watch?v=${videoId}`,
      "uploadDate": isoDate(product.updatedAt || product.createdAt) || undefined,
    };
  }
  const ratingCount = parseInt(product.ratingCount || product.reviewCount || 0, 10);
  const ratingAvg = num(product.ratingAvg || 0);
  if (ratingCount > 0 && ratingAvg > 0) {
    productLd.aggregateRating = {
      "@type": "AggregateRating",
      "ratingValue": ratingAvg.toFixed(1),
      "reviewCount": ratingCount,
      "ratingCount": ratingCount,
      "bestRating": "5",
      "worstRating": "1",
    };
  }
  if (reviews.length) productLd.review = reviews;

  const crumbs = [
    { name: "Home", href: "/", url: `${BASE_URL}/` },
    ...(categoryName ? [{ name: categoryName, href: `/category/${categorySlug}`, url: categoryUrl }] : []),
    { name, url: productUrl },
  ];

  const graph = {
    "@context": "https://schema.org",
    "@graph": [ORGANIZATION_LD, WEBSITE_LD, breadcrumbLd(`${productUrl}#breadcrumb`, crumbs), productLd],
  };

  const facts = [
    price > 0 ? `<li>দাম: <strong>${escText(priceLabel(product))}</strong>${mrp > price ? ` <s>${escText(taka(mrp))}</s>` : ""}</li>` : "",
    `<li>স্টক: ${stock > 0 ? "স্টকে আছে" : "স্টকে নেই"}</li>`,
    `<li>ডেলিভারি: ${escText(delivery || "সারা বাংলাদেশে হোম ডেলিভারি")}</li>`,
    imported ? "<li>বিদেশ থেকে আমদানি</li>" : "",
    "<li>পেমেন্ট: ক্যাশ অন ডেলিভারি</li>",
  ].filter(Boolean).join("\n      ");

  const specHtml = specs.length ? `    <h2>স্পেসিফিকেশন</h2>
    <table>
${specs.map(([k, v]) => `      <tr><th>${escText(k)}</th><td>${escText(v)}</td></tr>`).join("\n")}
    </table>
` : "";

  const body = `${crumbsHtml(crumbs)}    <h1>${escText(name)}</h1>
    <ul>
      ${facts}
    </ul>
    <h2>পণ্যের বিবরণ</h2>
    <p>${escText(summary)}</p>
${specHtml}${categoryName ? `    <p><a href="/category/${escAttr(categorySlug)}">আরও ${escText(categoryName)} দেখুন</a></p>\n` : ""}${relatedHtml}${footerHtml()}`;

  const extraHead = `  <meta name="keywords" content="${escAttr(productKeywords(product))}">
${videoId ? `  <meta property="og:video" content="https://www.youtube.com/embed/${escAttr(videoId)}">\n  <meta property="og:video:type" content="text/html">\n` : ""}  <meta property="product:price:amount" content="${escAttr(price.toFixed(2))}">
  <meta property="product:price:currency" content="BDT">
`;

  return renderShell({
    title,
    description,
    canonical: productUrl,
    robots,
    image: videoId ? `https://img.youtube.com/vi/${videoId}/hqdefault.jpg` : image,
    ogType: "product",
    jsonLdGraph: graph,
    bodyHtml: body,
    extraHead,
  });
}

// -----------------------------------------------------------------------------
// Category page
// -----------------------------------------------------------------------------

function categoryTitle(name) {
  return limitText(`${name} Price in Bangladesh | ChalakChar Mart`, 65);
}

function categoryDescription(name, category) {
  return limitText(
    cleanText(category.seoDescription || category.description) ||
      `ChalakChar Mart থেকে ${name} কিনুন — মডেল মিলিয়ে অর্ডার, ক্যাশ অন ডেলিভারি, সারা বাংলাদেশে হোম ডেলিভারি।`,
    160
  );
}

function createdMillis(p) {
  const d = toDate(p.createdAt);
  return d ? d.getTime() : 0;
}

/** Newest first, like the category page's default order. */
function newestFirst(products) {
  return [...products].sort((a, b) => createdMillis(b) - createdMillis(a));
}

/** "নাম — ৳দাম" product link list item. */
function productLinkItem(p) {
  const price = priceLabel(p);
  const label = `${limitText(plainText(p.name), 110)}${price ? ` — ${price}` : ""}`;
  return `      <li><a href="/product/${encodeURIComponent(p.id)}">${escText(label)}</a></li>`;
}

/** Subcategories of [category] with at least one shown product, by priority. */
function categorySubcategories(category, subcategories, products) {
  const counts = new Map();
  for (const p of products) {
    const id = cleanText(p.subcategoryId);
    if (id) counts.set(id, (counts.get(id) || 0) + 1);
  }
  return (subcategories || [])
    .filter((s) => isSubcategoryActive(s) && s.categoryId === category.id && counts.get(s.id) > 0)
    .sort((a, b) => ((Number(a.priority) || 0) - (Number(b.priority) || 0)) ||
      plainText(a.name).toLowerCase().localeCompare(plainText(b.name).toLowerCase()))
    .map((s) => ({ ...s, count: counts.get(s.id) }));
}

/** 2–3 line Bengali introduction from the category's own numbers. */
function categoryIntro(name, products, subs) {
  const prices = products.map(productPrice).filter((n) => n > 0);
  const lines = [];
  const subNames = subs.slice(0, 4).map((s) => plainText(s.name));
  lines.push(`ChalakChar Mart-এ ${name} ক্যাটাগরিতে এখন ${bn(products.length)}টি পণ্য আছে${subNames.length ? ` — ${subNames.join(", ")}${subs.length > 4 ? " ও আরও" : ""}` : ""}।`);
  if (prices.length) {
    const min = Math.min(...prices);
    const max = Math.max(...prices);
    lines.push(min === max ? `দাম ${taka(min)}।` : `দাম ${taka(min)} থেকে ${taka(max)} পর্যন্ত।`);
  }
  lines.push("মডেল মিলিয়ে অর্ডার করুন — ক্যাশ অন ডেলিভারি, সারা বাংলাদেশে হোম ডেলিভারি। কোন পার্টস আপনার মডেলে লাগবে জানতে WhatsApp-এ জিজ্ঞেস করুন।");
  return lines.join(" ");
}

/**
 * [category] doc (switched on), [products] = the products the shop shows in
 * it, [subcategories] = all subcategory docs, [indexable] from
 * isCategoryIndexable.
 */
function renderCategoryPage({ category, products, subcategories, indexable }) {
  const name = plainText(category.name);
  const slug = seoSlug(name);
  const canonical = `${BASE_URL}/category/${slug}`;
  const title = categoryTitle(name);
  const description = categoryDescription(name, category);
  const sorted = newestFirst(products);
  const listed = sorted.slice(0, MAX_CATEGORY_LINKS);
  const subs = categorySubcategories(category, subcategories, products);
  const crumbs = [
    { name: "Home", href: "/", url: `${BASE_URL}/` },
    { name, url: canonical },
  ];
  const ownDescription = plainText(category.seoDescription || category.description);

  const graph = {
    "@context": "https://schema.org",
    "@graph": [
      ORGANIZATION_LD,
      WEBSITE_LD,
      {
        "@type": "CollectionPage",
        "@id": `${canonical}#page`,
        "url": canonical,
        "name": title,
        "description": description,
        "inLanguage": "bn",
        "isPartOf": { "@id": `${BASE_URL}/#website` },
        "breadcrumb": { "@id": `${canonical}#breadcrumb` },
      },
      breadcrumbLd(`${canonical}#breadcrumb`, crumbs),
      ...(listed.length ? [{
        "@type": "ItemList",
        "numberOfItems": listed.length,
        "itemListElement": listed.slice(0, 30).map((p, i) => ({
          "@type": "ListItem",
          "position": i + 1,
          "url": `${BASE_URL}/product/${encodeURIComponent(p.id)}`,
          "name": limitText(plainText(p.name), 110),
        })),
      }] : []),
    ],
  };

  const subHtml = subs.length ? `    <h2>সাব-ক্যাটাগরি</h2>
    <ul>
${subs.map((s) => `      <li><a href="/category/${slug}?sub=${encodeURIComponent(subcategorySlug(s))}">${escText(plainText(s.name))} (${bn(s.count)})</a></li>`).join("\n")}
    </ul>
` : "";

  const listHtml = listed.length ? `    <h2>${escText(name)} — পণ্যের তালিকা</h2>
    <ul>
${listed.map(productLinkItem).join("\n")}
    </ul>
` : "    <p>এই ক্যাটাগরিতে এখন কোনো পণ্য নেই।</p>\n";

  const body = `${crumbsHtml(crumbs)}    <h1>${escText(name)}</h1>
    <p>${escText(categoryIntro(name, products, subs))}</p>
${ownDescription && ownDescription !== description ? `    <p>${escText(ownDescription)}</p>\n` : ""}${subHtml}${listHtml}${footerHtml()}`;

  return renderShell({
    title,
    description,
    canonical,
    robots: indexable ? "index, follow" : "noindex, follow",
    image: cleanText(category.imageUrl).startsWith("http") ? cleanText(category.imageUrl) : DEFAULT_IMAGE,
    jsonLdGraph: graph,
    bodyHtml: body,
  });
}

// -----------------------------------------------------------------------------
// Policy pages
// -----------------------------------------------------------------------------

const DEFAULT_PHONE = "01975838764";
const DEFAULT_EMAIL = "chalakcharmart@gmail.com";

/** Same substitution as lib/utils/contact_info.dart withSettingsContacts. */
function withContacts(text, contacts = {}) {
  let out = text;
  if (cleanText(contacts.phone)) out = out.split(DEFAULT_PHONE).join(cleanText(contacts.phone));
  if (cleanText(contacts.email)) out = out.split(DEFAULT_EMAIL).join(cleanText(contacts.email));
  return out;
}

/**
 * Policy text as HTML: the first line is the <h1>; a short first line of a
 * paragraph without an ending mark (". । : ! ?") is a <h2>; "•" lines are a
 * list; other lines keep their line breaks.
 */
function policyBodyHtml(text) {
  const blocks = text.replace(/\r\n/g, "\n").split(/\n\s*\n/).map((b) => b.trim()).filter(Boolean);
  const out = [];
  blocks.forEach((block, index) => {
    let lines = block.split("\n").map((l) => l.trim()).filter(Boolean);
    if (index === 0) {
      out.push(`    <h1>${escText(lines[0])}</h1>`);
      lines = lines.slice(1);
      if (!lines.length) return;
    }
    const isHeading = (l) => l.length <= 70 && !/[।.!?:]$/.test(l) && !l.startsWith("•");
    if (lines.length === 1 && isHeading(lines[0])) {
      out.push(`    <h2>${escText(lines[0])}</h2>`);
      return;
    }
    if (lines.length > 1 && isHeading(lines[0])) {
      out.push(`    <h2>${escText(lines[0])}</h2>`);
      lines = lines.slice(1);
    }
    let list = [];
    let para = [];
    const flush = () => {
      if (para.length) out.push(`    <p>${para.map(escText).join("<br>")}</p>`);
      if (list.length) out.push(`    <ul>\n${list.map((l) => `      <li>${escText(l)}</li>`).join("\n")}\n    </ul>`);
      para = [];
      list = [];
    };
    for (const line of lines) {
      if (line.startsWith("•")) {
        if (para.length) { const p = para; para = []; out.push(`    <p>${p.map(escText).join("<br>")}</p>`); }
        list.push(line.replace(/^•\s*/, ""));
      } else {
        if (list.length) { const l = list; list = []; out.push(`    <ul>\n${l.map((x) => `      <li>${escText(x)}</li>`).join("\n")}\n    </ul>`); }
        para.push(line);
      }
    }
    flush();
  });
  return `${out.join("\n")}\n`;
}

/** /about-us, /privacy-policy, ... ; null when [path] is not a policy page. */
function renderPolicyPage(path, contacts) {
  const seo = POLICY_PAGE_SEO[path];
  if (!seo) return null;
  const canonical = `${BASE_URL}${path}`;
  const text = POLICY_TEXTS[path];
  const body = text
    ? policyBodyHtml(withContacts(text, contacts))
    : `    <h1>${escText(seo.title.replace(/\s*\|.*$/, ""))}</h1>\n    <p>${escText(seo.description)}</p>\n`;
  return renderShell({
    ...seo,
    canonical,
    jsonLdGraph: {
      "@context": "https://schema.org",
      "@graph": [
        ORGANIZATION_LD,
        WEBSITE_LD,
        { "@type": "WebPage", "@id": `${canonical}#page`, "url": canonical, "name": seo.title, "inLanguage": "bn", "isPartOf": { "@id": `${BASE_URL}/#website` } },
      ],
    },
    bodyHtml: `${body}${footerHtml()}`,
  });
}

// SeoTitles.notFoundTitle / notFoundDescription (parity test).
const NOT_FOUND_PAGE = {
  title: "Page not found | ChalakChar Mart",
  description: "এই পেজটি পাওয়া যায়নি। ChalakChar Mart-এ মোবাইল ও ল্যাপটপ পার্টস, কম্পিউটার এক্সেসরিজ ও অন্যান্য পণ্য দেখুন।",
};
const NOT_FOUND_PRODUCT = {
  title: "Product not found | ChalakChar Mart",
  description: "এই পণ্যটি এখন পাওয়া যাচ্ছে না। ChalakChar Mart-এ মোবাইল ও ল্যাপটপ পার্টস, কম্পিউটার এক্সেসরিজ ও অন্যান্য পণ্য দেখুন।",
};

function renderNotFoundPage(path, kind = "page") {
  const product = kind === "product";
  return renderShell({
    ...(product ? NOT_FOUND_PRODUCT : NOT_FOUND_PAGE),
    canonical: product ? `${BASE_URL}/` : `${BASE_URL}${path}`,
    robots: "noindex, follow",
  });
}

/** 503 body: the app still opens; no robots meta (the status says "retry"). */
function renderUnavailablePage(path) {
  return renderShell({
    title: SITE_NAME,
    description: "ChalakChar Mart — মোবাইল ও ল্যাপটপ পার্টস, কম্পিউটার এক্সেসরিজ ও দৈনন্দিন পণ্য।",
    canonical: `${BASE_URL}${path}`,
    robots: "index, follow",
  }).replace(/\n {2}<meta name="robots"[^>]*>/, "");
}

// -----------------------------------------------------------------------------
// Home product links (for the home HTML, see handlers.homeProductsHtml)
// -----------------------------------------------------------------------------

/** The [limit] newest products the shop shows. */
function homeProducts(products, activeCategoriesLower, limit = 20) {
  return newestFirst(products.filter((p) => isProductIndexable(p, activeCategoriesLower))).slice(0, limit);
}

// Same as web/index.html and lib/services/seo_titles.dart SeoTitles.homeTitle.
const HOME_TITLE = "ChalakChar Mart | মোবাইল ও ল্যাপটপ পার্টস অনলাইন — ক্যাশ অন ডেলিভারি";
const HOME_DESCRIPTION = "মোবাইল ও ল্যাপটপ পার্টস, ডিসপ্লে, ব্যাটারি, মাদারবোর্ড ও কম্পিউটার এক্সেসরিজ অনলাইনে কিনুন। ক্যাশ অন ডেলিভারি, সারা বাংলাদেশে হোম ডেলিভারি।";

/**
 * Home page: [categories] all category docs, [products] active+approved
 * candidates (filtered here with the shop rule).
 */
function renderHomePage({ categories, products, activeCategoriesLower }) {
  const visible = products.filter((p) => isProductIndexable(p, activeCategoriesLower));
  const counts = new Map();
  for (const p of visible) {
    const key = cleanText(p.category).toLowerCase();
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  const cats = categories
    .filter((c) => c.isActive === true && counts.get(cleanText(c.name).toLowerCase()) > 0)
    .sort((a, b) => (Number(a.priority) || 0) - (Number(b.priority) || 0));
  const newest = homeProducts(products, activeCategoriesLower, 20);
  const body = `    <h1>ChalakChar Mart — মোবাইল ও ল্যাপটপ পার্টস অনলাইন শপ</h1>
    <p>চালাকচর বাজার, মনোহরদী, নরসিংদীর অনলাইন শপ। মোবাইল ও ল্যাপটপের ডিসপ্লে, ব্যাটারি, মাদারবোর্ড, কম্পিউটার এক্সেসরিজ ও দৈনন্দিন পণ্য।</p>
    <p>মডেল মিলিয়ে অর্ডার করুন — ক্যাশ অন ডেলিভারি, সারা বাংলাদেশে হোম ডেলিভারি।</p>
    <h2>ক্যাটাগরি</h2>
    <ul>
${cats.map((c) => `      <li><a href="/category/${seoSlug(c.name)}">${escText(plainText(c.name))}</a></li>`).join("\n")}
    </ul>
${newest.length ? `    <h2>নতুন পণ্য</h2>
    <ul>
${newest.map(productLinkItem).join("\n")}
    </ul>
` : ""}${footerHtml()}`;
  return renderShell({
    title: HOME_TITLE,
    description: HOME_DESCRIPTION,
    canonical: `${BASE_URL}/`,
    jsonLdGraph: {
      "@context": "https://schema.org",
      "@graph": [
        ORGANIZATION_LD,
        WEBSITE_LD,
        ...(cats.length ? [{
          "@type": "ItemList",
          "@id": `${BASE_URL}/#categories`,
          "itemListElement": cats.map((c, i) => ({
            "@type": "ListItem", "position": i + 1, "name": plainText(c.name), "url": `${BASE_URL}/category/${seoSlug(c.name)}`,
          })),
        }] : []),
      ],
    },
    bodyHtml: body,
  });
}

// -----------------------------------------------------------------------------
// Sitemap
// -----------------------------------------------------------------------------

function escapeXml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function latest(...values) {
  let best = null;
  for (const v of values.flat()) {
    const d = toDate(v);
    if (d && !Number.isNaN(d.getTime()) && (!best || d > best)) best = d;
  }
  return best;
}

function sitemapEntry(loc, lastmod, changefreq, priority) {
  return `  <url>
    <loc>${escapeXml(loc)}</loc>
${lastmod ? `    <lastmod>${escapeXml(lastmod.toISOString().slice(0, 10))}</lastmod>\n` : ""}    <changefreq>${changefreq}</changefreq>
    <priority>${priority}</priority>
  </url>`;
}

/**
 * Only indexable URLs, each lastmod from real data: products their
 * updatedAt, a category its own or its newest product's, the home page the
 * newest product's, policy pages [policyLastModified] (the date their text
 * last changed). No date → no lastmod (never "today").
 */
function renderSitemap({ categories, products, activeCategoriesLower, policyLastModified }) {
  const visible = products.filter((p) => isProductIndexable(p, activeCategoriesLower));
  const byCategory = new Map();
  for (const p of visible) {
    const key = cleanText(p.category).toLowerCase();
    if (!byCategory.has(key)) byCategory.set(key, []);
    byCategory.get(key).push(p);
  }
  const productDate = (p) => latest(p.updatedAt || p.createdAt);
  const urls = [sitemapEntry(`${BASE_URL}/`, latest(visible.map(productDate)), "daily", "1.0")];
  const policyDate = policyLastModified ? latest(policyLastModified) : null;
  for (const [path, priority] of [["/about-us", "0.5"], ["/privacy-policy", "0.3"], ["/terms-conditions", "0.3"], ["/return-policy", "0.3"]]) {
    urls.push(sitemapEntry(`${BASE_URL}${path}`, policyDate, "monthly", priority));
  }
  const seenSlugs = new Set();
  for (const c of categories) {
    if (c.isActive !== true) continue;
    const slug = seoSlug(c.name);
    const inIt = byCategory.get(cleanText(c.name).toLowerCase()) || [];
    if (!slug || seenSlugs.has(slug) || !inIt.length) continue;
    seenSlugs.add(slug);
    urls.push(sitemapEntry(`${BASE_URL}/category/${slug}`, latest(c.updatedAt || c.createdAt, inIt.map(productDate)), "weekly", "0.8"));
  }
  for (const p of visible) {
    urls.push(sitemapEntry(`${BASE_URL}/product/${encodeURIComponent(p.id)}`, productDate(p), "weekly", "0.7"));
  }
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.join("\n")}
</urlset>
`;
}

module.exports = {
  BASE_URL,
  POLICY_PAGE_SEO,
  APP_SHELL_PRECONNECTS,
  renderShell,
  renderProductPage,
  renderCategoryPage,
  renderPolicyPage,
  renderNotFoundPage,
  renderUnavailablePage,
  renderSitemap,
  renderHomePage,
  homeProducts,
  productLinkItem,
  // exported for tests
  productTitle,
  productSummary,
  deliveryText,
  isImportedProduct,
  specificationRows,
  categoryIntro,
  policyBodyHtml,
  withContacts,
  productStock,
};
