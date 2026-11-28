import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

import 'notification_service.dart';
import 'private_profile_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  // Created on first use, which is Android/iOS only (web signs in with the
  // Firebase popup). On web the GoogleSignIn() constructor starts the plugin
  // at once and, with no web client ID set, threw an uncaught "Null check"
  // error on every page load (F4).
  GoogleSignIn? _googleSignInInstance;
  GoogleSignIn get _googleSignIn => _googleSignInInstance ??= GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  String? get currentUid => _auth.currentUser?.uid;
  Stream<User?> get authChanges => _auth.authStateChanges();

  static const String roleSuperAdmin = 'superAdmin';
  static const String roleAdmin = 'admin';
  static const String roleStaff = 'staff';
  static const String roleVendor = 'vendor';
  static const String roleUser = 'user';

  // ---------------------------------------------------------------------
  // Account linking (one account per email).
  //
  // Signing in with Facebook when the email already belongs to a Google (or
  // other) account fails with account-exists-with-different-credential. The
  // Facebook credential from that error is kept here, in memory only, for a
  // short while; once the customer signs in the old way, it is linked to that
  // account (linkPendingCredentialIfAny), so Facebook then opens the same uid
  // with its orders and notifications. The same works the other way round.
  // ---------------------------------------------------------------------

  static PendingLink? _pendingLink;
  static const Duration _pendingLinkTtl = Duration(minutes: 15);

  static PendingLink? get pendingLink {
    final p = _pendingLink;
    if (p == null) return null;
    if (DateTime.now().difference(p.createdAt) > _pendingLinkTtl) {
      _pendingLink = null;
      return null;
    }
    return p;
  }

  static void clearPendingLink() => _pendingLink = null;

  /// Web hands back a generic OAuthCredential; linking wants the provider's own.
  static AuthCredential _normalizeCredential(AuthCredential c) {
    if (c is FacebookAuthCredential || c is GoogleAuthCredential) return c;
    if (c is OAuthCredential) {
      if (c.providerId == 'facebook.com' && c.accessToken != null) {
        return FacebookAuthProvider.credential(c.accessToken!);
      }
      if (c.providerId == 'google.com') {
        return GoogleAuthProvider.credential(idToken: c.idToken, accessToken: c.accessToken);
      }
    }
    return c;
  }

  /// Keeps the credential and throws [AccountExistsException] for the UI.
  Future<Never> _accountExists(
    FirebaseAuthException e,
    String providerId,
    AuthCredential? attempted,
  ) async {
    final credential = e.credential ?? attempted;
    if (credential != null) {
      _pendingLink = PendingLink(
        credential: _normalizeCredential(credential),
        providerId: providerId,
        email: e.email,
        createdAt: DateTime.now(),
      );
    }

    // Empty when email enumeration protection is on (it is for this
    // project); the UI then names every other method.
    var methods = <String>[];
    final email = e.email;
    if (email != null && email.isNotEmpty) {
      try {
        // ignore: deprecated_member_use
        methods = await _auth.fetchSignInMethodsForEmail(email);
      } catch (err) {
        debugPrint('fetchSignInMethodsForEmail unavailable: $err');
      }
    }
    throw AccountExistsException(
      providerId: providerId,
      email: email,
      existingMethods: methods.where((m) => m != providerId).toList(),
      canLink: credential != null,
    );
  }

  /// After any successful sign-in: links the kept credential to this
  /// account. Never throws.
  Future<LinkResult> linkPendingCredentialIfAny() async {
    final pending = pendingLink;
    final user = _auth.currentUser;
    if (pending == null || user == null) return const LinkResult.none();

    if (user.providerData.any((info) => info.providerId == pending.providerId)) {
      clearPendingLink();
      return const LinkResult.none();
    }
    // Someone else signed in on this device meanwhile: don't link.
    final pendingEmail = pending.email?.trim().toLowerCase() ?? '';
    final userEmail = user.email?.trim().toLowerCase() ?? '';
    if (pendingEmail.isNotEmpty && userEmail.isNotEmpty && pendingEmail != userEmail) {
      clearPendingLink();
      return const LinkResult.none();
    }

    try {
      await user.linkWithCredential(pending.credential);
      clearPendingLink();
      return LinkResult.linked(pending.providerId);
    } on FirebaseAuthException catch (e) {
      debugPrint('Link ${pending.providerId} failed: ${e.code} ${e.message}');
      clearPendingLink();
      return LinkResult.failed(pending.providerId, e.code);
    } catch (e) {
      debugPrint('Link ${pending.providerId} failed: $e');
      clearPendingLink();
      return LinkResult.failed(pending.providerId, 'unknown');
    }
  }

  /// Returns null when the customer cancels. Throws [AccountExistsException]
  /// or [FirebaseAuthException] (shown via authErrorBn).
  Future<User?> signInWithFacebook() async {
    AuthCredential? attempted;
    try {
      UserCredential credential;

      if (kIsWeb) {
        final provider = FacebookAuthProvider()
          ..addScope('email')
          ..addScope('public_profile');

        credential = await _auth.signInWithPopup(provider);
      } else {
        await FacebookAuth.instance.logOut();

        final result = await FacebookAuth.instance.login(
          permissions: ['email', 'public_profile'],
          // Force classic (non-limited) login so iOS always returns an
          // OAuth access token usable by FacebookAuthProvider.credential.
          // Limited login (the iOS ATT-driven default) returns a JWT
          // identity token that Firebase cannot verify the same way.
          loginTracking: LoginTracking.enabled,
        );

        if (result.status == LoginStatus.cancelled) {
          debugPrint('Facebook login cancelled by user');
          return null;
        }

        if (result.status != LoginStatus.success || result.accessToken == null) {
          debugPrint('Facebook login failed: ${result.status} ${result.message}');
          throw FirebaseAuthException(code: 'facebook-login-failed', message: result.message);
        }

        attempted = FacebookAuthProvider.credential(result.accessToken!.tokenString);
        credential = await _auth.signInWithCredential(attempted);
      }

      await createOrGetUser();
      await _afterLoginTasks();
      return credential.user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Facebook sign in Firebase error: ${e.code} ${e.message}');
      if (e.code == 'account-exists-with-different-credential') {
        await _accountExists(e, 'facebook.com', attempted);
      }
      rethrow;
    }
  }

  /// Returns null when the customer cancels. Throws [AccountExistsException]
  /// or [FirebaseAuthException] (shown via authErrorBn).
  Future<User?> signInWithGoogle() async {
    AuthCredential? attempted;
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

        attempted = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        credential = await _auth.signInWithCredential(attempted);
      }

      await createOrGetUser();
      await _afterLoginTasks();
      return credential.user;
    } on FirebaseAuthException catch (e) {
      debugPrint('Google sign in Firebase error: ${e.code} ${e.message}');
      if (e.code == 'account-exists-with-different-credential') {
        await _accountExists(e, 'google.com', attempted);
      }
      rethrow;
    }
  }

  Future<User?> register(String email, String password,
      {String? name, String? phone}) async {
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
        'whatsappNumber': '',
        'whatsappOptIn': false,
        'whatsappConsentVersion': '2026-07',
        'name': name?.trim().isNotEmpty == true
            ? name!.trim()
            : (user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : ''),
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
      if (user.displayName != null && _text(data['name']).isEmpty)
        'name': user.displayName,
      if (user.phoneNumber != null && _text(data['phone']).isEmpty)
        'phone': user.phoneNumber,
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

    // Public part only. Phone and address go to vendor_private (14b step B).
    // Commission is not set here: the applicant may not write it, and
    // the ledger function (functions/ledger) uses 10% when it is missing.
    await vendorRef.set({
      'ownerId': user.uid,
      'userId': user.uid,
      'shopName': shopName.trim(),
      'businessType': businessType,
      'status': 'pending',
      'isActive': false,
      'isVerified': false,
      'rating': 0,
      'totalOrders': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await PrivateProfileService.saveVendorPrivate(user.uid, {
      'phone': phone.trim(),
      'address': address.trim(),
    });

    // Step H2: no vendorId from the user (staff set it on approval).
    await _db.collection('users').doc(user.uid).set({
      'sellerStatus': 'pending',
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
    return _hasRoleInData(data, roleSuperAdmin) ||
        _hasRoleInData(data, roleAdmin);
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

    final allowed = data['isActive'] != false && data['isBanned'] != true;
    if (!allowed) return false;

    return _hasRoleInData(data, roleVendor) ||
        data['sellerStatus'] == 'approved' ||
        data['vendorStatus'] == 'approved';
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

    // ✅ SuperAdmin সবসময় সব permission পাবে
    if (_hasRoleInData(data, roleSuperAdmin)) return true;

    // ✅ Admin default permission সবসময় পাবে
    if (_hasRoleInData(data, roleAdmin) &&
        defaultAdminPermissions.contains(permission)) {
      return true;
    }

    final rawPermissions = data['permissions'];

    if (rawPermissions is List) {
      return rawPermissions.map((e) => e.toString()).contains(permission);
    }

    if (rawPermissions is Map) {
      return rawPermissions[permission] == true;
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

    await _db
        .collection('users')
        .doc(user.uid)
        .set(payload, SetOptions(merge: true));
  }

  Future<void> updateWhatsAppPreference({
    required bool optIn,
    String? whatsappNumber,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Login required');

    final raw = (whatsappNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    String normalized = '';
    if (raw.startsWith('8801') && raw.length == 13) {
      normalized = raw;
    } else if (raw.startsWith('01') && raw.length == 11) {
      normalized = '88$raw';
    }

    if (optIn && normalized.isEmpty) {
      throw Exception('Enter a valid Bangladeshi WhatsApp number');
    }

    await _db.collection('users').doc(user.uid).set({
      'whatsappOptIn': optIn,
      'whatsappNumber': optIn ? normalized : FieldValue.delete(),
      'whatsappConsentVersion': '2026-07',
      'whatsappConsentSource': 'customer_profile',
      if (optIn) 'whatsappOptInAt': FieldValue.serverTimestamp(),
      if (!optIn) 'whatsappOptOutAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
        await FacebookAuth.instance.logOut();
      } catch (e) {
        debugPrint('Facebook sign out skipped: $e');
      }

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
    final roles =
    List<String>.from(data['roles'] ?? []).map(_normalizeRole).toList();

    return primaryRole == normalized || roles.contains(normalized);
  }

  String _normalizeRole(String role) {
    final value = role.trim();

    if (value == 'super_admin' ||
        value == 'superadmin' ||
        value == 'SuperAdmin') {
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

/// A sign-in credential waiting to be linked (see AuthService).
class PendingLink {
  final AuthCredential credential;
  final String providerId;
  final String? email;
  final DateTime createdAt;

  const PendingLink({
    required this.credential,
    required this.providerId,
    required this.email,
    required this.createdAt,
  });
}

/// The email already has an account that uses another sign-in method.
class AccountExistsException implements Exception {
  /// The method the customer just tried ('facebook.com' / 'google.com').
  final String providerId;
  final String? email;

  /// Methods of the existing account; empty when Firebase won't say
  /// (email enumeration protection).
  final List<String> existingMethods;

  /// Whether the tried method will be linked after the next sign-in.
  final bool canLink;

  const AccountExistsException({
    required this.providerId,
    required this.email,
    required this.existingMethods,
    required this.canLink,
  });

  @override
  String toString() => 'AccountExistsException($providerId)';
}

class LinkResult {
  final String? providerId;
  final bool linked;
  final String? errorCode;

  const LinkResult.none() : providerId = null, linked = false, errorCode = null;
  const LinkResult.linked(String this.providerId) : linked = true, errorCode = null;
  const LinkResult.failed(String this.providerId, String this.errorCode) : linked = false;

  bool get failed => errorCode != null;
}
