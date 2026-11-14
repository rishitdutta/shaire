import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:widgetbook/widgetbook.dart';
import 'providers/currency_provider.dart';
import 'theme/theme.dart';
import 'widgets/friend_quick_action_modal.dart';
import 'widgets/edit_tags_dialog.dart';
import 'widgets/split_options_widget.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShaireWidgetbookApp());
}

class ShaireWidgetbookApp extends StatelessWidget {
  const ShaireWidgetbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Widgetbook.material(
      appBuilder: (context, child) {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => CurrencyProvider()),
          ],
          child: child,
        );
      },
      directories: [
        WidgetbookFolder(
          name: 'Quick Expense (New Feature)',
          children: [
            WidgetbookComponent(
              name: 'FriendQuickActionModal',
              useCases: [
                WidgetbookUseCase(
                  name: 'Interactive Trigger (Hold Friend Card)',
                  builder: (context) {
                    return _WidgetbookWrapper(
                      child: Builder(
                        builder: (ctx) => Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Press & Hold to Test Modal',
                                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Long-pressing turns the background translucent black and brings up friend actions + instant expense sheet.',
                                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                Card(
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(color: Theme.of(ctx).dividerColor),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    leading: CircleAvatar(
                                      radius: 22,
                                      backgroundColor: Theme.of(ctx)
                                          .colorScheme
                                          .primaryContainer,
                                      child: Text(
                                        'A',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                    title: const Text(
                                      'Alice Johnson',
                                      style: TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: const Text('You get ₹150.00 • Hold to test'),
                                    trailing: Icon(
                                      Icons.touch_app_outlined,
                                      color: Theme.of(ctx).colorScheme.primary,
                                    ),
                                    onLongPress: () {
                                      FriendQuickActionModal.show(
                                        ctx,
                                        friend: const {
                                          'id': 'u-1234',
                                          'full_name': 'Alice Johnson',
                                          'username': 'alice',
                                          'is_custom': false,
                                        },
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    FriendQuickActionModal.show(
                                      ctx,
                                      friend: const {
                                        'id': 'c-5678',
                                        'full_name': 'Bob Smith',
                                        'name': 'Bob Smith',
                                        'is_custom': true,
                                      },
                                    );
                                  },
                                  icon: const Icon(Icons.bolt),
                                  label: const Text('Open Directly for Bob (Custom Friend)'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                WidgetbookUseCase(
                  name: 'Embedded Sheet - Alice (Registered User)',
                  builder: (context) {
                    return _WidgetbookWrapper(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 450),
                          child: Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: FriendQuickActionModal(
                              friend: const {
                                'id': 'u-1234',
                                'full_name': 'Alice Johnson',
                                'username': 'alice',
                                'is_custom': false,
                                'linked_user_id': null,
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                WidgetbookUseCase(
                  name: 'Embedded Sheet - Bob (Custom / Name Only)',
                  builder: (context) {
                    return _WidgetbookWrapper(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 450),
                          child: Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: FriendQuickActionModal(
                              friend: const {
                                'id': 'c-5678',
                                'full_name': 'Bob Smith',
                                'name': 'Bob Smith',
                                'username': null,
                                'is_custom': true,
                                'linked_user_id': null,
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            WidgetbookComponent(
              name: 'EditTagsDialog',
              useCases: [
                WidgetbookUseCase(
                  name: 'Interactive Modal Trigger',
                  builder: (context) {
                    return _WidgetbookWrapper(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Quick Tags Manager',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            const Text('Add, delete, or reorder tags with drag-and-drop.'),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {
                                EditTagsDialog.show(context, [
                                  '🍔 Food',
                                  '☕ Coffee',
                                  '🚕 Cab',
                                ]);
                              },
                              icon: const Icon(Icons.tune),
                              label: const Text('Open Manage Tags Dialog'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                WidgetbookUseCase(
                  name: 'Dialog Preview',
                  builder: (context) {
                    return _WidgetbookWrapper(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: const EditTagsDialog(
                            initialTags: [
                              '🍔 Food',
                              '☕ Coffee',
                              '🚕 Cab',
                              '🛒 Grocery',
                              '🍿 Movie',
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        WidgetbookFolder(
          name: 'Split Options',
          children: [
            WidgetbookComponent(
              name: 'SplitOptionsWidget',
              useCases: [
                WidgetbookUseCase(
                  name: 'Equal Split with Multi-Payers',
                  builder: (context) => const _SplitOptionsDemoWrapper(),
                ),
              ],
            ),
          ],
        ),
      ],
      addons: [
        MaterialThemeAddon(
          themes: [
            WidgetbookTheme(
              name: 'Light',
              data: AppTheme.lightTheme,
            ),
            WidgetbookTheme(
              name: 'Dark',
              data: AppTheme.darkTheme,
            ),
          ],
        ),
      ],
    );
  }
}

class _SplitOptionsDemoWrapper extends StatefulWidget {
  const _SplitOptionsDemoWrapper();

  @override
  State<_SplitOptionsDemoWrapper> createState() => _SplitOptionsDemoWrapperState();
}

class _SplitOptionsDemoWrapperState extends State<_SplitOptionsDemoWrapper>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _totalAmountController =
      TextEditingController(text: '300.00');
  final Map<String, TextEditingController> _individualAmountControllers = {};
  final Map<String, TextEditingController> _individualPercentControllers = {};
  SplitType _splitType = SplitType.equal;

  final List<Map<String, dynamic>> _contacts = [
    {'id': '101', 'name': 'Bob Smith'},
    {'id': '102', 'name': 'Alice Johnson'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _totalAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _WidgetbookWrapper(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SplitOptionsWidget(
                tabController: _tabController,
                splitType: _splitType,
                selectedContacts: _contacts,
                totalAmountController: _totalAmountController,
                individualAmountControllers: _individualAmountControllers,
                individualPercentControllers: _individualPercentControllers,
                isMultiplePayers: true,
                payerAmounts: const {
                  'you': 180.0,
                  '101': 120.0,
                },
                onSplitTypeChanged: (type) {
                  setState(() => _splitType = type);
                },
                onAmountsChanged: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WidgetbookWrapper extends StatelessWidget {
  final Widget child;

  const _WidgetbookWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CurrencyProvider()),
      ],
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      ),
    );
  }
}
