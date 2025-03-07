import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildBalanceSection(),
          _buildRecentActivities(),
        ],
      ),
    );
  }

  Widget _buildBalanceSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildBalanceCard('You Get', '\$150.00', Colors.green),
          ),
          const SizedBox(width: 4), // Space between cards
          Expanded(
            child: _buildBalanceCard('You Owe', '\$75.00', Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(String title, String amount, Color color) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              amount, 
              style: TextStyle(
                fontSize: 24, 
                fontWeight: FontWeight.bold, 
                color: color
              )
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivities() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Recent Activities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              children: [
                _buildActivityItem('Dinner expense', 'You paid', '\$30.00', Icons.restaurant),
                _buildActivityItem('Movie tickets', 'John paid', '\$25.00', Icons.movie),
                _buildActivityItem('Groceries', 'You paid', '\$45.00', Icons.shopping_cart),
                _buildActivityItem('Uber ride', 'Sarah paid', '\$15.00', Icons.car_rental),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(String title, String action, String amount, IconData icon) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(action),
      trailing: Text(amount, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
