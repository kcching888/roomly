import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import 'roomly_logo.dart';

class AdminMonthCalendarScreen extends StatefulWidget {
  const AdminMonthCalendarScreen({
    super.key,
    required this.organizationId,
    required this.organizationName,
    required this.timezone,
    required this.initialDay,
  });

  final String organizationId;
  final String organizationName;
  final String timezone;
  final DateTime initialDay;

  @override
  State<AdminMonthCalendarScreen> createState() =>
      _AdminMonthCalendarScreenState();
}

class _AdminMonthCalendarScreenState
    extends State<AdminMonthCalendarScreen> {
  final _db = Supabase.instance.client;

  late DateTime _month;

  Map<String, Map<String, dynamic>> _days = {};

  bool _loading = true;
  String? _error;
  int _requestId = 0;

  static const _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  void initState() {
    super.initState();

    _month = DateTime(
      widget.initialDay.year,
      widget.initialDay.month,
      1,
    );

    _loadMonth();
  }

  String _dateKey(DateTime day) {
    return DateFormat('yyyy-MM-dd').format(day);
  }

  DateTime _facilityToday() {
    final now = tz.TZDateTime.now(
      tz.getLocation(widget.timezone),
    );

    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _loadMonth() async {
    final requestId = ++_requestId;
    final requestedMonth = _month;

    setState(() {
      _loading = true;
      _error = null;
      _days = {};
    });

    try {
      final result = await _db.rpc(
        'rm_admin_month_schedule',
        params: {
          'p_organization_id': widget.organizationId,
          'p_month': _dateKey(requestedMonth),
        },
      );

      final days = <String, Map<String, dynamic>>{};

      for (final item in result as List) {
        final row = Map<String, dynamic>.from(item as Map);
        final day = DateTime.parse(row['booking_day'] as String);

        days[_dateKey(day)] = row;
      }

      if (!mounted || requestId != _requestId) return;

      setState(() {
        _days = days;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;

      setState(() {
        _loading = false;
        _error = error is PostgrestException
            ? error.message
            : error.toString();
      });
    }
  }

  void _changeMonth(int offset) {
    setState(() {
      _month = DateTime(
        _month.year,
        _month.month + offset,
        1,
      );
    });

    _loadMonth();
  }

  void _showThisMonth() {
    final today = _facilityToday();

    setState(() {
      _month = DateTime(today.year, today.month, 1);
    });

    _loadMonth();
  }

  Widget _dayCell(DateTime day, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    final data = _days[_dateKey(day)];

    final pending =
        (data?['pending_count'] as num?)?.toInt() ?? 0;

    final confirmed =
        (data?['confirmed_count'] as num?)?.toInt() ?? 0;

    final total = pending + confirmed;
    final isToday = _dateKey(day) == _dateKey(_facilityToday());

    final tooltip =
        '${DateFormat('EEEE, MMMM d').format(day)}\n'
        '$confirmed confirmed · $pending pending\n'
        'Click to open day schedule';

    return Tooltip(
      message: tooltip,
      child: Material(
        color: total > 0
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isToday
                ? scheme.primary
                : scheme.outlineVariant,
            width: isToday ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.pop<DateTime>(context, day);
          },
          child: Padding(
            padding: EdgeInsets.all(compact ? 5 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: compact ? 12 : 15,
                    fontWeight: isToday
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: isToday
                        ? scheme.primary
                        : scheme.onSurface,
                  ),
                ),
                const Spacer(),

                if (total > 0)
                  Text(
                    compact
                        ? '$total'
                        : '$total ${total == 1 ? 'booking' : 'bookings'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.primary,
                    ),
                  ),

                if (pending > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    compact ? '${pending}p' : '$pending pending',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 10 : 11,
                      color: scheme.tertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthGrid() {
    final daysInMonth = DateTime(
      _month.year,
      _month.month + 1,
      0,
    ).day;

    // Monday is column zero.
    final leadingDays = _month.weekday - 1;

    final occupiedCells = leadingDays + daysInMonth;
    final cellCount = ((occupiedCells + 6) ~/ 7) * 7;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;

        return Column(
          children: [
            Row(
              children: _weekdays.map((name) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                    ),
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                gridDelegate:
                    SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: compact ? 86 : 110,
                  crossAxisSpacing: compact ? 4 : 8,
                  mainAxisSpacing: compact ? 4 : 8,
                ),
                itemCount: cellCount,
                itemBuilder: (context, index) {
                  final dayNumber = index - leadingDays + 1;

                  if (dayNumber < 1 || dayNumber > daysInMonth) {
                    return const SizedBox.shrink();
                  }

                  final day = DateTime(
                    _month.year,
                    _month.month,
                    dayNumber,
                  );

                  return _dayCell(day, compact: compact);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const RoomlyPageTitle(
          title: 'Monthly bookings',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh month',
            onPressed: _loading ? null : _loadMonth,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.organizationName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_month),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: _showThisMonth,
                  child: const Text('This month'),
                ),
              ],
            ),

            const SizedBox(height: 4),
            Text(
              'Event counts · ${widget.timezone}\n'
              'Tap a date to open its day schedule. '
              'On small screens, “p” means pending.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),

            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : _error != null
                      ? Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .error,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _loadMonth,
                                  child: const Text('Try again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _monthGrid(),
            ),
          ],
        ),
      ),
    );
  }
}