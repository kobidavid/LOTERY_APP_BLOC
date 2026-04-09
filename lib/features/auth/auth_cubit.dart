import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../repositories/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit({
    required AuthRepository authRepository,
  })  : _authRepository = authRepository,
        super(const AuthState.loading()) {
    _subscription = _authRepository.authStateChanges().listen((user) {
      if (user == null) {
        emit(const AuthState.unauthenticated());
        return;
      }

      emit(AuthState.authenticated(user));
    });
  }

  final AuthRepository _authRepository;
  late final StreamSubscription<dynamic> _subscription;

  bool get supportsAppleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> signInWithGoogle() async {
    emit(state.copyWith(isBusy: true, clearErrorMessage: true));
    try {
      final user = await _authRepository.signInWithGoogle();
      emit(AuthState.authenticated(user).copyWith(isBusy: false));
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: error.toString(),
          isBusy: false,
        ),
      );
    }
  }

  Future<void> signInWithApple() async {
    emit(state.copyWith(isBusy: true, clearErrorMessage: true));
    try {
      final user = await _authRepository.signInWithApple();
      emit(AuthState.authenticated(user).copyWith(isBusy: false));
    } catch (error) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: error.toString(),
          isBusy: false,
        ),
      );
    }
  }

  Future<void> signOut() => _authRepository.signOut();

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
