import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/expense.dart';
import '../providers/currency_provider.dart';
import '../providers/user_provider.dart';
import '../services/custom_friend_balance_service.dart';
import '../services/logger_service.dart';
import '../services/pdf_service.dart';
import '../widgets/receipt_scanner_section.dart';

class _ParticipantItem {
  final String id;
  final String name;
  final double shareAmount;
  final double paidAmount;
  final bool isYou;
  final bool isCustom;

  _ParticipantItem({
    required this.id,
    required this.name,
    required this.shareAmount,
    required this.paidAmount,
    this.isYou = false,
    this.isCustom = false,
  });
}

class ExpenseDetailsScreen extends StatefulWidget {
  final Expense expense;

  const ExpenseDetailsScreen({super.key, required this.expense});

  @override
  State<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends State<ExpenseDetailsScreen> {
  bool _loading = true;
  bool _isDownloadingPdf = false;
  List<_ParticipantItem> _participants = [];
  String _payerName = 'You';

  @override
  void initState() {
    super.initState();
    _loadExpenseDetails();
  }

  Future<void> _loadExpenseDetails() async {
    setState(() => _loading = true);
    try {
      SupabaseClient? supabase;
      try {
        supabase = Supabase.instance.client;
      } catch (_) {}

      final currentUserId = supabase?.auth.currentUser?.id;
      final List<_ParticipantItem> list = [];

      // 1. Fetch registered participants from expense_participants
      if (supabase != null) {
        try {
          final partsRes = await supabase
              .from('expense_participants')
              .select('user_id, share_amount, paid_amount, settled')
              .eq('expense_id', widget.expense.id);

          final parts = partsRes as List<dynamic>;
          final userIds = parts.map((p) => p['user_id'] as String).toSet().toList();

          final Map<String, String> names = {};
          if (userIds.isNotEmpty) {
            try {
              final profs = await supabase
                  .from('profiles')
                  .select('id, full_name, username')
                  .filter('id', 'in', userIds);
              for (var pr in profs) {
                final fn = pr['full_name'] as String?;
                final un = pr['username'] as String?;
                names[pr['id'] as String] = (fn != null && fn.isNotEmpty)
                    ? fn
                    : (un != null && un.isNotEmpty ? un : 'User');
              }
            } catch (e) {
              LoggerService.warning('Error fetching participant profiles: $e');
            }
          }

          for (var p in parts) {
            final uid = p['user_id'] as String;
            final isYou = uid == currentUserId;
            final name = isYou ? 'You' : (names[uid] ?? 'Friend');
            list.add(_ParticipantItem(
              id: uid,
              name: name,
              shareAmount: (p['share_amount'] as num?)?.toDouble() ?? 0.0,
              paidAmount: (p['paid_amount'] as num?)?.toDouble() ?? 0.0,
              isYou: isYou,
            ));
          }
        } catch (e) {
          LoggerService.warning('Error fetching expense_participants: $e');
        }

        // 2. Fetch custom friend participants
        try {
          if (currentUserId != null) {
            final customFriends = await supabase
                .from('custom_friends')
                .select('id, name')
                .eq('user_id', currentUserId);

            bool hasPayer = list.any((p) => p.paidAmount > 0.01);

            for (var cf in (customFriends as List<dynamic>)) {
              final cfId = cf['id'].toString();
              // Prevent duplicate participant if already in list
              if (list.any((p) => p.id == cfId)) continue;

              final expenses = await CustomFriendBalanceService.getExpenses(cfId);
              final match = expenses.firstWhere(
                (e) => (e['expense_id'] as num?)?.toInt() == widget.expense.id,
                orElse: () => {},
              );
              if (match.isNotEmpty) {
                final share = (match['friend_share'] as num?)?.toDouble() ?? 0.0;
                final paidByYou = match['paid_by_you'] == true;

                double paidAmount = 0.0;
                if (match['paid_amount'] != null) {
                  paidAmount = (match['paid_amount'] as num).toDouble();
                } else if (match['payer_id'] != null) {
                  paidAmount = (match['payer_id'].toString() == cfId)
                      ? widget.expense.totalAmount
                      : 0.0;
                } else {
                  // Legacy fallback: if you paid or list already has a payer, friend paid 0.
                  // Only if nobody has been marked as payer yet and paidByYou is false,
                  // mark this friend as payer once.
                  if (paidByYou || hasPayer) {
                    paidAmount = 0.0;
                  } else {
                    paidAmount = widget.expense.totalAmount;
                    hasPayer = true;
                  }
                }

                if (paidAmount > 0.01) {
                  hasPayer = true;
                }

                list.add(_ParticipantItem(
                  id: cfId,
                  name: cf['name'] ?? 'Friend',
                  shareAmount: share,
                  paidAmount: paidAmount,
                  isYou: false,
                  isCustom: true,
                ));
              }
            }
          }
        } catch (e) {
          LoggerService.warning('Error fetching custom friend participants: $e');
        }
    }

      // Fallback if no participant rows recorded
      if (list.isEmpty) {
        final isCreator = widget.expense.createdBy == currentUserId;
        list.add(_ParticipantItem(
          id: widget.expense.createdBy,
          name: isCreator ? 'You' : 'Creator',
          shareAmount: widget.expense.totalAmount,
          paidAmount: widget.expense.totalAmount,
          isYou: isCreator,
        ));
      }

      // Determine payer
      final payerItem = list.firstWhere(
        (p) => p.paidAmount > 0,
        orElse: () => _ParticipantItem(
          id: widget.expense.createdBy,
          name: widget.expense.createdBy == currentUserId ? 'You' : 'Creator',
          shareAmount: 0,
          paidAmount: 0,
          isYou: widget.expense.createdBy == currentUserId,
        ),
      );

      if (mounted) {
        setState(() {
          _participants = list;
          _payerName = payerItem.name;
          _loading = false;
        });
      }
    } catch (e) {
      LoggerService.error('Error loading expense details: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _getCurrentUserName() {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final fullName = userProvider.userData?['full_name'] as String?;
      if (fullName != null && fullName.trim().isNotEmpty) {
        return fullName.trim();
      }
      final username = userProvider.userData?['username'] as String?;
      if (username != null && username.trim().isNotEmpty) {
        return username.trim();
      }
    } catch (_) {}

    final user = Supabase.instance.client.auth.currentUser;
    final metaName = user?.userMetadata?['full_name'] as String? ??
        user?.userMetadata?['name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) {
      return metaName.trim();
    }
    if (user?.email != null && user!.email!.isNotEmpty) {
      return user.email!.split('@').first;
    }
    return 'User';
  }

  Future<void> _downloadPdf() async {
    setState(() => _isDownloadingPdf = true);
    try {
      final currencyProvider = Provider.of<CurrencyProvider>(context, listen: false);
      final currentUserName = _getCurrentUserName();
      final effectivePayerName =
          (_payerName.toLowerCase() == 'you') ? currentUserName : _payerName;

      Uint8List? receiptBytes;
      if (widget.expense.receiptImageUrl != null &&
          widget.expense.receiptImageUrl!.isNotEmpty) {
        try {
          final res = await http.get(Uri.parse(widget.expense.receiptImageUrl!));
          if (res.statusCode == 200) receiptBytes = res.bodyBytes;
        } catch (e) {
          LoggerService.warning('Failed to load receipt image bytes for PDF: $e');
        }
      }

      final participantNames = _participants.map((p) {
        return p.isYou || p.name.toLowerCase() == 'you'
            ? currentUserName
            : p.name;
      }).toList();

      final participantShares = _participants.map((p) {
        final displayName = p.isYou || p.name.toLowerCase() == 'you'
            ? currentUserName
            : p.name;
        return {
          'name': displayName,
          'share': p.shareAmount,
          'paid': p.paidAmount,
        };
      }).toList();

      final entries = [
        BillEntry(
          description: widget.expense.description.isNotEmpty
              ? widget.expense.description
              : 'Expense Total',
          amount: widget.expense.totalAmount,
          assignedTo: participantNames,
        ),
      ];

      await PdfService.downloadOrPrintPdf(
        title: widget.expense.description.isNotEmpty
            ? widget.expense.description
            : 'Expense Split',
        merchantName: widget.expense.categoryName,
        date: widget.expense.date,
        totalAmount: widget.expense.totalAmount,
        currencySymbol: currencyProvider.currencySymbol,
        splitType: widget.expense.splitType,
        billEntries: entries,
        participantShares: participantShares,
        receiptImageBytes: receiptBytes,
        payerName: effectivePayerName,
      );
    } catch (e) {
      LoggerService.error('Error generating PDF from expense details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloadingPdf = false);
      }
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Food & Drinks':
        return Icons.restaurant;
      case 'Transportation':
        return Icons.directions_bus;
      case 'Entertainment':
        return Icons.movie;
      case 'Shopping':
        return Icons.shopping_bag;
      case 'Utilities':
        return Icons.lightbulb;
      case 'Rent':
        return Icons.home;
      default:
        return Icons.category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyProvider = Provider.of<CurrencyProvider>(context);

    final title = widget.expense.description.isNotEmpty
        ? widget.expense.description
        : 'Untitled Expense';
    final formattedDate =
        DateFormat('EEEE, MMM d, yyyy · hh:mm a').format(widget.expense.date);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Details'),
        actions: [
          IconButton(
            icon: _isDownloadingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Download / Print PDF',
            onPressed: _isDownloadingPdf ? null : _downloadPdf,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Overview Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(
                        _getCategoryIcon(widget.expense.categoryName),
                        size: 32,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      currencyProvider.format(widget.expense.totalAmount),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formattedDate,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.category_outlined, size: 16),
                          label: Text(widget.expense.categoryName),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          avatar: const Icon(Icons.pie_chart_outline, size: 16),
                          label: Text('${widget.expense.splitType.toUpperCase()} SPLIT'),
                          visualDensity: VisualDensity.compact,
                        ),
                        Chip(
                          avatar: const Icon(Icons.person_pin_circle_outlined, size: 16),
                          label: Text('Paid by $_payerName'),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Split Breakdown Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.people_outline,
                            size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Split Breakdown',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Divider(height: 24, color: theme.dividerColor),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _participants.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 16, color: theme.dividerColor),
                        itemBuilder: (context, index) {
                          final p = _participants[index];
                          final isPayer = p.paidAmount > 0;

                          return Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isPayer
                                    ? colorScheme.primaryContainer
                                    : colorScheme.surfaceContainerHighest,
                                child: Text(
                                  p.name.isNotEmpty
                                      ? p.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isPayer
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (isPayer) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: colorScheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'paid',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme
                                                    .onPrimaryContainer,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (p.isCustom) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: colorScheme
                                                  .surfaceContainerHighest,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'custom',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      isPayer
                                          ? 'Paid ${currencyProvider.format(p.paidAmount)}'
                                          : 'Share: ${currencyProvider.format(p.shareAmount)}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                currencyProvider.format(p.shareAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Receipt Section (if available)
            if (widget.expense.receiptImageUrl != null &&
                widget.expense.receiptImageUrl!.isNotEmpty) ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: theme.dividerColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 20, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Receipt Image',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Divider(height: 24, color: theme.dividerColor),
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              child: InteractiveViewer(
                                child: Image.network(
                                  widget.expense.receiptImageUrl!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.network(
                                widget.expense.receiptImageUrl!,
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 120,
                                  color: colorScheme.surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: const Text('Could not load image'),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.zoom_in,
                                        size: 16, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text(
                                      'Tap to view',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Action Button: Download Split PDF
            OutlinedButton.icon(
              icon: _isDownloadingPdf
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_isDownloadingPdf
                  ? 'Generating PDF...'
                  : 'Download Split PDF'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isDownloadingPdf ? null : _downloadPdf,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
