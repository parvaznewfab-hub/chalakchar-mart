import 'package:flutter/material.dart';

class AIProductPreviewDialog extends StatelessWidget {
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

  final String suggestedCategory;
  final String suggestedSubCategory;
  final String productType;

  final VoidCallback onApply;

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
  });

  @override
  Widget build(BuildContext context) {
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
              _box(title),
              const SizedBox(height: 12),

              _sectionTitle('Bangla Title'),
              _box(banglaTitle),
              const SizedBox(height: 12),

              _sectionTitle('English Description'),
              _box(description),
              const SizedBox(height: 12),

              _sectionTitle('Bangla Description'),
              _box(banglaDescription),
              const SizedBox(height: 12),

              _sectionTitle('Meta Title'),
              _box(metaTitle),
              const SizedBox(height: 12),

              _sectionTitle('Meta Description'),
              _box(metaDescription),
              const SizedBox(height: 12),

              _sectionTitle('Facebook Caption'),
              _box(facebookCaption),
              const SizedBox(height: 12),

              _sectionTitle('WhatsApp Caption'),
              _box(whatsappCaption),
              const SizedBox(height: 12),

              _sectionTitle('SEO Tags'),
              _chips(seoTags),

              const SizedBox(height: 16),

              _sectionTitle('Search Keywords'),
              _chips(searchKeywords),

              const SizedBox(height: 16),

              _sectionTitle('Suggested Category'),
              _box(suggestedCategory),
              const SizedBox(height: 12),

              _sectionTitle('Suggested Sub Category'),
              _box(suggestedSubCategory),
              const SizedBox(height: 12),

              _sectionTitle('Product Type'),
              _box(productType),
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

            onApply();
          },
          icon: const Icon(Icons.check),
          label: const Text('Apply'),
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
