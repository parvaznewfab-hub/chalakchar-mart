import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  String? get currentUid => _auth.currentUser?.uid;
  Stream<User?> get authChanges => _auth.authStateChanges();

  static const String roleSuperAdmin = 'superAdmin';
  static const String roleAdmin = 'admin';
  static const String roleStaff = 'staff';
  static const String roleVendor = 'vendor';
  static const String roleUser = 'user';

  Future<User?> signInWithGoogle() async {
    try {
      UserCredential credential;

      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});

        credential = await _auth.signInWithPopup(provider);
      } else {
        await _googleSignIn.signOut();
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return null;

        final googleAuth = await googleUser.authentication;

        credential = await _auth.signInWithCredential(
          GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          ),
        );
      }

      await createOrGetUser();
      await _afterLoginTasks();
      return credential.user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Google sign in Firebase error: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Google sign in error: $e');
      return null;
    }
  }

  Future<User?> register(String email, String password, {String? name, String? phone}) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      if (name != null && name.trim().isNotEmpty) {
        await credential.user?.updateDisplayName(name.trim());
      }

      await createOrGetUser(
        name: name,
        phone: phone,
      );

      await _afterLoginTasks();
      return credential.user;
    } catch (e) {
      debugPrint('Register error: $e');
      rethrow;
    }
  }

  Future<String?> login(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final role = await createOrGetUser();
      await _afterLoginTasks();
      return role;
    } catch (e) {
      debugPrint('Login error: $e');
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<String> createOrGetUser({String? name, String? phone}) async {
    final user = _auth.currentUser;
    if (user == null) return roleUser;

    final ref = _db.collection('users').doc(user.uid);
    final doc = await ref.get();

    if (!doc.exists) {
      await ref.set({
        'uid': user.uid,
        'email': user.email,
        'phone': phone ?? user.phoneNumber ?? '',
        'name': name?.trim().isNotEmpty == true
            ? name!.trim()
            : (user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : ''),
        'photoUrl': user.photoURL ?? '',
        'role': roleUser,
        'roles': [roleUser],
        'sellerStatus': 'none',
        'vendorId': null,
        'points': 0,
        'totalEarnings': 0,
        'referralCount': 0,
        'isActive': true,
        'isBanned': false,
        'emailVerified': user.emailVerified,
        'providerIds': user.providerData.map((e) => e.providerId).toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return roleUser;
    }

    final data = doc.data() ?? {};
    final role = _text(data['role'], roleUser);

    await ref.set({
      'uid': user.uid,
      'email': user.email,
      'emailVerified': user.emailVerified,
      if (user.displayName != null && _text(data['name']).isEmpty) 'name': user.displayName,
      if (user.phoneNumber != null && _text(data['phone']).isEmpty) 'phone': user.phoneNumber,
      if (user.photoURL != null) 'photoUrl': user.photoURL,
      'providerIds': user.providerData.map((e) => e.providerId).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return role;
  }

  Future<Map<String, dynamic>?> currentUserData() async {
    final uid = currentUid;
    if (uid == null) return null;

    final doc = await _db.collection('users').doc(uid).get();
    return doc.data();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> currentUserDocStream() {
    final uid = currentUid;
    if (uid == null) {
      throw Exception('No logged in user');
    }
    return _db.collection('users').doc(uid).snapshots();
  }

  Future<bool> isUserAllowed() async {
    final data = await currentUserData();
    if (data == null) return false;

    final isActive = data['isActive'] != false;
    final isBanned = data['isBanned'] == true;
    return isActive && !isBanned;
  }

  Future<void> ensureUserAllowed() async {
    final allowed = await isUserAllowed();
    if (!allowed) {
      await signOut();
      throw Exception('Your account is disabled. Please contact support.');
    }
  }

  Future<void> requestSellerAccount({
    required String shopName,
    required String phone,
    required String address,
    String businessType = 'general',
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Login required');

    final vendorRef = _db.collection('vendors').doc(user.uid);

    await vendorRef.set({
      'ownerId': user.uid,
      'shopName': shopName.trim(),
      'phone': phone.trim(),
      'address': address.trim(),
      'businessType': businessType,
      'status': 'pending',
      'isActive': false,
      'isVerified': false,
      'commissionPercent': 10,
      'rating': 0,
      'totalSales': 0,
      'totalOrders': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db.collection('users').doc(user.uid).set({
      'sellerStatus': 'pending',
      'vendorId': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> approveVendor(String uid) async {
    await _db.collection('vendors').doc(uid).set({
      'status': 'approved',
      'isActive': true,
      'isVerified': true,
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db.collection('users').doc(uid).set({
      'role': roleVendor,
      'roles': FieldValue.arrayUnion([roleVendor]),
      'sellerStatus': 'approved',
      'vendorId': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> rejectVendor(String uid) async {
    await _db.collection('vendors').doc(uid).set({
      'status': 'rejected',
      'isActive': false,
      'isVerified': false,
      'rejectedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db.collection('users').doc(uid).set({
      'sellerStatus': 'rejected',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setUserRole(String uid, String role) async {
    final normalized = _normalizeRole(role);

    await _db.collection('users').doc(uid).set({
      'role': normalized,
      'roles': FieldValue.arrayUnion([normalized]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> addUserRole(String uid, String role) async {
    final normalized = _normalizeRole(role);

    await _db.collection('users').doc(uid).set({
      'roles': FieldValue.arrayUnion([normalized]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeUserRole(String uid, String role) async {
    final normalized = _normalizeRole(role);

    await _db.collection('users').doc(uid).set({
      'roles': FieldValue.arrayRemove([normalized]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> hasRole(String role) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final doc = await _db.collection('users').doc(user.uid).get();
    final data = doc.data() ?? {};
    return _hasRoleInData(data, role);
  }

  Future<bool> hasAnyRole(List<String> roles) async {
    for (final role in roles) {
      if (await hasRole(role)) return true;
    }
    return false;
  }

  Future<bool> isSuperAdmin() => hasRole(roleSuperAdmin);

  Future<bool> isAdmin() async {
    final data = await currentUserData();
    if (data == null) return false;
    return _hasRoleInData(data, roleSuperAdmin) || _hasRoleInData(data, roleAdmin);
  }

  Future<bool> isStaff() async {
    final data = await currentUserData();
    if (data == null) return false;
    return _hasRoleInData(data, roleSuperAdmin) ||
        _hasRoleInData(data, roleAdmin) ||
        _hasRoleInData(data, roleStaff);
  }

  Future<bool> isVendor() async {
    final data = await currentUserData();
    if (data == null) return false;

    return _hasRoleInData(data, roleVendor) ||
        data['sellerStatus'] == 'approved' ||
        _text(data['vendorId']).isNotEmpty;
  }

  Future<bool> canAccessAdminPanel() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final data = await currentUserData();
    if (data == null) return false;

    final allowed = data['isActive'] != false && data['isBanned'] != true;
    if (!allowed) return false;

    return _hasRoleInData(data, roleSuperAdmin) ||
        _hasRoleInData(data, roleAdmin) ||
        _hasRoleInData(data, roleStaff);
  }

  Future<void> ensureAdminAccess() async {
    final canAccess = await canAccessAdminPanel();
    if (!canAccess) {
      throw Exception('Admin access denied');
    }
  }

  static const Set<String> defaultAdminPermissions = {
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

    'notifications.view',
    'notifications.send',
    'notifications.manage',
    'notifications.delete',
    'notifications.open_related',

    // Admin can view settings, but only Super Admin should edit critical settings.
    'settings.view',
  };

  static const Set<String> defaultStaffPermissions = {
    'dashboard.view',
  };

  Future<bool> hasPermission(String permission) async {
    final data = await currentUserData();
    if (data == null) return false;

    final allowed = data['isActive'] != false && data['isBanned'] != true;
    if (!allowed) return false;

    if (_hasRoleInData(data, roleSuperAdmin)) return true;

    final rawPermissions = data['permissions'];
    final permissions = rawPermissions is List ? List<String>.from(rawPermissions) : <String>[];

    // If permissions are assigned manually, follow them strictly.
    if (permissions.isNotEmpty) {
      return permissions.contains(permission);
    }

    // Fallback defaults only when permissions field is empty/missing.
    if (_hasRoleInData(data, roleAdmin)) {
      return defaultAdminPermissions.contains(permission);
    }

    if (_hasRoleInData(data, roleStaff)) {
      return defaultStaffPermissions.contains(permission);
    }

    return false;
  }

  Future<void> setStaffPermissions(String uid, List<String> permissions) async {
    await _db.collection('users').doc(uid).set({
      'role': roleStaff,
      'roles': FieldValue.arrayUnion([roleStaff]),
      'permissions': permissions,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> blockUser(String uid, {String? reason}) async {
    await _db.collection('users').doc(uid).set({
      'isActive': false,
      'isBanned': true,
      'banReason': reason ?? '',
      'bannedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> unblockUser(String uid) async {
    await _db.collection('users').doc(uid).set({
      'isActive': true,
      'isBanned': false,
      'banReason': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateProfile({
    String? name,
    String? phone,
    String? address,
    String? division,
    String? district,
    String? upazila,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Login required');

    final payload = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) payload['name'] = name.trim();
    if (phone != null) payload['phone'] = phone.trim();
    if (address != null) payload['address'] = address.trim();
    if (division != null) payload['division'] = division.trim();
    if (district != null) payload['district'] = district.trim();
    if (upazila != null) payload['upazila'] = upazila.trim();

    await _db.collection('users').doc(user.uid).set(payload, SetOptions(merge: true));
  }

  Future<void> refreshFcmToken() => _safeSaveToken();

  Future<void> signOut() async {
    try {
      final uid = _auth.currentUser?.uid;

      if (uid != null) {
        final ref = _db.collection('users').doc(uid);
        final doc = await ref.get();

        if (doc.exists) {
          await ref.set({
            'lastLogoutAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint('Logout audit skipped: $e');
    }

    await _auth.signOut();

    if (!kIsWeb) {
      try {
        await _googleSignIn.disconnect();
      } catch (e) {
        debugPrint('Google disconnect skipped: $e');
      }

      try {
        await _googleSignIn.signOut();
      } catch (e) {
        debugPrint('Google sign out skipped: $e');
      }
    }
  }

  Future<void> deleteCurrentAccountSoft() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Login required');

    await _db.collection('users').doc(user.uid).set({
      'isActive': false,
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await signOut();
  }

  Future<void> _afterLoginTasks() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await createOrGetUser();
      }
    } catch (e) {
      debugPrint('User doc ensure skipped: $e');
    }

    await ensureUserAllowed();

    await _safeSaveToken();
  }

  Future<void> _safeSaveToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await NotificationService.saveToken(user.uid);
    } catch (e) {
      debugPrint('FCM token save skipped: $e');
    }
  }

  bool _hasRoleInData(Map<String, dynamic> data, String role) {
    final normalized = _normalizeRole(role);
    final primaryRole = _normalizeRole(_text(data['role'], roleUser));
    final roles = List<String>.from(data['roles'] ?? []).map(_normalizeRole).toList();

    return primaryRole == normalized || roles.contains(normalized);
  }

  String _normalizeRole(String role) {
    final value = role.trim();

    if (value == 'super_admin' || value == 'superadmin' || value == 'SuperAdmin') {
      return roleSuperAdmin;
    }

    if (value == 'administrator') return roleAdmin;
    if (value == 'seller') return roleVendor;

    return value;
  }

  String _text(dynamic value, [String fallback = '']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }
}



