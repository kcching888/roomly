import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_rooms_screen.dart';
import 'admin_calendar_screen.dart';

import 'roomly_logo.dart';
import 'roomly_customization.dart';
import 'canadian_time_zone_field.dart';

import 'package:timezone/timezone.dart' as tz;

typedef PlatformRow = Map<String, dynamic>;
SupabaseClient get _db => Supabase.instance.client;

List<PlatformRow> _rows(dynamic value) => (value as List)
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList();

String _message(Object error) => error is PostgrestException
    ? error.message
    : error is AuthException
    ? error.message
    : error.toString();

class PlatformOrganizationsScreen extends StatefulWidget {
  const PlatformOrganizationsScreen({super.key});
  @override
  State<PlatformOrganizationsScreen> createState() =>
      _PlatformOrganizationsScreenState();
}

class _PlatformOrganizationsScreenState
    extends State<PlatformOrganizationsScreen> {
  bool _loading = true;
  String? _error;
  List<PlatformRow> _organizations = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = _rows(await _db.rpc('rm_system_list_organizations'));
      if (!mounted) return;
      setState(() {
        _organizations = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e);
        _loading = false;
      });
    }
  }

  Future<void> _edit([PlatformRow? organization]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OrganizationForm(organization: organization),
    );
    if (!mounted) return;
    if (saved == true) await _load();
  }

  Future<void> _open(PlatformRow organization) async {
    final name = organization['organization_name'] as String;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(name),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    'Organization ID: ${organization['organization_id']}',
                  ),
                  const SizedBox(height: 12),
                  Text('Time zone: ${organization['timezone']}'),
                  Text(
                    'Visibility: ${organization['is_public'] == true ? 'Public' : 'Private'}',
                  ),
                  Text(
                    'Status: ${organization['active'] == true ? 'Active' : 'Inactive'}',
                  ),
                  Text(
                    'Administrators: ${organization['administrator_count']}',
                  ),
                  Text('Members: ${organization['member_count']}'),
                  Text('Active rooms: ${organization['active_room_count']}'),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final item in <String, String>{
                        'rooms': 'Manage rooms',
                        'calendar': 'Booking calendar',
                        'admins': 'Administrators',
                        'settings': 'Organization settings',
                      }.entries)
                        OutlinedButton(
                          onPressed: () {
                            Navigator.pop(dialogContext, item.key);
                          },
                          child: Text(item.value),
                        ),

                      RmSlugButton(
                        organizationId:
                            organization['organization_id'] as String,
                        currentSlug: organization['slug'] as String? ?? '',
                        onSaved: (newSlug) {
                          organization['slug'] = newSlug;
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
    if (!mounted || action == null) return;
    final id = organization['organization_id'] as String;
    if (action == 'settings') {
      await _edit(organization);
      return;
    }
    if (action == 'rooms') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) =>
              AdminRoomsScreen(organizationId: id, organizationName: name),
        ),
      );
    } else if (action == 'calendar') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AdminCalendarScreen(
            organizationId: id,
            organizationName: name,
            timezone: organization['timezone'] as String,
          ),
        ),
      );
    } else if (action == 'admins') {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => _OrganizationAdminsScreen(
            organizationId: id,
            organizationName: name,
          ),
        ),
      );
    }
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const RmBrandTitle(title: 'Platform dashboard'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Add organization'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if (_error != null) ...[
                  SelectableText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ] else if (_organizations.isEmpty)
                  const Text('No organizations yet.'),
                for (final org in _organizations)
                  Card(
                    child: ListTile(
                      title: Text(org['organization_name'] as String),
                      subtitle: Text(
                        '${org['timezone']} • ${org['active'] == true ? 'Active' : 'Inactive'}\n'
                        'Administrators: ${org['administrator_count']} • Members: ${org['member_count']} • '
                        'Active rooms: ${org['active_room_count']}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(org),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _OrganizationForm extends StatefulWidget {
  const _OrganizationForm({this.organization});
  final PlatformRow? organization;
  @override
  State<_OrganizationForm> createState() => _OrganizationFormState();
}

class _OrganizationFormState extends State<_OrganizationForm> {
  late final TextEditingController _name;
  late final TextEditingController _timezone;
  late bool _public;
  late bool _active;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: widget.organization?['organization_name'] as String? ?? '',
    );
    _timezone = TextEditingController(
      text: widget.organization?['timezone'] as String? ?? 'America/Edmonton',
    );
    _public = widget.organization?['is_public'] as bool? ?? true;
    _active = widget.organization?['active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty ||
        _name.text.trim().length > 200 ||
        !tz.timeZoneDatabase.locations.containsKey(_timezone.text.trim())) {
      setState(
        () => _error = 'Enter a name of 1–200 characters and select a supported time zone.',
      );
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Save organization?'),
        content: Text(
          'Name: ${_name.text.trim()}\nTime zone: ${_timezone.text.trim()}\n'
          'Visibility: ${_public ? 'Public' : 'Private'}\nStatus: ${_active ? 'Active' : 'Inactive'}\n\n'
          'Existing bookings are not cancelled by changing visibility or active status.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _db.rpc(
        'rm_system_save_organization',
        params: {
          'p_organization_id': widget.organization?['organization_id'],
          'p_name': _name.text.trim(),
          'p_timezone': _timezone.text.trim(),
          'p_is_public': _public,
          'p_active': _active,
        },
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _message(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(
        widget.organization == null
            ? 'Create organization'
            : 'Organization settings',
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                enabled: !_saving,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Organization name',
                ),
              ),
              const SizedBox(height: 12),
              CanadianTimeZoneField(
                value: _timezone.text.isEmpty ? null : _timezone.text,
                enabled: !_saving,
                onChanged: (zone) => setState(() => _timezone.text = zone),
              ),
              const SizedBox(height: 8),
              const Text(
                'Time zone changes are blocked once the organization has bookings.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Public organization'),
                value: _public,
                onChanged: _saving ? null : (v) => setState(() => _public = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active organization'),
                value: _active,
                onChanged: _saving ? null : (v) => setState(() => _active = v),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}

class _OrganizationAdminsScreen extends StatefulWidget {
  const _OrganizationAdminsScreen({
    required this.organizationId,
    required this.organizationName,
  });
  final String organizationId;
  final String organizationName;
  @override
  State<_OrganizationAdminsScreen> createState() =>
      _OrganizationAdminsScreenState();
}

class _OrganizationAdminsScreenState extends State<_OrganizationAdminsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<PlatformRow> _admins = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = _rows(
        await _db.rpc(
          'rm_system_list_organization_admins',
          params: {'p_organization_id': widget.organizationId},
        ),
      );
      if (!mounted) return;
      setState(() {
        _admins = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  Future<void> _grant() async {
    final user = await showDialog<PlatformRow>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _UserEmailDialog(),
    );

    if (!mounted || user == null) return;

    await _change(user['user_id'] as String, true, user['email'] as String);
  }

  Future<void> _change(String userId, bool makeAdmin, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          makeAdmin
              ? 'Grant administrator access?'
              : 'Revoke administrator access?',
        ),
        content: Text(
          '${widget.organizationName}\nUser: $label\nUUID: $userId\n\n'
          '${makeAdmin ? 'This existing Auth account will become an organization administrator.' : 'The user will remain a member. System-admin access, if any, is unchanged.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _db.rpc(
        'rm_system_set_organization_admin',
        params: {
          'p_organization_id': widget.organizationId,
          'p_user_id': userId,
          'p_make_admin': makeAdmin,
        },
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _message(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: RoomlyPageTitle(
        title: 'Administrators · ${widget.organizationName}',
      ),
      actions: [
        IconButton(
          onPressed: _loading || _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _loading || _busy ? null : _grant,
      icon: const Icon(Icons.person_add_outlined),
      label: const Text('Grant access'),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                SelectableText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Grant access using an existing user’s email address. '
                  'Revoking demotes the user to member. '
                  'The last organization administrator cannot be revoked.',
                ),
              ),
              if (_admins.isEmpty && _error == null)
                const Text('No organization administrators yet.'),
              for (final admin in _admins)
                Card(
                  child: ListTile(
                    title: Text(admin['email'] as String? ?? 'No email'),
                    subtitle: SelectableText(admin['user_id'] as String),
                    trailing: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _change(
                              admin['user_id'] as String,
                              false,
                              admin['email'] as String? ?? 'No email',
                            ),
                      child: const Text('Revoke'),
                    ),
                  ),
                ),
            ],
          ),
  );
}

class _UserEmailDialog extends StatefulWidget {
  const _UserEmailDialog();

  @override
  State<_UserEmailDialog> createState() => _UserEmailDialogState();
}

class _UserEmailDialogState extends State<_UserEmailDialog> {
  final _email = TextEditingController();

  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _findUser() async {
    if (_searching) return;

    final email = _email.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _error = 'Enter the user’s email address.';
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final result = await _db.rpc(
        'rm_system_find_user_by_email',
        params: {'p_email': email},
      );

      final user = Map<String, dynamic>.from(result as Map);

      if (!mounted) return;

      Navigator.pop(context, user);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _searching = false;
        _error = _message(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_searching,
      child: AlertDialog(
        title: const Text('Grant organization-admin access'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the email address of an existing '
                'Roomly account. You will review the '
                'account before granting access.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                enabled: !_searching,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'User email',
                  hintText: 'person@example.com',
                ),
                onSubmitted: (_) => _findUser(),
              ),
              if (_searching) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _searching ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _searching ? null : _findUser,
            child: Text(_searching ? 'Looking up…' : 'Find account'),
          ),
        ],
      ),
    );
  }
}
