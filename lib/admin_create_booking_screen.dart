import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_service.dart';
import 'roomly_logo.dart';
import 'roomly_customization.dart';

class AdminCreateBookingScreen extends StatefulWidget {
  const AdminCreateBookingScreen({
    super.key,
    required this.organizationId,
    required this.rooms,
    required this.initialRoomId,
    required this.initialStart,
  });

  final String organizationId;
  final List<Map<String, dynamic>> rooms;
  final String initialRoomId;
  final DateTime initialStart;

  @override
  State<AdminCreateBookingScreen> createState() =>
      _AdminCreateBookingScreenState();
}

class _AdminCreateBookingScreenState
    extends State<AdminCreateBookingScreen> {
  late final AdminService _adminService;

  final _titleController = TextEditingController();
  final _customerSearchController = TextEditingController();

String? _selectedCustomerId;
String? _selectedCustomerEmail;

List<Map<String, dynamic>> _customerResults = [];

bool _searchingCustomers = false;
String? _customerSearchError;
int _customerSearchRequest = 0;

  final _attendeesController = TextEditingController(text: '2');

  late String _selectedRoomId;
  late DateTime _startsAt;
  late DateTime _endsAt;

  String _status = 'confirmed';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _adminService = AdminService(Supabase.instance.client);

    _selectedRoomId = widget.initialRoomId;
    _startsAt = widget.initialStart;
    _endsAt = widget.initialStart.add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _customerSearchController.dispose();
    _attendeesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startsAt,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date == null) return;

    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        _startsAt.hour,
        _startsAt.minute,
      );

      _endsAt = DateTime(
        date.year,
        date.month,
        date.day,
        _endsAt.hour,
        _endsAt.minute,
      );
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final initial = isStart ? _startsAt : _endsAt;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null) return;

    final newValue = DateTime(
      initial.year,
      initial.month,
      initial.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStart) {
        _startsAt = newValue;

        if (!_endsAt.isAfter(_startsAt)) {
          _endsAt = _startsAt.add(const Duration(hours: 1));
        }
      } else {
        _endsAt = newValue;
      }
    });
  }

void _customerSearchChanged(String value) {
  // Invalidate any response from an earlier search.
  _customerSearchRequest++;

  setState(() {
    _selectedCustomerId = null;
    _selectedCustomerEmail = null;
    _customerResults = [];
    _customerSearchError = null;
    _searchingCustomers = false;
  });
}

Future<void> _searchCustomers() async {
  final search = _customerSearchController.text.trim();

  if (search.length < 2) {
    setState(() {
      _customerSearchError =
          'Enter at least two characters of an email address.';
      _customerResults = [];
    });
    return;
  }

  final request = ++_customerSearchRequest;

  setState(() {
    _searchingCustomers = true;
    _customerSearchError = null;
    _customerResults = [];
  });

  try {
    final results = await _adminService.searchCustomers(
      organizationId: widget.organizationId,
      search: search,
    );

    if (!mounted || request != _customerSearchRequest) return;

    setState(() {
      _customerResults = results;
      _searchingCustomers = false;

      if (results.isEmpty) {
        _customerSearchError =
            'No matching organization members found.';
      }
    });
  } catch (error) {
    if (!mounted || request != _customerSearchRequest) return;

    setState(() {
      _searchingCustomers = false;
      _customerSearchError = error is PostgrestException
          ? error.message
          : error.toString();
    });
  }
}

void _selectCustomer(Map<String, dynamic> customer) {
  _customerSearchRequest++;

  final email = customer['email'] as String;

  setState(() {
    _selectedCustomerId = customer['user_id'] as String;
    _selectedCustomerEmail = email;
    _customerSearchController.text = email;
    _customerResults = [];
    _customerSearchError = null;
    _searchingCustomers = false;
    _error = null;
  });

  FocusScope.of(context).unfocus();
}

Widget _customerPicker() {
  final scheme = Theme.of(context).colorScheme;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: _customerSearchController,
        enabled: !_saving,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.search,
        onChanged: _customerSearchChanged,
        onSubmitted: (_) {
          if (!_saving && !_searchingCustomers) {
            _searchCustomers();
          }
        },
        decoration: InputDecoration(
          labelText: 'Customer',
          hintText: 'Search by email',
          helperText:
              'Search, then select an organization member below.',
          border: const OutlineInputBorder(),
          suffixIcon: _searchingCustomers
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                )
              : IconButton(
                  tooltip: 'Search customers',
                  onPressed: _saving ? null : _searchCustomers,
                  icon: const Icon(Icons.search),
                ),
        ),
      ),

      if (_customerSearchError != null) ...[
        const SizedBox(height: 8),
        Text(
          _customerSearchError!,
          style: TextStyle(color: scheme.error),
        ),
      ],

      if (_customerResults.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            border: Border.all(
              color: scheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _customerResults.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1),
            itemBuilder: (context, index) {
              final customer = _customerResults[index];

              return ListTile(
                dense: true,
                enabled: !_saving,
                leading: const Icon(Icons.person_outline),
                title: Text(
                  customer['email'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _saving
                    ? null
                    : () => _selectCustomer(customer),
              );
            },
          ),
        ),
      ],

      if (_selectedCustomerId != null) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 18,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Selected: $_selectedCustomerEmail',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    ],
  );
}


  Future<void> _createBooking() async {
    final title = _titleController.text.trim();
    final customerId = _selectedCustomerId;
    final attendees = int.tryParse(_attendeesController.text.trim());

    if (title.isEmpty) {
      setState(() => _error = 'Enter a booking title.');
      return;
    }

   if (customerId == null || customerId.isEmpty) {
  setState(() {
    _error = 'Search for and select a customer first.';
  });
  return;
}

    if (attendees == null || attendees < 1) {
      setState(() => _error = 'Enter a valid attendee count.');
      return;
    }

    if (!_endsAt.isAfter(_startsAt)) {
      setState(() => _error = 'End time must be after start time.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _adminService.adminCreateBooking(
        organizationId: widget.organizationId,
        roomId: _selectedRoomId,
        userId: customerId,
        title: title,
        startsAt: _startsAt,
        endsAt: _endsAt,
        attendees: attendees,
        status: _status,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking created.'),
        ),
      );

      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: RmBrandTitle(
          organizationId: widget.organizationId,
          title: 'Create booking'
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedRoomId,
            decoration: const InputDecoration(
              labelText: 'Room',
              border: OutlineInputBorder(),
            ),
       items: widget.rooms.map((room) {
  final roomId = (room['room_id'] ?? room['id']) as String;
  final roomName =
      (room['room_name'] ?? room['name']) as String;

  return DropdownMenuItem<String>(
    value: roomId,
    child: Text(roomName),
  );
}).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedRoomId = value);
              }
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Booking title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
        _customerPicker(),
          const SizedBox(height: 16),
          TextField(
            controller: _attendeesController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Attendees',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    DateFormat('EEE, MMM d').format(_startsAt),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(isStart: true),
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    'Start: ${DateFormat.jm().format(_startsAt)}',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickTime(isStart: false),
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    'End: ${DateFormat.jm().format(_endsAt)}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'confirmed',
                child: Text('Confirmed'),
              ),
              DropdownMenuItem(
                value: 'pending',
                child: Text('Pending'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _status = value);
              }
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _createBooking,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.add),
            label: const Text('Create booking'),
          ),
        ],
      ),
    );
  }
}