import 'package:flutter/material.dart';
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
import 'services/logger_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://jdopfszmrrcdghgaowme.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Impkb3Bmc3ptcnJjZGdoZ2Fvd21lIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDQ0MTk1MzgsImV4cCI6MjA1OTk5NTUzOH0.hyuNiGoVf3nKFOYAlzU6iVeFZmVp2u6fjnjqcbFdTjI',
  );

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
          // home: const SplashScreen(), // Entry point is splash screen
          debugShowCheckedModeBanner: false,
          navigatorObservers: [routeObserver],
          initialRoute: '/',
          routes: {
            '/': (context) => const SplashScreen(), // Root route for redirects
            '/landing': (context) => const LandingScreen(),
            //'/auth': (context) => const AuthScreen(isSignUp: false), // Fixed: providing default value
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

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    /* // Initialize user provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<UserProvider>(context, listen: false).initialize();
    }); */

    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Use a shorter delay for better UX
    await Future.delayed(const Duration(milliseconds: 1500));

    final session = Supabase.instance.client.auth.currentSession;
    final user = Supabase.instance.client.auth.currentUser;

    if (!mounted) return; // Check if widget is still mounted

    // Clear navigation stack and go to appropriate screen
    if (session == null) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/landing', (route) => false);
    } else if (user?.emailConfirmedAt == null) {
      // Email not verified, go to Auth screen (which should show login)
      // Or potentially a dedicated "Please Verify Email" screen
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (route) => false,
          arguments: false); // Explicitly go to login
    } else {
      // Logged in and email verified, check profile completion
      try {
        // Use UserProvider to get profile status
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        // Fetch profile if not already loaded (getUserProfile handles caching)
        final profile = await userProvider.getUserProfile();

        if (!mounted) return; // Check again after await

        final bool isProfileComplete = profile['profile_complete'] ?? false;

        if (isProfileComplete) {
          // Profile complete, go home
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/home', (route) => false);
        } else {
          // Profile incomplete, go to complete profile screen
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (context) => const CompleteProfileScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        // Handle error fetching profile (e.g., show error message or go to login)
        LoggerService.error("Error fetching profile in SplashScreen: $e");
        if (mounted) {
          // Option: Go to login on error
          Navigator.of(context).pushNamedAndRemoveUntil(
              '/auth', (route) => false,
              arguments: false);
          // Option: Show a persistent error (less ideal for splash)
          // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading profile.")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Center(
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
              padding: const EdgeInsets.only(bottom: 80.0),
              child: CircularProgressIndicator(
                color: primaryColor,
                strokeWidth: 3,
              ),
            ),
          ],
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

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Initialize directly instead of using late
  final List<Widget> _screens = [
    const HomeScreen(),
    const GroupsScreen(),
    const SizedBox(), // Placeholder for FAB navigation
    const ExpensesScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Remove the initialization here
  }

  // Screen titles map (for centered title)
  final Map<int, String> _screenTitles = {
    0: 'Shaire',
    1: 'Groups',
    3: 'Expenses',
    4: 'Profile',
  };

  // In MainScreen class, update the _onItemTapped method:

  void _onItemTapped(int index) {
    if (index == 2) {
      // Navigate to add expense screen
      Navigator.push(context,
              MaterialPageRoute(builder: (context) => const AddExpenseScreen()))
          .then((_) {
        // Refresh expenses data when returning from the add expense screen
        if (mounted && _selectedIndex == 3) {
          // Expenses tab
          Provider.of<ExpenseProvider>(context, listen: false).fetchExpenses();
        }
      });
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Groups screen has its own AppBar, so we conditionally render the main AppBar
    final bool isGroupsScreen = _selectedIndex == 1;

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
                Padding(
                  padding: const EdgeInsets.only(
                      right: 16, top: 8, bottom: 8, left: 8),
                  child: IconButton(
                    icon: Icon(
                      _selectedIndex == 0
                          ? Icons.notifications
                          : _selectedIndex == 4
                              ? Icons.settings
                              : null,
                    ),
                    onPressed: () {
                      if (_selectedIndex == 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Notifications coming soon'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else if (_selectedIndex == 4) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(),
                          ),
                        );
                      }
                    },
                    style: _selectedIndex != 0 && _selectedIndex != 4
                        ? ButtonStyle(
                            foregroundColor:
                                WidgetStateProperty.all(Colors.transparent),
                          )
                        : null,
                  ),
                ),
              ],
            ),
      body: _screens[_selectedIndex == 2 ? 0 : _selectedIndex],
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onItemTapped(2),
        tooltip: 'Add Expense',
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 12.0,
        child: SizedBox(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left side items
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Shaire button
                    _buildNavItem(0, Icons.home, 'Shaire'),
                    // Groups button
                    _buildNavItem(1, Icons.group, 'Groups'),
                  ],
                ),
              ),

              // Space for the FAB
              const SizedBox(width: 50),

              // Right side items
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Expenses button
                    _buildNavItem(3, Icons.receipt_long, 'Expenses'),
                    // Profile button
                    _buildNavItem(4, Icons.person, 'Profile'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to build nav items with consistent style and reduced size
  Widget _buildNavItem(int index, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: Icon(
              icon,
              color: _selectedIndex == index
                  ? Theme.of(context).colorScheme.primary
                  : null,
              size: 28, // Explicit size
            ),
            onPressed: () => _onItemTapped(index),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: _selectedIndex == index
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
