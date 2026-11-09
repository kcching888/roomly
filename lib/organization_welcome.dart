import 'package:flutter/material.dart';

import 'roomly_logo.dart';
import 'roomly_customization.dart';

class OrganizationWelcome extends StatelessWidget {
  const OrganizationWelcome({
    super.key,
    required this.organizationName,
    required this.onSignIn,
    required this.onCreateAccount,
    required this.onRetry,
    this.organizationId,
    this.error,
    this.photoAsset,
    this.showCreateAccount = false,
  });

  final String organizationName;
  final VoidCallback onSignIn;
  final VoidCallback onCreateAccount;
  final VoidCallback onRetry;
  final String? organizationId;
  final String? error;
  final String? photoAsset;
  final bool showCreateAccount;

  static const teal = Color(0xFF01696F);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 104,
        backgroundColor: colors.surface,
        title: RmBrandTitle(
          organizationId: organizationId,
        ),
      ),
      body: LayoutBuilder(
        builder: (context, viewport) {
          final wide = viewport.maxWidth >= 900;
          final padding = wide ? 48.0 : 24.0;

          final introduction = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  'YOUR COMMUNITY. YOUR SPACE.',
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'A place to meet.\nSpace to connect.',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: wide ? 52 : 36,
                  fontWeight: FontWeight.w700,
                  height: 1.12,
                  letterSpacing: -1.3,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Welcome to $organizationName',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Sign in to find a room for your next meeting, '
                'workshop or gathering—and manage your bookings '
                'in one place.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 30),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: onSignIn,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Sign in'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 20,
                      ),
                    ),
                  ),
                  if (showCreateAccount)
                    OutlinedButton(
                      onPressed: onCreateAccount,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 20,
                        ),
                      ),
                      child: const Text('Create an account'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            Text(
  showCreateAccount
      ? 'New here? Create an account to get started.\n'
          'Organization membership may require approval.'
      : 'Sign in with your existing account.\n'
          'For access, contact your organization administrator.',
  style: theme.textTheme.bodySmall?.copyWith(
    color: colors.onSurfaceVariant,
    height: 1.6,
  ),
),
              if (error != null) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        error!,
                        style: TextStyle(
                          color: colors.onErrorContainer,
                        ),
                      ),
                      TextButton(
                        onPressed: onRetry,
                        child: const Text('Refresh page'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );

          final visual = ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: SizedBox(
              height: wide ? 500 : 280,
              width: double.infinity,
              child: photoAsset == null
                  ? _graphic()
                  : Image.asset(
                      photoAsset!,
                      fit: BoxFit.cover,
                      semanticLabel:
                          'A room at $organizationName',
                      errorBuilder: (_, __, ___) => _graphic(),
                    ),
            ),
          );

          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: viewport.maxHeight,
              ),
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1160),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (wide)
                          Row(
                            children: [
                              Expanded(child: introduction),
                              const SizedBox(width: 64),
                              Expanded(child: visual),
                            ],
                          )
                        else ...[
                          introduction,
                          const SizedBox(height: 32),
                          visual,
                        ],
                        const SizedBox(height: 36),
                        Text(
                          'Room booking, made simple. Powered by Roomly.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _graphic() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF01494E),
            Color(0xFF087D82),
            Color(0xFF54A49B),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -65,
            right: -55,
            child: _circle(240),
          ),
          Positioned(
            bottom: -90,
            left: -70,
            child: _circle(300),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
              child: const Icon(
                Icons.diversity_3_outlined,
                size: 90,
                color: Colors.white,
              ),
            ),
          ),
          const Positioned(
            left: 28,
            right: 28,
            bottom: 28,
            child: Text(
              'Bring people together.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
      ),
    );
  }
}