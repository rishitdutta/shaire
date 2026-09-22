import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/logger_service.dart';

class Friendship {
  final int id;
  final String user1;
  final String user2;
  final String status;
  final DateTime createdAt;

  Friendship({
    required this.id,
    required this.user1,
    required this.user2,
    required this.status,
    required this.createdAt,
  });

  factory Friendship.fromJson(Map<String, dynamic> json) {
    return Friendship(
      id: json['id'],
      user1: json['user_id_1'],
      user2: json['user_id_2'],
      status: json['status'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id_1': user1,
      'user_id_2': user2,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class FriendshipService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// Fetch friendship by checking both user1 → user2 and user2 → user1 combinations
  Future<Friendship?> fetchFriendship(String user1, String user2) async {
    try {
      final response = await supabase
          .from('friendships')
          .select('*')
          .or('user_id_1.eq.$user1.and.user_id_2.eq.$user2, user_id_1.eq.$user2.and.user_id_2.eq.$user1')
          .single();

      return Friendship.fromJson(response);
    } catch (error) {
      LoggerService.error('Error fetching friendship: $error');
      return null;
    }
  }

  /// Create a new friendship
  Future<bool> createFriendship(Friendship friendship) async {
    try {
      await supabase.from('friendships').insert(friendship.toJson());
      LoggerService.info('Friendship created successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error creating friendship: $error');
      return false;
    }
  }

  /// Update an existing friendship
  Future<bool> updateFriendship(Friendship friendship) async {
    try {
      await supabase
          .from('friendships')
          .update(friendship.toJson())
          .eq('id', friendship.id);
      LoggerService.info('Friendship updated successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error updating friendship: $error');
      return false;
    }
  }

  /// Delete a friendship by ID
  Future<bool> deleteFriendship(int id) async {
    try {
      await supabase.from('friendships').delete().eq('id', id);
      LoggerService.info('Friendship deleted successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error deleting friendship: $error');
      return false;
    }
  }
}
