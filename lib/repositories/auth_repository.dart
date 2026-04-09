import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';
import '../services/firebase_auth_service.dart';

class AuthRepository {
  static const Set<String> _operatorAllowlistEmails = <String>{
    'kobidev80@gmail.com',
  };

  AuthRepository({
    required FirebaseAuthService authService,
    FirebaseFirestore? firestore,
  })  : _authService = authService,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuthService _authService;
  final FirebaseFirestore _firestore;

  Stream<AppUser?> authStateChanges() {
    return _authService.authStateChanges().asyncMap((user) async {
      if (user == null) {
        return null;
      }

      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await _firestore.collection('users').doc(user.uid).get();
      if (!snapshot.exists) {
        return AppUser.fromFirebaseUser(
          user,
          operatorAccessOverride: _isAllowlistedOperator(user.email),
        );
      }

      return AppUser.fromMap(
        snapshot.data()!,
        fallbackUser: user,
        operatorAccessOverride: _isAllowlistedOperator(user.email),
      );
    });
  }

  Future<AppUser> signInWithGoogle() async {
    final UserCredential credential = await _authService.signInWithGoogle();
    return _syncUserProfile(credential.user!, provider: 'google.com');
  }

  Future<AppUser> signInWithApple() async {
    final UserCredential credential = await _authService.signInWithApple();
    return _syncUserProfile(credential.user!, provider: 'apple.com');
  }

  Future<void> signOut() => _authService.signOut();

  Future<AppUser> _syncUserProfile(
    User firebaseUser, {
    required String provider,
  }) async {
    final DocumentReference<Map<String, dynamic>> userRef =
        _firestore.collection('users').doc(firebaseUser.uid);

    await _firestore.runTransaction((transaction) async {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await transaction.get(userRef);
      final Map<String, dynamic> existing =
          snapshot.data() ?? <String, dynamic>{};

      transaction.set(
        userRef,
        <String, dynamic>{
          'uid': firebaseUser.uid,
          'email': firebaseUser.email,
          'displayName': firebaseUser.displayName,
          'photoUrl': firebaseUser.photoURL,
          'provider': provider,
          'operatorAccess': (existing['operatorAccess'] as bool? ?? false) ||
              _isAllowlistedOperator(firebaseUser.email),
          'balance': existing['balance'] ?? 0,
          'createdAt': existing['createdAt'] ?? FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    final DocumentSnapshot<Map<String, dynamic>> updatedSnapshot =
        await userRef.get();
    return AppUser.fromMap(
      updatedSnapshot.data()!,
      fallbackUser: firebaseUser,
      operatorAccessOverride: _isAllowlistedOperator(firebaseUser.email),
    );
  }

  static bool _isAllowlistedOperator(String? email) {
    if (email == null) {
      return false;
    }
    return _operatorAllowlistEmails.contains(email.trim().toLowerCase());
  }
}
