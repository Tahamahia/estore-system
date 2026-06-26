import 'package:flutter/material.dart';
import 'package:estore_app/app/theme.dart';

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Customers', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.person_add, size: 20),
                label: const Text('Add Customer'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search customers...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: AppTheme.darkCard,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: 12,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.darkBorder),
                itemBuilder: (context, index) {
                  final names = ['Ahmed Ali', 'Sara Hassan', 'Mohamed Ibrahim', 'Fatima Salem', 'Omar Khalid', 'Nour Eldin',
                    'Youssef Taha', 'Mariam Abbas', 'Khaled Mansour', 'Dina Farid', 'Hassan Nabil', 'Layla Mostafa'];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                      child: Text(names[index][0], style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
                    ),
                    title: Text(names[index], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    subtitle: Text('+218 9${(10000000 + index * 1234567).toString().substring(0, 8)}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${(index + 1) * 3} orders', style: const TextStyle(color: AppTheme.success, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, color: Colors.white38),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
