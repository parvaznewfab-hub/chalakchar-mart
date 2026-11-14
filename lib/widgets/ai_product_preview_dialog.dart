import 'package:flutter/material.dart';

import '../utils/ai_taxonomy_match.dart';

class AIProductPreviewDialog extends StatefulWidget {
  final String title;
  final String banglaTitle;
  final String description;
  final String banglaDescription;

  final List<String> seoTags;

  final String facebookCaption;
  final String whatsappCaption;

  final String metaTitle;
  final String metaDescription;

  final List<String> searchKeywords;

  /// The AI's own category answer, shown as-is.
  final String suggestedCategory;
  final String suggestedSubCategory;
  final String productType;

  /// The product's category/subcategory now (names and ids; '' = none).
  final String currentCategoryId;
  final String currentCategory;
  final String currentSubcategoryId;
  final String currentSubcategory;

  /// [suggestedCategory] matched to the store's active taxonomy; null or
  /// unmatched means the category stays as it is.
  final AiTaxonomyMatch? categoryMatch;

  /// [changeCategory] is the "change category" checkbox (off by default);
  /// everything else is applied regardless.
  final void Function(bool changeCategory) onApply;

  const AIProductPreviewDialog({
    super.key,
    required this.title,
    required this.banglaTitle,
    required this.description,
    required this.banglaDescription,
    required this.seoTags,
    required this.facebookCaption,
    required this.whatsappCaption,
    required this.metaTitle,
    required this.metaDescription,
    required this.searchKeywords,
    required this.suggestedCategory,
    required this.suggestedSubCategory,
    required this.productType,
    required this.onApply,
    this.currentCategoryId = '',
    this.currentCategory = '',
    this.currentSubcategoryId = '',
    this.currentSubcategory = '',
    this.categoryMatch,
  });

  @override
  State<AIProductPreviewDialog> createState() => _AIProductPreviewDialogState();
}

class _AIProductPreviewDialogState extends State<AIProductPreviewDialog> {
  bool _changeCategory = false;

  AiTaxonomyMatch? get _match {
    final m = widget.categoryMatch;
    return m != null && m.matched ? m : null;
  }

  /// A match that differs from what the product already has.
  bool get _canChange {
    final m = _match;
    return m != null &&
        (m.categoryId != widget.currentCategoryId ||
            m.subcategoryId != widget.currentSubcategoryId);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome, color: Colors.deepPurple),
          SizedBox(width: 8),
          Text('AI Product Preview'),
        ],
      ),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('English Title'),
              _box(w.title),
              const SizedBox(height: 12),

              _sectionTitle('Bangla Title'),
              _box(w.banglaTitle),
              const SizedBox(height: 12),

              _sectionTitle('English Description'),
              _box(w.description),
              const SizedBox(height: 12),

              _sectionTitle('Bangla Description'),
              _box(w.banglaDescription),
              const SizedBox(height: 12),

              _sectionTitle('Meta Title'),
              _box(w.metaTitle),
              const SizedBox(height: 12),

              _sectionTitle('Meta Description'),
              _box(w.metaDescription),
              const SizedBox(height: 12),

              _sectionTitle('Facebook Caption'),
              _box(w.facebookCaption),
              const SizedBox(height: 12),

              _sectionTitle('WhatsApp Caption'),
              _box(w.whatsappCaption),
              const SizedBox(height: 12),

              _sectionTitle('SEO Tags'),
              _chips(w.seoTags),

              const SizedBox(height: 16),

              _sectionTitle('Search Keywords'),
              _chips(w.searchKeywords),

              const SizedBox(height: 16),

              _sectionTitle('Category'),
              _categorySection(),
              const SizedBox(height: 12),

              _sectionTitle('Product Type'),
              _box(w.productType),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            Navigator.pop(context);

            await Future.delayed(
              const Duration(milliseconds: 100),
            );

            widget.onApply(_canChange && _changeCategory);
          },
          icon: const Icon(Icons.check),
          label: const Text('Apply'),
        ),
      ],
    );
  }

  static String _path(String category, String subcategory) {
    if (category.isEmpty) return '(none)';
    return subcategory.isEmpty ? '$category  ›  (no subcategory)' : '$category  ›  $subcategory';
  }

  Widget _categorySection() {
    final w = widget;
    final match = _match;
    final rawAnswer = [w.suggestedCategory, w.suggestedSubCategory]
        .where((t) => t.trim().isNotEmpty)
        .join(' / ');

    final proposed = match == null
        ? Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: const Text(
              'মিল পাওয়া যায়নি — বর্তমানটাই থাকবে',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          )
        : _box(_path(match.categoryName, match.subcategoryName));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text('Current', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  _box(_path(w.currentCategory, w.currentSubcategory)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 40, 8, 0),
              child: Icon(Icons.arrow_forward_rounded, size: 20),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text('Suggested', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  proposed,
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'AI answered: ${rawAnswer.isEmpty ? '(nothing)' : rawAnswer}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _canChange && _changeCategory,
          onChanged: _canChange ? (v) => setState(() => _changeCategory = v ?? false) : null,
          title: const Text('Change category to the suggested one'),
          subtitle: Text(
            match == null
                ? 'Not available: the suggestion is not one of our active categories.'
                : !_canChange
                    ? 'Already in the suggested category.'
                    : 'Off: only title, description, captions, tags and meta are applied.',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  static Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    );
  }

  static Widget _box(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        text.isEmpty ? 'No data' : text,
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  static Widget _chips(List<String> items) {
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('No data'),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((tag) => Chip(label: Text(tag))).toList(),
      ),
    );
  }
}
