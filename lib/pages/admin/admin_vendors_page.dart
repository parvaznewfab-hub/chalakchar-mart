import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';

class AdminVendorsPage extends StatefulWidget {
  const AdminVendorsPage({super.key});

  @override
  State<AdminVendorsPage> createState() => _AdminVendorsPageState();
}

class _AdminVendorsPageState extends State<AdminVendorsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();

  bool permissionLoading = true;
  bool canViewVendors = false;
  bool canEditVendors = false;
  bool canApproveVendors = false;
  bool canDeleteVendors = false;
  bool canChangeVendorStatus = false;
  bool canViewVendorDocuments = false;
  bool canContactVendors = false;

  final searchController = TextEditingController();

  String searchText = '';
  String statusFilter = 'all';
  String activeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final results = await Future.wait<bool>([
        authService.hasPermission('vendors.view'),
        authService.hasPermission('vendors.edit'),
        authService.hasPermission('vendors.approve'),
        authService.hasPermission('vendors.delete'),
        authService.hasPermission('vendors.status'),
        authService.hasPermission('vendors.documents'),
        authService.hasPermission('vendors.contact'),
      ]);

      if (!mounted) return;
      setState(() {
        canViewVendors = results[0];
        canEditVendors = results[1];
        canApproveVendors = results[2];
        canDeleteVendors = results[3];
        canChangeVendorStatus = results[4];
        canViewVendorDocuments = results[5];
        canContactVendors = results[6];
        permissionLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => permissionLoading = false);
      _snack('Permission load failed: $e');
    }
  }

  bool _denyUnless(bool allowed, String message) {
    if (allowed) return false;
    _snack(message);
    return true;
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  double _toDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  int _toInt(dynamic value, [int fallback = 0]) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  String _dateText(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
    }
    return 'N/A';
  }

  bool _active(Map<String, dynamic> data) => data['isActive'] == true;

  String _vendorOwnerId(String docId, Map<String, dynamic> data) {
    final ownerId = _text(data['ownerId']);
    if (ownerId.isNotEmpty) return ownerId;

    final userId = _text(data['userId']);
    if (userId.isNotEmpty) return userId;

    // IMPORTANT:
    // Do not fallback to vendor document id.
    // Owner/User ID must be the real Firebase Auth UID of the seller.
    // Wrong fallback causes users.vendorId not to link with the logged-in vendor account.
    return '';
  }

  List<QueryDocumentSnapshot> _filterVendors(List<QueryDocumentSnapshot> docs) {
    final q = searchText.toLowerCase().trim();

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final status = _text(data['status'], 'pending');
      final active = _active(data);

      if (statusFilter != 'all' && status != statusFilter) return false;
      if (activeFilter == 'active' && !active) return false;
      if (activeFilter == 'inactive' && active) return false;

      if (q.isEmpty) return true;

      final shopName = _text(data['shopName']).toLowerCase();
      final ownerName = _text(data['ownerName']).toLowerCase();
      final phone = _text(data['phone']).toLowerCase();
      final email = _text(data['email']).toLowerCase();
      final ownerId = _vendorOwnerId(doc.id, data).toLowerCase();

      return shopName.contains(q) ||
          ownerName.contains(q) ||
          phone.contains(q) ||
          email.contains(q) ||
          ownerId.contains(q) ||
          doc.id.toLowerCase().contains(q);
    }).toList();
  }

  Future<int> _countProducts(String vendorId) async {
    final snap = await db
        .collection('products')
        .where('vendorId', isEqualTo: vendorId)
        .limit(100)
        .get();

    return snap.docs.length;
  }

  Future<int> _countOrders(String vendorId, [String ownerId = '']) async {
    int total = 0;
    final seen = <String>{};

    Future<void> addDocs(QuerySnapshot<Map<String, dynamic>> snap) async {
      for (final doc in snap.docs) {
        if (seen.add(doc.id)) total++;
      }
    }

    final byVendorIds = await db
        .collection('orders')
        .where('vendorIds', arrayContains: vendorId)
        .limit(100)
        .get();
    await addDocs(byVendorIds);

    if (ownerId.isNotEmpty) {
      final byOwnerIds = await db
          .collection('orders')
          .where('vendorOwnerIds', arrayContains: ownerId)
          .limit(100)
          .get();
      await addDocs(byOwnerIds);
    }

    final byVendor = await db
        .collection('orders')
        .where('vendorId', isEqualTo: vendorId)
        .limit(100)
        .get();
    await addDocs(byVendor);

    return total;
  }

  Future<double> _vendorRevenue(String vendorId, [String ownerId = '']) async {
    final seen = <String>{};
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    Future<void> addDocs(QuerySnapshot<Map<String, dynamic>> snap) async {
      for (final doc in snap.docs) {
        if (seen.add(doc.id)) docs.add(doc);
      }
    }

    final byVendorIds = await db
        .collection('orders')
        .where('vendorIds', arrayContains: vendorId)
        .limit(100)
        .get();
    await addDocs(byVendorIds);

    if (ownerId.isNotEmpty) {
      final byOwnerIds = await db
          .collection('orders')
          .where('vendorOwnerIds', arrayContains: ownerId)
          .limit(100)
          .get();
      await addDocs(byOwnerIds);
    }

    final byVendor = await db
        .collection('orders')
        .where('vendorId', isEqualTo: vendorId)
        .limit(100)
        .get();
    await addDocs(byVendor);

    double total = 0;
    for (final doc in docs) {
      final data = doc.data();
      final items = data['items'] is List ? data['items'] as List : [];

      for (final item in items) {
        if (item is! Map) continue;
        if (_text(item['vendorId']) == vendorId) {
          final price = _toDouble(item['price']);
          final qty = _toInt(item['qty'], 1);
          total += price * qty;
        }
      }
    }

    return total;
  }

  Future<Map<String, dynamic>> _ownerInfo(String ownerId) async {
    if (ownerId.isEmpty) return {};
    final doc = await db.collection('users').doc(ownerId).get();
    return doc.data() ?? {};
  }


  Future<void> _syncVendorUser(String vendorId, Map<String, dynamic> data) async {
    if (_denyUnless(canApproveVendors || canEditVendors, 'Permission denied: vendors.approve or vendors.edit required')) return;

    final ownerId = _vendorOwnerId(vendorId, data);
    if (ownerId.isEmpty) {
      _snack('Owner/User ID missing. Edit vendor and set the seller Firebase Auth UID first.');
      return;
    }

    final status = _text(data['status'], 'pending').toLowerCase();
    final approved = status == 'approved';

    final userUpdate = <String, dynamic>{
      'sellerStatus': status,
      'vendorId': vendorId,
      'isVendor': approved,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (approved) {
      userUpdate['role'] = 'vendor';
      userUpdate['roles'] = FieldValue.arrayUnion(['user', 'vendor']);
      userUpdate['isActive'] = true;
      userUpdate['isBanned'] = false;
    } else if (status == 'rejected' || status == 'suspended') {
      userUpdate['role'] = 'user';
      userUpdate['roles'] = FieldValue.arrayRemove(['vendor']);
    }

    await db.collection('users').doc(ownerId).set(userUpdate, SetOptions(merge: true));
    _snack('Vendor user synced');
  }

  Future<void> _syncAllApprovedVendors() async {
    if (_denyUnless(canApproveVendors || canEditVendors, 'Permission denied: vendors.approve or vendors.edit required')) return;

    final ok = await _confirm(
      title: 'Sync approved vendors?',
      message: 'This will update linked user role for all approved vendors.',
      confirmText: 'Sync All',
      danger: false,
    );

    if (ok != true) return;

    try {
      final snap = await db
          .collection('vendors')
          .where('status', isEqualTo: 'approved')
          .limit(300)
          .get();

      int synced = 0;
      WriteBatch batch = db.batch();
      int batchCount = 0;

      Future<void> commitIfNeeded({bool force = false}) async {
        if (batchCount == 0) return;
        if (force || batchCount >= 450) {
          await batch.commit();
          batch = db.batch();
          batchCount = 0;
        }
      }

      for (final doc in snap.docs) {
        final data = doc.data();
        final ownerId = _vendorOwnerId(doc.id, data);
        if (ownerId.isEmpty) continue;

        batch.set(db.collection('users').doc(ownerId), {
          'role': 'vendor',
          'roles': FieldValue.arrayUnion(['user', 'vendor']),
          'sellerStatus': 'approved',
          'vendorId': doc.id,
          'isVendor': true,
          'isActive': true,
          'isBanned': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        batchCount++;
        synced++;
        await commitIfNeeded();
      }

      await commitIfNeeded(force: true);
      _snack('Synced $synced approved vendor users');
    } catch (e) {
      _snack('Sync failed: $e');
    }
  }

  Future<void> _approveVendor(String vendorId, Map<String, dynamic> data) async {
    if (_denyUnless(canApproveVendors, 'Permission denied: vendors.approve required')) return;

    final ownerId = _vendorOwnerId(vendorId, data);

    if (ownerId.isEmpty) {
      _snack('Owner/User ID missing. Edit vendor and set the seller Firebase Auth UID first.');
      return;
    }

    final ok = await _confirm(
      title: 'Approve Vendor?',
      message: 'This vendor will be activated and user role will be updated to vendor.',
      confirmText: 'Approve',
      danger: false,
    );

    if (ok != true) return;

    final batch = db.batch();

    batch.set(db.collection('vendors').doc(vendorId), {
      'ownerId': ownerId,
      'status': 'approved',
      'isActive': true,
      'isVerified': true,
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(db.collection('users').doc(ownerId), {
      'role': 'vendor',
      'roles': FieldValue.arrayUnion(['user', 'vendor']),
      'sellerStatus': 'approved',
      'vendorId': vendorId,
      'isVendor': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
    _snack('Vendor approved');
  }

  Future<void> _rejectVendor(String vendorId, Map<String, dynamic> data) async {
    if (_denyUnless(canApproveVendors, 'Permission denied: vendors.approve required')) return;

    final ownerId = _vendorOwnerId(vendorId, data);

    final ok = await _confirm(
      title: 'Reject Vendor?',
      message: 'This vendor request will be rejected.',
      confirmText: 'Reject',
      danger: true,
    );

    if (ok != true) return;

    final batch = db.batch();

    batch.set(db.collection('vendors').doc(vendorId), {
      'status': 'rejected',
      'isActive': false,
      'isVerified': false,
      'rejectedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (ownerId.isNotEmpty) {
      batch.set(db.collection('users').doc(ownerId), {
        'role': 'user',
        'roles': FieldValue.arrayRemove(['vendor']),
        'sellerStatus': 'rejected',
        'isVendor': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    _snack('Vendor rejected');
  }

  Future<void> _suspendVendor(String vendorId, Map<String, dynamic> data) async {
    if (_denyUnless(canChangeVendorStatus, 'Permission denied: vendors.status required')) return;

    final ownerId = _vendorOwnerId(vendorId, data);

    final ok = await _confirm(
      title: 'Suspend Vendor?',
      message: 'Vendor will be inactive and marketplace products may be hidden.',
      confirmText: 'Suspend',
      danger: true,
    );

    if (ok != true) return;

    final batch = db.batch();

    batch.set(db.collection('vendors').doc(vendorId), {
      'status': 'suspended',
      'isActive': false,
      'suspendedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (ownerId.isNotEmpty) {
      batch.set(db.collection('users').doc(ownerId), {
        'role': 'user',
        'roles': FieldValue.arrayRemove(['vendor']),
        'sellerStatus': 'suspended',
        'isVendor': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    _snack('Vendor suspended');
  }

  Future<void> _toggleActive(String vendorId, bool value) async {
    if (_denyUnless(canChangeVendorStatus, 'Permission denied: vendors.status required')) return;

    await db.collection('vendors').doc(vendorId).set({
      'isActive': value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _snack(value ? 'Vendor activated' : 'Vendor deactivated');
  }

  Future<void> _deleteVendor(String vendorId, Map<String, dynamic> data) async {
    if (_denyUnless(canDeleteVendors, 'Permission denied: vendors.delete required')) return;

    final productCount = await _countProducts(vendorId);
    final orderCount = await _countOrders(vendorId);

    if (productCount > 0 || orderCount > 0) {
      _snack('Cannot delete. This vendor has $productCount products and $orderCount orders.');
      return;
    }

    final ok = await _confirm(
      title: 'Delete Vendor?',
      message: 'This vendor record will be permanently deleted.',
      confirmText: 'Delete',
      danger: true,
    );

    if (ok != true) return;

    await db.collection('vendors').doc(vendorId).delete();
    _snack('Vendor deleted');
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmText,
    required bool danger,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  Future<void> _showVendorDialog({String? id, Map<String, dynamic>? data}) async {
    if (_denyUnless(canEditVendors, 'Permission denied: vendors.edit required')) return;

    final shopName = TextEditingController(text: _text(data?['shopName']));
    final ownerName = TextEditingController(text: _text(data?['ownerName']));
    final phone = TextEditingController(text: _text(data?['phone']));
    final email = TextEditingController(text: _text(data?['email']));
    final address = TextEditingController(text: _text(data?['address']));
    final businessType = TextEditingController(text: _text(data?['businessType'], 'general'));
    final ownerId = TextEditingController(text: _text(data?['ownerId'] ?? data?['userId']));
    final commission = TextEditingController(
      text: _toDouble(data?['commissionPercent'] ?? data?['commissionRate'], 10).toStringAsFixed(0),
    );
    final payoutAccount = TextEditingController(text: _text(data?['payoutAccount']));
    final tradeLicense = TextEditingController(text: _text(data?['tradeLicense']));
    final nidFront = TextEditingController(text: _text(data?['nidFront']));
    final nidBack = TextEditingController(text: _text(data?['nidBack']));
    final note = TextEditingController(text: _text(data?['note']));

    String status = _text(data?['status'], 'pending');
    bool active = data == null ? false : data['isActive'] == true;
    bool verified = data?['isVerified'] == true;
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            if (shopName.text.trim().isEmpty) {
              _snack('Shop name required');
              return;
            }
            if (phone.text.trim().isEmpty) {
              _snack('Phone required');
              return;
            }
            if (ownerId.text.trim().isEmpty) {
              _snack('Owner/User ID required. Set the seller Firebase Auth UID.');
              return;
            }

            setDialogState(() => saving = true);

            try {
              final payload = {
                'shopName': shopName.text.trim(),
                'ownerName': ownerName.text.trim(),
                'phone': phone.text.trim(),
                'email': email.text.trim(),
                'address': address.text.trim(),
                'businessType': businessType.text.trim().isEmpty ? 'general' : businessType.text.trim(),
                'ownerId': ownerId.text.trim(),
                'userId': ownerId.text.trim(),
                'commissionPercent': _toDouble(commission.text, 10),
                'commissionRate': _toDouble(commission.text, 10),
                'payoutAccount': payoutAccount.text.trim(),
                'tradeLicense': tradeLicense.text.trim(),
                'nidFront': nidFront.text.trim(),
                'nidBack': nidBack.text.trim(),
                'note': note.text.trim(),
                'status': status,
                'isActive': active,
                'isVerified': verified,
                'updatedAt': FieldValue.serverTimestamp(),
              };

              if (id == null) {
                final doc = await db.collection('vendors').add({
                  ...payload,
                  'rating': 0,
                  'totalSales': 0,
                  'totalOrders': 0,
                  'withdrawableBalance': 0,
                  'withdrawPendingBalance': 0,
                  'createdAt': FieldValue.serverTimestamp(),
                });

                if (ownerId.text.trim().isNotEmpty) {
                  await db.collection('users').doc(ownerId.text.trim()).set({
                    'vendorId': doc.id,
                    'sellerStatus': status,
                    'isVendor': status == 'approved',
                    if (status == 'approved') 'role': 'vendor',
                    if (status == 'approved') 'roles': FieldValue.arrayUnion(['user', 'vendor']),
                    if (status == 'rejected' || status == 'suspended') 'role': 'user',
                    if (status == 'rejected' || status == 'suspended') 'roles': FieldValue.arrayRemove(['vendor']),
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                }

                _snack('Vendor added');
              } else {
                await db.collection('vendors').doc(id).set(payload, SetOptions(merge: true));

                if (ownerId.text.trim().isNotEmpty) {
                  await db.collection('users').doc(ownerId.text.trim()).set({
                    'vendorId': id,
                    'sellerStatus': status,
                    'isVendor': status == 'approved',
                    if (status == 'approved') 'role': 'vendor',
                    if (status == 'approved') 'roles': FieldValue.arrayUnion(['user', 'vendor']),
                    if (status == 'rejected' || status == 'suspended') 'role': 'user',
                    if (status == 'rejected' || status == 'suspended') 'roles': FieldValue.arrayRemove(['vendor']),
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                }

                _snack('Vendor updated');
              }

              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              _snack('Save failed: $e');
            } finally {
              setDialogState(() => saving = false);
            }
          }

          return AlertDialog(
            title: Text(id == null ? 'Add Vendor' : 'Edit Vendor'),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _dialogField('Shop Name', shopName, Icons.storefront_rounded, required: true),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dialogField('Owner Name', ownerName, Icons.person_outline)),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogField('Phone', phone, Icons.call_outlined, required: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dialogField('Email', email, Icons.email_outlined)),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogField('Owner/User ID', ownerId, Icons.link_rounded, required: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dialogField('Business Type', businessType, Icons.business_center_outlined)),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogField('Commission %', commission, Icons.percent_rounded, number: true)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: ['pending', 'approved', 'rejected', 'suspended'].contains(status) ? status : 'pending',
                      decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'pending', child: Text('Pending')),
                        DropdownMenuItem(value: 'approved', child: Text('Approved')),
                        DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                        DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                      ],
                      onChanged: (v) => setDialogState(() => status = v ?? 'pending'),
                    ),
                    const SizedBox(height: 12),
                    _dialogField('Address', address, Icons.location_on_outlined, maxLines: 2),
                    const SizedBox(height: 12),
                    _dialogField('Payout Account / bKash / Bank', payoutAccount, Icons.account_balance_wallet_outlined, maxLines: 2),
                    const SizedBox(height: 12),
                    _dialogField('Trade License URL', tradeLicense, Icons.description_outlined),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dialogField('NID Front URL', nidFront, Icons.badge_outlined)),
                        const SizedBox(width: 10),
                        Expanded(child: _dialogField('NID Back URL', nidBack, Icons.badge_outlined)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _dialogField('Admin Note', note, Icons.note_alt_outlined, maxLines: 3),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: active,
                      title: const Text('Active Vendor'),
                      subtitle: const Text('Inactive vendors can be hidden from marketplace.'),
                      onChanged: (v) => setDialogState(() => active = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: verified,
                      title: const Text('Verified Vendor'),
                      subtitle: const Text('Verified vendors can get trust badge in future UI.'),
                      onChanged: (v) => setDialogState(() => verified = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton.icon(
                onPressed: saving ? null : save,
                icon: saving
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                label: Text(saving ? 'Saving...' : 'Save'),
              ),
            ],
          );
        },
      ),
    );

    shopName.dispose();
    ownerName.dispose();
    phone.dispose();
    email.dispose();
    address.dispose();
    businessType.dispose();
    ownerId.dispose();
    commission.dispose();
    payoutAccount.dispose();
    tradeLicense.dispose();
    nidFront.dispose();
    nidBack.dispose();
    note.dispose();
  }

  Widget _dialogField(
      String label,
      TextEditingController controller,
      IconData icon, {
        bool number = false,
        bool required = false,
        int maxLines = 1,
      }) {
    return TextField(
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _summaryGrid(List<QueryDocumentSnapshot> docs) {
    int approved = 0;
    int pending = 0;
    int rejected = 0;
    int suspended = 0;
    int active = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = _text(data['status'], 'pending');

      if (status == 'approved') approved++;
      if (status == 'pending') pending++;
      if (status == 'rejected') rejected++;
      if (status == 'suspended') suspended++;
      if (data['isActive'] == true) active++;
    }

    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth >= 1000 ? 5 : c.maxWidth >= 650 ? 3 : 2;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: count,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: count == 2 ? 1.7 : 2.05,
          children: [
            _summaryCard('Approved', '$approved', Icons.verified_rounded, Colors.green),
            _summaryCard('Pending', '$pending', Icons.pending_actions_rounded, Colors.orange),
            _summaryCard('Active', '$active', Icons.storefront_rounded, Colors.blue),
            _summaryCard('Rejected', '$rejected', Icons.cancel_rounded, Colors.red),
            _summaryCard('Suspended', '$suspended', Icons.pause_circle_rounded, Colors.deepOrange),
          ],
        );
      },
    );
  }

  Future<void> _openUrl(String url) async {
    if (_denyUnless(canViewVendorDocuments, 'Permission denied: vendors.documents required')) return;
    final link = url.trim();
    if (link.isEmpty) return;

    final uri = Uri.tryParse(link);
    if (uri == null) {
      _snack('Invalid document URL');
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _snack('Could not open document');
  }

  Widget _docButton(String title, String url, IconData icon) {
    final hasUrl = url.trim().isNotEmpty;

    return OutlinedButton.icon(
      onPressed: hasUrl ? () => _openUrl(url) : null,
      icon: Icon(icon, size: 18),
      label: Text(title),
      style: OutlinedButton.styleFrom(
        foregroundColor: hasUrl ? const Color(0xFF2563EB) : Colors.grey,
        side: BorderSide(color: hasUrl ? const Color(0xFFBFDBFE) : Colors.grey.shade300),
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(title, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, c) {
            final compact = c.maxWidth < 900;

            final search = TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText: 'Search shop, owner, phone, email, vendor id...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => searchText = v),
            );

            final status = DropdownButtonFormField<String>(
              initialValue: statusFilter,
              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'approved', child: Text('Approved')),
                DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
              ],
              onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
            );

            final active = DropdownButtonFormField<String>(
              initialValue: activeFilter,
              decoration: const InputDecoration(labelText: 'Active', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
              onChanged: (v) => setState(() => activeFilter = v ?? 'all'),
            );

            if (compact) {
              return Column(
                children: [
                  search,
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: status),
                      const SizedBox(width: 8),
                      Expanded(child: active),
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 2, child: search),
                const SizedBox(width: 8),
                Expanded(child: status),
                const SizedBox(width: 8),
                Expanded(child: active),
              ],
            );
          },
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    if (status == 'approved') return Colors.green;
    if (status == 'rejected') return Colors.red;
    if (status == 'suspended') return Colors.deepOrange;
    return Colors.orange;
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _vendorCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final vendorId = doc.id;
    final ownerId = _vendorOwnerId(vendorId, data);
    final shopName = _text(data['shopName'], 'Unnamed Shop');
    final ownerName = _text(data['ownerName'], 'No owner name');
    final phone = _text(data['phone'], 'No phone');
    final email = _text(data['email'], 'No email');
    final status = _text(data['status'], 'pending');
    final active = data['isActive'] == true;
    final verified = data['isVerified'] == true;
    final commission = _toDouble(data['commissionPercent'] ?? data['commissionRate'], 10);

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _ownerInfo(ownerId),
        _countProducts(vendorId),
        _countOrders(vendorId, ownerId),
        _vendorRevenue(vendorId, ownerId),
      ]),
      builder: (context, snap) {
        final owner = snap.data != null && snap.data!.isNotEmpty ? snap.data![0] as Map<String, dynamic> : {};
        final productCount = snap.data != null && snap.data!.length > 1 ? snap.data![1] as int : 0;
        final orderCount = snap.data != null && snap.data!.length > 2 ? snap.data![2] as int : 0;
        final revenue = snap.data != null && snap.data!.length > 3 ? snap.data![3] as double : 0.0;

        return Card(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 900;

                final avatar = CircleAvatar(
                  radius: 30,
                  backgroundColor: _statusColor(status).withValues(alpha: 0.12),
                  child: Icon(Icons.storefront_rounded, color: _statusColor(status), size: 30),
                );

                final info = Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shopName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('$ownerName • $phone', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700)),
                      const SizedBox(height: 2),
                      Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      if (_text(owner['name']).isNotEmpty)
                        Text('Linked user: ${_text(owner['name'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _chip(status.toUpperCase(), _statusColor(status)),
                          _chip(active ? 'Active' : 'Inactive', active ? Colors.green : Colors.red),
                          if (verified) _chip('Verified', Colors.deepPurple),
                          _chip('Commission ${commission.toStringAsFixed(0)}%', Colors.blue),
                          _chip('$productCount Products', Colors.teal),
                          _chip('$orderCount Orders', Colors.orange),
                          _chip('৳${revenue.toStringAsFixed(0)} Sales', Colors.green),
                          _chip('Created ${_dateText(data['createdAt'])}', Colors.blueGrey),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (canViewVendorDocuments) ...[
                            _docButton('Trade License', _text(data['tradeLicense']), Icons.description_outlined),
                            _docButton('NID Front', _text(data['nidFront']), Icons.badge_outlined),
                            _docButton('NID Back', _text(data['nidBack']), Icons.badge_outlined),
                          ],
                        ],
                      ),
                    ],
                  ),
                );

                final actions = Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    if (canApproveVendors || canEditVendors)
                      OutlinedButton.icon(
                        onPressed: () => _syncVendorUser(vendorId, data),
                        icon: const Icon(Icons.sync_rounded, size: 18, color: Colors.blue),
                        label: const Text('Sync User', style: TextStyle(color: Colors.blue)),
                      ),
                    if (canApproveVendors && status != 'approved')
                      OutlinedButton.icon(
                        onPressed: () => _approveVendor(vendorId, data),
                        icon: const Icon(Icons.check_circle_rounded, size: 18, color: Colors.green),
                        label: const Text('Approve', style: TextStyle(color: Colors.green)),
                      ),
                    if (canApproveVendors && status != 'rejected')
                      OutlinedButton.icon(
                        onPressed: () => _rejectVendor(vendorId, data),
                        icon: const Icon(Icons.cancel_rounded, size: 18, color: Colors.red),
                        label: const Text('Reject', style: TextStyle(color: Colors.red)),
                      ),
                    if (canChangeVendorStatus && status != 'suspended')
                      OutlinedButton.icon(
                        onPressed: () => _suspendVendor(vendorId, data),
                        icon: const Icon(Icons.pause_circle_rounded, size: 18, color: Colors.deepOrange),
                        label: const Text('Suspend', style: TextStyle(color: Colors.deepOrange)),
                      ),
                    if (canEditVendors)
                      OutlinedButton.icon(
                        onPressed: () => _showVendorDialog(id: vendorId, data: data),
                        icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.orange),
                        label: const Text('Edit', style: TextStyle(color: Colors.orange)),
                      ),
                    if (canChangeVendorStatus)
                      Switch(
                        value: active,
                        onChanged: (v) => _toggleActive(vendorId, v),
                      ),
                    if (canDeleteVendors)
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _deleteVendor(vendorId, data),
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                      ),
                  ],
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [avatar, const SizedBox(width: 12), info]),
                      const Divider(height: 22),
                      actions,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(width: 14),
                    info,
                    const SizedBox(width: 12),
                    SizedBox(width: 420, child: actions),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _vendorList() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('vendors').orderBy('createdAt', descending: true).limit(300).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()));
        }

        if (snap.hasError) {
          return Center(child: Text('Vendors load failed: ${snap.error}'));
        }

        final docs = snap.data?.docs ?? [];
        final vendors = _filterVendors(docs);

        if (docs.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('No vendors found')));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryGrid(docs),
            const SizedBox(height: 14),
            _filters(),
            const SizedBox(height: 12),
            Text(
              'Vendors (${vendors.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (vendors.isEmpty)
              const Card(
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: Text('No matching vendors')),
                ),
              )
            else
              ...vendors.map(_vendorCard),
          ],
        );
      },
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (permissionLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FA),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!canViewVendors) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, size: 54, color: Colors.red.shade400),
                const SizedBox(height: 12),
                const Text(
                  'Vendor access denied',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text('Required permission: vendors.view'),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isMobile = constraints.maxWidth < 600;

          final title = const Text(
            'Vendor Manager Pro',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          );

          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: isMobile ? WrapAlignment.start : WrapAlignment.end,
            children: [
              if (canApproveVendors || canEditVendors)
                OutlinedButton.icon(
                  onPressed: _syncAllApprovedVendors,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Sync All'),
                ),
              if (canEditVendors)
                ElevatedButton.icon(
                  onPressed: () => _showVendorDialog(),
                  icon: const Icon(Icons.add_business_rounded, size: 18),
                  label: const Text('Add Vendor'),
                ),
            ],
          );

          return ListView(
            padding: EdgeInsets.all(isMobile ? 14 : 18),
            children: [
              if (isMobile) ...[
                title,
                const SizedBox(height: 10),
                actions,
              ] else
                Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    actions,
                  ],
                ),
              const SizedBox(height: 14),
              _vendorList(),
            ],
          );
        },
      ),
    );
  }
}
