import 'package:intl/intl.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef AdminRow = Map<String, dynamic>;

class AdminService {
  AdminService(this._db);

  final SupabaseClient _db;

  List<AdminRow> _rows(dynamic value) {
    return (value as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<List<AdminRow>> listRooms(String organizationId) async {
    final result = await _db.rpc(
      'rm_admin_list_rooms',
      params: {
        'p_organization_id': organizationId,
      },
    );

    return _rows(result);
  }

  Future<AdminRow> createRoom({
    required String organizationId,
    required String name,
    required String description,
    required String location,
    required int capacity,
    required int hourlyRateCents,
    required List<String> amenities,
    required bool requiresApproval,
    required int setupMinutes,
    required int cleanupMinutes,
    required String opensAt,
    required String closesAt,
  }) async {
    final result = await _db.rpc(
      'rm_admin_create_room',
      params: {
        'p_organization_id': organizationId,
        'p_name': name,
        'p_description': description,
        'p_location': location,
        'p_capacity': capacity,
        'p_hourly_rate_cents': hourlyRateCents,
        'p_amenities': amenities,
        'p_requires_approval': requiresApproval,
        'p_setup_minutes': setupMinutes,
        'p_cleanup_minutes': cleanupMinutes,
        'p_opens_at': opensAt,
        'p_closes_at': closesAt,
      },
    );

    return Map<String, dynamic>.from(result as Map);
  }

  Future<AdminRow> updateRoom({
    required String roomId,
    required String name,
    required String description,
    required String location,
    required int capacity,
    required int hourlyRateCents,
    required List<String> amenities,
    required bool requiresApproval,
    required int setupMinutes,
    required int cleanupMinutes,
    required String opensAt,
    required String closesAt,
  }) async {
    final result = await _db.rpc(
      'rm_admin_update_room',
      params: {
        'p_room_id': roomId,
        'p_name': name,
        'p_description': description,
        'p_location': location,
        'p_capacity': capacity,
        'p_hourly_rate_cents': hourlyRateCents,
        'p_amenities': amenities,
        'p_requires_approval': requiresApproval,
        'p_setup_minutes': setupMinutes,
        'p_cleanup_minutes': cleanupMinutes,
        'p_opens_at': opensAt,
        'p_closes_at': closesAt,
      },
    );

    return Map<String, dynamic>.from(result as Map);
  }

  Future<AdminRow> setRoomActive({
    required String roomId,
    required bool active,
  }) async {
    final result = await _db.rpc(
      'rm_admin_set_room_active',
      params: {
        'p_room_id': roomId,
        'p_active': active,
      },
    );

    return Map<String, dynamic>.from(result as Map);
  }

  Future<int> expireStalePendingBookings() async {
    final result = await _db.rpc(
      'rm_expire_stale_pending_bookings',
    );

    return (result as num).toInt();
  }

Future<List<AdminRow>> daySchedule({
  required String organizationId,
  required DateTime day,
}) async {
  final result = await _db.rpc(
    'rm_admin_day_schedule',
    params: {
      'p_organization_id': organizationId,
      'p_day': DateFormat('yyyy-MM-dd').format(day),
    },
  );

  return _rows(result);
}

Future<String> adminCreateBooking({
  required String organizationId,
  required String roomId,
  required String userId,
  required String title,
  required DateTime startsAt,
  required DateTime endsAt,
  required int attendees,
  String status = 'confirmed',
}) async {
  final result = await _db.rpc(
    'rm_admin_create_booking',
    params: {
      'p_organization_id': organizationId,
      'p_room_id': roomId,
      'p_user_id': userId,
      'p_title': title,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_ends_at': endsAt.toUtc().toIso8601String(),
      'p_attendees': attendees,
      'p_status': status,
    },
  );

  return result as String;
}

Future<void> adminUpdateBooking({
  required String organizationId,
  required String bookingId,
  required String roomId,
  required String title,
  required DateTime startsAt,
  required DateTime endsAt,
  required int attendees,
  required String status,
}) async {
  await _db.rpc(
    'rm_admin_update_booking',
    params: {
      'p_organization_id': organizationId,
      'p_booking_id': bookingId,
      'p_room_id': roomId,
      'p_title': title,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_ends_at': endsAt.toUtc().toIso8601String(),
      'p_attendees': attendees,
      'p_status': status,
    },
  );
}

Future<List<Map<String, dynamic>>> searchCustomers({
  required String organizationId,
  required String search,
}) async {
  final term = search.trim();

  if (term.length < 2) {
    return [];
  }

  final result = await _db.rpc(
    'rm_admin_search_customers',
    params: {
      'p_organization_id': organizationId,
      'p_search': term,
    },
  );

  return (result as List)
      .map(
        (item) => Map<String, dynamic>.from(item as Map),
      )
      .toList();
}
}