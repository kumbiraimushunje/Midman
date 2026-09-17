import 'package:flutter/material.dart';

import '../../models/models.dart';
import 'new_request_screen.dart';

/// Step 2 of the guided request flow: the customer already picked a numbered
/// Service (group) on the Home screen; this shows that group's Categories as
/// buttons. Tapping one opens the request form with the category preselected
/// - the specific Service Type (Level 3) is then chosen there, since it's
/// really the first field of the form rather than a separate screen.
class CategoryPickerScreen extends StatelessWidget {
  final ServiceGroup group;
  const CategoryPickerScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(group.label)),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: group.categories.length,
          separatorBuilder: (_, index) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final category = group.categories[i];
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => NewRequestScreen(initialCategory: category.value)),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(category.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(category.subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
