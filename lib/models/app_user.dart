import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.provider,
    required this.operatorAccess,
    this.createdAt,
    this.lastLoginAt,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String provider;
  final bool operatorAccess;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  factory AppUser.fromFirebaseUser(
    User user, {
    String? providerOverride,
    bool? operatorAccessOverride,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return AppUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      provider: providerOverride ?? _providerFromUser(user),
      operatorAccess: operatorAccessOverride ?? false,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
    );
  }

  factory AppUser.fromMap(
    Map<String, dynamic> map, {
    User? fallbackUser,
    bool? operatorAccessOverride,
  }) {
    return AppUser(
      uid: map['uid'] as String? ?? fallbackUser?.uid ?? '',
      email: map['email'] as String? ?? fallbackUser?.email,
      displayName: map['displayName'] as String? ?? fallbackUser?.displayName,
      photoUrl: map['photoUrl'] as String? ?? fallbackUser?.photoURL,
      provider: map['provider'] as String? ??
          (fallbackUser != null ? _providerFromUser(fallbackUser) : 'unknown'),
      operatorAccess:
          operatorAccessOverride ?? (map['operatorAccess'] as bool? ?? false),
      createdAt: _asDateTime(map['createdAt']),
      lastLoginAt: _asDateTime(map['lastLoginAt']),
    );
  }

  static String _providerFromUser(User user) {
    if (user.providerData.isEmpty) {
      return 'unknown';
    }
    return user.providerData.first.providerId;
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  @override
  List<Object?> get props => [
        uid,
        email,
        displayName,
        photoUrl,
        provider,
        operatorAccess,
        createdAt,
        lastLoginAt,
      ];
}
