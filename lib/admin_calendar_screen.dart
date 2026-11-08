import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_service.dart';
import 'admin_create_booking_screen.dart';
import 'admin_booking_details_screen.dart';
import 'admin_month_calendar_screen.dart';

import 'dart:math' as math;
import 'package:timezone/timezone.dart' as tz;

class AdminCalendarScreen extends StatefulWidget {
  const AdminCalendarScreen({
    super.key,
    required this.organizationId,
    required this.organizationName,
    required this.timezone,
  });

  final String organizationId;
  final String organizationName;
  final String timezone;

  @override
  State<AdminCalendarScreen> createState() => _AdminCalendarScreenState();
}

class _AdminCalendarScreenState extends State<AdminCalendarScreen> {
  late final AdminService _adminService;

  late DateTime _selectedDay;
  List<AdminRow> _schedule = [];
  bool _loading = true;
  String? _error;

  static const double _hourWidth = 110;
  static const int _startHour = 6;
  static const int _endHour = 24;

  static const int _compactStartHour = 6;
static const int _compactEndHour = 24;

static const double _compactHeaderHeight = 32;
static const double _compactRowHeight = 56;
static const double _compactMinimumHourWidth = 32;

  @override
  void initState() {
    super.initState();

    _adminService = AdminService(Supabase.instance.client);

    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);

    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final schedule = await _adminService.daySchedule(
        organizationId: widget.organizationId,
        day: _selectedDay,
      );

      if (!mounted) return;

      setState(() {
        _schedule = schedule;
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

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selected == null) return;

    setState(() => _selectedDay = selected);
    await _loadSchedule();
  }

  Future<void> _openMonthCalendar() async {
  final selectedDay = await Navigator.push<DateTime>(
    context,
    MaterialPageRoute<DateTime>(
      builder: (_) => AdminMonthCalendarScreen(
        organizationId: widget.organizationId,
        organizationName: widget.organizationName,
        timezone: widget.timezone,
        initialDay: _selectedDay,
      ),
    ),
  );

  if (!mounted || selectedDay == null) return;

  setState(() {
    _selectedDay = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
    );
  });

  await _loadSchedule();
}

  Future<void> _openCreateBooking() async {
  final rooms = _rooms();

  if (rooms.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No rooms available.'),
      ),
    );
    return;
  }

  final created = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => AdminCreateBookingScreen(
        organizationId: widget.organizationId,
        rooms: rooms,
        initialRoomId: rooms.first['room_id'] as String,
        initialStart: DateTime(
          _selectedDay.year,
          _selectedDay.month,
          _selectedDay.day,
          9,
        ),
      ),
    ),
  );

  if (created == true) {
    await _loadSchedule();
  }
}

Future<void> _openBookingDetails(AdminRow booking) async {
  final rooms = _rooms();

  if (rooms.isEmpty) return;

  final updated = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => AdminBookingDetailsScreen(
        organizationId: widget.organizationId,
        booking: booking,
        rooms: rooms,
      ),
    ),
  );

  if (updated == true) {
    await _loadSchedule();
  }
}

  List<AdminRow> _rooms() {
    final rooms = <String, AdminRow>{};

    for (final row in _schedule) {
      final roomId = row['room_id'] as String;

      rooms.putIfAbsent(
        roomId,
        () => {
          'room_id': roomId,
          'room_name': row['room_name'],
          'room_active': row['room_active'],
        },
      );
    }

    final values = rooms.values.toList();

    values.sort(
      (a, b) {
        final activeA = a['room_active'] == true ? 0 : 1;
        final activeB = b['room_active'] == true ? 0 : 1;

        final activeCompare = activeA.compareTo(activeB);
        if (activeCompare != 0) return activeCompare;

        return (a['room_name'] as String)
            .compareTo(b['room_name'] as String);
      },
    );

    return values;
  }

  List<AdminRow> _bookingsForRoom(String roomId) {
    return _schedule
        .where(
          (row) =>
              row['room_id'] == roomId && row['booking_id'] != null,
        )
        .toList();
  }

  double _minutesFromDayStart(DateTime value) {
    final local = value.toLocal();

    final minutes =
        local.hour * 60 + local.minute + local.second / 60;

    return minutes - (_startHour * 60);
  }

  Widget _bookingBlock(AdminRow booking) {
    final start = DateTime.parse(booking['booking_starts_at'] as String);
    final end = DateTime.parse(booking['booking_ends_at'] as String);

    final startMinutes = _minutesFromDayStart(start);
    final endMinutes = _minutesFromDayStart(end);

    final left = startMinutes / 60 * _hourWidth;
    final width = ((endMinutes - startMinutes) / 60 * _hourWidth)
        .clamp(40.0, double.infinity);

    final status = booking['booking_status'] as String;

    final color = switch (status) {
      'confirmed' => Theme.of(context).colorScheme.primary,
      'pending' => Theme.of(context).colorScheme.tertiary,
      _ => Theme.of(context).colorScheme.outline,
    };

    return Positioned(
      left: left,
      width: width,
      top: 8,
      bottom: 8,
      child: Tooltip(
        message:
            '${booking['booking_title']}\n'
            '${DateFormat.jm().format(start.toLocal())}–'
            '${DateFormat.jm().format(end.toLocal())}\n'
            '${booking['attendees']} guests\n'
            'Status: $status',
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openBookingDetails(booking),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking['booking_title'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${DateFormat.jm().format(start.toLocal())}–'
                    '${DateFormat.jm().format(end.toLocal())}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showBookingDetails(AdminRow booking) {
    final start =
        DateTime.parse(booking['booking_starts_at'] as String).toLocal();
    final end =
        DateTime.parse(booking['booking_ends_at'] as String).toLocal();
    final blockedStart =
        DateTime.parse(booking['blocked_starts_at'] as String).toLocal();
    final blockedEnd =
        DateTime.parse(booking['blocked_ends_at'] as String).toLocal();

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(booking['booking_title'] as String),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Room: ${booking['room_name']}'),
                const SizedBox(height: 8),
                Text('Status: ${booking['booking_status']}'),
                const SizedBox(height: 8),
                Text(
                  'Event: '
                  '${DateFormat('EEE, MMM d').format(start)} · '
                  '${DateFormat.jm().format(start)}–'
                  '${DateFormat.jm().format(end)}',
                ),
                const SizedBox(height: 8),
                Text(
                  'Reserved including buffers: '
                  '${DateFormat.jm().format(blockedStart)}–'
                  '${DateFormat.jm().format(blockedEnd)}',
                ),
                const SizedBox(height: 8),
                Text('Attendees: ${booking['attendees']}'),
                const SizedBox(height: 8),
                Text(
                  'Quoted room rental: '
                  '${NumberFormat.currency(
                    locale: 'en_CA',
                    symbol: 'CA\$',
                  ).format(
                    (booking['quoted_total_cents'] as num) / 100,
                  )}',
                ),
                const SizedBox(height: 8),
                Text('Booked by: ${booking['booked_by_email']}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _rooms();
    final dayLabel = DateFormat('EEEE, MMMM d, yyyy').format(_selectedDay);

    return Scaffold(
      appBar: AppBar(
        title: Text('Calendar · ${widget.organizationName}'),
        actions: [
          IconButton(
            tooltip: 'Monthly overview',
            onPressed: _openMonthCalendar,
            icon: const Icon(Icons.calendar_view_month_outlined),
          ),
          IconButton(
            tooltip: 'Previous day',
            onPressed: _loading
                ? null
                : () {
                    setState(() {
                      _selectedDay =
                          _selectedDay.subtract(const Duration(days: 1));
                    });
                    _loadSchedule();
                  },
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Choose date',
            onPressed: _loading ? null : _pickDate,
            icon: const Icon(Icons.calendar_today_outlined),
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: _loading
                ? null
                : () {
                    setState(() {
                      _selectedDay =
                          _selectedDay.add(const Duration(days: 1));
                    });
                    _loadSchedule();
                  },
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: 'Create booking',
            onPressed: _loading ? null : _openCreateBooking,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadSchedule,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dayLabel,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text('Timezone: ${widget.timezone}'),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (rooms.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text(
                        'No rooms are configured for this organization.',
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: _compactDayTimeline(),
                  ),
                ],
            ),
    );
  }

  Widget _timeHeader() {
    final hours = List.generate(
      _endHour - _startHour,
      (index) => _startHour + index,
    );

    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 170),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: (_endHour - _startHour) * _hourWidth,
                child: Row(
                  children: hours
                      .map(
                        (hour) => SizedBox(
                          width: _hourWidth,
                          child: Text(
                            DateFormat.j().format(
                              DateTime(2026, 1, 1, hour),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomRow(AdminRow room) {
    final roomId = room['room_id'] as String;
    final bookings = _bookingsForRoom(roomId);

    return SizedBox(
      height: 76,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 170,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    room['room_name'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    room['room_active'] == true
                        ? 'Active'
                        : 'Inactive',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: (_endHour - _startHour) * _hourWidth,
                child: Stack(
                  children: [
                    ...List.generate(
                      _endHour - _startHour,
                      (index) => Positioned(
                        left: index * _hourWidth,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 1,
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                    ...bookings.map(_bookingBlock),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

String _compactHourLabel(int hour) {
  if (hour == 0 || hour == 24) return '12a';
  if (hour == 12) return '12p';

  return hour < 12 ? '${hour}a' : '${hour - 12}p';
}

DateTime _compactFacilityTime(String value) {
  return tz.TZDateTime.from(
    DateTime.parse(value),
    tz.getLocation(widget.timezone),
  );
}

double _compactMinutesFromStart(DateTime value) {
  // Use calendar-date arithmetic so overnight bookings are positioned
  // relative to the selected day, not only their hour of day.
  final selectedDate = DateTime.utc(
    _selectedDay.year,
    _selectedDay.month,
    _selectedDay.day,
  );

  final valueDate = DateTime.utc(
    value.year,
    value.month,
    value.day,
  );

  final dayOffset =
      valueDate.difference(selectedDate).inDays * 24 * 60;

  return dayOffset +
      value.hour * 60 +
      value.minute +
      value.second / 60 -
      _compactStartHour * 60;
}

Widget _compactDayTimeline() {
  final rooms = _rooms();
  final scheme = Theme.of(context).colorScheme;

  if (rooms.isEmpty) {
    return const Center(
      child: Text('No rooms available.'),
    );
  }

  final hourCount = _compactEndHour - _compactStartHour;

  return LayoutBuilder(
    builder: (context, constraints) {
      final roomColumnWidth =
          constraints.maxWidth < 600 ? 110.0 : 150.0;

      final availableTimelineWidth = math.max(
        0.0,
        constraints.maxWidth - roomColumnWidth,
      );

      final hourWidth = math.max(
        _compactMinimumHourWidth,
        availableTimelineWidth / hourCount,
      );

      final timelineWidth = hourWidth * hourCount;

      return SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fixed room-name column.
            SizedBox(
              width: roomColumnWidth,
              child: Column(
                children: [
                  Container(
                    height: _compactHeaderHeight,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                    ),
                    child: const Text(
                      'Room',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  ...rooms.map((room) {
                    return Container(
                      height: _compactRowHeight,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: scheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: Text(
                        room['room_name'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: room['room_active'] == true
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Header and all timelines share one horizontal scroll.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: timelineWidth,
                  child: Column(
                    children: [
                      SizedBox(
                        height: _compactHeaderHeight,
                        child: Row(
                          children: List.generate(
                            hourCount,
                            (index) {
                              final hour =
                                  _compactStartHour + index;

                              return SizedBox(
                                width: hourWidth,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 3,
                                  ),
                                  child: Text(
                                    _compactHourLabel(hour),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      ...rooms.map((room) {
                        return _compactTimelineRoomRow(
                          room,
                          hourWidth,
                          timelineWidth,
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _compactTimelineRoomRow(
  AdminRow room,
  double hourWidth,
  double timelineWidth,
) {
  final bookings = _bookingsForRoom(
    room['room_id'] as String,
  );

  final scheme = Theme.of(context).colorScheme;
  final hourCount = _compactEndHour - _compactStartHour;

  return Container(
    height: _compactRowHeight,
    width: timelineWidth,
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: scheme.outlineVariant,
        ),
      ),
    ),
    child: ClipRect(
      child: Stack(
        children: [
          // Vertical hour grid lines.
          ...List.generate(
            hourCount,
            (index) => Positioned(
              left: index * hourWidth,
              top: 0,
              bottom: 0,
              child: Container(
                width: 1,
                color: scheme.outlineVariant.withValues(
                  alpha: 0.55,
                ),
              ),
            ),
          ),

          ...bookings.map(
            (booking) => _compactTimelineBooking(
              booking,
              hourWidth,
              timelineWidth,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _compactTimelineBooking(
  AdminRow booking,
  double hourWidth,
  double timelineWidth,
) {
  final start = _compactFacilityTime(
    booking['booking_starts_at'] as String,
  );

  final end = _compactFacilityTime(
    booking['booking_ends_at'] as String,
  );

  final rawLeft =
      _compactMinutesFromStart(start) / 60 * hourWidth;

  final rawRight =
      _compactMinutesFromStart(end) / 60 * hourWidth;

  // Clip bookings to the displayed time window.
  final left = math.max(0.0, rawLeft);
  final right = math.min(timelineWidth, rawRight);

  if (right <= left) {
    return const SizedBox.shrink();
  }

  final width = right - left;
  final status = booking['booking_status'] as String;
  final title = booking['booking_title'] as String;

  final scheme = Theme.of(context).colorScheme;

  final background = status == 'pending'
      ? scheme.tertiaryContainer
      : scheme.primaryContainer;

  final foreground = status == 'pending'
      ? scheme.onTertiaryContainer
      : scheme.onPrimaryContainer;

  final timeLabel =
      '${DateFormat.jm().format(start)}–'
      '${DateFormat.jm().format(end)}';

  return Positioned(
    left: left,
    width: width,
    top: 7,
    bottom: 7,
    child: Tooltip(
      message: '$title\n$timeLabel\n$status',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(5),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openBookingDetails(booking),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Keep short bookings visible without making their
              // displayed duration artificially wider.
              if (constraints.maxWidth < 28) {
                return Center(
                  child: Container(
                    width: 3,
                    height: 16,
                    color: foreground,
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 3,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),

                    if (constraints.maxWidth >= 110)
                      Text(
                        timeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: foreground,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}


}