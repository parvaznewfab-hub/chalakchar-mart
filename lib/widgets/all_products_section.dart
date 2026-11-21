import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_settings_service.dart';
import '../services/category_service.dart';
import '../utils/shop_visibility.dart';
import 'product_card.dart';

/// End of the home page: a row of reasons to trust the shop, then every
/// product shoppers can see, newest first, 20 at a time.
///
/// Only products in an existing, active category: the old grocery /
/// uncategorized items stay out until the owner decides on them (audit D1).
class AllProductsSection extends StatefulWidget {
  const AllProductsSection({super.key, this.onAddToCart, this.isDesktop = false});

  final Function(GlobalKey)? onAddToCart;
  final bool isDesktop;

  @override
  State<AllProductsSection> createState() => _AllProductsSectionState();
}

class _AllProductsSectionState extends State<AllProductsSection> {
  static const int _pageSize = 20;
  static const Color _accent = Color(0xFF1E7A3A);

  int _shown = _pageSize;
  late final Future<List<String>> _categoryNames = CategoryService.activeCategoryNames();

  static int _createdMs(Map<String, dynamic> p) {
    final v = p['createdAt'];
    return v is Timestamp ? v.millisecondsSinceEpoch : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TrustRow(isDesktop: widget.isDesktop),
        SizedBox(height: widget.isDesktop ? 24 : 12),
        FutureBuilder<List<String>>(
          future: _categoryNames,
          builder: (context, cats) {
            final names = cats.data ?? const <String>[];
            if (names.isEmpty) return const SizedBox.shrink();
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // Same filters as the category sections (existing index:
              // isActive, approvalStatus, category); newest first below.
              stream: FirebaseFirestore.instance
                  .collection('products')
                  .where('isActive', isEqualTo: true)
                  .where('approvalStatus', isEqualTo: 'approved')
                  .where('category', whereIn: names.take(30).toList())
                  .limit(300)
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? const [];
                final active = {for (final n in names) n.toLowerCase()};
                final products = <Map<String, dynamic>>[
                  for (final d in shopVisibleOnly(docs, active, (d) => d.data()))
                    {...d.data(), 'id': d.id},
                ]..sort((a, b) => _createdMs(b).compareTo(_createdMs(a)));
                if (products.isEmpty) return const SizedBox.shrink();
                final visible = products.take(_shown).toList();
                return _grid(context, visible, hasMore: products.length > _shown);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _grid(BuildContext context, List<Map<String, dynamic>> products, {required bool hasMore}) {
    return Container(
      margin: widget.isDesktop ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'সব প্রোডাক্ট',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = widget.isDesktop
                  ? (constraints.maxWidth / 190).floor().clamp(3, 6)
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                clipBehavior: Clip.none,
                padding: EdgeInsets.zero,
                itemCount: products.length,
                gridDelegate: ProductCard.gridDelegate(context, crossAxisCount: columns),
                itemBuilder: (context, i) => ProductCard(
                  data: products[i],
                  gridMode: true,
                  onAddToCart: widget.onAddToCart,
                ),
              );
            },
          ),
          if (hasMore) ...[
            const SizedBox(height: 14),
            Center(
              child: OutlinedButton(
                onPressed: () => setState(() => _shown += _pageSize),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _accent),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                ),
                child: const Text('আরও দেখুন', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Cash on delivery · nationwide delivery · WhatsApp help.
class _TrustRow extends StatelessWidget {
  const _TrustRow({required this.isDesktop});

  final bool isDesktop;

  static String _whatsappUrl(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) digits = '8801975838764';
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = '880${digits.substring(1)}';
    return 'https://wa.me/$digits';
  }

  @override
  Widget build(BuildContext context) {
    final whatsapp = AppSettingsService.cached.whatsappNumber;
    final items = <(IconData, String, String, VoidCallback?)>[
      (Icons.payments_outlined, 'ক্যাশ অন ডেলিভারি', 'পণ্য হাতে পেয়ে টাকা দিন', null),
      (Icons.local_shipping_outlined, 'সারা দেশে ডেলিভারি', 'সময় প্রোডাক্ট পেজে লেখা থাকে', null),
      (
        Icons.chat_outlined,
        'WhatsApp-এ যোগাযোগ',
        'মডেল মিলিয়ে দিতে সাহায্য',
        () => launchUrl(Uri.parse(_whatsappUrl(whatsapp)), mode: LaunchMode.externalApplication),
      ),
    ];

    Widget tile((IconData, String, String, VoidCallback?) item) {
      final (icon, title, subtitle, onTap) = item;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF1E7A3A), size: isDesktop ? 28 : 24),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(fontSize: isDesktop ? 14 : 12, fontWeight: FontWeight.w700, height: 1.2),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(fontSize: isDesktop ? 12 : 10.5, color: Colors.grey.shade700, height: 1.2),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: isDesktop ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final item in items) Expanded(child: tile(item))],
      ),
    );
  }
}
