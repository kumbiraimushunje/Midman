import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme.dart';
import '../requests/new_request_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              const CircleAvatar(radius: 22, backgroundColor: MidManColors.navy, child: Icon(Icons.person, color: Colors.white)),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Good to see you', style: TextStyle(fontSize: 16, color: Colors.grey)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(radius: 22, backgroundColor: MidManColors.gold, child: Icon(Icons.auto_awesome, color: Colors.black)),
                const SizedBox(height: 14),
                const Text('Tell me what you\nwant me to do...', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3)),
                const SizedBox(height: 8),
                const Text('Type or speak', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                TextField(
                  decoration: InputDecoration(
                    hintText: "I'm your personal concierge...",
                    suffixIcon: const Icon(Icons.mic, color: MidManColors.gold),
                  ),
                  onSubmitted: (value) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => NewRequestScreen(prefillDescription: value)),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: kServiceCategories
                .map((c) => _ServiceCard(
                      option: c,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => NewRequestScreen(initialCategory: c.value)),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final ServiceCategoryOption option;
  final VoidCallback onTap;

  const _ServiceCard({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(option.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            Text(option.subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
