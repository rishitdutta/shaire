import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/balance.dart';
import '../database/notifications.dart';
import 'custom_friend_balance_service.dart';
import 'logger_service.dart';

class QuickExpenseService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Ensures a shadow profile exists in `profiles` for unlinked custom friends
  /// so that foreign key constraints on `expense_participants` succeed.
  static Future<bool> _ensureCustomFriendProfileExists(
      String customFriendId, String name) async {
    try {
      final existing = await _supabase
          .from('profiles')
          .select('id')
          .eq('id', customFriendId)
          .maybeSingle();
      if (existing != null) return true;

      final safeName = name.replaceAll(' ', '').toLowerCase();
      final profileData = {
        'id': customFriendId,
        'username':
            'custom_${safeName}_${customFriendId.replaceAll('-', '').substring(0, 4)}',
        'full_name': name,
        'updated_at': DateTime.now().toIso8601String(),
        'currency': 'INR',
        'avatar_url': null,
        'website': null,
      };
      await _supabase.from('profiles').insert(profileData);
      return true;
    } catch (e) {
      LoggerService.warning('Cannot create shadow profile for custom friend: $e');
      return false;
    }
  }

  /// Get current user display name for notifications
  static String _getCurrentUserName() {
    final user = _supabase.auth.currentUser;
    final metaName = user?.userMetadata?['full_name'] as String? ??
        user?.userMetadata?['name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) {
      return metaName.trim();
    }
    if (user?.email != null && user!.email!.isNotEmpty) {
      return user.email!.split('@').first;
    }
    return 'Your friend';
  }

  /// Creates a quick direct-owe expense between current user and friend.
  /// [paidByYou]:
  ///   - true: You paid full amount => Friend owes you [amount]
  ///   - false: Friend paid full amount => You owe friend [amount]
  static Future<bool> createQuickExpense({
    required dynamic friendId,
    required String friendName,
    required bool isCustom,
    required String? linkedUserId,
    required double amount,
    required String description,
    required bool paidByYou,
    required String currencyCode,
    required String currencySymbol,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception("User not authenticated");

    final now = DateTime.now();
    final effectiveDesc =
        description.trim().isNotEmpty ? description.trim() : 'Expense';

    // 1. Insert into `expenses`
    final expenseRes = await _supabase.from('expenses').insert({
      'description': effectiveDesc,
      'total_amount': amount,
      'currency': currencyCode,
      'date': now.toIso8601String(),
      'created_by': user.id,
      'split_type': 'exact',
      'category_id': 7, // Other
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    }).select('id').single();

    final int expenseId = expenseRes['id'] as int;

    // 2. Determine actual participant target ID
    final bool isUnlinkedCustom =
        isCustom && (linkedUserId == null || linkedUserId.isEmpty);
    final String friendIdStr = friendId.toString();
    final String targetUserId =
        (isCustom && linkedUserId != null && linkedUserId.isNotEmpty)
            ? linkedUserId
            : friendIdStr;

    bool hasShadowProfile = false;
    if (isUnlinkedCustom) {
      hasShadowProfile =
          await _ensureCustomFriendProfileExists(friendIdStr, friendName);
    }

    // 3. Insert into `expense_participants` if registered, linked, or has shadow profile
    if (!isUnlinkedCustom || hasShadowProfile) {
      final participantRows = [
        {
          'expense_id': expenseId,
          'user_id': user.id,
          'share_amount': paidByYou ? 0.0 : amount,
          'paid_amount': paidByYou ? amount : 0.0,
          'settled': false,
        },
        {
          'expense_id': expenseId,
          'user_id': targetUserId,
          'share_amount': paidByYou ? amount : 0.0,
          'paid_amount': paidByYou ? 0.0 : amount,
          'settled': false,
        },
      ];
      try {
        await _supabase.from('expense_participants').insert(participantRows);
      } catch (e) {
        LoggerService.error("Error inserting expense participants: $e");
      }
    }

    // 4. Update balances
    if (!isUnlinkedCustom) {
      // Registered or linked user
      final balanceService = BalanceService();
      await balanceService.adjustBalance(
        fromUserId: user.id,
        toUserId: targetUserId,
        deltaAmount: paidByYou ? amount : -amount,
        currency: currencyCode,
      );

      // 5. Send in-app notification to the friend
      try {
        final currentUserName = _getCurrentUserName();
        final formattedAmt = '$currencySymbol${amount.toStringAsFixed(2)}';
        final notifContent = paidByYou
            ? '$currentUserName paid $formattedAmt for "$effectiveDesc" (you owe $formattedAmt)'
            : '$currentUserName recorded that you paid $formattedAmt for "$effectiveDesc"';

        final notif = Notification(
          id: 0,
          userId: targetUserId,
          type: 'expense_added',
          content: notifContent,
          relatedEntityId: expenseId,
          relatedEntityType: 'expense',
          isRead: false,
          createdAt: now,
        );
        await NotificationService().createNotification(notif);
      } catch (e) {
        LoggerService.warning("Failed to create friend notification: $e");
      }
    } else {
      // Unlinked custom friend: update local custom balance & record participation
      await CustomFriendBalanceService.adjustBalance(
        customFriendId: friendIdStr,
        deltaAmount: paidByYou ? amount : -amount,
      );

      await CustomFriendBalanceService.recordParticipation(
        expenseId: expenseId,
        customFriendId: friendIdStr,
        description: effectiveDesc,
        totalAmount: amount,
        friendShare: paidByYou ? amount : 0.0,
        paidByYou: paidByYou,
        date: now,
        payerId: paidByYou ? user.id : friendIdStr,
        paidAmount: paidByYou ? 0.0 : amount,
      );
    }

    LoggerService.info('Quick expense $expenseId created with $friendName ($amount)');
    return true;
  }
}
