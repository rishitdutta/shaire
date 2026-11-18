import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'auth_screen.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 1),
              // Logo at top - much bigger
              Center(
                child: SvgPicture.asset(
                  'assets/images/logo.svg',
                  height: 160, // Increased size
                  width: 160, // Increased size
                ),
              ),
              const SizedBox(height: 32),
              // Welcome text - now bold
              Text(
                'WELCOME TO',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold, // Make it bold
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Shaire logo text
              SvgPicture.asset(
                'assets/images/logo_text.svg',
                height: 50,
                colorFilter: ColorFilter.mode(
                  primaryColor,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: 24), // Slightly more space
              // Tagline - larger and on two lines
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Share Bills and manage\nexpenses with AI!',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
              const Spacer(flex: 2),
              // Sign up button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Use direct navigation with MaterialPageRoute just like in the AuthScreen toggle
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AuthScreen(isSignUp: true),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text('Sign up with Email'),
                ),
              ),
              const SizedBox(height: 20),
              // Sign in text - consistent color
              GestureDetector(
                onTap: () {
                  // Use direct navigation with MaterialPageRoute
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AuthScreen(isSignUp: false),
                    ),
                  );
                },
                child: Text.rich(
                  TextSpan(
                    text: "Already have an account? ",
                    children: [
                      TextSpan(
                        text: 'Sign In',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: primaryColor, // Consistent green color
                          decoration: TextDecoration.underline,
                          decorationColor: primaryColor, // Green underline
                        ),
                      ),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
