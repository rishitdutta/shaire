import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/user_provider.dart';
import 'package:provider/provider.dart';

class AuthService {
  final SupabaseClient? _client;
  AuthService([this._client]);

  SupabaseClient get supabase => _client ?? Supabase.instance.client;

  // Sign out function
  Future<void> signOut(BuildContext context) async {
    try {
      // Clear cached user data
      await Provider.of<UserProvider>(context, listen: false).clearCache();

      // Sign out from Supabase
      await supabase.auth.signOut();

      // Clear navigation stack and go to splash screen
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e')),
        );
      }
    }
  }

  /// Sends a password reset email using Supabase Auth.
  Future<void> sendPasswordResetEmail(String email) async {
    await supabase.auth.resetPasswordForEmail(email.trim());
  }

  /// Verifies an OTP recovery code and sets a new password.
  Future<void> verifyRecoveryCodeAndResetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await supabase.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.recovery,
    );
    if (response.session == null && response.user == null) {
      throw const AuthException('Invalid or expired recovery code');
    }
    await supabase.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  /// Updates the user's password (e.g. after arriving via password recovery link).
  Future<void> updatePassword(String newPassword) async {
    await supabase.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }
}
