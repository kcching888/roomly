import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_service.dart';

class AdminRoomsScreen extends StatefulWidget {
  const AdminRoomsScreen({
    super.key,
    required this.organizationId,
    required this.organizationName,
  });

  final String organizationId;
  final String organizationName;

  @override
  State<AdminRoomsScreen> createState() => _AdminRoomsScreenState();
}

class _AdminRoomsScreenState extends State<AdminRoomsScreen> {
  late final AdminService _adminService;

  List<AdminRow> _rooms = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _adminService = AdminService(Supabase.instance.client);
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rooms = await _adminService.listRooms(
        widget.organizationId,
      );

      if (!mounted) return;

      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openRoomForm([AdminRow? room]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RoomFormDialog(
        organizationId: widget.organizationId,
        existingRoom: room,
      ),
    );

    if (saved == true) {
      await _loadRooms();
    }
  }

  Future<void> _toggleActive(AdminRow room) async {
    final active = room['active'] != true;
    final action = active ? 'reactivate' : 'deactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${active ? 'Reactivate' : 'Deactivate'} room?'),
        content: Text(
          'Do you want to $action "${room['name']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(active ? 'Reactivate' : 'Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _adminService.setRoomActive(
        roomId: room['id'] as String,
        active: active,
      );

      if (!mounted) return;

      setState(() => _saving = false);
      await _loadRooms();
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
        title: Text('Rooms · ${widget.organizationName}'),
        actions: [
          IconButton(
            tooltip: 'Refresh rooms',
            onPressed: _loading || _saving ? null : _loadRooms,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _openRoomForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add room'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_rooms.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No rooms yet. Add your first room to begin '
                        'accepting bookings.',
                      ),
                    ),
                  )
                else
                  ..._rooms.map(_roomCard),
              ],
            ),
    );
  }

  Widget _roomCard(AdminRow room) {
    final active = room['active'] == true;
    final approval = room['requires_approval'] == true;
    final rate = room['hourly_rate_cents'] as num;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    room['name'] as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Chip(
                  label: Text(active ? 'Active' : 'Inactive'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(room['location'] as String),
            const SizedBox(height: 8),
            Text(room['description'] as String),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text('Up to ${room['capacity']} guests'),
                Text(
                  '${NumberFormat.currency(
                    locale: 'en_CA',
                    symbol: 'CA\$',
                  ).format(rate / 100)} / hour',
                ),
                Text(
                  '${room['opens_at']}–${room['closes_at']}',
                ),
                Text(
                  approval
                      ? 'Approval required'
                      : 'Instant confirmation',
                ),
                Text(
                  'Setup ${room['setup_minutes']} min · '
                  'Cleanup ${room['cleanup_minutes']} min',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: (room['amenities'] as List)
                  .map((item) => Chip(label: Text('$item')))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _openRoomForm(room),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => _toggleActive(room),
                  child: Text(
                    active ? 'Deactivate' : 'Reactivate',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RoomFormDialog extends StatefulWidget {
  const RoomFormDialog({
    super.key,
    required this.organizationId,
    this.existingRoom,
  });

  final String organizationId;
  final AdminRow? existingRoom;

  @override
  State<RoomFormDialog> createState() => _RoomFormDialogState();
}

class _RoomFormDialogState extends State<RoomFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _capacity;
  late final TextEditingController _hourlyRate;
  late final TextEditingController _amenities;
  late final TextEditingController _setup;
  late final TextEditingController _cleanup;

  late TimeOfDay _opens;
  late TimeOfDay _closes;
  late bool _requiresApproval;

  bool _saving = false;
  String? _error;

  late final AdminService _adminService;

  @override
  void initState() {
    super.initState();

    final room = widget.existingRoom;

    _adminService = AdminService(Supabase.instance.client);

    _name = TextEditingController(text: room?['name'] ?? '');
    _description =
        TextEditingController(text: room?['description'] ?? '');
    _location = TextEditingController(text: room?['location'] ?? '');
    _capacity = TextEditingController(
      text: room == null ? '10' : '${room['capacity']}',
    );
    _hourlyRate = TextEditingController(
      text: room == null
          ? '25'
          : ((room['hourly_rate_cents'] as num) / 100)
              .toStringAsFixed(2),
    );
    _amenities = TextEditingController(
      text: room == null
          ? ''
          : (room['amenities'] as List).join(', '),
    );
    _setup = TextEditingController(
      text: room == null ? '0' : '${room['setup_minutes']}',
    );
    _cleanup = TextEditingController(
      text: room == null ? '15' : '${room['cleanup_minutes']}',
    );

    _opens = _parseTime(room?['opens_at'], const TimeOfDay(hour: 8, minute: 0));
    _closes = _parseTime(
      room?['closes_at'],
      const TimeOfDay(hour: 22, minute: 0),
    );
    _requiresApproval = room?['requires_approval'] != false;
  }

  TimeOfDay _parseTime(dynamic value, TimeOfDay fallback) {
    if (value is! String || value.length < 5) return fallback;

    final parts = value.split(':');

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) return fallback;

    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _location.dispose();
    _capacity.dispose();
    _hourlyRate.dispose();
    _amenities.dispose();
    _setup.dispose();
    _cleanup.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool opening) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: opening ? _opens : _closes,
    );

    if (selected == null) return;

    setState(() {
      if (opening) {
        _opens = selected;
      } else {
        _closes = selected;
      }
    });
  }

  String _timeText(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');

    return '$hour:$minute:00';
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final capacity = int.tryParse(_capacity.text.trim());
    final rate = double.tryParse(_hourlyRate.text.trim());
    final setup = int.tryParse(_setup.text.trim());
    final cleanup = int.tryParse(_cleanup.text.trim());

    if (name.isEmpty) {
      setState(() => _error = 'Enter a room name.');
      return;
    }

    if (capacity == null || capacity < 1) {
      setState(() => _error = 'Enter a valid capacity.');
      return;
    }

    if (rate == null || rate < 0) {
      setState(() => _error = 'Enter a valid hourly rate.');
      return;
    }

    if (setup == null || cleanup == null) {
      setState(() => _error = 'Enter valid setup and cleanup minutes.');
      return;
    }

    if (_opens.hour * 60 + _opens.minute >=
        _closes.hour * 60 + _closes.minute) {
      setState(
        () => _error = 'Opening time must be earlier than closing time.',
      );
      return;
    }

    final amenities = _amenities.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (widget.existingRoom == null) {
        await _adminService.createRoom(
          organizationId: widget.organizationId,
          name: name,
          description: _description.text.trim(),
          location: _location.text.trim(),
          capacity: capacity,
          hourlyRateCents: (rate * 100).round(),
          amenities: amenities,
          requiresApproval: _requiresApproval,
          setupMinutes: setup,
          cleanupMinutes: cleanup,
          opensAt: _timeText(_opens),
          closesAt: _timeText(_closes),
        );
      } else {
        await _adminService.updateRoom(
          roomId: widget.existingRoom!['id'] as String,
          name: name,
          description: _description.text.trim(),
          location: _location.text.trim(),
          capacity: capacity,
          hourlyRateCents: (rate * 100).round(),
          amenities: amenities,
          requiresApproval: _requiresApproval,
          setupMinutes: setup,
          cleanupMinutes: cleanup,
          opensAt: _timeText(_opens),
          closesAt: _timeText(_closes),
        );
      }

      if (!mounted) return;

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
    final editing = widget.existingRoom != null;

    return AlertDialog(
      title: Text(editing ? 'Edit room' : 'Add room'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Room name',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _location,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  hintText: 'For example: Main floor · East wing',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _capacity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Capacity',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: TextField(
                      controller: _hourlyRate,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Hourly rate (CAD)',
                        prefixText: 'CA\$ ',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amenities,
                decoration: const InputDecoration(
                  labelText: 'Amenities',
                  hintText: 'Wi-Fi, Display, Whiteboard',
                  helperText: 'Separate items with commas.',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _setup,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Setup minutes',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _cleanup,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cleanup minutes',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: () => _pickTime(true),
                    child: Text('Opens ${_opens.format(context)}'),
                  ),
                  OutlinedButton(
                    onPressed: () => _pickTime(false),
                    child: Text('Closes ${_closes.format(context)}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Require administrator approval'),
                value: _requiresApproval,
                onChanged: _saving
                    ? null
                    : (value) {
                        setState(() => _requiresApproval = value);
                      },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
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
          child: Text(
            _saving
                ? 'Saving…'
                : editing
                    ? 'Save changes'
                    : 'Create room',
          ),
        ),
      ],
    );
  }
}