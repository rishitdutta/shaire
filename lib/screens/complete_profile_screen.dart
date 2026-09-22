import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../providers/currency_provider.dart'; // For currency list

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _upiIdController = TextEditingController();
  String? _selectedCurrencyCode; // Store the 3-letter code
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Set default currency selection
    _selectedCurrencyCode = 'INR'; // Default to INR
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _upiIdController.dispose();
    super.dispose();
  }

  Future<void> _submitProfile() async {
    if (!_formKey.currentState!.validate()) {
      return; // Don't submit if form is invalid
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final updates = {
        'full_name': _fullNameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'upi_id': _upiIdController.text.trim().isEmpty
            ? null
            : _upiIdController.text.trim(),
        'currency': _selectedCurrencyCode,
        'profile_complete': true, // Mark profile as complete
      };

      await Provider.of<UserProvider>(context, listen: false)
          .updateUserProfile(updates);

      if (mounted) {
        // Navigate to home screen and remove all previous routes
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error updating profile: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

//TODO: Add profile picture upload functionality
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Your Profile'),
        automaticallyImplyLeading: false, // No back button
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Welcome! Please complete your profile.',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your full name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                      labelText: 'Phone Number (Optional)'),
                  keyboardType: TextInputType.phone,
                  // Add validation if needed
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _upiIdController,
                  decoration:
                      const InputDecoration(labelText: 'UPI ID (Optional)'),
                  // Add validation if needed
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCurrencyCode,
                  decoration:
                      const InputDecoration(labelText: 'Default Currency'),
                  items: CurrencyProvider.availableCurrencies.entries
                      .map((entry) => DropdownMenuItem<String>(
                            value: entry.key, // Use the 3-letter code
                            child: Text("${entry.key} (${entry.value})"),
                          ))
                      .toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedCurrencyCode = newValue;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select a currency';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  ElevatedButton(
                    onPressed: _submitProfile,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Save and Continue'),
                  ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
