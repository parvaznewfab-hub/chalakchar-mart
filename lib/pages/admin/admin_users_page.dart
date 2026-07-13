import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();
  final TextEditingController searchController = TextEditingController();

  bool permissionLoading = true;
  bool isSuperAdminViewer = false;
  bool canViewUsers = false;
  bool canEditUsers = false;
  bool canEditPermissions = false;
  bool canBlockUsers = false;
  bool canEditWallet = false;
  String? currentViewerUid;

  String searchText = '';
  String roleFilter = 'all';
  String statusFilter = 'all';

  static const List<String> roleOptions = [
    'user',
    'staff',
    'admin',
    'superAdmin',
    'vendor',
    'deliveryPartner',
  ];

  static const List<String> permissionOptions = [
    'dashboard.view',
    'analytics.view',
    'orders.view',
    'orders.edit',
    'orders.assign_rider',
    'orders.invoice',
    'orders.settle_cod',
    'orders.discount',
    'orders.confirm',
    'products.view',
    'products.edit',
    'products.delete',
    'products.bulk',
    'products.status',
    'vendor_products.view',
    'vendor_products.edit',
    'vendor_products.approve',
    'vendor_products.delete',
    'vendor_products.status',
    'categories.view',
    'categories.edit',
    'categories.delete',
    'categories.status',
    'banners.view',
    'banners.edit',
    'banners.delete',
    'banners.status',
    'banners.priority',
    'coupons.view',
    'coupons.edit',
    'coupons.delete',
    'coupons.status',
    'lists.view',
    'lists.edit',
    'doctors.view',
    'doctors.edit',
    'appointments.view',
    'appointments.edit',
    'users.view',
    'users.edit',
    'users.permissions',
    'users.block',
    'wallet.edit',
    'vendors.view',
    'vendors.edit',
    'vendors.approve',
    'vendors.delete',
    'vendors.status',
    'vendors.documents',
    'vendors.contact',
    'vendors.payouts',
    'delivery.view',
    'delivery.approve',
    'delivery.block',
    'delivery.withdraw',
    'delivery.settle_cod',
    'delivery.documents',
    'delivery.contact',
    'referrals.view',
    'referrals.edit',
    'settings.view',
    'settings.edit',
    'notifications.view',
    'notifications.send',
    'notifications.manage',
    'notifications.delete',
    'notifications.open_related',
  ];

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final data = await authService.currentUserData();
      final role = _text(data?['role'], 'user');
      final roles = List<String>.from(data?['roles'] ?? []);

      final superAccess = role == 'superAdmin' || roles.contains('superAdmin');
      final rawPermissions = data?['permissions'];
      final permissions = rawPermissions is List
          ? List<String>.from(rawPermissions)
          : <String>[];

      bool has(String permission) {
        if (superAccess) return true;
        return permissions.contains(permission);
      }

      if (!mounted) return;
      setState(() {
        isSuperAdminViewer = superAccess;
        currentViewerUid = authService.currentUid;
        canViewUsers = has('users.view');
        // User role/permission/wallet/block are critical actions.
        // Only Super Admin should get these automatically.
        // Normal Admin/Staff need explicit permissions in Firestore.
        canEditUsers = has('users.edit');
        canEditPermissions = has('users.permissions');
        canBlockUsers = has('users.block');
        canEditWallet = has('wallet.edit');
        permissionLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => permissionLoading = false);
      _snack('Permission load failed: $e');
    }
  }

  bool _targetIsSuperAdmin(Map<String, dynamic> data) {
    final roles = _roles(data);
    return _text(data['role']) == 'superAdmin' || roles.contains('superAdmin');
  }

  bool _isSelf(String uid) => currentViewerUid == uid;

  bool _isDangerousPermission(String permission) {
    return {
      'users.permissions',
      'users.block',
      'wallet.edit',
      'settings.edit',
      'vendors.delete',
      'vendors.payouts',
      'delivery.withdraw',
      'delivery.settle_cod',
    }.contains(permission);
  }

  bool _canModifyTarget(String uid, Map<String, dynamic> data,
      {bool permissionAction = false}) {
    if (_isSelf(uid)) {
      _snack(
          'For safety, you cannot modify your own role, permissions, block status, or wallet.');
      return false;
    }

    if (_targetIsSuperAdmin(data) && !isSuperAdminViewer) {
      _snack('Only Super Admin can modify a Super Admin account.');
      return false;
    }

    if (permissionAction && !canEditPermissions) {
      _snack('You do not have users.permissions access.');
      return false;
    }

    if (!permissionAction && !canEditUsers) {
      _snack('You do not have users.edit access.');
      return false;
    }

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

  List<String> _roles(Map<String, dynamic> data) {
    final roles = <String>[];

    final rawRoles = data['roles'];
    if (rawRoles is List) {
      for (final r in rawRoles) {
        final role = _text(r);
        if (role.isNotEmpty && !roles.contains(role)) roles.add(role);
      }
    }

    final primary = _text(data['role'], 'user');
    if (primary.isNotEmpty && !roles.contains(primary)) {
      roles.insert(0, primary);
    }

    if (roles.isEmpty) roles.add('user');
    return roles;
  }

  bool _isActive(Map<String, dynamic> data) {
    return data['isActive'] != false && data['isBanned'] != true;
  }

  Future<void> _setPrimaryRole(
      String uid, String role, Map<String, dynamic> data) async {
    if (!_canModifyTarget(uid, data)) return;
    if (role == 'superAdmin' && !isSuperAdminViewer) {
      _snack('Only Super Admin can assign Super Admin role.');
      return;
    }

    final cleanRoles = <String>[];

    if (role == 'superAdmin') {
      cleanRoles.addAll(['user', 'admin', 'superAdmin']);
    } else if (role == 'admin') {
      cleanRoles.addAll(['user', 'admin']);
    } else if (role == 'staff') {
      cleanRoles.addAll(['user', 'staff']);
    } else if (role == 'vendor') {
      cleanRoles.addAll(['user', 'vendor']);
    } else if (role == 'deliveryPartner') {
      cleanRoles.addAll(['user', 'deliveryPartner']);
    } else {
      cleanRoles.add('user');
    }

    await db.collection('users').doc(uid).update({
      'role': role,
      'roles': cleanRoles,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    _snack('Primary role updated to $role');
  }

  Future<void> _toggleRole(
      String uid, String role, bool add, Map<String, dynamic> data) async {
    if (!_canModifyTarget(uid, data)) return;
    if (role == 'superAdmin' && !isSuperAdminViewer) {
      _snack('Only Super Admin can change Super Admin role.');
      return;
    }

    final currentPrimary = _text(data['role'], 'user');

    if (!add && role == currentPrimary) {
      _snack('Primary role cannot be removed. Change primary role first.');
      return;
    }

    await db.collection('users').doc(uid).set({
      'roles':
          add ? FieldValue.arrayUnion([role]) : FieldValue.arrayRemove([role]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _snack(add ? '$role role added' : '$role role removed');
  }

  Future<void> _toggleBlock(String uid, Map<String, dynamic> data) async {
    if (_isSelf(uid)) {
      _snack('For safety, you cannot block your own account.');
      return;
    }

    if (!canBlockUsers) {
      _snack('You do not have users.block access.');
      return;
    }
    if (_targetIsSuperAdmin(data) && !isSuperAdminViewer) {
      _snack('Only Super Admin can block/unblock Super Admin account.');
      return;
    }

    final banned = data['isBanned'] == true || data['isActive'] == false;

    if (banned) {
      await db.collection('users').doc(uid).set({
        'isActive': true,
        'isBanned': false,
        'banReason': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _snack('User unblocked');
      return;
    }

    final reasonController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Block User?'),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await db.collection('users').doc(uid).set({
        'isActive': false,
        'isBanned': true,
        'banReason': reasonController.text.trim(),
        'bannedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _snack('User blocked');
    }
  }

  Future<void> _adjustPoints(String uid, Map<String, dynamic> data) async {
    if (_isSelf(uid)) {
      _snack('For safety, you cannot adjust your own wallet.');
      return;
    }

    if (!canEditWallet) {
      _snack('You do not have wallet.edit access.');
      return;
    }
    if (_targetIsSuperAdmin(data) && !isSuperAdminViewer) {
      _snack('Only Super Admin can adjust Super Admin wallet.');
      return;
    }

    final pointsController = TextEditingController();
    final noteController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
            'Adjust ChalakChar Mart Cash / Points for ${_text(data['name'], 'User')}'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pointsController,
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true),
                decoration: const InputDecoration(
                  labelText: 'Amount (+ add / - remove)',
                  hintText: 'Example: 50 or -20',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (ok != true) return;

    final amount = int.tryParse(pointsController.text.trim()) ?? 0;
    if (amount == 0) {
      _snack('Amount cannot be zero');
      return;
    }

    final batch = db.batch();
    final userRef = db.collection('users').doc(uid);

    batch.set(
        userRef,
        {
          'points': FieldValue.increment(amount),
          if (amount > 0) 'totalEarnings': FieldValue.increment(amount),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    batch.set(db.collection('wallet_logs').doc(), {
      'userId': uid,
      'amount': amount,
      'type': amount > 0 ? 'admin_add' : 'admin_remove',
      'note': noteController.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    _snack('Points updated');
  }

  Future<void> _showPermissionsDialog(
      String uid, Map<String, dynamic> data) async {
    if (!_canModifyTarget(uid, data, permissionAction: true)) return;

    final roles = _roles(data);

    if (!roles.contains('staff') &&
        !roles.contains('admin') &&
        !roles.contains('superAdmin')) {
      _snack('Permission can be edited only for staff/admin users.');
      return;
    }

    List<String> selected = List<String>.from(data['permissions'] ?? []);

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('User Permissions'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: permissionOptions.map((p) {
                    return CheckboxListTile(
                      dense: true,
                      value: selected.contains(p),
                      title: Text(p),
                      onChanged: (v) {
                        setDialogState(() {
                          if (v == true) {
                            if (!selected.contains(p)) selected.add(p);
                          } else {
                            selected.remove(p);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (!isSuperAdminViewer) {
                    selected.removeWhere(_isDangerousPermission);
                  }

                  await db.collection('users').doc(uid).set({
                    'permissions': selected,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));

                  if (context.mounted) Navigator.pop(context);
                  _snack('Permissions updated');
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showUserDetails(String uid, Map<String, dynamic> data) async {
    final roles = _roles(data);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_text(data['name'], 'User Details')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('UID', uid),
                _detailRow('Name', _text(data['name'], 'N/A')),
                _detailRow('Email', _text(data['email'], 'N/A')),
                _detailRow('Phone', _text(data['phone'], 'N/A')),
                _detailRow('Primary Role', _text(data['role'], 'user')),
                _detailRow('All Roles', _roles(data).join(', ')),
                _detailRow('Points', _toInt(data['points']).toString()),
                _detailRow(
                    'Total Earnings', _toInt(data['totalEarnings']).toString()),
                _detailRow(
                    'Referral Count', _toInt(data['referralCount']).toString()),
                _detailRow(
                    'Seller Status', _text(data['sellerStatus'], 'none')),
                _detailRow('Delivery Partner',
                    roles.contains('deliveryPartner') ? 'Yes' : 'No'),
                _detailRow('Vendor ID', _text(data['vendorId'], 'N/A')),
                _detailRow('Active', _isActive(data) ? 'Yes' : 'No'),
                _detailRow('Banned', data['isBanned'] == true ? 'Yes' : 'No'),
                _detailRow('Created', _dateText(data['createdAt'])),
                _detailRow('Last Login', _dateText(data['lastLoginAt'])),
                _detailRow('Address', _text(data['address'], 'N/A')),
                _detailRow(
                  'Area',
                  '${_text(data['division'], '-')} / ${_text(data['district'], '-')} / ${_text(data['upazila'], '-')}',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _detailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 125,
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w900))),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  List<QueryDocumentSnapshot> _filterUsers(List<QueryDocumentSnapshot> docs) {
    final s = searchText.toLowerCase().trim();

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final roles = _roles(data);
      final active = _isActive(data);

      if (roleFilter != 'all' && !roles.contains(roleFilter)) return false;
      if (statusFilter == 'active' && !active) return false;
      if (statusFilter == 'blocked' && active) return false;
      if (statusFilter == 'vendorPending' && data['sellerStatus'] != 'pending') {
        return false;
      }

      if (s.isEmpty) return true;

      final name = _text(data['name']).toLowerCase();
      final email = _text(data['email']).toLowerCase();
      final phone = _text(data['phone']).toLowerCase();
      final uid = doc.id.toLowerCase();

      return name.contains(s) ||
          email.contains(s) ||
          phone.contains(s) ||
          uid.contains(s);
    }).toList();
  }

  Widget _summaryGrid(List<QueryDocumentSnapshot> docs) {
    int users = 0;
    int admins = 0;
    int staff = 0;
    int vendors = 0;
    int blocked = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final roles = _roles(data);

      if (roles.contains('user')) users++;
      if (roles.contains('admin') || roles.contains('superAdmin')) admins++;
      if (roles.contains('staff')) staff++;
      if (roles.contains('vendor') || data['sellerStatus'] == 'approved') {
        vendors++;
      }
      if (!_isActive(data)) blocked++;
    }

    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth >= 1000
            ? 5
            : c.maxWidth >= 650
                ? 3
                : 2;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: count,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: count == 2 ? 1.7 : 2.05,
          children: [
            _summaryCard(
                'Users', '$users', Icons.people_alt_rounded, Colors.blue),
            _summaryCard('Admins', '$admins',
                Icons.admin_panel_settings_rounded, Colors.deepPurple),
            _summaryCard('Staff', '$staff', Icons.badge_rounded, Colors.teal),
            _summaryCard(
                'Vendors', '$vendors', Icons.storefront_rounded, Colors.orange),
            _summaryCard(
                'Blocked', '$blocked', Icons.block_rounded, Colors.red),
          ],
        );
      },
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
                Text(value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900)),
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
            final small = c.maxWidth < 900;

            final search = TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText: 'Search name, email, phone, uid...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => searchText = v),
            );

            final role = DropdownButtonFormField<String>(
              initialValue: roleFilter,
              decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Roles')),
                DropdownMenuItem(value: 'user', child: Text('User')),
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(
                    value: 'superAdmin', child: Text('Super Admin')),
                DropdownMenuItem(value: 'vendor', child: Text('Vendor')),
                DropdownMenuItem(
                    value: 'deliveryPartner', child: Text('Delivery Partner')),
              ],
              onChanged: (v) => setState(() => roleFilter = v ?? 'all'),
            );

            final status = DropdownButtonFormField<String>(
              initialValue: statusFilter,
              decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                DropdownMenuItem(
                    value: 'vendorPending', child: Text('Vendor Pending')),
              ],
              onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
            );

            if (small) {
              return Column(
                children: [
                  search,
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: role),
                      const SizedBox(width: 8),
                      Expanded(child: status),
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 2, child: search),
                const SizedBox(width: 8),
                Expanded(child: role),
                const SizedBox(width: 8),
                Expanded(child: status),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _roleChip(String role) {
    Color color = Colors.blueGrey;
    if (role == 'superAdmin') color = Colors.deepPurple;
    if (role == 'admin') color = Colors.indigo;
    if (role == 'staff') color = Colors.teal;
    if (role == 'vendor') color = Colors.orange;
    if (role == 'deliveryPartner') color = Colors.teal;
    if (role == 'user') color = Colors.blue;
    return _chip(role, color);
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _userCard(String uid, Map<String, dynamic> data) {
    final name = _text(data['name'], 'Unknown User');
    final email = _text(data['email']);
    final phone = _text(data['phone']);
    final active = _isActive(data);
    final roles = _roles(data);
    final primaryRole = _text(data['role'], 'user');

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
              radius: 28,
              backgroundColor: active
                  ? const Color(0xFFEAF6FA)
                  : Colors.red.withValues(alpha: 0.12),
              backgroundImage: _text(data['photoUrl']).isNotEmpty
                  ? NetworkImage(_text(data['photoUrl']))
                  : null,
              child: _text(data['photoUrl']).isEmpty
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: active ? const Color(0xFF1592B3) : Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    )
                  : null,
            );

            final info = Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  if (email.isNotEmpty)
                    Text(email, style: TextStyle(color: Colors.grey.shade700)),
                  if (phone.isNotEmpty)
                    Text(phone, style: TextStyle(color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ...roles.map(_roleChip),
                      _chip(active ? 'Active' : 'Blocked',
                          active ? Colors.green : Colors.red),
                      _chip('Seller: ${_text(data['sellerStatus'], 'none')}',
                          Colors.orange),
                      _chip('Points ${_toInt(data['points'])}', Colors.blue),
                    ],
                  ),
                ],
              ),
            );

            final roleSelector = SizedBox(
              width: compact ? double.infinity : 180,
              child: DropdownButtonFormField<String>(
                initialValue:
                    roleOptions.contains(primaryRole) ? primaryRole : 'user',
                decoration: const InputDecoration(
                  labelText: 'Primary Role',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: roleOptions
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: canEditUsers && !_isSelf(uid)
                    ? (v) {
                        if (v != null) _setPrimaryRole(uid, v, data);
                      }
                    : null,
              ),
            );

            final actions = Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showUserDetails(uid, data),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('View'),
                ),
                if (canEditWallet && !_isSelf(uid))
                  OutlinedButton.icon(
                    onPressed: () => _adjustPoints(uid, data),
                    icon: const Icon(Icons.account_balance_wallet_rounded,
                        size: 18),
                    label: const Text('Points'),
                  ),
                if (canEditPermissions && !_isSelf(uid))
                  OutlinedButton.icon(
                    onPressed: () => _showPermissionsDialog(uid, data),
                    icon: const Icon(Icons.security_rounded, size: 18),
                    label: const Text('Permissions'),
                  ),
                if (canBlockUsers && !_isSelf(uid))
                  OutlinedButton.icon(
                    onPressed: () => _toggleBlock(uid, data),
                    icon: Icon(
                        active ? Icons.block_rounded : Icons.lock_open_rounded,
                        size: 18),
                    label: Text(active ? 'Block' : 'Unblock'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: active ? Colors.red : Colors.green),
                  ),
                if (canEditUsers && !_isSelf(uid))
                  PopupMenuButton<String>(
                    tooltip: 'More roles',
                    onSelected: (value) {
                      final parts = value.split(':');
                      if (parts.length == 2) {
                        _toggleRole(uid, parts[1], parts[0] == 'add', data);
                      }
                    },
                    itemBuilder: (_) {
                      return roleOptions.map((r) {
                        final has = roles.contains(r);
                        return PopupMenuItem(
                          value: '${has ? 'remove' : 'add'}:$r',
                          child: Text('${has ? 'Remove' : 'Add'} $r'),
                        );
                      }).toList();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.more_horiz_rounded),
                    ),
                  ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [avatar, const SizedBox(width: 12), info]),
                  const SizedBox(height: 12),
                  roleSelector,
                  const SizedBox(height: 10),
                  actions,
                ],
              );
            }

            return Row(
              children: [
                avatar,
                const SizedBox(width: 14),
                info,
                const SizedBox(width: 12),
                roleSelector,
                const SizedBox(width: 12),
                SizedBox(width: 420, child: actions),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _usersList() {
    if (permissionLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!canViewUsers) {
      return _accessDenied();
    }

    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('users')
          .orderBy('createdAt', descending: true)
          .limit(500)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final allDocs = snapshot.data!.docs;
        final users = _filterUsers(allDocs);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryGrid(allDocs),
            const SizedBox(height: 14),
            _filters(),
            const SizedBox(height: 12),
            Text(
              'Users (${users.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (users.isEmpty)
              const Card(
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: Text('No matching users')),
                ),
              )
            else
              ...users.map((doc) {
                return _userCard(doc.id, doc.data() as Map<String, dynamic>);
              }),
          ],
        );
      },
    );
  }

  Widget _accessDenied() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.lock_outline_rounded,
                size: 42, color: Colors.red.shade400),
            const SizedBox(height: 12),
            const Text(
              'Access Denied',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'You need users.view permission to access this page.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Admin Users Pro • Permission Secured',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          _usersList(),
        ],
      ),
    );
  }
}
