import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAuthService {
  FirebaseAuthService({
    FirebaseAuth? firebaseAuth,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  Future<UserCredential> signInWithGoogle() {
    final GoogleAuthProvider provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile');
    if (kIsWeb) {
      return _firebaseAuth.signInWithPopup(provider);
    }
    return _firebaseAuth.signInWithProvider(provider);
  }

  Future<UserCredential> signInWithApple() {
    final AppleAuthProvider provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    if (kIsWeb) {
      return _firebaseAuth.signInWithPopup(provider);
    }
    return _firebaseAuth.signInWithProvider(provider);
  }

  Future<void> signOut() => _firebaseAuth.signOut();
}
