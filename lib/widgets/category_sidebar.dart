import 'package:flutter/material.dart';

import '../services/category_service.dart';
import '../services/web_url_service.dart';

/// Desktop-web "Categories" box shared by the home page and the category
/// page. A category with active subcategories gets a ">" that expands its
/// subcategory list; the category name itself opens the category page.
class CategorySidebar extends StatefulWidget {
  /// The category whose page is open, highlighted and expanded initially.
  final String? activeCategoryId;

  /// The selected subcategory's slug on that page, highlighted.
  final String? activeSubSlug;

  /// When set, a subcategory of [activeCategoryId] is selected through this
  /// callback instead of navigating (the page is already open).
  final ValueChanged<String>? onSelectActiveSub;

  const CategorySidebar({
    super.key,
    this.activeCategoryId,
    this.activeSubSlug,
    this.onSelectActiveSub,
  });

  static const Color _accent = Color(0xFF32A8C7);

  @override
  State<CategorySidebar> createState() => _CategorySidebarState();
}

class _CategorySidebarState extends State<CategorySidebar> {
  // Held once so a rebuild (expand/collapse) doesn't resubscribe.
  late final Stream<List<CategoryModel>> _categories =
      CategoryService.watchHomeCategories();
  final Future<Map<String, List<SubcategoryModel>>> _subcategories =
      CategoryService.activeSubcategoriesByCategory();

  late final Set<String> _expanded = {
    if (widget.activeCategoryId != null) widget.activeCategoryId!,
  };

  void _open(String path) {
    WebUrlService.push(path);
    Navigator.of(context, rootNavigator: true).pushNamed(path);
  }

  void _openCategory(CategoryModel category) {
    if (category.name.trim().isEmpty) return;
    _open(
        '/category/${Uri.encodeComponent(CategoryService.slugOf(category.name))}');
  }

  void _openSubcategory(CategoryModel category, SubcategoryModel sub) {
    final onSelect = widget.onSelectActiveSub;
    if (onSelect != null && category.id == widget.activeCategoryId) {
      onSelect(sub.slug);
      return;
    }
    _open(
        '/category/${Uri.encodeComponent(CategoryService.slugOf(category.name))}'
        '?sub=${Uri.encodeQueryComponent(sub.slug)}');
  }

  void _toggle(String categoryId) {
    setState(() {
      if (!_expanded.remove(categoryId)) _expanded.add(categoryId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              "Categories",
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black87),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<CategoryModel>>(
              stream: _categories,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const SizedBox();
                }

                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Category error: ${snap.error}',
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  );
                }

                final categories = snap.data ?? const <CategoryModel>[];
                if (categories.isEmpty) return const SizedBox();

                return FutureBuilder<Map<String, List<SubcategoryModel>>>(
                  future: _subcategories,
                  builder: (context, subSnap) {
                    // Until loaded (or if the read failed) the list renders
                    // without ">" — categories still open normally.
                    final subsByCategory = subSnap.data ?? const {};
                    return ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        return _categoryTile(
                          category,
                          subsByCategory[category.id] ?? const [],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _categoryTile(CategoryModel category, List<SubcategoryModel> subs) {
    final isActive = category.id == widget.activeCategoryId;
    final expanded = subs.isNotEmpty && _expanded.contains(category.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: isActive
              ? CategorySidebar._accent.withValues(alpha: 0.08)
              : Colors.transparent,
          child: ListTile(
            contentPadding:
                EdgeInsets.fromLTRB(20, 4, subs.isEmpty ? 20 : 8, 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: category.imageUrl.isNotEmpty
                  ? Image.network(
                      category.imageUrl,
                      width: 24,
                      height: 24,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.category_outlined,
                        size: 20,
                        color: Colors.grey,
                      ),
                    )
                  : const Icon(Icons.category_outlined,
                      size: 20, color: Colors.grey),
            ),
            title: Text(
              category.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? CategorySidebar._accent : Colors.black87,
              ),
            ),
            trailing: subs.isEmpty
                ? null
                : IconButton(
                    tooltip:
                        expanded ? 'Hide subcategories' : 'Show subcategories',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _toggle(category.id),
                    icon: AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.chevron_right,
                          size: 16, color: Colors.grey),
                    ),
                  ),
            onTap: () => _openCategory(category),
          ),
        ),
        if (expanded)
          for (final sub in subs) _subcategoryTile(category, sub, isActive),
      ],
    );
  }

  Widget _subcategoryTile(
      CategoryModel category, SubcategoryModel sub, bool parentActive) {
    final selected = parentActive && sub.slug == widget.activeSubSlug;

    return InkWell(
      onTap: () => _openSubcategory(category, sub),
      child: Container(
        padding: const EdgeInsets.fromLTRB(64, 9, 20, 9),
        decoration: BoxDecoration(
          color:
              selected ? CategorySidebar._accent.withValues(alpha: 0.12) : null,
          border: Border(
            left: BorderSide(
              color: selected ? CategorySidebar._accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          sub.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            color: selected ? CategorySidebar._accent : Colors.black54,
          ),
        ),
      ),
    );
  }
}
