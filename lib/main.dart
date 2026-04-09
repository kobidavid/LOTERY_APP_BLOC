import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/auth/auth_cubit.dart';
import 'features/auth/auth_state.dart';
import 'features/operator/operator_console_page.dart';
import 'features/operator/operator_sign_in_page.dart';
import 'features/auth/sign_in_page.dart';
import 'features/main_shell_page.dart';
import 'firebase_options.dart';
import 'repositories/auth_repository.dart';
import 'services/firebase_auth_service.dart';
import 'services/group_invite_link_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await _ensureFirebaseInitialized();
  final AuthRepository authRepository = AuthRepository(
    authService: FirebaseAuthService(),
  );
  final GroupInviteLinkService inviteLinkService = GroupInviteLinkService();
  await inviteLinkService.initialize();

  runApp(
    LotoGroupApp(
      authRepository: authRepository,
      inviteLinkService: inviteLinkService,
    ),
  );
}

class LotoGroupApp extends StatelessWidget {
  const LotoGroupApp({
    super.key,
    required this.authRepository,
    required this.inviteLinkService,
  });

  final AuthRepository authRepository;
  final GroupInviteLinkService inviteLinkService;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthCubit(authRepository: authRepository),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LotoGroup',
        themeMode: ThemeMode.system,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: _AuthGate(
          authRepository: authRepository,
          inviteLinkService: inviteLinkService,
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFE91E63),
      brightness: brightness,
      surface: isDark ? const Color(0xFF17171B) : const Color(0xFFF8F3F7),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF2B2B33) : Colors.black87,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor:
            isDark ? const Color(0xFF2D1C26) : const Color(0xFFF3B7CC),
        foregroundColor: isDark ? Colors.white : Colors.black,
        titleTextStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 30,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

Future<FirebaseApp> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) {
    return Firebase.app();
  }

  try {
    return await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (error) {
    if (error.code == 'duplicate-app' && Firebase.apps.isNotEmpty) {
      return Firebase.app();
    }
    rethrow;
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate({
    required this.authRepository,
    required this.inviteLinkService,
  });

  final AuthRepository authRepository;
  final GroupInviteLinkService inviteLinkService;

  bool get _wantsOperatorConsole {
    if (!kIsWeb) {
      return false;
    }

    final Uri uri = Uri.base;
    return uri.queryParameters['operator'] == '1' ||
        uri.pathSegments.contains('operator');
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        switch (state.status) {
          case AuthStatus.loading:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case AuthStatus.authenticated:
            if (_wantsOperatorConsole) {
              if (state.user!.operatorAccess) {
                return OperatorConsolePage(user: state.user!);
              }
              return const _OperatorAccessDeniedPage();
            }
            return MainShellPage(
              user: state.user!,
              authRepository: authRepository,
              inviteLinkService: inviteLinkService,
            );
          case AuthStatus.failure:
          case AuthStatus.unauthenticated:
            return _wantsOperatorConsole
                ? const OperatorSignInPage()
                : const SignInPage();
        }
      },
    );
  }
}

class _OperatorAccessDeniedPage extends StatelessWidget {
  const _OperatorAccessDeniedPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Operator console access is restricted to operator accounts.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
