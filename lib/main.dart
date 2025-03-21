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
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://ikcvgwtrgbeorwdycrxs.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlrY3Znd3RyZ2Jlb3J3ZHljcnhzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDE1MTM3MDMsImV4cCI6MjA1NzA4OTcwM30.azV2oLxI813aNEfmrApta7h6PZ1sbo31NgQq4s6W2Eo',
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeNotifier()),
        ChangeNotifierProvider(create: (context) => CurrencyProvider()),
        ChangeNotifierProvider(create: (context) => GroupProvider()),
        ChangeNotifierProvider(create: (context) => ExpenseProvider()),
        ChangeNotifierProvider(create: (context) => AnalyticsProvider()),
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
          home: const SplashScreen(),
          debugShowCheckedModeBanner: false,
          routes: {
            '/landing': (context) => const LandingScreen(),
            '/auth': (context) => const AuthScreen(),
            '/home': (context) => const MainScreen(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/auth') {
              final bool isSignUp = settings.arguments as bool? ?? false;
              return MaterialPageRoute(
                builder: (context) => LandingScreen(),
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
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Use a short delay for the normal app flow
    await Future.delayed(const Duration(seconds: 2));

    final session = Supabase.instance.client.auth.currentSession;

    if (context.mounted) {
      if (session == null) {
        Navigator.pushReplacementNamed(context, '/landing');
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: CircularProgressIndicator(),  // Show a loading indicator during splash
      ),
    );
  }
}


class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController(); // For sign-up
  final _confirmPasswordController = TextEditingController(); // For sign-up
  bool _isLoading = false;
  bool _isSignUp = false; // Toggle between login and sign-up

  Future<void> _signUp() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match!')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: _emailController.text,
        password: _passwordController.text,
        data: {'username': _usernameController.text},
      );
      if (response.user != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign-up successful!')),
        );
        setState(() => _isSignUp = false); // Switch back to login
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (response.session != null) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
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
            // Logo in center - match size with landing page
            SvgPicture.asset(
              'assets/images/logo.svg',
              height: 160,
              width: 160,
            ),
            const SizedBox(height: 24),
            // "Shaire" text logo - match size with landing page
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

  void _onItemTapped(int index) {
    if (index == 2) {
      // Navigate to add expense screen
      Navigator.push(context,
          MaterialPageRoute(builder: (context) => const AddExpenseScreen()));
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
