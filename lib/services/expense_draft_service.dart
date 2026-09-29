import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/receipt_scanner_section.dart';
import 'logger_service.dart';

class ExpenseDraft {
  final String description;
  final double? totalAmount;
  final String? category;
  final DateTime date;
  final String splitType;
  final List<Map<String, dynamic>> selectedContacts;
  final Map<String, String> individualAmounts;
  final Map<String, String> individualPercents;
  final List<BillEntry> billEntries;
  final String? receiptImagePath;
  final int? currentReceiptId;
  final int? groupId;
  final String? groupName;
  final dynamic friendId;
  final String? friendName;
  final String payerId;
  final String payerName;
  final DateTime lastUpdated;

  ExpenseDraft({
    this.description = '',
    this.totalAmount,
    this.category,
    DateTime? date,
    this.splitType = 'equal',
    this.selectedContacts = const [],
    this.individualAmounts = const {},
    this.individualPercents = const {},
    this.billEntries = const [],
    this.receiptImagePath,
    this.currentReceiptId,
    this.groupId,
    this.groupName,
    this.friendId,
    this.friendName,
    this.payerId = 'you',
    this.payerName = 'You',
    DateTime? lastUpdated,
  })  : date = date ?? DateTime.now(),
        lastUpdated = lastUpdated ?? DateTime.now();

  bool get hasContent =>
      description.trim().isNotEmpty ||
      (totalAmount != null && totalAmount! > 0) ||
      selectedContacts.isNotEmpty ||
      billEntries.isNotEmpty ||
      receiptImagePath != null;

  Map<String, dynamic> toJson() => {
        'description': description,
        'totalAmount': totalAmount,
        'category': category,
        'date': date.toIso8601String(),
        'splitType': splitType,
        'selectedContacts': selectedContacts,
        'individualAmounts': individualAmounts,
        'individualPercents': individualPercents,
        'billEntries': billEntries
            .map((e) => {
                  'description': e.description,
                  'amount': e.amount,
                  'assignedTo': e.assignedTo,
                  'type': e.type.name,
                })
            .toList(),
        'receiptImagePath': receiptImagePath,
        'currentReceiptId': currentReceiptId,
        'groupId': groupId,
        'groupName': groupName,
        'friendId': friendId,
        'friendName': friendName,
        'payerId': payerId,
        'payerName': payerName,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory ExpenseDraft.fromJson(Map<String, dynamic> json) {
    return ExpenseDraft(
      description: json['description'] as String? ?? '',
      totalAmount: (json['totalAmount'] as num?)?.toDouble(),
      category: json['category'] as String?,
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String) ?? DateTime.now()
          : DateTime.now(),
      splitType: json['splitType'] as String? ?? 'equal',
      selectedContacts: (json['selectedContacts'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      individualAmounts: (json['individualAmounts'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          {},
      individualPercents: (json['individualPercents'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
          {},
      billEntries: (json['billEntries'] as List?)
              ?.map((e) {
                final map = Map<String, dynamic>.from(e as Map);
                return BillEntry(
                  description: map['description'] as String? ?? '',
                  amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
                  assignedTo:
                      List<String>.from(map['assignedTo'] as List? ?? []),
                  type: BillEntryType.values.firstWhere(
                    (t) => t.name == map['type'],
                    orElse: () => BillEntryType.item,
                  ),
                );
              })
              .toList() ??
          [],
      receiptImagePath: json['receiptImagePath'] as String?,
      currentReceiptId: json['currentReceiptId'] as int?,
      groupId: json['groupId'] as int?,
      groupName: json['groupName'] as String?,
      friendId: json['friendId'],
      friendName: json['friendName'] as String?,
      payerId: json['payerId'] as String? ?? 'you',
      payerName: json['payerName'] as String? ?? 'You',
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.tryParse(json['lastUpdated'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class ExpenseDraftService {
  static const String _draftKey = 'shaire_expense_draft';

  /// Saves the draft into local storage. If draft has no meaningful content, it clears the draft.
  static Future<void> saveDraft(ExpenseDraft draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!draft.hasContent) {
        await prefs.remove(_draftKey);
        return;
      }
      await prefs.setString(_draftKey, jsonEncode(draft.toJson()));
    } catch (e) {
      LoggerService.warning('Failed to save expense draft: $e');
    }
  }

  /// Retrieves the saved draft from local storage, or null if none exists.
  static Future<ExpenseDraft?> getDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_draftKey);
      if (str == null || str.isEmpty) return null;

      final json = jsonDecode(str) as Map<String, dynamic>;
      final draft = ExpenseDraft.fromJson(json);
      return draft.hasContent ? draft : null;
    } catch (e) {
      LoggerService.warning('Failed to read expense draft: $e');
      return null;
    }
  }

  /// Clears the cached draft from local storage.
  static Future<void> clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (e) {
      LoggerService.warning('Failed to clear expense draft: $e');
    }
  }

  /// Returns true if an active draft with content exists.
  static Future<bool> hasDraft() async {
    final draft = await getDraft();
    return draft != null && draft.hasContent;
  }
}
