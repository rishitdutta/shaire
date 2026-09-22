import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FriendProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 50,
      colors: true,
      printEmojis: true,
      printTime: true,
    ),
  );

  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _pendingReceived = [];
  List<Map<String, dynamic>> _pendingSent = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get friends => _friends;
  List<Map<String, dynamic>> get pendingReceived => _pendingReceived;
  List<Map<String, dynamic>> get pendingSent => _pendingSent;
  bool get isLoading => _isLoading;
  String? get error => _error;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<Map<String, double>> getFriendBalance(String friendId) async {
    if (currentUserId == null) return {'youOwe': 0.0, 'youAreOwed': 0.0};

    try {
      final expensesRes = await _supabase.rpc(
        'get_shared_expenses',
        params: {
          'p_current_user_id': currentUserId,
          'p_friend_id': friendId,
        },
      );

      final paymentsRes = await _supabase
          .from('payments')
          .select('amount, from_user_id, to_user_id')
          .or('and(from_user_id.eq.$currentUserId,to_user_id.eq.$friendId),and(from_user_id.eq.$friendId,to_user_id.eq.$currentUserId)');

      double expensesYouOwe = 0.0;
      double expensesYouAreOwed = 0.0;

      for (final e in expensesRes) {
        final amount = (e['total_amount'] as num).toDouble();
        final yourShare = (e['your_share'] as num? ?? 0).toDouble();
        final friendShare = (e['friend_share'] as num?)?.toDouble() ??
            (amount > yourShare ? amount - yourShare : 0.0);
        final youPaid = (e['you_paid'] as num? ?? 0).toDouble();
        final friendPaid = (e['friend_paid'] as num? ?? 0).toDouble();

        if (youPaid > 0 && friendShare > 0) {
          final coverage = amount > 0 ? (youPaid / amount).clamp(0.0, 1.0) : 1.0;
          expensesYouAreOwed += friendShare * coverage;
        }
        if (friendPaid > 0 && yourShare > 0) {
          final coverage = amount > 0 ? (friendPaid / amount).clamp(0.0, 1.0) : 1.0;
          expensesYouOwe += yourShare * coverage;
        }
      }

      double paidToFriend = 0.0;
      double receivedFromFriend = 0.0;
      for (final p in paymentsRes) {
        final amt = (p['amount'] as num).toDouble();
        if (p['from_user_id'] == currentUserId) {
          paidToFriend += amt;
        } else {
          receivedFromFriend += amt;
        }
      }

      final net = (expensesYouAreOwed - expensesYouOwe) + (paidToFriend - receivedFromFriend);
      return {
        'youOwe': net < 0 ? net.abs() : 0.0,
        'youAreOwed': net > 0 ? net : 0.0,
      };
    } catch (e) {
      _logger.e('Error getting friend balance: $e');
      return {'youOwe': 0.0, 'youAreOwed': 0.0};
    }
  }

  Future<void> fetchFriendsAndRequests() async {
    if (currentUserId == null) return;

    _isLoading = true;
    _error = null;
    // Consider removing immediate notifyListeners if it causes build errors
    // notifyListeners();

    try {
      // --- Fetch Accepted Friends ---
      // Find friendships where status is 'accepted' and current user is involved
      final friendshipsRes = await _supabase
          .from('friendships')
          .select('id, user_id_1, user_id_2')
          .or('user_id_1.eq.$currentUserId,user_id_2.eq.$currentUserId')
          .eq('status', 'accepted');

      final List<String> friendIds = friendshipsRes.map<String>((friendship) {
        return friendship['user_id_1'] == currentUserId
            ? friendship['user_id_2']
            : friendship['user_id_1'];
      }).toList();

      if (friendIds.isNotEmpty) {
        // Fetch profile details for these friend IDs
        final friendsRes = await _supabase
            .from('profiles')
            .select(
                'id, username, full_name, avatar_url') // Add fields as needed
            .inFilter('id', friendIds);
        _friends = friendsRes;
      } else {
        _friends = [];
      }

      // --- Fetch Pending Received Requests ---
      // Where current user is user_id_2 and status is 'pending'
      final pendingReceivedRes = await _supabase
          .from('friendships')
          .select(
              'id, user_id_1, user_id_2, profiles!user_id_1(id, username, full_name, avatar_url)') // Fetch sender profile
          .eq('user_id_2', currentUserId!)
          .eq('status', 'pending');
      _pendingReceived = pendingReceivedRes.map((req) {
        // Restructure to include friendship ID and sender profile
        return {
          'friendship_id': req['id'],
          'sender_profile': req['profiles'],
        };
      }).toList();

      // --- Fetch Pending Sent Requests ---
      // Where current user is user_id_1 and status is 'pending'
      final pendingSentRes = await _supabase
          .from('friendships')
          .select(
              'id, user_id_1, user_id_2, profiles!user_id_2(id, username, full_name, avatar_url)') // Fetch receiver profile
          .eq('user_id_1', currentUserId!)
          .eq('status', 'pending');
      _pendingSent = pendingSentRes.map((req) {
        // Restructure to include friendship ID and receiver profile
        return {
          'friendship_id': req['id'],
          'receiver_profile': req['profiles'],
        };
      }).toList();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _logger.e("Error fetching friends/requests", error: e);
      _error = "Failed to load friends data: ${e.toString()}";
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendFriendRequest(String usernameOrEmail) async {
    if (currentUserId == null) throw Exception("Not logged in");
    if (usernameOrEmail.trim().isEmpty) {
      throw Exception("Username/Email cannot be empty");
    }

    _isLoading = true;
    notifyListeners();

    try {
      // 1. Find the target user's ID
      final potentialUsers = await _supabase
          .from('profiles')
          .select('id, username')
          .or('username.eq.$usernameOrEmail,email.eq.$usernameOrEmail') // Assuming email is in auth.users, might need RPC if not on profile
          .limit(1);

      if (potentialUsers.isEmpty) {
        throw Exception("User not found.");
      }
      final targetUserId = potentialUsers[0]['id'];

      if (targetUserId == currentUserId) {
        throw Exception("You cannot send a friend request to yourself.");
      }

      // 2. Check if friendship already exists (any status)
      final existingFriendship = await _supabase
          .from('friendships')
          .select('id, status')
          .or('and(user_id_1.eq.$currentUserId,user_id_2.eq.$targetUserId),and(user_id_1.eq.$targetUserId,user_id_2.eq.$currentUserId)')
          .maybeSingle();

      if (existingFriendship != null) {
        if (existingFriendship['status'] == 'accepted') {
          throw Exception("You are already friends with this user.");
        } else if (existingFriendship['status'] == 'pending') {
          throw Exception("A friend request already exists with this user.");
        }
        // Potentially handle 'rejected' case if needed (e.g., allow resending after a while)
      }

      // 3. Insert new friendship request
      await _supabase.from('friendships').insert({
        'user_id_1': currentUserId,
        'user_id_2': targetUserId,
        'status': 'pending',
      });

      // 4. Refresh data
      await fetchFriendsAndRequests(); // This handles loading state and notifyListeners
    } catch (e) {
      _logger.e("Error sending friend request", error: e);
      _isLoading = false; // Ensure loading is reset on error
      notifyListeners();
      rethrow; // Re-throw the exception to be caught in the UI
    }
  }

  Future<void> respondToFriendRequest(int friendshipId, bool accept) async {
    if (currentUserId == null) throw Exception("Not logged in");

    try {
      _logger.i("Responding to $friendshipId (accept=$accept)");
      // find the pending request
      final idx = _pendingReceived
          .indexWhere((r) => r['friendship_id'] == friendshipId);
      if (idx < 0) throw Exception("Request not found");
      final req = _pendingReceived[idx];
      final newStatus = accept ? 'accepted' : 'rejected';
      await _supabase.from('friendships').update({'status': newStatus}).eq(
          'id', friendshipId); // use int directly

      _pendingReceived.removeAt(idx);
      if (accept && req['sender_profile'] != null) {
        _friends.add({
          'id': req['sender_profile']['id'],
          'username': req['sender_profile']['username'],
          'full_name': req['sender_profile']['full_name'],
          'avatar_url': req['sender_profile']['avatar_url'],
        });
      }

      notifyListeners();
      _logger.d("Notified listeners");

      await Future.delayed(const Duration(milliseconds: 300));
      fetchFriendsAndRequests();
    } catch (e, st) {
      _logger.e("Failed to respond", error: e, stackTrace: st);
      rethrow;
    }
  }
}

  // Add removeFriend method if needed

