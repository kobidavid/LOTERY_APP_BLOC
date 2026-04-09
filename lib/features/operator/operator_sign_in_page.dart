import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/auth_cubit.dart';
import '../auth/auth_state.dart';

class OperatorSignInPage extends StatelessWidget {
  const OperatorSignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthCubit authCubit = context.read<AuthCubit>();
    return Scaffold(
      backgroundColor: const Color(0xFF11141B),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: BlocBuilder<AuthCubit, AuthState>(
                builder: (context, state) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2B3443),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'OPERATOR MODE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Operator Console',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Sign in with an operator-enabled account to access dispatch overview and the receipt intake queue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.45,
                          color: Color(0xFFD4D9E1),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F29),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFF324055),
                          ),
                        ),
                        child: const Text(
                          'This is a separate admin surface. Consumer users should continue using the main app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFB5BECC),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF3B7CC),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        onPressed:
                            state.isBusy ? null : authCubit.signInWithGoogle,
                        icon: const Icon(Icons.admin_panel_settings_outlined),
                        label: const Text(
                          'Sign in to Operator Console',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (state.isBusy) ...[
                        const SizedBox(height: 18),
                        const Center(child: CircularProgressIndicator()),
                      ],
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: 18),
                        Text(
                          state.errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFFB4B4),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
