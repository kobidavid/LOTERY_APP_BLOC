import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'auth_cubit.dart';
import 'auth_state.dart';

class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthCubit authCubit = context.read<AuthCubit>();
    final bool supportsApple = authCubit.supportsAppleSignIn;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: BlocBuilder<AuthCubit, AuthState>(
                builder: (context, state) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'LotoGroup',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'התחבר כדי לשמור טפסים, לשלוח אותם ולגשת להיסטוריה האישית שלך',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed:
                            state.isBusy ? null : authCubit.signInWithGoogle,
                        icon: const Icon(Icons.login),
                        label: const Text('התחברות עם Google'),
                      ),
                      if (supportsApple) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed:
                              state.isBusy ? null : authCubit.signInWithApple,
                          icon: const Icon(Icons.apple),
                          label: const Text('התחברות עם Apple'),
                        ),
                      ],
                      if (state.isBusy) ...[
                        const SizedBox(height: 18),
                        const Center(child: CircularProgressIndicator()),
                      ],
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: 18),
                        Text(
                          state.errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
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
