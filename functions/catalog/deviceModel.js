// -----------------------------------------------------------------------------
// Device model keys from a product name, for "more parts for this model".
//
//   "Fully Tested Motherboard For iPhone 12 Pro Max ..."
//      -> [{ key: "iphone 12 pro max", series: "iphone 12" }]
//
// Pro / Pro Max / Plus / mini / Max / Lite / e / s / FE / Ultra / + are part
// of the model: iphone 12, iphone 12 pro, iphone 12 pro max and iphone 12
// mini are four different keys (a 12 Pro Max board does not fit a 12). The
// series key drops them, for the wider "{series} সিরিজের আরও পার্টস" row.
//
// Mirror: lib/utils/device_model.dart. Both are checked against
// test/fixtures/device_model_cases.json — keep them in step.
// -----------------------------------------------------------------------------

const SUFFIX_WORDS = new Set(["pro", "max", "plus", "mini", "lite", "ultra", "fe"]);
// Words that may sit inside a list of models without ending it.
const LIST_NOISE = new Set(["4g", "5g", "and", "&", "galaxy"]);

// Every iPhone a key may name; anything else ("xr max", "11 plus") falls
// back to its base model.
const IPHONE_MODELS = (() => {
  const set = new Set(["6", "6 plus", "6s", "6s plus", "7", "7 plus", "8", "8 plus",
    "se", "se 2020", "se 2022", "x", "xr", "xs", "xs max",
    "11", "11 pro", "11 pro max", "16e", "17 air"]);
  for (const n of [12, 13]) for (const s of ["", " mini", " pro", " pro max"]) set.add(`${n}${s}`);
  for (const n of [14, 15, 16]) for (const s of ["", " plus", " pro", " pro max"]) set.add(`${n}${s}`);
  for (const s of ["", " pro", " pro max"]) set.add(`17${s}`);
  return set;
})();

/** Lower-cased words, with glued suffixes split: "12ProMax" -> 12 pro max. */
function tokenize(name) {
  let s = String(name ?? "").toLowerCase();
  s = s.replace(/[/,|()[\]{}:;!?"']/g, " ");
  s = s.replace(/\bse(20(?:20|22))\b/g, "se $1");
  s = s.replace(/\bs(\d{2})u\b/g, "s$1 ultra");
  // "+" after a model or "pro" means Plus; "AAA+++" (a grade) stays junk.
  s = s.replace(/(\d|\bpro)\+/g, "$1 plus ");
  s = s.replace(/promax\b/g, "pro max");
  s = s.replace(/(\d[se]?)(pro|max|plus|mini|lite|ultra|fe)\b/g, "$1 $2");
  s = s.replace(/\b(cyber)(\d+)\b/g, "$1 $2");
  return s.split(/\s+/).filter(Boolean);
}

function hasLetterSuffix(base) {
  return /\d[a-z]$/.test(base) || base === "xr" || base === "xs";
}

/**
 * Suffix words right after a model: "pro max" is one suffix, other words
 * each give a model of their own ("s21 plus ultra" -> s21 plus, s21 ultra).
 */
function readSuffixes(tokens, start) {
  const words = [];
  let i = start;
  while (i < tokens.length && SUFFIX_WORDS.has(tokens[i])) words.push(tokens[i++]);
  const suffixes = [];
  for (let j = 0; j < words.length; j++) {
    if (words[j] === "pro" && (words[j + 1] === "max" || words[j + 1] === "plus")) {
      suffixes.push(`pro ${words[++j]}`);
    } else {
      suffixes.push(words[j]);
    }
  }
  return { suffixes, next: i };
}

function seriesOf(prefix, base) {
  let b = base;
  if (prefix === "iphone") {
    if (b === "xr" || b === "xs") b = "x";
    else if (b.startsWith("se")) b = "se";
  }
  b = b.replace(/^([a-z]?\d+)[a-z]$/, "$1");
  return `${prefix} ${b}`;
}

function collector() {
  const out = [];
  const seen = new Set();
  return {
    out,
    add(key, series) {
      if (seen.has(key)) return;
      seen.add(key);
      out.push({ key, series });
    },
  };
}

/**
 * Models after a family word ("nova 2 2i 3e", "redmi note 9 10 7 pro") until
 * a word that is neither a model, a suffix nor list noise.
 */
function readRun(tokens, start, prefix, modelRe, add) {
  let i = start;
  let inList = false; // previous model in this run had no suffix
  while (i < tokens.length) {
    const t = tokens[i];
    if (LIST_NOISE.has(t)) { i++; continue; }
    if (!modelRe.test(t)) break;
    const { suffixes, next } = readSuffixes(tokens, i + 1);
    const usable = hasLetterSuffix(t) ? [] : suffixes;
    addModel(add, prefix, t, usable, inList);
    inList = !suffixes.length;
    i = next;
  }
  return i;
}

/**
 * A suffixed model that ends a list of plain ones names the plain model too:
 * "X XR XS Max" lists x, xr, xs and xs max; "S21 S20 Ultra" s20 and s20 ultra.
 */
function addModel(add, prefix, base, suffixes, inList, series = seriesOf(prefix, base)) {
  if (!suffixes.length || inList) add(`${prefix} ${base}`, series);
  for (const sfx of suffixes) add(`${prefix} ${base} ${sfx}`, series);
}

function apple(tokens, add) {
  // Whole name: listings put models after "For" with no "iPhone" ("for
  // 6Plus 6sPlus") and between screen words ("LCD 11 Pro MAX Touch").
  const baseRe = /^(?:[678]s?|x|xr|xs|se|1[1-7]e?)$/;
  let plainEnd = -1; // index just after the last plain (suffix-less) model
  for (let i = 0; i < tokens.length; i++) {
    const start = i;
    let t = tokens[i];
    if (!baseRe.test(t)) continue;
    if (t === "se" && /^20(20|22)$/.test(tokens[i + 1] || "")) t = `se ${tokens[++i]}`;
    if (t === "x" && tokens[i - 1] !== "iphone" && !baseRe.test(tokens[i - 1] || "") &&
      !baseRe.test(tokens[i + 1] || "")) continue; // a lone "x" is a dimension/"x2", not an iPhone
    const { suffixes, next } = readSuffixes(tokens, i + 1);
    const valid = suffixes.filter((s) => IPHONE_MODELS.has(`${t} ${s}`));
    if (!IPHONE_MODELS.has(t) && !valid.length) continue;
    const inList = plainEnd === start && IPHONE_MODELS.has(t);
    addModel(add, "iphone", t, valid, inList);
    if (!valid.length) plainEnd = next;
    i = next - 1;
  }
}

function samsung(tokens, add) {
  let plainEnd = -1;
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (/^[asmfj]\d{1,2}[se]?$/.test(t)) {
      const { suffixes, next } = readSuffixes(tokens, i + 1);
      const usable = hasLetterSuffix(t) ? [] : suffixes;
      addModel(add, "samsung", t, usable, plainEnd === i);
      if (!usable.length) plainEnd = next;
      i = next - 1;
    } else if (/^s\d{1,2}fe$/.test(t)) {
      add(`samsung ${t.slice(0, -2)} fe`, seriesOf("samsung", t.slice(0, -2)));
    } else if (t === "note") {
      i = readRun(tokens, i + 1, "samsung note", /^\d{1,2}$/, add) - 1;
    } else if (t === "tab" && /^(a\d?|s\d{0,2})$/.test(tokens[i + 1] || "")) {
      const model = tokens[i + 1];
      const size = /^\d{1,2}\.\d$/.test(tokens[i + 2] || "") ? ` ${tokens[i + 2]}` : "";
      add(`samsung tab ${model}${size}`, `samsung tab ${model}`);
    }
  }
}

function huawei(tokens, add) {
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t === "nova") i = readRun(tokens, i + 1, "huawei nova", /^\d{1,2}[a-z]?$/, add) - 1;
    else if (t === "mate") i = readRun(tokens, i + 1, "huawei mate", /^\d{1,2}$/, add) - 1;
    else if (/^[py]\d{1,2}$/.test(t)) i = readRun(tokens, i, "huawei", /^[py]\d{1,2}$/, add) - 1;
  }
}

function redmi(tokens, add) {
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i] !== "redmi") continue;
    const note = tokens[i + 1] === "note";
    const prefix = note ? "redmi note" : "redmi";
    i = readRun(tokens, i + (note ? 2 : 1), prefix, /^(?:[ac]?\d{1,2}[a-z]?)$/, add) - 1;
  }
}

function realme(tokens, add) {
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i] !== "realme") continue;
    // "C11 2020" (was "C11(2020)"): the year is not a model.
    const filtered = tokens.map((t, j) => (j > i && /^20\d\d$/.test(t) ? "and" : t));
    i = readRun(filtered, i + 1, "realme", /^(?:[c]?\d{1,2})$/, add) - 1;
  }
}

function moto(tokens, add) {
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i] !== "moto" && tokens[i] !== "motorola") continue;
    i = readRun(tokens, i + 1, "moto", /^[ge]\d{1,3}$/, add) - 1;
  }
}

function other(tokens, add) {
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t === "cyber" && tokens[i - 1] === "hotwav" && /^\d{1,2}$/.test(tokens[i + 1] || "")) {
      add(`hotwav cyber ${tokens[i + 1]}`, `hotwav cyber ${tokens[i + 1]}`);
    }
    if (t === "probook" || t === "elitebook" || t === "pavilion") {
      const m = tokens[i + 1] || "";
      if (/^\d{2,4}(-[a-z0-9]+)?$/.test(m)) add(`hp ${t} ${m}`, `hp ${t} ${m}`);
    }
    if (/^\d{3}$/.test(t) && /^g\d$/.test(tokens[i + 1] || "") && tokens.includes("hp")) {
      add(`hp ${t} ${tokens[i + 1]}`, `hp ${t} ${tokens[i + 1]}`);
    }
  }
}

/** [{ key, series }] for every device model the name names, in order. */
function deviceModels(name) {
  const tokens = tokenize(name);
  const has = (w) => tokens.includes(w);
  const c = collector();
  if (has("iphone")) apple(tokens, c.add);
  if (has("samsung") || has("galaxy")) samsung(tokens, c.add);
  if (has("huawei")) huawei(tokens, c.add);
  if (has("redmi")) redmi(tokens, c.add);
  if (has("realme")) realme(tokens, c.add);
  if (has("moto") || has("motorola")) moto(tokens, c.add);
  other(tokens, c.add);
  return c.out;
}

/** Fields stored on the product doc: modelKeys + modelSeries (unique). */
function modelFieldsForName(name) {
  const models = deviceModels(name);
  return {
    modelKeys: models.map((m) => m.key),
    modelSeries: [...new Set(models.map((m) => m.series))],
  };
}

const MODEL_KEYS_STAMP = "modelKeysAt";
const MODEL_KEYS_SOURCE = "model_keys";

function sameList(a, b) {
  return Array.isArray(a) && a.length === b.length && a.every((v, i) => v === b[i]);
}

/**
 * The write that brings a product's modelKeys/modelSeries in line with its
 * name, stamped like the price guard; null when they already match (so the
 * trigger event this write causes computes null — no loop).
 * [stamp] is the timestamp value to store (FieldValue.serverTimestamp()).
 */
function modelKeysUpdate(product, stamp) {
  const fields = modelFieldsForName(product?.name);
  if (sameList(product?.modelKeys, fields.modelKeys) && sameList(product?.modelSeries, fields.modelSeries)) {
    return null;
  }
  return { ...fields, [MODEL_KEYS_STAMP]: stamp, lastWriteSource: MODEL_KEYS_SOURCE };
}

function stampMs(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return 0;
}

/** True when THIS write is the model-key sync (new modelKeysAt): it sends nothing. */
function isModelKeysWrite(before, after) {
  const afterMs = stampMs(after?.[MODEL_KEYS_STAMP]);
  return afterMs > 0 && afterMs !== stampMs(before?.[MODEL_KEYS_STAMP]);
}

module.exports = {
  deviceModels,
  modelFieldsForName,
  modelKeysUpdate,
  isModelKeysWrite,
  tokenize,
  MODEL_KEYS_SOURCE,
};
