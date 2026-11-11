import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef MembershipRow = Map<String, dynamic>;

class MembershipStatus extends StatefulWidget {
  const MembershipStatus({
    super.key,
    required this.userId,
  });

  final String? userId;

  @override
  State<MembershipStatus> createState() =>
      _MembershipStatusState();
}

class _MembershipStatusState extends State<MembershipStatus> {
  late Future<List<MembershipRow>> _memberships;

  @override
  void initState() {
    super.initState();
    _memberships = _loadMemberships();
  }

  @override
  void didUpdateWidget(covariant MembershipStatus oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.userId != widget.userId) {
      _memberships = _loadMemberships();
    }
  }

  Future<List<MembershipRow>> _loadMemberships() async {
    final db = Supabase.instance.client;
    final userId = widget.userId;

    if (userId == null ||
        db.auth.currentSession == null ||
        db.auth.currentUser?.id != userId) {
      return [];
    }

    // Always filter by the current user. Administrators may have
    // permission to read other people's memberships as well.
    final result = await db
        .from('rm_memberships')
        .select('organization_id, role')
        .eq('user_id', userId)
        .order('organization_id');

    final memberships = result
        .map(
          (item) => Map<String, dynamic>.from(item),
        )
        .toList();

    if (memberships.isEmpty) return memberships;

    final organizationIds = memberships
        .map((item) => item['organization_id'] as String)
        .toSet()
        .toList();

    // This query still respects organization visibility policies.
    // An inactive organization may not be readable by the user.
    final organizations = await db
        .from('rm_organizations')
        .select('id, name')
        .inFilter('id', organizationIds);

    final namesById = <String, String>{
      for (final organization in organizations)
        organization['id'] as String:
            organization['name'] as String,
    };

    return memberships.map((membership) {
      return <String, dynamic>{
        ...membership,
        'organization_name':
            namesById[membership['organization_id']],
      };
    }).toList();
  }

  void _refresh() {
    setState(() {
      _memberships = _loadMemberships();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'My organizations',
                    style:
                        Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh memberships',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<MembershipRow>>(
              future: _memberships,
              builder: (context, snapshot) {
                if (snapshot.connectionState !=
                    ConnectionState.done) {
                  return const LinearProgressIndicator();
                }

                if (snapshot.hasError) {
                  final error = snapshot.error;
                  final message = error is PostgrestException
                      ? error.message
                      : 'Could not check your memberships.';

                  return Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  );
                }

                final memberships = snapshot.data ?? [];

                if (memberships.isEmpty) {
                  return const Text(
                    'Your account is signed in, but you do not '
                    'belong to an organization yet.\n\n'
                    'You can browse public organizations, or ask '
                    'an organization administrator about membership.',
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final membership in memberships)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          membership['role'] == 'admin'
                              ? Icons.admin_panel_settings_outlined
                              : Icons.business_outlined,
                        ),
                        title: Text(
                          membership['organization_name'] as String? ??
                              'Organization details unavailable',
                        ),
                        subtitle: Text(
                          membership['role'] == 'admin'
                              ? 'Role: ${membership['role']}\n'
                                  'Organization ID: ${membership['organization_id']}'
                              : 'Role: ${membership['role']}',
                        ),
                        isThreeLine: membership['role'] == 'admin',
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}