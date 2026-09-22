import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/logger_service.dart';

class GroupProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _groups = [];
  bool _isLoading = false;
  bool _hasFetched = false;
  String? _error;

  List<Map<String, dynamic>> get groups => _groups;
  bool get isLoading => _isLoading || !_hasFetched;
  String? get error => _error;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<void> fetchGroups() async {
    if (currentUserId == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Fetch group IDs the user is a member of
      final memberRes = await _supabase
          .from('group_members')
          .select('group_id')
          .eq('user_id', currentUserId!);

      final List<int> groupIds =
          memberRes.map<int>((m) => m['group_id'] as int).toList();

      if (groupIds.isNotEmpty) {
        // Fetch details for those groups
        // Also fetch member count for each group (example using count)
        final groupsRes = await _supabase
            .from('groups')
            .select(
                'id, name, description, created_at, group_members(count)') // Fetch member count
            .inFilter('id', groupIds);

        // Map the result to include member count directly
        _groups = groupsRes.map((group) {
          final memberCount =
              (group['group_members'] as List?)?.isNotEmpty ?? false
                  ? group['group_members'][0]['count']
                  : 0;
          return {
            'id': group['id'] as int,
            'name': group['name'],
            'description': group['description'],
            'created_at': group['created_at'],
            'member_count': memberCount,
          };
        }).toList();
      } else {
        _groups = [];
      }
      _hasFetched = true;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      LoggerService.error("Error fetching groups: $e");
      _error = "Failed to load groups data: ${e.toString()}";
      _hasFetched = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int> createGroup(String name, String? description) async {
    if (currentUserId == null) throw Exception("Not logged in");
    if (name.trim().isEmpty) throw Exception("Group name cannot be empty");

    _isLoading = true;
    _error = null;
    notifyListeners();

    LoggerService.info("Creating group: $name");
    LoggerService.debug("Description: ${description ?? '<none>'}");

    try {
      final insertRes = await _supabase
          .from('groups')
          .insert({
            'name': name.trim(),
            'description': description?.trim(),
            'created_by': currentUserId!,
          })
          .select('id')
          .single();
      final newGroupId = insertRes['id'] as int;

      LoggerService.info("Created group with ID: $newGroupId");

      // add creator as admin
      await _supabase.from('group_members').insert({
        'group_id': newGroupId,
        'user_id': currentUserId!,
        'role': 'admin',
      });
      LoggerService.info("Added creator $currentUserId as admin to $newGroupId");

      await fetchGroups();
      return newGroupId;
    } catch (e, st) {
      LoggerService.error("Failed to create group", e, st);
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addMembersToGroup(int groupId, List<String> userIds) async {
    if (currentUserId == null) throw Exception('Not logged in');

    if (userIds.isEmpty) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now().toIso8601String();

      // Create a batch of records to insert
      final membersToAdd = userIds
          .map((userId) => {
                'group_id': groupId,
                'user_id': userId,
                'role': 'member',
                'joined_at': now
              })
          .toList();

      LoggerService.debug('Adding ${membersToAdd.length} members to group $groupId');

      // Insert into group_members table
      await _supabase.from('group_members').insert(membersToAdd);
      LoggerService.info('Successfully added members to group $groupId');

      await fetchGroups(); // Refresh the groups data
    } catch (e) {
      _error = e.toString();
      LoggerService.error('Error adding members: $_error', e);
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> joinGroup(String inviteCode) async {
    final userId = currentUserId; // Store in local variable
    if (userId == null) throw Exception('Not logged in');

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      LoggerService.debug('Joining group with code: "${inviteCode.trim()}"');

      final results = await _supabase
          .from('groups')
          .select('id')
          .eq('invite_code', inviteCode.trim());

      if (results.isEmpty) {
        throw Exception('Invalid invite code. Please check and try again.');
      }

      final groupId = results[0]['id'];
      LoggerService.debug('Found group with ID: $groupId');

      final existingCheck = await _supabase
          .from('group_members')
          .select('id')
          .eq('group_id', groupId)
          .eq('user_id', userId);

      if (existingCheck.isNotEmpty) {
        throw Exception('You are already a member of this group.');
      }

      await _supabase.from('group_members').insert({
        'group_id': groupId,
        'user_id': userId,
        'role': 'member',
      });

      LoggerService.info('Successfully joined group with ID: $groupId');
      await fetchGroups();
    } catch (e) {
      _error = e.toString();
      LoggerService.error('Error joining group: $_error', e);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch full details for a group: info, members with profiles, activities, and pairwise balances
  Future<Map<String, dynamic>> fetchGroupDetails(int groupId) async {
    final userId = currentUserId;

    // 1. Fetch group info
    final groupRes = await _supabase
        .from('groups')
        .select('name, invite_code, created_by')
        .eq('id', groupId)
        .single();

    final groupName = groupRes['name'] as String?;
    final inviteCode = groupRes['invite_code'] as String?;
    final createdById = groupRes['created_by'] as String?;

    // 2. Fetch members with profiles
    final membersRes = await _supabase
        .from('group_members')
        .select(
            'user_id, role, joined_at, profiles:user_id(username, full_name, avatar_url)')
        .eq('group_id', groupId);

    final List<Map<String, dynamic>> members = [];
    for (final m in membersRes) {
      final profile = m['profiles'] ?? {};
      members.add({
        'user_id': m['user_id'],
        'role': m['role'],
        'joined_at': m['joined_at'],
        'username': profile['username'],
        'full_name': profile['full_name'],
        'avatar_url': profile['avatar_url'],
      });
    }

    // 3. Fetch expenses
    final expensesRes = await _supabase
        .from('expenses')
        .select('''
        id, description, total_amount, date, created_at,
        creator:created_by(username, full_name)
      ''')
        .eq('group_id', groupId)
        .order('date', ascending: false)
        .limit(20);

    final List<Map<String, dynamic>> activities = [];
    for (final e in expensesRes) {
      final creator = e['creator'] ?? {};
      activities.add({
        'id': e['id'],
        'desc': e['description'],
        'amount': e['total_amount'],
        'when': e['date'] != null
            ? DateTime.parse(e['date'])
            : DateTime.parse(e['created_at']),
        'actor': creator['full_name'] ?? creator['username'] ?? 'Unknown',
      });
    }

    // 4. Calculate member balances
    final Map<String, Map<String, double>> memberBalances = {};
    final expenseIds = expensesRes.map((e) => e['id'] as int).toList();
    if (expenseIds.isNotEmpty && userId != null) {
      final participantsRes = await _supabase
          .from('expense_participants')
          .select('expense_id, user_id, share_amount, paid_amount, settled')
          .inFilter('expense_id', expenseIds);

      final Map<int, List<Map<String, dynamic>>> expenseParticipants = {};
      for (final p in participantsRes) {
        final expId = p['expense_id'] as int;
        expenseParticipants.putIfAbsent(expId, () => []).add(p);
      }

      for (final m in members) {
        final memberId = m['user_id'] as String;
        if (memberId == userId) continue;

        double youOwe = 0.0;
        double youAreOwed = 0.0;

        for (final exp in expensesRes) {
          final expId = exp['id'] as int;
          final parts = expenseParticipants[expId] ?? [];
          final totalExpAmount = (exp['total_amount'] as num).toDouble();
          if (totalExpAmount <= 0) continue;

          final myPart = parts.where((p) => p['user_id'] == userId).firstOrNull;
          final memberPart = parts.where((p) => p['user_id'] == memberId).firstOrNull;

          if (myPart != null && memberPart != null) {
            final myPaid = (myPart['paid_amount'] as num? ?? 0).toDouble();
            final memberShare = (memberPart['share_amount'] as num? ?? 0).toDouble();
            final memberPaid = (memberPart['paid_amount'] as num? ?? 0).toDouble();
            final myShare = (myPart['share_amount'] as num? ?? 0).toDouble();

            if (myPaid > 0 && memberShare > 0) {
              final ratio = (myPaid / totalExpAmount).clamp(0.0, 1.0);
              youAreOwed += memberShare * ratio;
            }
            if (memberPaid > 0 && myShare > 0) {
              final ratio = (memberPaid / totalExpAmount).clamp(0.0, 1.0);
              youOwe += myShare * ratio;
            }
          }
        }

        final net = youAreOwed - youOwe;
        memberBalances[memberId] = {
          'youOwe': net < 0 ? net.abs() : 0.0,
          'youAreOwed': net > 0 ? net : 0.0,
        };
      }
    }

    return {
      'groupName': groupName,
      'inviteCode': inviteCode,
      'createdById': createdById,
      'members': members,
      'activities': activities,
      'memberBalances': memberBalances,
    };
  }

  Future<void> updateGroupName(int groupId, String newName) async {
    await _supabase.from('groups').update({
      'name': newName.trim(),
    }).eq('id', groupId);
    LoggerService.info('Updated group $groupId name to $newName');
    await fetchGroups();
  }

  Future<void> deleteGroup(int groupId) async {
    await _supabase.from('groups').delete().eq('id', groupId);
    LoggerService.info('Deleted group $groupId');
    _groups.removeWhere((g) => g['id'] == groupId);
    notifyListeners();
  }
}
