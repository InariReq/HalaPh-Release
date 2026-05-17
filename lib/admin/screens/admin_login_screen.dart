import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_auth_service.dart';
import '../widgets/admin_ui.dart';

class AdminLoginScreen extends StatefulWidget {
  final AdminAuthService authService;

  const AdminLoginScreen({super.key, required this.authService});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message ?? 'Admin sign in failed.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Admin sign in failed. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 860;
                  final brandPanel = Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1220),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.route_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'HalaPH Admin',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'A focused console for routes, content, campaigns, and trust operations.',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.72),
                                  ),
                        ),
                        const SizedBox(height: 28),
                        const _LoginValue(
                          icon: Icons.shield_rounded,
                          title: 'Role-aware',
                          body:
                              'Every page respects the permissions already in Firestore.',
                        ),
                        const SizedBox(height: 14),
                        const _LoginValue(
                          icon: Icons.route_rounded,
                          title: 'Operations-first',
                          body:
                              'Routes, reports, ads, and content stay close at hand.',
                        ),
                      ],
                    ),
                  );
                  final formPanel = ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: AdminDataCard(
                      padding: const EdgeInsets.all(26),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Sign in',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Use an active Firebase admin account.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 22),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_rounded),
                              ),
                              validator: (value) {
                                final text = value?.trim() ?? '';
                                if (!text.contains('@')) {
                                  return 'Enter a valid email address.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock_rounded),
                              ),
                              validator: (value) {
                                if ((value ?? '').isEmpty) {
                                  return 'Enter your password.';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) => _signIn(),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              AdminErrorState(
                                title: 'Sign in failed',
                                message: _error!,
                              ),
                            ],
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _loading ? null : _signIn,
                                icon: _loading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.login_rounded),
                                label: const Text('Sign in'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );

                  if (stacked) {
                    return Column(
                      children: [
                        brandPanel,
                        const SizedBox(height: 16),
                        Center(child: formPanel),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: brandPanel),
                      const SizedBox(width: 24),
                      formPanel,
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

class _LoginValue extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _LoginValue({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.88), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.68),
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
