import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'platform_organizations_screen.dart';
import 'roomly_customization.dart';

/// Use this widget for the /platform route instead of opening the dashboard directly.
class PlatformAccessGate extends StatefulWidget {
  const PlatformAccessGate({super.key});
  @override
  State<PlatformAccessGate> createState() => _PlatformAccessGateState();
}

class _PlatformAccessGateState extends State<PlatformAccessGate> {
  final _db = Supabase.instance.client;
  StreamSubscription<AuthState>? _subscription;
  bool _checking = true;
  bool _allowed = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _subscription = _db.auth.onAuthStateChange.listen(
      (_) { _check(); },
      onError: (Object error, StackTrace stack) {
        if (!mounted) return;
        _request++;
        setState(() {
          _checking = false;
          _allowed = false;
          _error = 'Unable to restore your session. Please try again.';
        });
      },
    );
    _check();
  }

  Future<void> _check() async {
    final request = ++_request;
    final userId = _db.auth.currentSession?.user.id;
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _allowed = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _checking = true;
      _allowed = false;
      _error = null;
    });
    try {
      final result = await _db.rpc('rm_is_system_admin');
      if (!mounted || request != _request ||
          _db.auth.currentSession?.user.id != userId) return;
      setState(() {
        _allowed = result == true;
        _checking = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _checking = false;
        _allowed = false;
        _error = 'Unable to verify platform access. Please try again.';
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await _db.auth.signOut(scope: SignOutScope.local);
      if (mounted) await _check();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to sign out. Please try again.')),
      );
    }
  }

  @override
  void dispose() {
    _request++;
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_db.auth.currentSession == null) {
      return const _PlatformSignIn();
    }
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_allowed) return const PlatformOrganizationsScreen();
    return Scaffold(
      appBar: AppBar(title: const RmBrandTitle(title: 'Platform access')),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.admin_panel_settings_outlined, size: 56),
            const SizedBox(height: 20),
            Text(_error == null ? 'Platform administrator access required'
              : 'Unable to check access',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(_error ?? 'This account does not have platform administrator access. '
              'Sign out and use your authorized administrator account.',
              textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center,
              children: [
                if (_error != null) OutlinedButton(onPressed: _check,
                  child: const Text('Try again')),
                FilledButton(onPressed: _signOut,
                  child: const Text('Sign out / switch account')),
              ]),
          ]),
        ),
      )),
    );
  }
}

class _PlatformSignIn extends StatefulWidget {
  const _PlatformSignIn();
  @override
  State<_PlatformSignIn> createState() => _PlatformSignInState();
}

class _PlatformSignInState extends State<_PlatformSignIn> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(), password: _password.text,
      );
      // The gate listens for sign-in, then verifies platform privileges.
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error =
        'Unable to sign in. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const RmBrandTitle()),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
        child: Card(child: Padding(padding: const EdgeInsets.all(28),
          child: Form(key: _form, child: AutofillGroup(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings_outlined, size: 48),
              const SizedBox(height: 20),
              Text('Platform administrator sign in',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text('Sign in with your authorized Roomly administrator account.',
                textAlign: TextAlign.center),
              const SizedBox(height: 28),
              TextFormField(controller: _email, enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email address'),
                validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Enter your email address.' : null),
              const SizedBox(height: 16),
              TextFormField(controller: _password, enabled: !_busy,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(labelText: 'Password',
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined))),
                validator: (value) => (value ?? '').isEmpty
                  ? 'Enter your password.' : null),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 16),
                child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))),
              const SizedBox(height: 24),
              FilledButton(onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Signing in…' : 'Sign in')),
            ],
          ))),
        )),
      ),
    )),
  );
}
