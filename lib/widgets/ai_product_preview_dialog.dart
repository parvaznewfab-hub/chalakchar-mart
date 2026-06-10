import 'package:flutter/material.dart';

class AIProductPreviewDialog extends StatelessWidget {
  final String title;
  final String banglaTitle;
  final String description;
  final List<String> seoTags;
  final VoidCallback onApply;

  const AIProductPreviewDialog({
    super.key,
    required this.title,
    required this.banglaTitle,
    required this.description,
    required this.seoTags,
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
        width: 520,
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

              _sectionTitle('Description'),
              _box(description),
              const SizedBox(height: 12),

              _sectionTitle('SEO Tags'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: seoTags.map((tag) {
                  return Chip(
                    label: Text(tag),
                    backgroundColor: Colors.deepPurple.withOpacity(0.08),
                  );
                }).toList(),
              ),
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
}