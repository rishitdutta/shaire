import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/logger_service.dart';

class GroupMember {
  final int id;
  final int groupId;
  final String userId;
  final DateTime joinedAt;
  final String role;

  GroupMember({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.joinedAt,
    required this.role,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'],
      groupId: json['group_id'],
      userId: json['user_id'],
      joinedAt: DateTime.parse(json['joined_at']),
      role: json['role'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'group_id': groupId,
      'user_id': userId,
      'joined_at': joinedAt.toIso8601String(),
      'role': role,
    };
  }
}

class GroupMemberService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// Fetch a group member by group ID and user ID
  Future<GroupMember?> fetchGroupMember(int groupId, String userId) async {
    try {
      final response = await supabase
          .from('group_members')
          .select('*')
          .eq('group_id', groupId)
          .eq('user_id', userId)
          .maybeSingle();  // Fetch a single row or return null if no match

      if (response == null) {
        LoggerService.warning('Group member not found');
        return null;
      }
      return GroupMember.fromJson(response);
    } catch (error) {
      LoggerService.error('Error fetching group member: $error');
      return null;
    }
  }

  /// Add a new group member
  Future<bool> addGroupMember(GroupMember member) async {
    try {
      await supabase.from('group_members').insert(member.toJson());
      LoggerService.info('Group member added successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error adding group member: $error');
      return false;
    }
  }

  /// Update an existing group member
  Future<bool> updateGroupMember(GroupMember member) async {
    try {
      await supabase
          .from('group_members')
          .update(member.toJson())
          .eq('id', member.id);

      LoggerService.info('Group member updated successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error updating group member: $error');
      return false;
    }
  }

  /// Remove a group member by ID
  Future<bool> removeGroupMember(int id) async {
    try {
      await supabase.from('group_members').delete().eq('id', id);
      LoggerService.info('Group member removed successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error removing group member: $error');
      return false;
    }
  }
}
