import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';

class AdminDeliveryPartnerApprovalPage extends StatefulWidget {
  const AdminDeliveryPartnerApprovalPage({super.key});

  @override
  State<AdminDeliveryPartnerApprovalPage> createState() =>
      _AdminDeliveryPartnerApprovalPageState();
}

class _DeliveryPermissions {
  final bool view;
  final bool approve;
  final bool block;
  final bool withdraw;
  final bool settleCod;
  final bool documents;
  final bool contact;

  const _DeliveryPermissions({
    required this.view,
    required this.approve,
    required this.block,
    required this.withdraw,
    required this.settleCod,
    required this.documents,
    required this.contact,
  });

  bool get canManagePartner => approve || block;
}

class _AdminDeliveryPartnerApprovalPageState
    extends State<AdminDeliveryPartnerApprovalPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final AuthService authService = AuthService();

  late Future<_DeliveryPermissions> _permissionFuture;

  @override
  void initState() {
    super.initState();
    _permissionFuture = _loadPermissions();
  }

  Future<_DeliveryPermissions> _loadPermissions() async {
    final view = await authService.hasPermission('delivery.view');
    return _DeliveryPermissions(
      view: view,
      approve: await authService.hasPermission('delivery.approve'),
      block: await authService.hasPermission('delivery.block'),
      withdraw: await authService.hasPermission('delivery.withdraw'),
      settleCod: await authService.hasPermission('delivery.settle_cod'),
      documents: await authService.hasPermission('delivery.documents'),
      contact: await authService.hasPermission('delivery.contact'),
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : const Color(0xFF32A8C7),
      ),
    );
  }

  void _permissionDenied([String message = 'You do not have permission for this action.']) {
    _snack(message, error: true);
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _text(dynamic v, [String fallback = '']) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  Color _statusColor(String status) {
    if (status == 'approved') return Colors.green;
    if (status == 'rejected') return Colors.red;
    if (status == 'blocked') return Colors.black87;
    return Colors.orange;
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmText,
    bool danger = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
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
    return ok == true;
  }

  Future<void> _updateStatus(String uid, String status, _DeliveryPermissions p) async {
    final isApproveRejectOrPending = status == 'approved' || status == 'rejected' || status == 'pending';
    final isBlock = status == 'blocked';

    if (isApproveRejectOrPending && !p.approve) {
      _permissionDenied('delivery.approve permission required.');
      return;
    }

    if (isBlock && !p.block) {
      _permissionDenied('delivery.block permission required.');
      return;
    }

    final ok = await _confirm(
      title: '${status[0].toUpperCase()}${status.substring(1)} delivery partner?',
      message: 'This will update the delivery partner status to "$status".',
      confirmText: status == 'blocked' || status == 'rejected' ? status.toUpperCase() : 'Confirm',
      danger: status == 'blocked' || status == 'rejected',
    );

    if (!ok) return;

    try {
      final updateData = <String, dynamic>{
        'status': status,
        'isActive': status == 'approved',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (status == 'approved') {
        updateData['approvedAt'] = FieldValue.serverTimestamp();
        updateData['rejectedAt'] = FieldValue.delete();
        updateData['blockedAt'] = FieldValue.delete();
        updateData['documentStatus'] = 'verified';
      } else if (status == 'rejected') {
        updateData['rejectedAt'] = FieldValue.serverTimestamp();
        updateData['documentStatus'] = 'rejected';
      } else if (status == 'blocked') {
        updateData['blockedAt'] = FieldValue.serverTimestamp();
      } else {
        updateData['documentStatus'] = 'submitted';
      }

      await db.collection('deliveryPartners').doc(uid).set(
        updateData,
        SetOptions(merge: true),
      );

      _snack('Delivery partner $status');
    } catch (e) {
      _snack('Update failed: $e', error: true);
    }
  }

  Future<void> _approveWithdraw(
      String withdrawId,
      String riderId,
      double amount,
      _DeliveryPermissions p,
      ) async {
    if (!p.withdraw) {
      _permissionDenied('delivery.withdraw permission required.');
      return;
    }

    final ok = await _confirm(
      title: 'Approve withdraw?',
      message: 'This will approve ৳${amount.toStringAsFixed(0)} withdraw request.',
      confirmText: 'Approve',
    );

    if (!ok) return;

    try {
      final batch = db.batch();

      batch.update(db.collection('deliveryWithdraws').doc(withdrawId), {
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(db.collection('deliveryPartners').doc(riderId), {
        'withdrawnAmount': FieldValue.increment(amount),
        'pendingAmount': FieldValue.increment(-amount),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      _snack('Withdraw approved');
    } catch (e) {
      _snack('Approval failed: $e', error: true);
    }
  }

  Future<void> _rejectWithdraw(
      String withdrawId,
      String riderId,
      double amount,
      _DeliveryPermissions p,
      ) async {
    if (!p.withdraw) {
      _permissionDenied('delivery.withdraw permission required.');
      return;
    }

    final ok = await _confirm(
      title: 'Reject withdraw?',
      message: 'This will reject ৳${amount.toStringAsFixed(0)} withdraw request.',
      confirmText: 'Reject',
      danger: true,
    );

    if (!ok) return;

    try {
      final batch = db.batch();

      batch.update(db.collection('deliveryWithdraws').doc(withdrawId), {
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(db.collection('deliveryPartners').doc(riderId), {
        'pendingAmount': FieldValue.increment(-amount),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      _snack('Withdraw rejected');
    } catch (e) {
      _snack('Reject failed: $e', error: true);
    }
  }

  Future<void> _settleCod(String riderId, double codDue, _DeliveryPermissions p) async {
    if (!p.settleCod) {
      _permissionDenied('delivery.settle_cod permission required.');
      return;
    }

    final ok = await _confirm(
      title: 'Settle COD?',
      message: 'This will clear COD due ৳${codDue.toStringAsFixed(0)} for this rider.',
      confirmText: 'Settle',
    );

    if (!ok) return;

    try {
      await db.collection('deliveryPartners').doc(riderId).set({
        'codDue': 0,
        'lastCodSettlementAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _snack('COD settled successfully');
    } catch (e) {
      _snack('Settlement failed: $e', error: true);
    }
  }

  Future<void> _openUrl(String url, _DeliveryPermissions p) async {
    if (!p.documents) {
      _permissionDenied('delivery.documents permission required.');
      return;
    }

    final clean = url.trim();
    if (clean.isEmpty) {
      _snack('Document image not found', error: true);
      return;
    }

    final uri = Uri.tryParse(clean);
    if (uri == null) {
      _snack('Invalid image URL', error: true);
      return;
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack('Could not open image', error: true);
    }
  }

  Future<void> _call(String phone, _DeliveryPermissions p) async {
    if (!p.contact) {
      _permissionDenied('delivery.contact permission required.');
      return;
    }

    final clean = phone.trim();
    if (clean.isEmpty) {
      _snack('Phone not found', error: true);
      return;
    }

    final uri = Uri.parse('tel:$clean');
    await launchUrl(uri);
  }

  Widget _blockedPage(String message) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 44, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'Access Restricted',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DeliveryPermissions>(
      future: _permissionFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FA),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final p = snapshot.data!;
        if (!p.view) {
          return _blockedPage('delivery.view permission required.');
        }

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            appBar: AppBar(
              title: const Text('Delivery Partner Management'),
              backgroundColor: const Color(0xFF32A8C7),
              foregroundColor: Colors.white,
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Partners'),
                  Tab(text: 'Withdraws'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _PartnersTab(permissions: p),
                _WithdrawTab(permissions: p),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PartnersTab extends StatelessWidget {
  final _DeliveryPermissions permissions;

  const _PartnersTab({required this.permissions});

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_AdminDeliveryPartnerApprovalPageState>();
    final db = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('deliveryPartners').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Load failed: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final partners = snapshot.data!.docs;
        if (partners.isEmpty) {
          return const Center(child: Text('No delivery partner applications found'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: partners.length,
          itemBuilder: (context, index) {
            final doc = partners[index];
            final data = doc.data();
            final uid = doc.id;

            final name = state?._text(data['name'], 'No Name') ?? 'No Name';
            final phone = state?._text(data['phone']) ?? '';
            final area = state?._text(data['preferredArea']) ?? '';
            final vehicle = state?._text(data['vehicleType']) ?? '';
            final nid = state?._text(data['nidNumber']) ?? '';
            final address = state?._text(data['address']) ?? '';
            final note = state?._text(data['note']) ?? '';
            final status = state?._text(data['status'], 'pending') ?? 'pending';
            final documentStatus = state?._text(data['documentStatus'], 'not_submitted') ?? 'not_submitted';

            final frontUrl = state?._text(data['nidFrontUrl']) ?? '';
            final backUrl = state?._text(data['nidBackUrl']) ?? '';

            final totalEarning = state?._toDouble(data['totalEarning']) ?? 0;
            final withdrawn = state?._toDouble(data['withdrawnAmount']) ?? 0;
            final pending = state?._toDouble(data['pendingAmount']) ?? 0;
            final codDue = state?._toDouble(data['codDue']) ?? 0;

            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _partnerHeader(
                      context: context,
                      name: name,
                      uid: uid,
                      status: status,
                      documentStatus: documentStatus,
                      state: state,
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        _row(Icons.phone, 'Phone', phone),
                        _row(Icons.location_on, 'Area', area),
                        _row(Icons.delivery_dining, 'Vehicle', vehicle),
                        _row(Icons.badge, 'NID', nid),
                        _row(Icons.home, 'Address', address),
                      ],
                    ),
                    if (note.isNotEmpty) _row(Icons.note, 'Note', note),
                    const SizedBox(height: 12),
                    _documentSection(state, frontUrl, backUrl),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _moneyBox('Earned', totalEarning, Colors.green),
                        _moneyBox('Withdrawn', withdrawn, Colors.blue),
                        _moneyBox('Pending', pending, Colors.orange),
                        _moneyBox('COD Due', codDue, Colors.red),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (codDue > 0 && permissions.settleCod)
                          ElevatedButton.icon(
                            onPressed: () => state?._settleCod(uid, codDue, permissions),
                            icon: const Icon(Icons.payments),
                            label: const Text('Settle COD'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        if (permissions.approve) ...[
                          ElevatedButton.icon(
                            onPressed: status == 'approved'
                                ? null
                                : () => state?._updateStatus(uid, 'approved', permissions),
                            icon: const Icon(Icons.check),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: status == 'rejected'
                                ? null
                                : () => state?._updateStatus(uid, 'rejected', permissions),
                            icon: const Icon(Icons.close),
                            label: const Text('Reject'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => state?._updateStatus(uid, 'pending', permissions),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Pending'),
                          ),
                        ],
                        if (permissions.block)
                          ElevatedButton.icon(
                            onPressed: status == 'blocked'
                                ? null
                                : () => state?._updateStatus(uid, 'blocked', permissions),
                            icon: const Icon(Icons.block),
                            label: const Text('Block'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black87,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        if (permissions.contact)
                          OutlinedButton.icon(
                            onPressed: phone.isEmpty ? null : () => state?._call(phone, permissions),
                            icon: const Icon(Icons.call),
                            label: const Text('Call'),
                          ),
                      ],
                    ),
                    if (!permissions.canManagePartner &&
                        !permissions.settleCod &&
                        !permissions.contact)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Read-only mode: management permissions are not enabled.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _partnerHeader({
    required BuildContext context,
    required String name,
    required String uid,
    required String status,
    required String documentStatus,
    required _AdminDeliveryPartnerApprovalPageState? state,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final compact = c.maxWidth < 720;

        final header = Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF32A8C7).withValues(alpha: 0.12),
              child: const Icon(Icons.delivery_dining, color: Color(0xFF32A8C7)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'UID: $uid',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );

        final chips = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              label: Text(
                status.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              backgroundColor: state?._statusColor(status) ?? Colors.orange,
            ),
            Chip(
              label: Text('DOC: ${documentStatus.toUpperCase()}', style: const TextStyle(fontSize: 11)),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [header, const SizedBox(height: 10), chips],
          );
        }

        return Row(children: [Expanded(child: header), chips]);
      },
    );
  }

  Widget _documentSection(
      _AdminDeliveryPartnerApprovalPageState? state,
      String frontUrl,
      String backUrl,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_outlined, color: Color(0xFF32A8C7)),
              SizedBox(width: 8),
              Text('NID / ID Verification Images', style: TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          if (!permissions.documents)
            const Text('Document view permission not enabled.', style: TextStyle(color: Colors.grey))
          else
            LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 620;
                final front = _imageCard(
                  title: 'Front Side',
                  url: frontUrl,
                  onOpen: () => state?._openUrl(frontUrl, permissions),
                );
                final back = _imageCard(
                  title: 'Back Side',
                  url: backUrl,
                  onOpen: () => state?._openUrl(backUrl, permissions),
                );

                if (compact) {
                  return Column(children: [front, const SizedBox(height: 10), back]);
                }

                return Row(children: [Expanded(child: front), const SizedBox(width: 10), Expanded(child: back)]);
              },
            ),
        ],
      ),
    );
  }

  Widget _imageCard({
    required String title,
    required String url,
    required VoidCallback onOpen,
  }) {
    final hasImage = url.trim().isNotEmpty;

    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(child: Text('Image load failed')),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new, color: Colors.white, size: 16),
                    label: const Text('Open', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ],
      )
          : Center(
        child: Text(
          '$title not uploaded',
          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _WithdrawTab extends StatelessWidget {
  final _DeliveryPermissions permissions;

  const _WithdrawTab({required this.permissions});

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_AdminDeliveryPartnerApprovalPageState>();
    final db = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('deliveryWithdraws').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Load failed: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final withdraws = snapshot.data!.docs;
        if (withdraws.isEmpty) {
          return const Center(child: Text('No withdraw requests'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: withdraws.length,
          itemBuilder: (context, index) {
            final doc = withdraws[index];
            final data = doc.data();
            final withdrawId = doc.id;
            final riderId = (data['deliveryPartnerId'] ?? '').toString();
            final amount = state?._toDouble(data['amount']) ?? 0;
            final status = (data['status'] ?? 'pending').toString();
            final createdAt = data['createdAt'];

            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            riderId.isEmpty ? 'Unknown Rider' : riderId,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Chip(label: Text(status.toUpperCase())),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Withdraw Amount: ৳${amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (createdAt is Timestamp) ...[
                      const SizedBox(height: 4),
                      Text('Requested: ${createdAt.toDate()}'),
                    ],
                    const SizedBox(height: 14),
                    if (status == 'pending' && permissions.withdraw)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => state?._approveWithdraw(withdrawId, riderId, amount, permissions),
                            icon: const Icon(Icons.check),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => state?._rejectWithdraw(withdrawId, riderId, amount, permissions),
                            icon: const Icon(Icons.close),
                            label: const Text('Reject'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      )
                    else if (!permissions.withdraw)
                      const Text('Read-only mode: delivery.withdraw permission not enabled.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Widget _moneyBox(String title, double amount, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          '৳${amount.toStringAsFixed(0)}',
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    ),
  );
}

Widget _row(IconData icon, String label, String value) {
  if (value.trim().isEmpty) return const SizedBox.shrink();

  return ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 220),
    child: Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Flexible(child: Text(value)),
        ],
      ),
    ),
  );
}
