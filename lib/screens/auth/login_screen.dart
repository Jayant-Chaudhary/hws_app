import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../core/theme.dart';
import '../../providers/app_providers.dart';
import '../../models/user_model.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.primarySapphire, Color(0xFF001F3F)],
              ),
            ),
          ),
          // Floating Glows
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accentNeonCyan.withOpacity(0.1),
              ),
            ),
          ),
          // Content
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Container(
                padding: const EdgeInsets.all(30),
                decoration: glassDecoration(opacity: 0.15),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      FontAwesomeIcons.suitcaseRolling,
                      size: 80,
                      color: AppTheme.accentNeonCyan,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Smart Bag",
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: AppTheme.accentNeonCyan,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Secure your journey.",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    _buildLoginButton(
                      context,
                      "Connect with Google",
                      FontAwesomeIcons.google,
                      AppTheme.accentNeonCyan,
                      () => _handleLogin(ref),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      "Secure, unified access for all tasks.",
                      style: TextStyle(fontSize: 12, color: AppTheme.textDim),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.1),
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.5)),
          elevation: 0,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }

  void _handleLogin(WidgetRef ref) async {
    final authService = ref.read(authServiceProvider);
    await authService.signInWithGoogle();
  }
}
