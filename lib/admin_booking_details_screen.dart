import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_service.dart';
import 'roomly_logo.dart';

class AdminBookingDetailsScreen extends StatefulWidget {
  const AdminBookingDetailsScreen({
    super.key,
    required this.organizationId,
    required this.booking,
    required this.rooms,
  });

  final String organizationId;
  final Map<String, dynamic> booking;
  final List<Map<String, dynamic>> rooms;

  @override
  State<AdminBookingDetailsScreen> createState() =>
      _AdminBookingDetailsScreenState();
}

class _AdminBookingDetailsScreenState
    extends State<AdminBookingDetailsScreen> {
  late final AdminService _adminService;

  late final TextEditingController _titleController;
  late final TextEditingController _attendeesController;

  late String _selectedRoomId;
  late String _selectedStatus;
  late DateTime _startsAt;
  late DateTime _endsAt;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _adminService = AdminService(Supabase.instance.client);

    final booking = widget.booking;

    _titleController =
        TextEditingController(text: booking['booking_title'] as String);

    _attendeesController = TextEditingController(
      text: (booking['attendees'] as num).toString(),
    );

    _selectedRoomId = booking['room_id'] as String;
    _selectedStatus = booking['booking_status'] as String;

    _startsAt =
        DateTime.parse(booking['booking_starts_at'] as String).toLocal();

    _endsAt =
        DateTime.parse(booking['booking_ends_at'] as String).toLocal();
  }

  @override
  void dispose() {
    _titleController.dispose();
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

  Future<void> _saveChanges() async {
    final title = _titleController.text.trim();
    final attendees = int.tryParse(_attendeesController.text.trim());

    if (title.isEmpty) {
      setState(() => _error = 'Enter a booking title.');
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
      await _adminService.adminUpdateBooking(
        organizationId: widget.organizationId,
        bookingId: widget.booking['booking_id'] as String,
        roomId: _selectedRoomId,
        title: title,
        startsAt: _startsAt,
        endsAt: _endsAt,
        attendees: attendees,
        status: _selectedStatus,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking updated.')),
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
        title: const RoomlyPageTitle(
          title: 'Booking details',
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
            items: widget.rooms
                .map(
                  (room) => DropdownMenuItem(
                    value: room['room_id'] as String,
                    child: Text(room['room_name'] as String),
                  ),
                )
                .toList(),
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
            initialValue: _selectedStatus,
            decoration: const InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'pending',
                child: Text('Pending'),
              ),
              DropdownMenuItem(
                value: 'confirmed',
                child: Text('Confirmed'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedStatus = value);
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
            onPressed: _saving ? null : _saveChanges,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}