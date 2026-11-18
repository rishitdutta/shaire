import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'screens/groups_screen.dart';
import 'screens/add_expense_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/landing_screen.dart';
import 'theme/theme.dart';
import 'providers/currency_provider.dart';
import 'providers/expense_provider.dart';
import 'providers/group_provider.dart';
import 'providers/user_spending_analytics_provider.dart';
import 'providers/user_provider.dart';
import 'providers/prediction_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'screens/auth_screen.dart';
import 'screens/complete_profile_screen.dart';
import 'providers/friend_provider.dart';
import 'database/notifications.dart';
import 'services/realtime_service.dart';
import 'widgets/notifications_sheet.dart';
import 'services/logger_service.dart';

/// Breakpoint (logical px) at which the shell switches from the phone bottom
/// bar to a tablet/desktop navigation rail.
const double kWideLayoutBreakpoint = 720;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jdopfszmrrcdghgaowme.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseAnonKey.isEmpty) {
    throw StateError(
      'SUPABASE_ANON_KEY is not defined. '
      'Please ensure you have configured your .env file and run with '
      '--dart-define-from-file=.env',
    );
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  // Table-change broadcasts keep provider caches honest across devices.
  RealtimeService.instance.start();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeNotifier()),
        ChangeNotifierProvider(create: (context) => CurrencyProvider()),
        ChangeNotifierProvider(create: (context) => GroupProvider()),
        ChangeNotifierProvider(create: (context) => ExpenseProvider()),
        ChangeNotifierProvider(create: (context) => AnalyticsProvider()),
        ChangeNotifierProvider(create: (context) => UserProvider()),
        ChangeNotifierProvider(create: (context) => PredictionProvider()),
        ChangeNotifierProvider(create: (context) => FriendProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        return MaterialApp(
          title: 'Shaire',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeNotifier.themeMode,
          debugShowCheckedModeBanner: false,
          navigatorObservers: [routeObserver],
          initialRoute: '/',
          routes: {
            '/': (context) => const SplashScreen(), // Root route for redirects
            '/landing': (context) => const LandingScreen(),
            '/home': (context) => const MainScreen(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/auth') {
              final bool isSignUp = settings.arguments as bool? ?? false;
              return MaterialPageRoute(
                builder: (context) => AuthScreen(isSignUp: isSignUp),
              );
            }
            return null;
          },
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _minVisibleDuration = Duration(milliseconds: 350);

  late final AnimationController _introController;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();
    _checkAuthAndNavigate();
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndNavigate() async {
    final start = DateTime.now();

    // Kick off the auth work immediately — no artificial delay before it.
    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;

    String? targetRoute;
    Object? targetArguments;
    var targetIsNamed = true;

    if (session == null) {
      targetRoute = '/landing';
    } else if (user?.emailConfirmedAt == null) {
      targetRoute = '/auth';
      targetArguments = false;
    } else {
      try {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final profile = await userProvider.getUserProfile();
        final bool isProfileComplete = profile['profile_complete'] ?? false;
        if (isProfileComplete) {
          targetRoute = '/home';
        } else {
          targetIsNamed = false;
        }
      } catch (e) {
        LoggerService.error("Error fetching profile in SplashScreen: $e");
        targetRoute = '/auth';
        targetArguments = false;
      }
    }

    // Keep the brand frame visible for a beat to avoid a flash, but never
    // block on a fixed timer like the old 1500 ms delay did.
    final elapsed = DateTime.now().difference(start);
    if (elapsed < _minVisibleDuration) {
      await Future.delayed(_minVisibleDuration - elapsed);
    }

    if (!mounted) return;

    if (targetIsNamed) {
      Navigator.of(context).pushNamedAndRemoveUntil(
          targetRoute!, (route) => false,
          arguments: targetArguments);
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const CompleteProfileScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: DecoratedBox(
        // Flat brand surface — no gradient.
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _introController,
                curve: Curves.easeOut,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // Logo in center
                  SvgPicture.asset(
                    'assets/images/logo.svg',
                    height: 160,
                    width: 160,
                  ),
                  const SizedBox(height: 24),
                  // "Shaire" text logo
                  SvgPicture.asset(
                    'assets/images/logo_text.svg',
                    height: 50,
                    colorFilter: ColorFilter.mode(
                      primaryColor,
                      BlendMode.srcIn,
                    ),
                  ),
                  const Spacer(),
                  // Loader at the bottom
                  Padding(
                    padding: const EdgeInsets.only(bottom: 64.0),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: primaryColor,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

/// One tab entry of the phone bottom bar. Replaces the old raw-IconButton row
/// which had tiny (40 px) tap targets, no indicator and a hidden third
/// button with a null icon.
class _BottomNavDestination extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BottomNavDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Icon(icon, size: 24, color: foreground),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: foreground,
                  ),
                  child:
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  int _unreadNotifications = 0;

  @override
  void initState() {
    super.initState();
    _refreshUnreadCount();
  }

  Future<void> _refreshUnreadCount() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final count = await NotificationService().unreadCountForUser(user.id);
    if (mounted) setState(() => _unreadNotifications = count);
  }

  // Screen order matches the four tab destinations; index 2 in the old
  // (5-slot) scheme was just a placeholder for the FAB and is gone now.
  static const List<Widget> _screens = [
    HomeScreen(),
    GroupsScreen(),
    ExpensesScreen(),
    ProfileScreen(),
  ];

  static const List<_TabSpec> _tabs = [
    _TabSpec('Shaire', Icons.home_outlined, Icons.home),
    _TabSpec('Groups', Icons.group_outlined, Icons.group),
    _TabSpec('Expenses', Icons.receipt_long_outlined, Icons.receipt_long),
    _TabSpec('Profile', Icons.person_outline, Icons.person),
  ];

  static const Map<int, String> _screenTitles = {
    0: 'Shaire',
    2: 'Expenses',
    3: 'Profile',
  };

  /// Maps bottom-bar indices to IndexedStack children (the FAB no longer
  /// occupies a slot, but keeps the docked middle position visually).
  int get _stackIndex => _selectedIndex;

  void _openAddExpense() {
    // Returning to the shell refreshes Home and Expenses through their
    // own RouteAware didPopNext hooks — no duplicate fetch needed here.
    Navigator.push(context,
        MaterialPageRoute(builder: (context) => const AddExpenseScreen()));
  }

  void _onItemTapped(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= kWideLayoutBreakpoint;

    // Groups screen has its own AppBar, so we conditionally render the main
    // AppBar.
    final bool isGroupsScreen = _selectedIndex == 1;

    final body = IndexedStack(
      index: _stackIndex,
      children: _screens,
    );

    return Scaffold(
      // Only show AppBar if NOT on the Groups screen
      appBar: isGroupsScreen
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              leading: Padding(
                padding: const EdgeInsets.only(
                    left: 20, top: 8, bottom: 8, right: 8),
                child: Image.asset('assets/images/logo.png'),
              ),
              title: Text(
                _screenTitles[_selectedIndex] ?? '',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              centerTitle: true,
              actions: [
                // One meaningful action per tab instead of an invisible
                // null-icon button on the other two.
                if (_selectedIndex == 0)
                  IconButton(
                    icon: Badge(
                      isLabelVisible: _unreadNotifications > 0,
                      label: Text(_unreadNotifications > 99
                          ? '99+'
                          : '$_unreadNotifications'),
                      child: const Icon(Icons.notifications_none),
                    ),
                    tooltip: 'Notifications',
                    onPressed: () async {
                      await NotificationsSheet.show(context);
                      if (!mounted) return;
                      _refreshUnreadCount();
                      // A "mark all read" may have changed what Home shows.
                    },
                  )
                else if (_selectedIndex == 3)
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
              ],
            ),
      body: isWide
          ? Row(
              children: [
                _buildRail(context),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  // Cap content width on very large screens for readability.
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 840),
                      child: body,
                    ),
                  ),
                ),
              ],
            )
          : body,
      // On phones the FAB docks in the notch; on wide layouts it floats at
      // the end of the content area.
      floatingActionButton: isWide
          ? null
          : FloatingActionButton(
              onPressed: _openAddExpense,
              tooltip: 'Add Expense',
              child: const Icon(Icons.add),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: isWide
          ? null
          : BottomAppBar(
              shape: const CircularNotchedRectangle(),
              notchMargin: 10,
              padding: EdgeInsets.zero,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    // Two tabs, the notched gap, two tabs.
                    for (final i in const [0, 1])
                      _BottomNavDestination(
                        icon: _selectedIndex == i
                            ? _tabs[i].selectedIcon
                            : _tabs[i].icon,
                        label: _tabs[i].label,
                        selected: _selectedIndex == i,
                        onTap: () => _onItemTapped(i),
                      ),
                    const SizedBox(width: 72),
                    for (final i in const [2, 3])
                      _BottomNavDestination(
                        icon: _selectedIndex == i
                            ? _tabs[i].selectedIcon
                            : _tabs[i].icon,
                        label: _tabs[i].label,
                        selected: _selectedIndex == i,
                        onTap: () => _onItemTapped(i),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRail(BuildContext context) {
    return NavigationRail(
      onDestinationSelected: _onItemTapped,
      selectedIndex: _selectedIndex,
      labelType: NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            SvgPicture.asset('assets/images/logo.svg', height: 44, width: 44),
            const SizedBox(height: 24),
          ],
        ),
      ),
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: FloatingActionButton(
              heroTag: 'railAddExpense',
              onPressed: _openAddExpense,
              tooltip: 'Add Expense',
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ),
      destinations: [
        for (final tab in _tabs)
          NavigationRailDestination(
            icon: Icon(tab.icon),
            selectedIcon: Icon(tab.selectedIcon),
            label: Text(tab.label),
          ),
      ],
    );
  }
}

class _TabSpec {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  const _TabSpec(this.label, this.icon, this.selectedIcon);
}
