// -----------------------------------------------------------------------------
// Publish policy for search-miss imports (search box and chat fallback).
//
// They used to be forced live (forcePublish) whatever the admin's
// importSettings.autoPublish said; on 2026-11-14 a chat question imported 5
// unrelated costume products straight onto the storefront. Now they go live
// only when the admin allows it twice: importSettings.autoPublish AND
// importSettings.searchImportAutoPublish (default off). needsReview is always
// set, so they are never marketed until an admin publishes/reviews them.
//
// Pure: no Firestore.
// -----------------------------------------------------------------------------

/**
 * @param {{autoPublish?: boolean, searchImportAutoPublish?: boolean}} importSettings
 *   marketplaceImportSettings() output
 * @returns {{ publish: boolean, options: { forcePublish?: true, forceUnpublish?: true, needsReview: true } }}
 */
function searchImportPublishOptions(importSettings) {
  const publish = importSettings?.autoPublish === true && importSettings?.searchImportAutoPublish === true;
  return {
    publish,
    options: publish
      ? { forcePublish: true, needsReview: true }
      : { forceUnpublish: true, needsReview: true },
  };
}

module.exports = { searchImportPublishOptions };
