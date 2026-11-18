import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/logger_service.dart';

class Notification {
  final int id;
  final String userId;
  final String type;
  final String content;
  final int? relatedEntityId;
  final String? relatedEntityType;
  final bool isRead;
  final DateTime createdAt;

  Notification({
    required this.id,
    required this.userId,
    required this.type,
    required this.content,
    this.relatedEntityId,
    this.relatedEntityType,
    required this.isRead,
    required this.createdAt,
  });

  /// Factory constructor to create Notification from JSON
  factory Notification.fromJson(Map<String, dynamic> json) {
    return Notification(
      id: json['id'] as int,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      content: json['content'] as String,
      relatedEntityId: json['related_entity_id'] as int?,
      relatedEntityType: json['related_entity_type'] as String?,
      isRead: json['is_read'] as bool,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  /// Convert Notification to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type,
      'content': content,
      'related_entity_id': relatedEntityId,
      'related_entity_type': relatedEntityType,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class NotificationService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// Fetch a notification by ID
  Future<Notification?> fetchNotification(int id) async {
    try {
      final response = await supabase
          .from('notifications')
          .select('*')
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        LoggerService.warning('No notification found for ID: $id');
        return null;
      }

      return Notification.fromJson(response);
    } catch (error) {
      LoggerService.error('Error fetching notification: $error');
      return null;
    }
  }

  /// Create a new notification
  Future<bool> createNotification(Notification notification) async {
    try {
      final json = notification.toJson();
      if (notification.id == 0) {
        json.remove('id');
      }
      await supabase.from('notifications').insert(json);
      LoggerService.info('Notification created successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error creating notification: $error');
      return false;
    }
  }

  /// Update an existing notification
  Future<bool> updateNotification(Notification notification) async {
    try {
      await supabase
          .from('notifications')
          .update(notification.toJson())
          .eq('id', notification.id);

      LoggerService.info('Notification updated successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error updating notification: $error');
      return false;
    }
  }

  /// Delete a notification by ID
  Future<bool> deleteNotification(int id) async {
    try {
      await supabase.from('notifications').delete().eq('id', id);
      LoggerService.info('Notification deleted successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error deleting notification: $error');
      return false;
    }
  }

  /// Recent notifications for a user, newest first. Throws so callers can
  /// show a real error state instead of an empty "no notifications" lie.
  Future<List<Notification>> fetchRecentForUser(String userId,
      {int limit = 50}) async {
    final rows = await supabase
        .from('notifications')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map((json) => Notification.fromJson(json)).toList();
  }

  /// Count of unread notifications for the badge. Never throws — a failed
  /// count simply hides the badge.
  Future<int> unreadCountForUser(String userId) async {
    try {
      final count = await supabase
          .from('notifications')
          .count(CountOption.exact)
          .eq('user_id', userId)
          .eq('is_read', false);
      return count;
    } catch (error) {
      LoggerService.warning('Error counting unread notifications: $error');
      return 0;
    }
  }

  /// Mark every unread notification for the user as read.
  Future<void> markAllReadForUser(String userId) async {
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }
}
