import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'roomly_logo.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  final _db = Supabase.instance.client;

  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _db.rpc('rm_my_bookings');

      if (!mounted) return;

      setState(() {
        _bookings = List<Map<String, dynamic>>.from(result);
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

  List<Map<String, dynamic>> get _upcoming {
    final now = DateTime.now();

    return _bookings
        .where(
          (booking) =>
              DateTime.parse(booking['starts_at'] as String)
                  .toLocal()
                  .isAfter(now) &&
              booking['status'] != 'cancelled' &&
              booking['status'] != 'expired',
        )
        .toList();
  }

  List<Map<String, dynamic>> get _past {
    final now = DateTime.now();

    return _bookings
        .where(
          (booking) =>
              DateTime.parse(booking['starts_at'] as String)
                  .toLocal()
                  .isBefore(now) ||
              booking['status'] == 'cancelled' ||
              booking['status'] == 'expired',
        )
        .toList();
  }

  Future<void> _cancelBooking(Map<String, dynamic> booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cancel booking?'),
          content: Text(
            'Cancel “${booking['title']}”? '
            'This booking will be marked as cancelled.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep booking'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel booking'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _db.rpc(
        'rm_request_cancellation',
        params: {
          'p_booking_id': booking['booking_id'],
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled.'),
        ),
      );

      await _loadBookings();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Color _statusColor(String status) {
    return switch (status) {
      'confirmed' => Colors.green,
      'pending' => Colors.orange,
      'cancelled' => Colors.red,
      'expired' => Colors.grey,
      _ => Colors.blueGrey,
    };
  }

  Widget _bookingCard(Map<String, dynamic> booking) {
    final start =
        DateTime.parse(booking['starts_at'] as String).toLocal();
    final end =
        DateTime.parse(booking['ends_at'] as String).toLocal();

    final status = booking['status'] as String;
    final canCancel = booking['can_cancel'] == true;

    final price = NumberFormat.currency(
      locale: 'en_CA',
      symbol: 'CA\$',
    ).format(
      (booking['quoted_total_cents'] as num) / 100,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    booking['title'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: _statusColor(status),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Room: ${booking['room_name']}'),
            const SizedBox(height: 4),
            Text(
              '${DateFormat('EEE, MMM d, yyyy').format(start)} · '
              '${DateFormat.jm().format(start)}–'
              '${DateFormat.jm().format(end)}',
            ),
            const SizedBox(height: 4),
            Text('Attendees: ${booking['attendees']}'),
            const SizedBox(height: 4),
            Text('Quoted room rental: $price'),
            if (canCancel) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _cancelBooking(booking),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required List<Map<String, dynamic>> bookings,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (bookings.isEmpty)
          const Text('Nothing here yet.')
        else
          ...bookings.map(_bookingCard),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const RoomlyPageTitle(
          title: 'My bookings',
          ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadBookings,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadBookings,
              child: ListView(
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
                  _section(
                    title: 'Upcoming',
                    bookings: _upcoming,
                  ),
                  _section(
                    title: 'Past and closed',
                    bookings: _past,
                  ),
                ],
              ),
            ),
    );
  }
}