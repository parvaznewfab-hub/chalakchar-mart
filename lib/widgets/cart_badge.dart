import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../pages/user/cart_page.dart';
import '../services/guest_cart_service.dart';
import '../services/product_service.dart';

class CartBadge extends StatelessWidget {
  final Color iconColor;

  const CartBadge({
    super.key,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid ?? '';

    Widget iconWithBadge(int count) {
      return Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: Icon(Icons.shopping_cart, color: iconColor),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartPage()),
              );

              // Needed when a guest changes qty/removes items in CartPage.
              await GuestCartService.refreshCount();
            },
          ),
          if (count > 0)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      );
    }

    if (userId.isEmpty) {
      GuestCartService.refreshCount();

      return ValueListenableBuilder<int>(
        valueListenable: GuestCartService.cartCount,
        builder: (_, count, __) => iconWithBadge(count),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cart')
          .doc(userId)
          .collection('items')
          .snapshots(),
      builder: (context, snapshot) {
        int count = 0;

        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            count += ProductService.toInt(data['qty'], 1);
          }
        }

        return iconWithBadge(count);
      },
    );
  }
}
