// Pages only staff, sellers and delivery partners open (admin panel, vendor
// dashboard, delivery dashboard, sign-up forms). Loaded on demand through
// staff.dart, so shoppers never download this code (about half the app).
// Import staff.dart, never this file directly: a normal import would pull
// all of it back into the main bundle.

import 'package:flutter/widgets.dart';

import '../pages/admin/admin_dashboard_page.dart';
import '../pages/admin/admin_edit_order_page.dart';
import '../pages/admin/admin_lists_page.dart';
import '../pages/admin/admin_notifications_page.dart';
import '../pages/user/delivery/delivery_partner_apply_page.dart';
import '../pages/user/delivery/delivery_partner_dashboard_page.dart';
import '../pages/vendor/vendor_apply_page.dart';
import '../pages/vendor/vendor_dashboard_page.dart';

Widget adminDashboard() => const AdminDashboard();
Widget adminEditOrder(String orderId) => AdminEditOrderPage(orderId: orderId);
Widget adminLists() => const AdminListsPage();
Widget adminNotifications() => const AdminNotificationsPage();
Widget deliveryPartnerApply() => const DeliveryPartnerApplyPage();
Widget deliveryPartnerDashboard() => const DeliveryPartnerDashboardPage();
Widget vendorApply() => const VendorApplyPage();
Widget vendorDashboard() => const VendorDashboardPage();
