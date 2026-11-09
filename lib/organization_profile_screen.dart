import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'roomly_logo.dart';
import 'roomly_customization.dart';
import 'canadian_time_zone_field.dart';

class OrganizationProfileScreen extends StatefulWidget {
  const OrganizationProfileScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  State<OrganizationProfileScreen> createState() =>
      _OrganizationProfileScreenState();
}

class _OrganizationProfileScreenState extends State<OrganizationProfileScreen> {
  final _db = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _website = TextEditingController();
  final _address = TextEditingController();

  String _timezone = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _email.dispose();
    _phone.dispose();
    _website.dispose();
    _address.dispose();
    super.dispose();
  }

  String _errorMessage(Object error) {
    if (error is PostgrestException) return error.message;
    if (error is AuthException) return error.message;

    return 'Unable to complete the request. Please try again.';
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _db.rpc(
        'rm_admin_get_organization_profile',
        params: {'p_organization_id': widget.organizationId},
      );

      final profile = Map<String, dynamic>.from(result as Map);

      if (!mounted) return;

      _name.text = profile['name'] as String;
      _description.text = profile['description'] as String;
      _email.text = profile['contact_email'] as String;
      _phone.text = profile['phone'] as String;
      _website.text = profile['website'] as String;
      _address.text = profile['address'] as String;

      setState(() {
        _timezone = profile['timezone'] as String;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = _errorMessage(error);
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final savedName = _name.text.trim();

      await _db.rpc(
        'rm_admin_update_organization_profile',
        params: {
          'p_organization_id': widget.organizationId,
          'p_name': savedName,
          'p_description': _description.text.trim(),
          'p_contact_email': _email.text.trim(),
          'p_phone': _phone.text.trim(),
          'p_website': _website.text.trim(),
          'p_address': _address.text.trim(),
        },
      );

      if (!mounted) return;

      // Return the saved name so the home screen can update its selector.
      Navigator.pop<String>(context, savedName);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = _errorMessage(error);
      });
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required int limit,
    int lines = 1,
    TextInputType? keyboardType,
    bool requiredField = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        enabled: !_saving,
        maxLength: limit,
        minLines: lines,
        maxLines: lines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          counterText: '',
          alignLabelWithHint: lines > 1,
        ),
        validator: (value) {
          final text = value?.trim() ?? '';

          if (requiredField && text.isEmpty) {
            return 'Enter $label.';
          }

          return null;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: RmBrandTitle(
            organizationId: widget.organizationId,
            title: 'Organization profile',
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _timezone.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error ?? 'Unable to load organization.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _loadProfile,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Organization details',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Update the name and contact information '
                            'for this organization.',
                          ),
                          const SizedBox(height: 24),

                          _field(
                            controller: _name,
                            label: 'Organization name',
                            limit: 200,
                            requiredField: true,
                          ),
                          _field(
                            controller: _description,
                            label: 'Description',
                            limit: 2000,
                            lines: 3,
                          ),
                          _field(
                            controller: _email,
                            label: 'Contact email',
                            limit: 254,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          _field(
                            controller: _phone,
                            label: 'Phone',
                            limit: 100,
                            keyboardType: TextInputType.phone,
                          ),
                          _field(
                            controller: _website,
                            label: 'Website',
                            limit: 500,
                            keyboardType: TextInputType.url,
                          ),
                          _field(
                            controller: _address,
                            label: 'Address',
                            limit: 2000,
                            lines: 3,
                          ),

                          CanadianTimeZoneField(
                            value: _timezone,
                            enabled: false,
                            onChanged: (_) {},
                            helperText:
                                'Managed by the platform administrator. '
                                'Existing bookings keep their stored timestamps.',
                          ),
                          const SizedBox(height: 20),

                          if (_error != null) ...[
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          FilledButton.icon(
                            onPressed: _saving ? null : _saveProfile,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_saving ? 'Saving…' : 'Save profile'),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Photos and branding'),
                            onPressed: () {
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => RmOrganizationMediaScreen(
                                    organizationId: widget.organizationId,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
