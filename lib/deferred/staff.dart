import 'package:flutter/material.dart';

import 'staff_pages.dart' deferred as pages;

/// Staff / seller / delivery-partner pages, loaded the first time one is
/// opened (see staff_pages.dart). Each getter returns a widget that shows a
/// spinner while that code downloads, then the page.
class StaffPages {
  StaffPages._();

  static Future<void>? _loading;

  static Future<void> _load() => _loading ??= pages.loadLibrary().catchError((Object e) {
        _loading = null; // let a later attempt retry (e.g. after going offline)
        throw e;
      });

  static Widget adminDashboard() => _DeferredPage(() => pages.adminDashboard());
  static Widget adminEditOrder(String orderId) => _DeferredPage(() => pages.adminEditOrder(orderId));
  static Widget adminLists() => _DeferredPage(() => pages.adminLists());
  static Widget adminNotifications() => _DeferredPage(() => pages.adminNotifications());
  static Widget deliveryPartnerApply() => _DeferredPage(() => pages.deliveryPartnerApply());
  static Widget deliveryPartnerDashboard() => _DeferredPage(() => pages.deliveryPartnerDashboard());
  static Widget vendorApply() => _DeferredPage(() => pages.vendorApply());
  static Widget vendorDashboard() => _DeferredPage(() => pages.vendorDashboard());
}

class _DeferredPage extends StatefulWidget {
  const _DeferredPage(this.build);

  final Widget Function() build;

  @override
  State<_DeferredPage> createState() => _DeferredPageState();
}

class _DeferredPageState extends State<_DeferredPage> {
  late Future<void> _future = StaffPages._load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done && !snap.hasError) {
          return widget.build();
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load this page. Check your connection.'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(() => _future = StaffPages._load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
