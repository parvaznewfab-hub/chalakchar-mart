import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';

class ManageCouponsPage extends StatefulWidget {
  const ManageCouponsPage({super.key});

  @override
  State<ManageCouponsPage> createState() => _ManageCouponsPageState();
}

class _ManageCouponsPageState extends State<ManageCouponsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();

  bool permissionLoading = true;
  bool canView = false;
  bool canEdit = false;
  bool canDelete = false;
  bool canStatus = false;


  final formKey = GlobalKey<FormState>();

  final codeController = TextEditingController();
  final valueController = TextEditingController();
  final minController = TextEditingController();
  final maxController = TextEditingController();
  final usageLimitController = TextEditingController(text: '0');
  final perUserLimitController = TextEditingController(text: '1');
  final searchController = TextEditingController();

  String type = 'percent';
  String filter = 'all';
  String searchText = '';

  bool isActive = true;
  bool saving = false;

  DateTime expiryDate = DateTime.now().add(const Duration(days: 7));

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final results = await Future.wait([
        authService.hasPermission('coupons.view'),
        authService.hasPermission('coupons.edit'),
        authService.hasPermission('coupons.delete'),
        authService.hasPermission('coupons.status'),
      ]);

      if (!mounted) return;

      setState(() {
        canView = results[0];
        canEdit = results[1];
        canDelete = results[2];
        canStatus = results[3];
        permissionLoading = false;
      });

      if (canStatus || canEdit) {
        await _disableExpiredCoupons();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => permissionLoading = false);
      _snack('Permission load failed: $e');
    }
  }

  @override
  void dispose() {
    codeController.dispose();
    valueController.dispose();
    minController.dispose();
    maxController.dispose();
    usageLimitController.dispose();
    perUserLimitController.dispose();
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

  String _dateText(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
  }

  DateTime? _expiryDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  bool _isExpired(Map<String, dynamic> data) {
    final expiry = _expiryDate(data['expiry']);
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry);
  }

  void _deny([String message = 'You do not have permission for this action']) {
    _snack(message);
  }

  Widget _noAccessPage() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.all(22),
          constraints: const BoxConstraints(maxWidth: 440),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 46, color: Colors.red),
              SizedBox(height: 12),
              Text(
                'Coupon access denied',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 8),
              Text(
                'You need coupons.view permission to open this page.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _disableExpiredCoupons() async {
    try {
      final snap = await db.collection('coupons').where('isActive', isEqualTo: true).get();
      final batch = db.batch();

      for (final doc in snap.docs) {
        final data = doc.data();
        if (_isExpired(data)) {
          batch.update(doc.reference, {
            'isActive': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error disabling coupons: $e');
    }
  }

  void _generateRandomCode() {
    if (!canEdit) {
      _deny('You need coupons.edit permission.');
      return;
    }
    final random = Random();
    final number = 100000 + random.nextInt(900000);
    setState(() => codeController.text = 'SAVE$number');
  }

  String? _number(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Required';
    if (double.tryParse(text) == null) return 'Enter valid number';
    return null;
  }

  String? _couponCodeValidator(String? value) {
    final code = (value ?? '').trim();
    if (code.isEmpty) return 'Required';
    if (!RegExp(r'^[A-Z0-9_-]+$').hasMatch(code.toUpperCase())) {
      return 'Use only A-Z, 0-9, _ or -';
    }
    return null;
  }

  bool _validateBusinessRules() {
    final value = _toDouble(valueController.text);
    final min = _toDouble(minController.text);
    final max = _toDouble(maxController.text);

    if (value <= 0) {
      _snack('Discount value must be greater than 0');
      return false;
    }

    if (type == 'percent' && value > 100) {
      _snack('Percent discount cannot be more than 100%');
      return false;
    }

    if (min < 0 || max < 0) {
      _snack('Amount cannot be negative');
      return false;
    }

    if (type == 'flat' && max > 0 && value > max) {
      _snack('Flat discount value should not be greater than max discount');
      return false;
    }

    if (expiryDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      _snack('Expiry date cannot be in the past');
      return false;
    }

    return true;
  }

  Future<void> _pickExpiryDate({DateTime? initial}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? expiryDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );

    if (picked != null) {
      setState(() => expiryDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59));
    }
  }

  Future<void> _createCoupon() async {
    if (!canEdit) {
      _deny('You need coupons.edit permission.');
      return;
    }

    if (!formKey.currentState!.validate()) return;
    if (!_validateBusinessRules()) return;

    final code = codeController.text.trim().toUpperCase();

    setState(() => saving = true);

    try {
      final existing = await db.collection('coupons').doc(code).get();
      if (existing.exists) {
        _snack('Coupon code already exists');
        return;
      }

      await db.collection('coupons').doc(code).set({
        'code': code,
        'type': type,
        'value': _toDouble(valueController.text),
        'minAmount': _toDouble(minController.text),
        'maxDiscount': _toDouble(maxController.text),
        'usageLimit': _toInt(usageLimitController.text),
        'usedCount': 0,
        'perUserLimit': _toInt(perUserLimitController.text, 1),
        'isActive': isActive,
        'expiry': Timestamp.fromDate(expiryDate),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _clearForm();
      _snack('Coupon created successfully');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _clearForm() {
    codeController.clear();
    valueController.clear();
    minController.clear();
    maxController.clear();
    usageLimitController.text = '0';
    perUserLimitController.text = '1';

    setState(() {
      type = 'percent';
      isActive = true;
      expiryDate = DateTime.now().add(const Duration(days: 7));
    });
  }

  Future<void> _showEditDialog(String id, Map<String, dynamic> data) async {
    if (!canEdit) {
      _deny('You need coupons.edit permission.');
      return;
    }

    final code = TextEditingController(text: _text(data['code'], id));
    final value = TextEditingController(text: _toDouble(data['value']).toStringAsFixed(0));
    final min = TextEditingController(text: _toDouble(data['minAmount']).toStringAsFixed(0));
    final max = TextEditingController(text: _toDouble(data['maxDiscount']).toStringAsFixed(0));
    final usageLimit = TextEditingController(text: _toInt(data['usageLimit']).toString());
    final usedCount = TextEditingController(text: _toInt(data['usedCount']).toString());
    final perUserLimit = TextEditingController(text: _toInt(data['perUserLimit'], 1).toString());

    String editType = _text(data['type'], 'percent');
    bool editActive = data['isActive'] == true;
    DateTime editExpiry = _expiryDate(data['expiry']) ?? DateTime.now().add(const Duration(days: 7));

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool validateEditRules() {
            final v = _toDouble(value.text);
            final maxDiscount = _toDouble(max.text);
            if (v <= 0) {
              _snack('Discount value must be greater than 0');
              return false;
            }
            if (editType == 'percent' && v > 100) {
              _snack('Percent discount cannot be more than 100%');
              return false;
            }
            if (editType == 'flat' && maxDiscount > 0 && v > maxDiscount) {
              _snack('Flat discount should not exceed max discount');
              return false;
            }
            return true;
          }

          Future<void> pickEditDate() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: editExpiry,
              firstDate: DateTime.now().subtract(const Duration(days: 3650)),
              lastDate: DateTime.now().add(const Duration(days: 3650)),
            );

            if (picked != null) {
              setDialogState(() {
                editExpiry = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
              });
            }
          }

          Future<void> saveEdit() async {
            if (code.text.trim().isEmpty) {
              _snack('Coupon code required');
              return;
            }

            if (!validateEditRules()) return;

            await db.collection('coupons').doc(id).update({
              'code': code.text.trim().toUpperCase(),
              'type': editType,
              'value': _toDouble(value.text),
              'minAmount': _toDouble(min.text),
              'maxDiscount': _toDouble(max.text),
              'usageLimit': _toInt(usageLimit.text),
              'usedCount': _toInt(usedCount.text),
              'perUserLimit': _toInt(perUserLimit.text, 1),
              'isActive': editActive,
              'expiry': Timestamp.fromDate(editExpiry),
              'updatedAt': FieldValue.serverTimestamp(),
            });

            if (context.mounted) Navigator.pop(context);
            _snack('Coupon updated');
          }

          return AlertDialog(
            title: const Text('Edit Coupon'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Coupon Code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: editType,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'percent', child: Text('Percent (%)')),
                        DropdownMenuItem(value: 'flat', child: Text('Flat (৳)')),
                      ],
                      onChanged: (v) => setDialogState(() => editType = v ?? 'percent'),
                    ),
                    const SizedBox(height: 10),
                    _dialogGrid([
                      _dialogField('Discount Value', value),
                      _dialogField('Min Order', min),
                      _dialogField('Max Discount', max),
                      _dialogField('Usage Limit (0 = unlimited)', usageLimit),
                      _dialogField('Used Count', usedCount),
                      _dialogField('Per User Limit', perUserLimit),
                    ]),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: pickEditDate,
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text('Expiry: ${_dateText(editExpiry)}'),
                    ),
                    SwitchListTile(
                      value: editActive,
                      title: const Text('Active'),
                      onChanged: (v) => setDialogState(() => editActive = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton.icon(
                onPressed: saveEdit,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Update'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _dialogField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }

  Widget _dialogGrid(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth > 480 ? 2 : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: children.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: count == 1 ? 5.6 : 4.2,
          ),
          itemBuilder: (_, i) => children[i],
        );
      },
    );
  }

  Future<void> _deleteCoupon(String id) async {
    if (!canDelete) {
      _deny('You need coupons.delete permission.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Coupon?'),
        content: Text('Are you sure you want to delete $id?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await db.collection('coupons').doc(id).delete();
      _snack('Coupon deleted');
    }
  }

  Future<void> _toggleCoupon(String id, bool value) async {
    if (!canStatus) {
      _deny('You need coupons.status permission.');
      return;
    }

    await db.collection('coupons').doc(id).update({
      'isActive': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  List<QueryDocumentSnapshot> _filterCoupons(List<QueryDocumentSnapshot> docs) {
    final s = searchText.toLowerCase().trim();

    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final code = _text(data['code'], doc.id).toLowerCase();
      final active = data['isActive'] == true;
      final expired = _isExpired(data);

      if (filter == 'active' && (!active || expired)) return false;
      if (filter == 'inactive' && active) return false;
      if (filter == 'expired' && !expired) return false;
      if (filter == 'percent' && _text(data['type']) != 'percent') return false;
      if (filter == 'flat' && _text(data['type']) != 'flat') return false;

      if (s.isNotEmpty && !code.contains(s)) return false;

      return true;
    }).toList();
  }

  Widget _summaryGrid(List<QueryDocumentSnapshot> docs) {
    int active = 0;
    int expired = 0;
    int disabled = 0;
    int used = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final isExpired = _isExpired(data);
      final isActive = data['isActive'] == true;

      if (isExpired) {
        expired++;
      } else if (isActive) {
        active++;
      } else {
        disabled++;
      }

      used += _toInt(data['usedCount']);
    }

    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth >= 900 ? 4 : c.maxWidth >= 600 ? 2 : 1;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: count,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: count == 1 ? 4.5 : 2.2,
          children: [
            _summaryCard('Active', '$active', Icons.verified_rounded, Colors.green),
            _summaryCard('Expired', '$expired', Icons.event_busy_rounded, Colors.red),
            _summaryCard('Disabled', '$disabled', Icons.toggle_off_rounded, Colors.orange),
            _summaryCard('Total Used', '$used', Icons.trending_up_rounded, Colors.blue),
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

  Widget _field({
    required String label,
    required TextEditingController controller,
    IconData? icon,
    String? hint,
    bool number = false,
    String? Function(String?)? validator,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      textCapitalization: capitalization,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon == null ? null : Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _formCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create Coupon', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _field(
                label: 'Coupon Code',
                controller: codeController,
                hint: 'SAVE50',
                icon: Icons.confirmation_number_outlined,
                capitalization: TextCapitalization.characters,
                validator: _couponCodeValidator,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _generateRandomCode,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Generate Code'),
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(
                  labelText: 'Discount Type',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: const [
                  DropdownMenuItem(value: 'percent', child: Text('Percent (%)')),
                  DropdownMenuItem(value: 'flat', child: Text('Flat (৳)')),
                ],
                onChanged: (v) => setState(() => type = v ?? 'percent'),
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Discount Value',
                controller: valueController,
                icon: Icons.discount_outlined,
                number: true,
                validator: _number,
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Minimum Order Amount',
                controller: minController,
                icon: Icons.shopping_cart_outlined,
                number: true,
                validator: _number,
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Maximum Discount',
                controller: maxController,
                icon: Icons.price_check_outlined,
                number: true,
                validator: _number,
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Usage Limit (0 = unlimited)',
                controller: usageLimitController,
                icon: Icons.repeat_rounded,
                number: true,
                validator: _number,
              ),
              const SizedBox(height: 12),
              _field(
                label: 'Per User Limit',
                controller: perUserLimitController,
                icon: Icons.person_outline_rounded,
                number: true,
                validator: _number,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickExpiryDate,
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text('Expiry: ${_dateText(expiryDate)}'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: isActive,
                title: const Text('Active Coupon'),
                onChanged: (v) => setState(() => isActive = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: saving ? null : _createCoupon,
                  icon: saving
                      ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'Saving...' : 'Save Coupon'),
                ),
              ),
            ],
          ),
        ),
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
            final small = c.maxWidth < 760;

            final search = TextField(
              controller: searchController,
              decoration: const InputDecoration(
                hintText: 'Search coupon code...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => searchText = v),
            );

            final dropdown = DropdownButtonFormField<String>(
              initialValue: filter,
              decoration: const InputDecoration(
                labelText: 'Filter',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                DropdownMenuItem(value: 'expired', child: Text('Expired')),
                DropdownMenuItem(value: 'percent', child: Text('Percent')),
                DropdownMenuItem(value: 'flat', child: Text('Flat')),
              ],
              onChanged: (v) => setState(() => filter = v ?? 'all'),
            );

            if (small) {
              return Column(
                children: [
                  search,
                  const SizedBox(height: 8),
                  dropdown,
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 2, child: search),
                const SizedBox(width: 8),
                Expanded(child: dropdown),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _couponCard(String id, Map<String, dynamic> data) {
    final code = _text(data['code'], id);
    final active = data['isActive'] == true;
    final expired = _isExpired(data);
    final cType = _text(data['type'], 'percent');
    final value = _toDouble(data['value']);
    final expiry = _expiryDate(data['expiry']);
    final usageLimit = _toInt(data['usageLimit']);
    final usedCount = _toInt(data['usedCount']);

    final usable = active && !expired && (usageLimit == 0 || usedCount < usageLimit);

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
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: usable ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.12),
              child: Icon(
                usable ? Icons.confirmation_number_rounded : Icons.block_rounded,
                color: usable ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cType == 'percent'
                        ? '${value.toStringAsFixed(0)}% discount'
                        : '৳${value.toStringAsFixed(0)} flat discount',
                    style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _chip(usable ? 'Usable' : expired ? 'Expired' : 'Disabled', usable ? Colors.green : Colors.red),
                      _chip('Min ৳${_toDouble(data['minAmount']).toStringAsFixed(0)}', Colors.blue),
                      _chip('Max ৳${_toDouble(data['maxDiscount']).toStringAsFixed(0)}', Colors.teal),
                      _chip('Used $usedCount/${usageLimit == 0 ? '∞' : usageLimit}', Colors.orange),
                      if (expiry != null) _chip('Exp ${_dateText(expiry)}', expired ? Colors.red : Colors.purple),
                    ],
                  ),
                ],
              ),
            ),
            Switch(
              value: active && !expired,
              onChanged: (!canStatus || expired) ? null : (v) => _toggleCoupon(id, v),
            ),
            if (canEdit)
              IconButton(
                tooltip: 'Edit',
                onPressed: () => _showEditDialog(id, data),
                icon: const Icon(Icons.edit_rounded, color: Colors.orange),
              ),
            if (canDelete)
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _deleteCoupon(id),
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              ),
          ],
        ),
      ),
    );
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

  Widget _couponList() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('coupons').orderBy('createdAt', descending: true).limit(300).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
        }

        final allDocs = snapshot.data!.docs;
        final docs = _filterCoupons(allDocs);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryGrid(allDocs),
            const SizedBox(height: 14),
            _filters(),
            const SizedBox(height: 12),
            Text(
              'Coupons (${docs.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              const Card(
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: Text('No matching coupons')),
                ),
              )
            else
              ...docs.map((doc) => _couponCard(doc.id, doc.data() as Map<String, dynamic>)),
          ],
        );
      },
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (permissionLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!canView) {
      return _noAccessPage();
    }

    final wide = MediaQuery.of(context).size.width >= 1100;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Coupon Manager Pro',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (canEdit) ...[
                  Expanded(flex: 4, child: _formCard()),
                  const SizedBox(width: 16),
                  Expanded(flex: 7, child: _couponList()),
                ] else
                  Expanded(child: _couponList()),
              ],
            )
          else ...[
            if (canEdit) ...[
              _formCard(),
              const SizedBox(height: 16),
            ],
            _couponList(),
          ],
        ],
      ),
    );
  }
}
