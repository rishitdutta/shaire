import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../providers/currency_provider.dart'; // For currency list

class EditPaymentInfoScreen extends StatefulWidget {
  const EditPaymentInfoScreen({super.key});

  @override
  State<EditPaymentInfoScreen> createState() => _EditPaymentInfoScreenState();
}

class _EditPaymentInfoScreenState extends State<EditPaymentInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _upiIdController;
  String? _selectedCurrencyCode;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Initialize controllers/selection with current data from provider
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentProfile = userProvider.userData ?? {};
    _upiIdController =
        TextEditingController(text: currentProfile['upi_id'] ?? '');
    _selectedCurrencyCode =
        currentProfile['currency'] ?? 'INR'; // Default to INR if null
  }

  @override
  void dispose() {
    _upiIdController.dispose();
    super.dispose();
  }

  Future<void> _savePaymentInfo() async {
    if (!_formKey.currentState!.validate()) {
      return; // Don't submit if form is invalid
    }

    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currencyProvider =
        Provider.of<CurrencyProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final updates = {
        'upi_id': _upiIdController.text.trim().isEmpty
            ? null
            : _upiIdController.text.trim(),
        'currency': _selectedCurrencyCode,
      };
      await userProvider.updateUserProfile(updates);
      if (mounted) {
        // Also update the global CurrencyProvider state if it changed
        final currentGlobalCurrency =
            currencyProvider.currencyCode; // Use stored provider ref
        if (_selectedCurrencyCode != currentGlobalCurrency) {
          currencyProvider
              .setCurrency(_selectedCurrencyCode!); // Use stored provider ref
        }

        scaffoldMessenger.showSnackBar(
          // Use stored scaffoldMessenger
          const SnackBar(content: Text('Payment info updated successfully!')),
        );
        navigator.pop(); // Use stored navigator
      }
      // ---
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error updating payment info: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Payment Info'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 16),
              TextFormField(
                controller: _upiIdController,
                decoration:
                    const InputDecoration(labelText: 'UPI ID (Optional)'),
                // Add more specific validation if needed (e.g., regex for format)
              ),
              const SizedBox(height: 32),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                ElevatedButton(
                  onPressed: _savePaymentInfo,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Save Changes'),
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
    );
  }
}
