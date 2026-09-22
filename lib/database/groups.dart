import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/logger_service.dart';

class Group {
  final int id;
  final String name;
  final String? description;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  Group({
    required this.id,
    required this.name,
    this.description,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class GroupService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// Fetch a group by ID
  Future<Group?> fetchGroup(int id) async {
    try {
      final response = await supabase
          .from('groups')
          .select('*')
          .eq('id', id)
          .single();  // Fetch single row

      return Group.fromJson(response);
    } catch (error) {
      LoggerService.error('Error fetching group: $error');
      return null;
    }
  }

  /// Create a new group
  Future<bool> createGroup(Group group) async {
    try {
      await supabase.from('groups').insert(group.toJson());
      LoggerService.info('Group created successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error creating group: $error');
      return false;
    }
  }

  /// Update an existing group
  Future<bool> updateGroup(Group group) async {
    try {
      await supabase
          .from('groups')
          .update(group.toJson())
          .eq('id', group.id);
      LoggerService.info('Group updated successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error updating group: $error');
      return false;
    }
  }

  /// Delete a group by ID
  Future<bool> deleteGroup(int id) async {
    try {
      await supabase.from('groups').delete().eq('id', id);
      LoggerService.info('Group deleted successfully');
      return true;
    } catch (error) {
      LoggerService.error('Error deleting group: $error');
      return false;
    }
  }
}
