import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import 'package:flutter/widgets.dart' as widgets show Row;

import 'package:go_router/go_router.dart';
//import 'package:flutter_web_plugins/url_strategy.dart';

import 'admin_rooms_screen.dart';
import 'admin_calendar_screen.dart';
import 'admin_booking_details_screen.dart';
import 'organization_profile_screen.dart';
import 'platform_organizations_screen.dart';
import 'admin_members_screen.dart';

import 'organization_welcome.dart';
import 'membership_status.dart';
import 'add_member_dialog.dart';
import 'roomly_logo.dart';
import 'roomly_customization.dart';
import 'platform_access_gate.dart';

typedef Row = Map<String, dynamic>;

SupabaseClient get db => Supabase.instance.client;

List<Row> rows(dynamic value) {
  return (value as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
}

String money(num cents) {
  return NumberFormat.currency(
    locale: 'en_CA',
    symbol: 'CA\$',
  ).format(cents / 100);
}

String readableError(Object error) {
  if (error is AuthException) {
    return error.message;
  }

  if (error is PostgrestException) {
    if (error.code == '23P01') {
      return 'This room was just booked. Please search again.';
    }
    return error.message;
  }

  if (error is FormatException) {
    return error.message;
  }

  return 'Unable to complete the request. Check your connection and retry.';
}

String bookingTime(DateTime value, String zone) {
  final local = tz.TZDateTime.from(value, tz.getLocation(zone));
  return DateFormat('EEE, MMM d · h:mm a').format(local);
}

String endTime(DateTime value, String zone) {
  final local = tz.TZDateTime.from(value, tz.getLocation(zone));
  return DateFormat('h:mm a').format(local);
}

// Interpret the selected time in the facility's timezone,
// not in the timezone of the customer's phone or browser.
DateTime facilityUtc(DateTime day, TimeOfDay time, String zone) {
  final location = tz.getLocation(zone);

  final selected = tz.TZDateTime(
    location,
    day.year,
    day.month,
    day.day,
    time.hour,
    time.minute,
  );

  bool matches(tz.TZDateTime candidate) {
    return candidate.year == day.year &&
        candidate.month == day.month &&
        candidate.day == day.day &&
        candidate.hour == time.hour &&
        candidate.minute == time.minute;
  }

  if (!matches(selected)) {
    throw const FormatException(
      'This time does not exist because of daylight saving time.',
    );
  }

  // Reject ambiguous local times rather than silently picking an offset.
  for (final offset in [-120, -90, -60, -30, 30, 60, 90, 120]) {
    final alternative = tz.TZDateTime.from(
      selected.toUtc().add(Duration(minutes: offset)),
      location,
    );

    if (matches(alternative)) {
      throw const FormatException(
        'This time occurs twice because of daylight saving time. '
        'Choose another time.',
      );
    }
  }

  return selected.toUtc();
}

class RoomSearch {
  const RoomSearch({
    required this.organizationId,
    required this.zone,
    required this.start,
    required this.end,
    required this.attendees,
  });

  final String organizationId;
  final String zone;
  final DateTime start;
  final DateTime end;
  final int attendees;

  Map<String, dynamic> get parameters => {
    'p_organization_id': organizationId,
    'p_start': start.toIso8601String(),
    'p_end': end.toIso8601String(),
    'p_attendees': attendees,
  };

  String get label {
    return '${bookingTime(start, zone)} – ${endTime(end, zone)}';
  }

  int estimate(Row room) {
    final rate = room['hourly_rate_cents'] as num;
    return (rate * end.difference(start).inSeconds / 3600).ceil();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  //usePathUrlStrategy();
  tzdata.initializeTimeZones();

  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (url.isEmpty || key.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Missing Supabase configuration.\n\n'
                'Run with --dart-define-from-file=config.json',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  await Supabase.initialize(url: url, anonKey: key);

  runApp(const RoomlyApp());
}

class RoomlyApp extends StatefulWidget {
  const RoomlyApp({super.key});

  @override
  State<RoomlyApp> createState() => _RoomlyAppState();
}

class _RoomlyAppState extends State<RoomlyApp> {
  ThemeMode _mode = ThemeMode.system;

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF01696F),
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF7F6F2)
          : const Color(0xFF171614),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(44, 48)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Roomly',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _mode,
      routerConfig: _router,
      builder: (context, child) => RmPageShell(
        child: child ?? const SizedBox.shrink(),
),
    );
  }

  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Welcome to Roomly.\n\n'
                  'Open the booking link provided by your organization.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/o/:slug',
        builder: (context, state) {
          final slug = state.pathParameters['slug']!;

          return StreamBuilder<AuthState>(
            stream: db.auth.onAuthStateChange,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Scaffold(
                  body: Center(
                    child: Text(
                      'Authentication could not be refreshed. '
                      'Check your connection and reload.',
                    ),
                  ),
                );
              }

              final userId = db.auth.currentUser?.id ?? 'guest';

              return BookingHome(
                key: ValueKey('$slug:$userId'),
                organizationSlug: slug,
                toggleTheme: _toggleTheme,
              );
            },
          );
        },
      ),
      GoRoute(
        path: '/platform',
        builder: (context, state) {
          return const PlatformAccessGate();
        },
      ),
    ],
    errorBuilder: (context, state) {
      return Scaffold(
        appBar: AppBar(title: const Text('Page not found')),
        body: Center(
          child: TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Go to Roomly home'),
          ),
        ),
      );
    },
  );

  void _toggleTheme() {
    setState(() {
      final currentlyDark =
          _mode == ThemeMode.dark ||
          (_mode == ThemeMode.system &&
              WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                  Brightness.dark);

      _mode = currentlyDark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }
}

class BookingHome extends StatefulWidget {
  const BookingHome({
    super.key,
    required this.organizationSlug,
    required this.toggleTheme,
  });

  final String organizationSlug;
  final VoidCallback toggleTheme;

  @override
  State<BookingHome> createState() => _BookingHomeState();
}

class _BookingHomeState extends State<BookingHome> {
  final _guests = TextEditingController(text: '10');

  List<Row> _organizations = [];
  Row? _organization;
  Row? _signupContext;
  Map<String, dynamic>? _publicBranding;
  String? _membershipNotice;
  int _loadRequest = 0;
  bool _requestingMembership = false;
  String? _requestStatus;

  DateTime _day = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 11, minute: 0);

  RoomSearch? _searched;
  Future<List<Row>>? _results;
  Future<List<Row>>? _bookings;

  bool _loadingOrganizations = true;
  bool _admin = false;
  bool _changingStatus = false;

  String? _error;
  int _tab = 0;
  int _organizationRequest = 0;

  String get _zone {
    return _organization?['timezone'] as String? ?? 'America/Edmonton';
  }

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
  }

  @override
  void dispose() {
    _guests.dispose();
    super.dispose();
  }

  Future<void> _loadOrganizations() async {
  final request = ++_loadRequest;
  ++_organizationRequest;

  setState(() {
    _loadingOrganizations = true;
    _error = null;
    _membershipNotice = null;
    _signupContext = null;
    _organizations = [];
    _organization = null;
    _admin = false;
    _tab = 0;
    _results = null;
    _searched = null;
    _bookings = null;
    _publicBranding = null;
  });

  try {
    // Load public branding independently of registration availability.
    final brandingResult = await db.rpc(
      'rm_public_branding',
      params: {
        'p_slug': widget.organizationSlug,
      },
    );

    if (!mounted || request != _loadRequest) return;

    final branding = brandingResult == null
        ? null
        : Map<String, dynamic>.from(brandingResult as Map);

    // An old booking slug can resolve to the current slug.
    final canonicalSlug =
        branding?['slug'] as String? ?? widget.organizationSlug;

    setState(() {
      _publicBranding = branding;
    });

    // This remains null when registration is disabled.
    final signupResult = await db.rpc(
      'rm_get_signup_context',
      params: {
        'p_slug': canonicalSlug,
      },
    );

    if (!mounted || request != _loadRequest) return;

    setState(() {
      _signupContext = signupResult == null
          ? null
          : Map<String, dynamic>.from(signupResult as Map);
    });

    // Preserve the existing membership-completion behavior.
    if (db.auth.currentSession != null) {
      final result = await db.rpc(
        'rm_complete_signup_membership',
      );

      if (!mounted || request != _loadRequest) return;

      final notice = result as String?;

      setState(() {
        _membershipNotice =
            notice == 'No organization membership was requested.'
                ? null
                : notice;
      });
    }

    // Preserve the existing RLS-protected organization lookup.
    final data = await db
        .from('rm_organizations')
        .select()
        .eq('slug', canonicalSlug)
        .limit(1);

    if (!mounted || request != _loadRequest) return;

    setState(() {
      _organizations = rows(data);
    });

    if (_organizations.isNotEmpty) {
      await _selectOrganization(_organizations.first);
    }

    if (!mounted || request != _loadRequest) return;

    setState(() {
      _loadingOrganizations = false;
    });
  } catch (error) {
    if (!mounted || request != _loadRequest) return;

    setState(() {
      _loadingOrganizations = false;
      _error = readableError(error);
    });
  }
}

  Future<void> _selectOrganization(Row organization) async {
    final request = ++_organizationRequest;
    final now = tz.TZDateTime.now(
      tz.getLocation(organization['timezone'] as String),
    );

    setState(() {
      _organization = organization;
      _day = DateTime(now.year, now.month, now.day + 1);
      _results = null;
      _searched = null;
      _bookings = null;
      _admin = false;
      _tab = 0;
      _error = null;
    });

    if (db.auth.currentUser == null) return;

    try {
      final isAdmin = await db.rpc(
        'rm_is_admin',
        params: {'p_organization_id': organization['id']},
      );

      if (!mounted || request != _organizationRequest) return;

      setState(() {
        _admin = isAdmin == true;
      });
    } catch (error) {
      if (!mounted || request != _organizationRequest) return;
      setState(() => _error = readableError(error));
    }
  }

  void _invalidateSearch() {
    _results = null;
    _searched = null;
    _error = null;
  }

  Future<void> _pickDate() async {
    final now = tz.TZDateTime.now(tz.getLocation(_zone));
    final today = DateTime(now.year, now.month, now.day);

    final selected = await showDatePicker(
      context: context,
      initialDate: _day.isBefore(today) ? today : _day,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );

    if (selected == null || !mounted) return;

    setState(() {
      _day = selected;
      _invalidateSearch();
    });
  }

  Future<void> _pickTime(bool start) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );

    if (selected == null || !mounted) return;

    setState(() {
      if (start) {
        _start = selected;
      } else {
        _end = selected;
      }
      _invalidateSearch();
    });
  }

  void _openRoomManagement() {
    final organization = _organization;

    if (organization == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminRoomsScreen(
          organizationId: organization['id'] as String,
          organizationName: organization['name'] as String,
        ),
      ),
    );
  }

  void _openCalendar() {
    final organization = _organization;

    if (organization == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminCalendarScreen(
          organizationId: organization['id'] as String,
          organizationName: organization['name'] as String,
          timezone: _zone,
        ),
      ),
    );
  }

  Future<void> _openMemberManagement() async {
    final organization = _organization;

    if (organization == null || !_admin) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AdminMembersScreen(
          organizationId: organization['id'] as String,
          organizationName: organization['name'] as String,
        ),
      ),
    );

    if (!mounted) return;

    // Refresh organization-related state after returning.
    await _loadOrganizations();
  }

  Future<void> _openAddMember() async {
    final organization = _organization;

    if (organization == null || !_admin) return;

    await showAddMemberDialog(
      context: context,
      organizationId: organization['id'] as String,
      organizationName: organization['name'] as String,
    );
  }

  void _search() {
    if (_organization == null) return;

    try {
      final guests = int.tryParse(_guests.text.trim());

      if (guests == null || guests < 1 || guests > 10000) {
        throw const FormatException(
          'Enter a valid number of guests between 1 and 10,000.',
        );
      }

      final start = facilityUtc(_day, _start, _zone);
      final end = facilityUtc(_day, _end, _zone);

      if (!start.isAfter(DateTime.now().toUtc())) {
        throw const FormatException('Choose a future start time.');
      }

      if (!end.isAfter(start) ||
          end.difference(start) > const Duration(hours: 12)) {
        throw const FormatException(
          'End time must follow start time, with a maximum of 12 hours.',
        );
      }

      final criteria = RoomSearch(
        organizationId: _organization!['id'] as String,
        zone: _zone,
        start: start,
        end: end,
        attendees: guests,
      );

      setState(() {
        _error = null;
        _searched = criteria;
        _results = _fetchRooms(criteria);
      });
    } catch (error) {
      setState(() => _error = readableError(error));
    }
  }

  Future<List<Row>> _fetchRooms(RoomSearch criteria) async {
    final data = await db.rpc('rm_search_rooms', params: criteria.parameters);

    return rows(data);
  }

  Future<List<Row>> _fetchBookings(bool admin) async {
    final user = db.auth.currentUser;
    final organization = _organization;

    if (user == null || organization == null) return [];

    var query = db
        .from('rm_bookings')
        .select('*, rm_rooms(name)')
        .eq('organization_id', organization['id']);

    if (!admin) {
      query = query.eq('user_id', user.id);
    }

    final data = await query.order('starts_at', ascending: false).limit(100);

    return rows(data);
  }

  Future<bool> _editManagedBooking(Row booking) async {
    final organization = _organization;

    if (organization == null || db.auth.currentUser == null) {
      return false;
    }

    final status = booking['status'] as String?;

    if (status != 'pending' && status != 'confirmed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only pending or confirmed bookings can be edited.'),
        ),
      );

      return false;
    }

    try {
      // Load this organization's room choices.
      final data = await db
          .from('rm_rooms')
          .select('id, name, active')
          .eq('organization_id', organization['id'])
          .order('name');

      final roomOptions = <Map<String, dynamic>>[];

      for (final item in data) {
        // Include active rooms and the booking's current room.
        if (item['active'] == true || item['id'] == booking['room_id']) {
          roomOptions.add({'room_id': item['id'], 'room_name': item['name']});
        }
      }

      if (!mounted) return false;

      final currentRoomIncluded = roomOptions.any(
        (room) => room['room_id'] == booking['room_id'],
      );

      if (!currentRoomIncluded) {
        throw StateError('The booking room could not be loaded.');
      }

      // Convert the table fields to the editor's expected keys.
      final editorBooking = <String, dynamic>{
        'booking_id': booking['id'],
        'room_id': booking['room_id'],
        'booking_title': booking['title'],
        'booking_status': booking['status'],
        'booking_starts_at': booking['starts_at'],
        'booking_ends_at': booking['ends_at'],
        'attendees': booking['attendees'],
        'quoted_total_cents': booking['quoted_total_cents'],
      };

      final updated = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => AdminBookingDetailsScreen(
            organizationId: organization['id'] as String,
            booking: editorBooking,
            rooms: roomOptions,
          ),
        ),
      );

      if (!mounted) return false;

      return updated == true;
    } catch (error) {
      if (!mounted) return false;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not edit booking: $error')));

      return false;
    }
  }

  void _navigate(int index) {
    setState(() {
      _tab = index;
      _error = null;

      if (index != 0) {
        _bookings = _fetchBookings(index == 2);
      }
    });
  }

  Future<void> _authenticate({bool register = false}) async {
    final organizationId =
        _organization?['id'] as String? ??
        _signupContext?['organization_id'] as String?;

    final organizationName =
        _organization?['name'] as String? ??
        _signupContext?['organization_name'] as String?;

    await showDialog<void>(
      context: context,
      builder: (_) => AuthDialog(
        organizationId: organizationId,
        organizationName: organizationName,
        initialRegister: register,
      ),
    );
  }

  Future<void> _requestMembership() async {
    final organizationId =
        _organization?['id'] as String? ??
        _signupContext?['organization_id'] as String?;

    if (db.auth.currentUser == null || organizationId == null) {
      await _authenticate(register: true);
      return;
    }

    if (_requestingMembership) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Request membership?'),
        content: Text(
          'Request membership in '
          '${_organization?["name"] ?? _signupContext?["organization_name"] ?? "this organization"}?\n\n'
          'An organization administrator will review your request. '
          'This does not grant administrator access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Submit request'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _requestingMembership = true;
      _error = null;
    });

    try {
      final result = await db.rpc(
        'rm_request_organization_membership',
        params: {'p_organization_id': organizationId},
      );

      if (!mounted) return;

      setState(() {
        _requestingMembership = false;
        _requestStatus = result as String?;
        _membershipNotice = _requestStatus;
      });

      await _loadOrganizations();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _requestingMembership = false;
        _error = readableError(error);
      });
    }
  }

  Future<void> _chooseRoom(Row room, RoomSearch criteria) async {
    if (db.auth.currentUser == null) {
      await _authenticate();
      // Signing in recreates BookingHome with fresh authorization state.
      return;
    }

    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BookingDialog(room: room, criteria: criteria),
    );

    if (!mounted) return;

    if (completed == true) {
      _navigate(1);
    } else {
      // Availability may have changed while the dialog was open.
      _search();
    }
  }

  Future<void> _changeStatus(Row booking, String status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update booking?'),
        content: Text('Change "${booking['title']}" to $status?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep unchanged'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _changingStatus = true;
      _error = null;
    });

    try {
      await db.rpc(
        'rm_change_booking_status',
        params: {'p_booking_id': booking['id'], 'p_status': status},
      );

      if (!mounted) return;

      setState(() {
        _changingStatus = false;
        _bookings = _fetchBookings(_tab == 2);
        _results = null;
        _searched = null;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _changingStatus = false;
        _error = readableError(error);
      });
    }
  }

  Future<void> _openOrganizationProfile() async {
    final organization = _organization;

    if (organization == null || !_admin) return;

    final organizationId = organization['id'] as String;

    final savedName = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (_) =>
            OrganizationProfileScreen(organizationId: organizationId),
      ),
    );

    if (!mounted || savedName == null) return;

    setState(() {
      _organizations = _organizations.map((item) {
        if (item['id'] != organizationId) return item;

        return <String, dynamic>{...item, 'name': savedName};
      }).toList();

      if (_organization?['id'] == organizationId) {
        _organization = <String, dynamic>{..._organization!, 'name': savedName};
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Organization profile updated.')),
    );
  }

  Widget _message(String title, String detail, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(detail),
          if (action != null) ...[const SizedBox(height: 20), action],
        ],
      ),
    );
  }

  Widget _searchView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Find an available room',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose your date, time and group size. '
          'We’ll show rooms that fit.',
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: 180,
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(DateFormat('EEE, MMM d').format(_day)),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: OutlinedButton(
                        onPressed: () => _pickTime(true),
                        child: Text('From ${_start.format(context)}'),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: OutlinedButton(
                        onPressed: () => _pickTime(false),
                        child: Text('To ${_end.format(context)}'),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _guests,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Guests'),
                        onChanged: (_) {
                          setState(_invalidateSearch);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'All times: $_zone. '
                  'Opening hours include setup and cleanup buffers.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _search,
                  icon: const Icon(Icons.search),
                  label: const Text('Find available rooms'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (_results == null)
          _message(
            'Your next gathering starts here',
            'Search to see suitable rooms and estimated rental costs.',
          )
        else
          FutureBuilder<List<Row>>(
            future: _results,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: LinearProgressIndicator(),
                );
              }

              if (snapshot.hasError) {
                return _message(
                  'Search could not be completed',
                  readableError(snapshot.error!),
                  action: OutlinedButton(
                    onPressed: _search,
                    child: const Text('Try again'),
                  ),
                );
              }

              final available = snapshot.data ?? [];
              final criteria = _searched!;

              if (available.isEmpty) {
                return _message(
                  'No matching rooms',
                  'Try a different time or a smaller group. '
                      'Opening hours and setup/cleanup time also affect availability.',
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${available.length} available rooms',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(criteria.label),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth >= 760
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;

                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: available.map((room) {
                          return SizedBox(
                            width: width,
                            child: _roomCard(room, criteria),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _roomCard(Row room, RoomSearch criteria) {
    final approval = room['requires_approval'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              room['name'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(room['location'] as String),
            const SizedBox(height: 12),
            Text(room['description'] as String),
            const SizedBox(height: 16),
            Text('Up to ${room['capacity']} guests'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: (room['amenities'] as List)
                  .map((item) => Chip(label: Text('$item')))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Text('${money(room['hourly_rate_cents'] as num)} / hour'),
            const SizedBox(height: 4),
            Text(
              '${money(criteria.estimate(room))} estimated room rental',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              approval
                  ? 'Administrator approval required'
                  : 'Instant confirmation',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _chooseRoom(room, criteria),
              icon: const Icon(Icons.arrow_forward),
              label: Text(
                db.auth.currentUser == null
                    ? 'Sign in to choose'
                    : 'Choose room',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactAdminBooking(Row booking) {
    final start = DateTime.parse(booking['starts_at'] as String);
    final end = DateTime.parse(booking['ends_at'] as String);
    final status = booking['status'] as String;

    final roomData = booking['rm_rooms'];
    final roomName = roomData is Map ? '${roomData['name'] ?? 'Room'}' : 'Room';

    final active = status == 'pending' || status == 'confirmed';
    final canManage = _admin && active && start.isAfter(DateTime.now());

    final scheme = Theme.of(context).colorScheme;

    final statusColor = switch (status) {
      'confirmed' => Colors.green,
      'pending' => Colors.orange.shade800,
      'cancelled' => scheme.error,
      'declined' => scheme.error,
      _ => scheme.onSurfaceVariant,
    };

    final statusBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: statusColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    Future<void> editBooking() async {
      final updated = await _editManagedBooking(booking);

      if (!mounted || !updated) return;

      setState(() {
        _error = null;
        _bookings = _fetchBookings(_tab == 2);
        _results = null;
        _searched = null;
      });
    }

    final actions = widgets.Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canManage)
          IconButton(
            tooltip: 'Edit booking',
            visualDensity: VisualDensity.compact,
            onPressed: _changingStatus ? null : editBooking,
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),

        if (canManage && status == 'pending')
          IconButton(
            tooltip: 'Approve booking',
            visualDensity: VisualDensity.compact,
            color: scheme.primary,
            onPressed: _changingStatus
                ? null
                : () => _changeStatus(booking, 'confirmed'),
            icon: const Icon(Icons.check_circle_outline, size: 21),
          ),

        if (canManage)
          PopupMenuButton<String>(
            tooltip: 'More booking actions',
            enabled: !_changingStatus,
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) async {
              await _changeStatus(booking, value);
            },
            itemBuilder: (_) => [
              if (status == 'pending')
                const PopupMenuItem<String>(
                  value: 'declined',
                  child: Text('Decline booking'),
                ),
              const PopupMenuItem<String>(
                value: 'cancelled',
                child: Text('Cancel booking'),
              ),
            ],
          ),
      ],
    );

    final identity = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          booking['title'] as String,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 3),
        Text(
          '$roomName · ${booking['attendees']} guests',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );

    final schedule = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${bookingTime(start, _zone)} – ${endTime(end, _zone)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 3),
        Text(
          '${money(booking['quoted_total_cents'] as num)} quoted',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 800) {
            return widgets.Row(
              children: [
                Expanded(flex: 3, child: identity),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: schedule),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: statusBadge,
                  ),
                ),
                SizedBox(
                  width: 132,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: actions,
                  ),
                ),
              ],
            );
          }

          // Stack the information on narrower screens.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widgets.Row(
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 8),
                  statusBadge,
                ],
              ),
              const SizedBox(height: 6),
              schedule,
              if (canManage)
                Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        },
      ),
    );
  }

  Widget _bookingsView() {
    final adminView = _tab == 2;

    if (db.auth.currentUser == null) {
      return _message(
        'Your bookings, in one place',
        'Sign in to view and manage your bookings.',
        action: FilledButton(
          onPressed: _authenticate,
          child: const Text('Sign in'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              adminView ? 'Manage bookings' : 'My bookings',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            IconButton(
              tooltip: 'Refresh bookings',
              onPressed: _changingStatus
                  ? null
                  : () {
                      setState(() {
                        _bookings = _fetchBookings(adminView);
                      });
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Latest 100 bookings for the selected organization.'),
        const SizedBox(height: 20),
        FutureBuilder<List<Row>>(
          future: _bookings,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }

            if (snapshot.hasError) {
              return _message(
                'Bookings could not be loaded',
                readableError(snapshot.error!),
              );
            }

            final bookings = snapshot.data ?? [];

            if (bookings.isEmpty) {
              return _message(
                'No bookings yet',
                'Your room reservations will appear here.',
                action: OutlinedButton(
                  onPressed: () => _navigate(0),
                  child: const Text('Find a room'),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: bookings.map((booking) {
                if (adminView) {
                  return _compactAdminBooking(booking);
                }
                final start = DateTime.parse(booking['starts_at'] as String);
                final end = DateTime.parse(booking['ends_at'] as String);
                final status = booking['status'] as String;
                final active = status == 'pending' || status == 'confirmed';
                final future = start.isAfter(DateTime.now());
                final roomData = booking['rm_rooms'];
                final roomName = roomData is Map ? roomData['name'] : 'Room';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking['title'] as String,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text('$roomName · ${booking['attendees']} guests'),
                        const SizedBox(height: 8),
                        Text(
                          '${bookingTime(start, _zone)}'
                          ' – ${endTime(end, _zone)}',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${money(booking['quoted_total_cents'] as num)}'
                          ' quoted room rental',
                        ),
                        const SizedBox(height: 8),
                        Chip(label: Text(status.toUpperCase())),
                        if (active && future) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              if (adminView && _admin)
                                OutlinedButton.icon(
                                  onPressed: _changingStatus
                                      ? null
                                      : () async {
                                          final updated =
                                              await _editManagedBooking(
                                                booking,
                                              );

                                          if (!mounted || !updated) return;

                                          setState(() {
                                            _error = null;

                                            // Reload whichever booking tab is currently open.
                                            _bookings = _fetchBookings(
                                              _tab == 2,
                                            );

                                            // Discard availability results made before the edit.
                                            _results = null;
                                            _searched = null;
                                          });
                                        },
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit'),
                                ),

                              if (adminView && status == 'pending')
                                FilledButton(
                                  onPressed: _changingStatus
                                      ? null
                                      : () =>
                                            _changeStatus(booking, 'confirmed'),
                                  child: const Text('Approve'),
                                ),

                              if (adminView && status == 'pending')
                                OutlinedButton(
                                  onPressed: _changingStatus
                                      ? null
                                      : () =>
                                            _changeStatus(booking, 'declined'),
                                  child: const Text('Decline'),
                                ),

                              TextButton(
                                onPressed: _changingStatus
                                    ? null
                                    : () => _changeStatus(booking, 'cancelled'),
                                child: const Text('Cancel booking'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 1000;

    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.search),
        label: 'Find a room',
      ),
      const NavigationDestination(
        icon: Icon(Icons.event_note_outlined),
        label: 'My bookings',
      ),
      if (_admin)
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          label: 'Manage',
        ),
    ];

    final content = _loadingOrganizations
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: EdgeInsets.all(desktop ? 32 : 16),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_membershipNotice != null) ...[
                      Text(_membershipNotice!),
                      const SizedBox(height: 12),
                    ],
                    if (db.auth.currentUser != null) ...[
                      MembershipStatus(userId: db.auth.currentUser!.id),
                      const SizedBox(height: 24),
                    ],
                    if (_organization != null) ...[
                      Text(
                        _organization!['name'] as String,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'All booking times: $_zone',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_organizations.isEmpty)
                      _message(
                        'Organization unavailable',
                        'This link may be incorrect, the organization may be '
                            'inactive, or you may need to sign in to access it.',
                        action: db.auth.currentUser == null
                            ? OutlinedButton(
                                onPressed: _authenticate,
                                child: const Text('Sign in'),
                              )
                            : OutlinedButton(
                                onPressed: _loadOrganizations,
                                child: const Text('Try again'),
                              ),
                      )
                    else if (_tab == 0)
                      _searchView()
                    else
                      _bookingsView(),
                  ],
                ),
              ),
            ),
          );

// New welcome screen for signed-out visitors.
if (!_loadingOrganizations &&
    _organization == null &&
    db.auth.currentUser == null &&
    _publicBranding != null) {
  return OrganizationWelcome(
    organizationId:
        _publicBranding!['organization_id'] as String?,
    organizationName:
        _publicBranding!['organization_name'] as String? ??
        'your organization',
    showCreateAccount: _signupContext != null,
    onSignIn: () => _authenticate(),
    onCreateAccount: () => _authenticate(register: true),
    onRetry: () => _loadOrganizations(),
    photoAsset: 'assets/images/community_room.jpg',
    error: _error,
  );
}

    if (!_loadingOrganizations && _organization == null) {
      final signedIn = db.auth.currentUser != null;

      return Scaffold(
        appBar: AppBar(
        toolbarHeight: 104,
        title: RmBrandTitle(
          organizationId: _signupContext?['organization_id'] as String?,
        ),
      ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    signedIn
                        ? 'Membership required'
                        : _signupContext != null
                        ? 'Sign in or create an account'
                        : 'Organization unavailable',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    signedIn
                        ? 'This account does not currently have access to this organization, '
                              'or the organization is unavailable.'
                        : _signupContext != null
                        ? 'Create an account for ${_signupContext!["organization_name"]}, '
                              'or sign in with an existing account.'
                        : 'Sign in with an authorized account. Registration is not '
                              'available at this link.',
                    textAlign: TextAlign.center,
                  ),
                  if (_membershipNotice != null) ...[
                    const SizedBox(height: 12),
                    Text(_membershipNotice!, textAlign: TextAlign.center),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: _loadOrganizations,
                        child: const Text('Try again'),
                      ),

                      if (!signedIn)
                        FilledButton(
                          onPressed: () => _authenticate(),
                          child: const Text('Sign in'),
                        ),

                      if (!signedIn && _signupContext != null)
                        OutlinedButton(
                          onPressed: () => _authenticate(register: true),
                          child: const Text('Create account'),
                        ),

                      if (signedIn &&
                          _signupContext != null &&
                          _requestStatus == null)
                        FilledButton(
                          onPressed: _requestingMembership
                              ? null
                              : _requestMembership,
                          child: Text(
                            _requestingMembership
                                ? 'Submitting…'
                                : 'Request membership',
                          ),
                        ),

                      if (signedIn)
                        FilledButton(
                          onPressed: () async {
                            try {
                              await db.auth.signOut();
                            } catch (error) {
                              if (!mounted) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(readableError(error))),
                              );
                            }
                          },
                          child: const Text('Sign out'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 104,
        title: RmBrandTitle(
          organizationId: _organization?['id'] as String?,
        ),
      
    actions: [
          if (db.auth.currentUser != null)
            FutureBuilder<bool>(
              future: db.rpc('rm_is_system_admin'),
              builder: (context, snapshot) {
                if (snapshot.data != true) {
                  return const SizedBox.shrink();
                }

                return IconButton(
                  tooltip: 'Platform dashboard',
                  onPressed: () {
                    context.push('/platform');
                  },
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                );
              },
            ),
          IconButton(
            tooltip: 'Switch light/dark appearance',
            onPressed: widget.toggleTheme,
            icon: const Icon(Icons.brightness_6_outlined),
          ),
          IconButton(
            tooltip: 'My bookings',
            onPressed: () => _navigate(1),
            icon: const Icon(Icons.event_note_outlined),
          ),
          if (_admin)
            IconButton(
              tooltip: 'Booking calendar',
              onPressed: _openCalendar,
              icon: const Icon(Icons.calendar_month_outlined),
            ),
          if (_admin)
            IconButton(
              tooltip: 'Manage rooms',
              onPressed: _openRoomManagement,
              icon: const Icon(Icons.meeting_room_outlined),
            ),
          if (_admin)
            IconButton(
              tooltip: 'Manage members',
              onPressed: _openMemberManagement,
              icon: const Icon(Icons.group_outlined),
            ),
          if (_admin)
            IconButton(
              tooltip: 'Add organization member',
              onPressed: _openAddMember,
              icon: const Icon(Icons.person_add_outlined),
            ),
          if (_admin)
            IconButton(
              tooltip: 'Organization profile',
              onPressed: _openOrganizationProfile,
              icon: const Icon(Icons.business_outlined),
            ),
          if (db.auth.currentUser == null)
            TextButton(onPressed: _authenticate, child: const Text('Sign in'))
          else
            TextButton(
              onPressed: () async {
                try {
                  await db.auth.signOut();
                } catch (error) {
                  if (mounted) {
                    setState(() => _error = readableError(error));
                  }
                }
              },
              child: const Text('Sign out'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: widgets.Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (desktop)
            NavigationRail(
              extended: true,
              selectedIndex: _tab,
              onDestinationSelected: _navigate,
              destinations: [
                const NavigationRailDestination(
                  icon: Icon(Icons.search),
                  label: Text('Find a room'),
                ),
                const NavigationRailDestination(
                  icon: Icon(Icons.event_note_outlined),
                  label: Text('My bookings'),
                ),
                if (_admin)
                  const NavigationRailDestination(
                    icon: Icon(Icons.admin_panel_settings_outlined),
                    label: Text('Manage bookings'),
                  ),
              ],
            ),
          Expanded(child: content),
        ],
      ),
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: _navigate,
              destinations: destinations,
            ),
    );
  }
}

class AuthDialog extends StatefulWidget {
  const AuthDialog({
    super.key,
    this.organizationId,
    this.organizationName,
    this.initialRegister = false,
  });

  final String? organizationId;
  final String? organizationName;
  final bool initialRegister;

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> {
  final _fullName = TextEditingController();
  final _contactPhone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _joinOrganization = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _register = widget.initialRegister;
    _joinOrganization = _register && widget.organizationId != null;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _contactPhone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toggleMode() {
    if (_busy) return;
    setState(() {
      _register = !_register;
      _error = null;
      _notice = null;
      if (_register) _joinOrganization = widget.organizationId != null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;
    final name = _fullName.text.trim();
    final phone = _contactPhone.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    if (_register && (name.isEmpty || name.length > 200)) {
      setState(() => _error = 'Enter your full name, up to 200 characters.');
      return;
    }
    if (_register && phone.length > 50) {
      setState(() => _error = 'Contact phone must be 50 characters or fewer.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_register) {
        final response = await db.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': name,
            'contact_phone': phone,
            if (_joinOrganization && widget.organizationId != null)
              'requested_organization_id': widget.organizationId,
          },
        );
        if (!mounted) return;
        if (response.session != null) {
          Navigator.pop(context);
          return;
        }
        setState(() {
          _busy = false;
          _register = false;
          _password.clear();
          _notice =
              'Check your email for account confirmation, then return '
              'to this organization link and sign in. Membership may require '
              'administrator approval.';
        });
      } else {
        await db.auth.signInWithPassword(email: email, password: password);
        if (!mounted) return;
        Navigator.pop(context);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = readableError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(_register ? 'Create your account' : 'Sign in'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.organizationName != null) ...[
                  Text(
                    widget.organizationName!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                ],
                if (_register) ...[
                  TextField(
                    controller: _fullName,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Full name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contactPhone,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    maxLength: 50,
                    decoration: const InputDecoration(
                      labelText: 'Contact phone — optional',
                      helperText: 'Contact information only; not a phone sign-in method.',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofillHints: [
                    _register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: const InputDecoration(labelText: 'Password'),
                  onSubmitted: (_) => _submit(),
                ),
                if (_register && widget.organizationId != null) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      'Join ${widget.organizationName ?? "this organization"}',
                    ),
                    subtitle: const Text(
                      'Membership may require administrator approval. '
                      'This does not grant administrator access.',
                    ),
                    value: _joinOrganization,
                    onChanged: _busy
                        ? null
                        : (value) => setState(
                            () => _joinOrganization = value ?? false,
                          ),
                  ),
                ],
                if (_notice != null) ...[
                  const SizedBox(height: 16),
                  Text(_notice!),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : _toggleMode,
                  child: Text(
                    _register
                        ? 'Already have an account? Sign in'
                        : 'New here? Create an account',
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              _busy
                  ? 'Please wait…'
                  : _register
                  ? 'Create account'
                  : 'Sign in',
            ),
          ),
        ],
      ),
    );
  }
}

class BookingDialog extends StatefulWidget {
  const BookingDialog({super.key, required this.room, required this.criteria});

  final Row room;
  final RoomSearch criteria;

  @override
  State<BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<BookingDialog> {
  final _title = TextEditingController();
  final _requestId = const Uuid().v4();

  int _step = 0;
  bool _busy = false;
  bool _attempted = false;

  String? _error;
  Row? _created;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });

    try {
      final result = await db.rpc(
        'rm_create_booking',
        params: {
          'p_room_id': widget.room['id'],
          'p_start': widget.criteria.start.toIso8601String(),
          'p_end': widget.criteria.end.toIso8601String(),
          'p_attendees': widget.criteria.attendees,
          'p_title': _title.text.trim(),
          'p_request_id': _requestId,
        },
      );

      if (!mounted) return;

      setState(() {
        _created = Map<String, dynamic>.from(result as Map);
        _busy = false;
        _step = 2;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _error = readableError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final approval = widget.room['requires_approval'] == true;
    final success = _step == 2;

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          success
              ? (_created!['status'] == 'pending'
                    ? 'Booking requested'
                    : 'Booking confirmed')
              : _step == 0
              ? 'Room details'
              : 'Review your booking',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.room['name'] as String,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(widget.criteria.label),
                const SizedBox(height: 8),
                Text('Timezone: ${widget.criteria.zone}'),
                const SizedBox(height: 8),
                Text('${widget.criteria.attendees} guests'),
                const SizedBox(height: 16),
                if (_step == 0) ...[
                  Text(widget.room['description'] as String),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _title,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'Event name',
                      hintText: 'For example: Monthly planning meeting',
                    ),
                  ),
                ] else ...[
                  Text('Event: ${_title.text.trim()}'),
                  const SizedBox(height: 12),
                ],
                Text(
                  '${money(success ? _created!['quoted_total_cents'] as num : widget.criteria.estimate(widget.room))}'
                  ' room rental',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'CAD. Room-rental quote only; taxes, deposits and '
                  'other charges are not calculated in this starter. '
                  'No payment is collected.',
                ),
                const SizedBox(height: 16),
                Text(
                  success
                      ? (_created!['status'] == 'pending'
                            ? 'Your request is awaiting administrator approval.'
                            : 'Your room is reserved.')
                      : approval
                      ? 'This room requires administrator approval.'
                      : 'This room can be confirmed immediately.',
                ),
                if (success) ...[
                  const SizedBox(height: 12),
                  SelectableText('Reference: ${_created!['id']}'),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A retry here uses the same request ID. '
                    'If you close after a connection error, check '
                    'My bookings before starting another request.',
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: success
            ? [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('View my bookings'),
                ),
              ]
            : [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: const Text('Close'),
                ),
                if (_step == 1 && !_attempted)
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _step = 0),
                    child: const Text('Back'),
                  ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () {
                          if (_step == 0) {
                            if (_title.text.trim().isEmpty) {
                              setState(() {
                                _error = 'Please enter an event name.';
                              });
                              return;
                            }

                            setState(() {
                              _error = null;
                              _step = 1;
                            });
                          } else {
                            _submit();
                          }
                        },
                  child: Text(
                    _busy
                        ? 'Saving…'
                        : _step == 0
                        ? 'Review booking'
                        : approval
                        ? 'Submit request'
                        : 'Confirm booking',
                  ),
                ),
              ],
      ),
    );
  }
}
