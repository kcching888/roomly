import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'roomly_logo.dart';

typedef MemberRow = Map<String, dynamic>;
typedef RequestRow = Map<String, dynamic>;

String _memberError(Object error) {
  if (error is PostgrestException) return error.message;
  return 'Unable to complete the request. Please try again.';
}

class AdminMembersScreen extends StatefulWidget {
  const AdminMembersScreen({
    super.key,
    required this.organizationId,
    required this.organizationName,
  });

  final String organizationId;
  final String organizationName;

  @override
  State<AdminMembersScreen> createState() => _AdminMembersScreenState();
}

class _AdminMembersScreenState extends State<AdminMembersScreen> {
  final _search = TextEditingController();

  List<MemberRow> _members = [];
  List<RequestRow> _requests = [];

  bool _loading = true;
  bool _busy = false;
  bool _showRequests = false;

  String? _error;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final members = await _db.rpc(
        'rm_admin_list_members',
        params: {'p_organization_id': widget.organizationId},
      );

      final requests = await _db.rpc(
        'rm_admin_list_membership_requests',
        params: {'p_organization_id': widget.organizationId},
      );

      if (!mounted) return;

      setState(() {
        _members = (members as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        _requests = (requests as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = _memberError(error);
      });
    }
  }

  Future<void> _add() async {
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddMemberForm(
        organizationId: widget.organizationId,
        organizationName: widget.organizationName,
      ),
    );

    if (!mounted || message == null) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

    await _load();
  }

  Future<void> _remove(MemberRow member) async {
    final email = member['email'] as String? ?? '';
    final name = member['full_name'] as String? ?? '';
    final userId = member['user_id'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove organization membership?'),
        content: Text(
          'Organization: ${widget.organizationName}\n'
          'Name: $name\n'
          'Email: $email\n'
          'User ID: $userId\n\n'
          'This removes only this organization membership. '
          'The account, other memberships, and existing bookings '
          'are unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove membership'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _db.rpc(
        'rm_admin_remove_member',
        params: {
          'p_organization_id': widget.organizationId,
          'p_user_id': userId,
        },
      );

      if (!mounted) return;

      setState(() => _busy = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Membership removed. Existing bookings were not cancelled.',
          ),
        ),
      );

      await _load();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _error = _memberError(error);
      });
    }
  }

  Future<void> _review(RequestRow request, bool approve) async {
    final userId = request['user_id'] as String;
    final email = request['email'] as String? ?? '';
    final name = request['full_name'] as String? ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve request?' : 'Reject request?'),
        content: Text(
          'Organization: ${widget.organizationName}\n'
          'Name: $name\n'
          'Email: $email\n\n'
          '${approve ? "This grants ordinary member access to this organization. It does not grant administrator access." : "This rejects the pending membership request. The account is not deleted and the person may submit a new request later."}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _db.rpc(
        'rm_admin_review_membership_request',
        params: {
          'p_organization_id': widget.organizationId,
          'p_user_id': userId,
          'p_approve': approve,
        },
      );

      if (!mounted) return;

      setState(() => _busy = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'Membership request approved.'
                : 'Membership request rejected.',
          ),
        ),
      );

      await _load();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _error = _memberError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final term = _search.text.trim().toLowerCase();

    final visibleMembers = _members
        .where(
          (member) =>
              '${member['full_name'] ?? ''} '
                      '${member['email'] ?? ''} '
                      '${member['contact_phone'] ?? ''}'
                  .toLowerCase()
                  .contains(term),
        )
        .toList();

    final visibleRequests = _requests
        .where(
          (request) =>
              '${request['full_name'] ?? ''} '
                      '${request['email'] ?? ''} '
                      '${request['contact_phone'] ?? ''}'
                  .toLowerCase()
                  .contains(term),
        )
        .toList();

    final memberCount = _members
        .where((member) => member['role'] == 'member')
        .length;
    final adminCount = _members
        .where((member) => member['role'] == 'admin')
        .length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: RoomlyPageTitle(
            title: 'Members · ${widget.organizationName}',
          ),
        
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading || _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Members', icon: const Icon(Icons.group_outlined)),
              Tab(
                text: 'Requests (${_requests.length})',
                icon: const Icon(Icons.pending_actions_outlined),
              ),
            ],
          ),
        ),
        floatingActionButton: !_showRequests
            ? FloatingActionButton.extended(
                onPressed: _loading || _busy ? null : _add,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add member'),
              )
            : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_busy) const LinearProgressIndicator(),

                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _showRequests
                              ? '${_requests.length} pending requests'
                              : '$memberCount members · '
                                    '$adminCount administrators',
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Search name, email, or phone',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Names and contact phones are supplied by users '
                          'and are not verified contact details.',
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          SelectableText(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _load,
                            child: const Text('Reload list'),
                          ),
                        ],
                      ],
                    ),
                  ),

                  Expanded(
                    child: TabBarView(
                      children: [
                        _membersView(visibleMembers),
                        _requestsView(visibleRequests),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _membersView(List<MemberRow> visible) {
    if (visible.isEmpty) {
      return Center(
        child: Text(
          _error != null
              ? 'The member list could not be loaded.'
              : _members.isEmpty
              ? 'No memberships yet.'
              : 'No matching members.',
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _showRequests = false;
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final member = visible[index];
          final isAdmin = member['role'] == 'admin';
          final name = (member['full_name'] as String? ?? '').trim();
          final email = member['email'] as String? ?? 'No email';
          final phone = (member['contact_phone'] as String? ?? '').trim();

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? email : name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText('Email: $email'),
                  SelectableText(
                    'Phone: ${phone.isEmpty ? 'Not provided' : phone}',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: Text(
                          isAdmin ? 'Administrator' : '${member['role']}',
                        ),
                      ),
                      if (member['role'] == 'member')
                        TextButton.icon(
                          onPressed: _busy ? null : () => _remove(member),
                          icon: const Icon(Icons.person_remove_outlined),
                          label: const Text('Remove membership'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _requestsView(List<RequestRow> visible) {
    if (visible.isEmpty) {
      return Center(
        child: Text(
          _error != null
              ? 'Pending requests could not be loaded.'
              : _requests.isEmpty
              ? 'No pending membership requests.'
              : 'No matching requests.',
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _showRequests = true;
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final request = visible[index];
          final name = (request['full_name'] as String? ?? '').trim();
          final email = request['email'] as String? ?? 'No email';
          final phone = (request['contact_phone'] as String? ?? '').trim();
          final requestedAt = DateTime.tryParse(
            request['requested_at'] as String? ?? '',
          );

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? email : name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText('Email: $email'),
                  SelectableText(
                    'Phone: ${phone.isEmpty ? 'Not provided' : phone}',
                  ),
                  if (requestedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Requested: '
                      '${DateFormat.yMMMd().add_jm().format(requestedAt.toLocal())}',
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _review(request, true),
                        icon: const Icon(Icons.check),
                        label: const Text('Approve'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _review(request, false),
                        icon: const Icon(Icons.close),
                        label: const Text('Reject'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AddMemberForm extends StatefulWidget {
  const _AddMemberForm({
    required this.organizationId,
    required this.organizationName,
  });

  final String organizationId;
  final String organizationName;

  @override
  State<_AddMemberForm> createState() => _AddMemberFormState();
}

class _AddMemberFormState extends State<_AddMemberForm> {
  final _email = TextEditingController();

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final email = _email.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter an email address.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add member?'),
        content: Text(
          'Organization: ${widget.organizationName}\n'
          'Existing account email: $email\n'
          'Role: Member',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final result = await Supabase.instance.client.rpc(
        'rm_admin_add_member_by_email',
        params: {'p_organization_id': widget.organizationId, 'p_email': email},
      );

      if (!mounted) return;

      Navigator.pop(context, result as String);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = _memberError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Add existing member'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Organization: ${widget.organizationName}'),
              const SizedBox(height: 12),
              const Text(
                'The person must already have a Roomly account. '
                'Existing administrator roles will not be changed.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                enabled: !_saving,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Email'),
                onSubmitted: (_) => _save(),
              ),
              if (_saving) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Adding…' : 'Review'),
          ),
        ],
      ),
    );
  }
}
