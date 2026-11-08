const { test, describe } = require("node:test");
const assert = require("node:assert/strict");

const {
  buildCategorySuggestionPrompt,
  parseCategorySuggestionResponse,
} = require("../category/suggestAliExpressCategoryAi");

describe("buildCategorySuggestionPrompt", () => {
  test("lists every candidate category and includes the product title", () => {
    const prompt = buildCategorySuggestionPrompt({
      title: "JBL Speaker Portable",
      candidateNames: ["Electronics", "Mobile Parts", "Grocery"],
    });
    assert.match(prompt, /Electronics/);
    assert.match(prompt, /Mobile Parts/);
    assert.match(prompt, /Grocery/);
    assert.match(prompt, /JBL Speaker Portable/);
  });

  test("handles an empty candidate list without throwing", () => {
    const prompt = buildCategorySuggestionPrompt({ title: "Something", candidateNames: [] });
    assert.match(prompt, /Something/);
    assert.match(prompt, /none yet/);
  });
});

describe("parseCategorySuggestionResponse", () => {
  const candidates = ["Electronics", "Mobile Parts", "Grocery"];

  test("accepts an exact-match matchedCategory", () => {
    const result = parseCategorySuggestionResponse(
      JSON.stringify({ matchedCategory: "Electronics", suggestedNewCategory: "" }),
      candidates
    );
    assert.deepEqual(result, { matchedCategory: "Electronics", suggestedNewCategory: "" });
  });

  test("is case/whitespace-insensitive but returns the canonical stored name", () => {
    const result = parseCategorySuggestionResponse(
      JSON.stringify({ matchedCategory: "  electronics  " }),
      candidates
    );
    assert.equal(result.matchedCategory, "Electronics");
  });

  test("rejects a hallucinated category not in the candidate list — never trusted blindly", () => {
    const result = parseCategorySuggestionResponse(
      JSON.stringify({ matchedCategory: "Speakers & Audio", suggestedNewCategory: "Speakers & Audio" }),
      candidates
    );
    assert.equal(result.matchedCategory, null);
    assert.equal(result.suggestedNewCategory, "Speakers & Audio");
  });

  test("falls through to suggestedNewCategory when matchedCategory is null", () => {
    const result = parseCategorySuggestionResponse(
      JSON.stringify({ matchedCategory: null, suggestedNewCategory: "Home Decor" }),
      candidates
    );
    assert.deepEqual(result, { matchedCategory: null, suggestedNewCategory: "Home Decor" });
  });

  test("malformed JSON never throws — resolves to no match, no suggestion", () => {
    const result = parseCategorySuggestionResponse("not json at all", candidates);
    assert.deepEqual(result, { matchedCategory: null, suggestedNewCategory: "" });
  });

  test("suggestedNewCategory is ignored once a real match is found, even if the model also filled it in", () => {
    const result = parseCategorySuggestionResponse(
      JSON.stringify({ matchedCategory: "Grocery", suggestedNewCategory: "Something Else" }),
      candidates
    );
    assert.equal(result.matchedCategory, "Grocery");
    assert.equal(result.suggestedNewCategory, "");
  });
});
