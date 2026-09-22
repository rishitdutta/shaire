import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import '../services/logger_service.dart';

class UserProvider extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  Map<String, dynamic>? _userData;
  bool _isLoading = false;
  DateTime? _lastFetched;

  // Getters
  Map<String, dynamic>? get userData => _userData;
  bool get isLoading => _isLoading;

  // Initialize the provider - call this early in your app
  Future<void> initialize() async {
    await _loadFromCache();
  }

  // Load user data from local cache
  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_profile_data');
    final lastFetchedString = prefs.getString('user_profile_last_fetched');

    if (userDataString != null) {
      try {
        _userData = jsonDecode(userDataString);
        if (lastFetchedString != null) {
          _lastFetched = DateTime.parse(lastFetchedString);
        }
        notifyListeners();
      } catch (e) {
        LoggerService.error('Error loading cached user data: $e');
        // Consider clearing cache if decode fails
        // await clearCache();
      }
    }
  }

  // Save user data to local cache
  Future<void> _saveToCache() async {
    if (_userData != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_profile_data', jsonEncode(_userData));
      _lastFetched = DateTime.now();
      await prefs.setString(
          'user_profile_last_fetched', _lastFetched!.toIso8601String());
    }
  }

  // Get user profile - with caching
  Future<Map<String, dynamic>> getUserProfile(
      {bool forceRefresh = false}) async {
    // If we already have data and it's not too old, return it
    final now = DateTime.now();
    final dataIsFresh = _lastFetched != null &&
        now.difference(_lastFetched!).inMinutes < 30; // Cache for 30 minutes

    if (_userData != null && dataIsFresh && !forceRefresh) {
      return _userData!;
    }

    // Otherwise fetch fresh data
    return await refreshUserProfile();
  }

  // Force refresh user profile
  Future<Map<String, dynamic>> refreshUserProfile() async {
    _isLoading = true;
    //notifyListeners();

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No user is logged in');
      }

      final response = await _supabase
          .from('profiles')
          .select(
              'id, username, full_name, phone, upi_id, currency, profile_complete, avatar_url')
          .eq('id', user.id)
          .single();

      _userData = response;
      _isLoading = false;
      await _saveToCache();
      notifyListeners();
      return _userData!;
    } catch (error) {
      _isLoading = false;
      notifyListeners();
      if (error is PostgrestException) {
        // Handle specific case where profile might not exist yet (though trigger should handle it)
        if (error.code == 'PGRST116') {
          // "JSON object requested, multiple (or no) rows returned"
          throw Exception(
              'User profile not found. Please try logging out and back in.');
        }
        throw Exception('Database Error: ${error.message}');
      } else {
        throw Exception('Failed to fetch user profile: $error');
      }
    }
  }

  // Update user profile
  Future<void> updateUserProfile(Map<String, dynamic> updates) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('No user is logged in');
    }

    try {
      _isLoading = true;
      notifyListeners();

      updates['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('profiles').update(updates).eq('id', user.id);

      // Update the cached data immediately for responsiveness
      if (_userData != null) {
        // Create a new map to ensure change notification works if needed elsewhere
        _userData = Map<String, dynamic>.from(_userData!)..addAll(updates);
      } else {
        // If cache was empty, fetch fresh data to populate it
        await refreshUserProfile(); // This will save to cache and notify
        return; // Return early as refreshUserProfile handles state updates
      }

      await _saveToCache(); // Save the updated merged data
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      throw Exception('Failed to update profile: $e');
    }
  }

  // Clear cached data on logout
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_profile_data');
    await prefs.remove('user_profile_last_fetched');
    _userData = null;
    _lastFetched = null;
    notifyListeners();
  }
}
