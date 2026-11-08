import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<bool?> showAddMemberDialog({
  required BuildContext context,
  required String organizationId,
  required String organizationName,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AddMemberDialog(
      organizationId: organizationId,
      organizationName: organizationName,
    ),
  );
}

class _AddMemberDialog extends StatefulWidget {
  const _AddMemberDialog({
    required this.organizationId,
    required this.organizationName,
  });

  final String organizationId;
  final String organizationName;

  @override
  State<_AddMemberDialog> createState() =>
      _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _email = TextEditingController();

  bool _saving = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    if (_saving || _notice != null) return;

    final email = _email.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = 'Enter the person’s email address.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Grant organization membership?'),
        content: Text(
          'Organization: ${widget.organizationName}\n'
          'Email: $email\n'
          'Role: Member\n\n'
          'This grants membership to the existing account '
          'registered with this email. It does not grant '
          'administrator access.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Add member'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final result = await Supabase.instance.client.rpc(
        'rm_admin_add_member_by_email',
        params: {
          'p_organization_id': widget.organizationId,
          'p_email': email,
        },
      );

      if (!mounted) return;

      setState(() {
        _saving = false;
        _notice = result as String;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = error is PostgrestException
            ? error.message
            : 'Could not add the member. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = _notice != null;

    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(
          'Add member · ${widget.organizationName}',
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the email of an existing Roomly '
                  'account. The person must register first '
                  'if they do not already have an account.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  enabled: !_saving && !completed,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Member email',
                    hintText: 'person@example.com',
                  ),
                  onSubmitted: (_) => _addMember(),
                ),
                if (_saving) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: 12),
                  Text(_notice!),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () {
                    Navigator.pop(context, completed);
                  },
            child: Text(completed ? 'Done' : 'Cancel'),
          ),
          if (!completed)
            FilledButton(
              onPressed: _saving ? null : _addMember,
              child: Text(
                _saving ? 'Adding…' : 'Review membership',
              ),
            ),
        ],
      ),
    );
  }
}