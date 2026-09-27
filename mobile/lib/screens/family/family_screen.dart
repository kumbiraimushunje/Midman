import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  late Future<List<Beneficiary>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.listBeneficiaries();
  }

  void _reload() => setState(() {
        _future = ApiService.listBeneficiaries();
      });

  Future<void> _addBeneficiary() async {
    final nameController = TextEditingController();
    final relationshipController = TextEditingController();
    final addressController = TextEditingController();
    final linkController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add beneficiary'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 12),
              TextField(controller: relationshipController, decoration: const InputDecoration(labelText: 'Relationship (e.g. Mother, Child, Property)')),
              const SizedBox(height: 12),
              TextField(controller: addressController, decoration: const InputDecoration(labelText: 'Address (optional)')),
              const SizedBox(height: 16),
              TextField(
                controller: linkController,
                decoration: const InputDecoration(
                  labelText: "Link to their MidMan account (optional)",
                  hintText: 'Their member ID, email, or phone',
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  "If they have a MidMan account, linking lets them start Family Care & Child Support "
                  'requests as your beneficiary, which you approve before MidMan does.',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        final saved = await ApiService.createBeneficiary(
          fullName: nameController.text.trim(),
          relationshipType: relationshipController.text.trim().isEmpty ? 'Other' : relationshipController.text.trim(),
          address: addressController.text.trim().isEmpty ? null : addressController.text.trim(),
          linkedMemberIdentifier: linkController.text.trim().isEmpty ? null : linkController.text.trim(),
        );
        _reload();
        if (!mounted) return;
        if (linkController.text.trim().isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(saved.isLinkedToAccount
                ? 'Linked to their MidMan account.'
                : "Couldn't find a MidMan account matching that - beneficiary saved without a link."),
          ));
        }
      } on ApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _deleteBeneficiary(Beneficiary b) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove beneficiary'),
        content: Text('Remove ${b.fullName} from your beneficiaries?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: MidManColors.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.deleteBeneficiary(b.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                const Expanded(child: Text('Family & Beneficiaries', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
                IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: _addBeneficiary),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Beneficiary>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data ?? [];
                if (list.isEmpty) {
                  return const Center(child: Text('No beneficiaries yet. Add someone you take care of.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: list.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final b = list[i];
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          const CircleAvatar(child: Icon(Icons.person_outline)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(b.relationshipType, style: const TextStyle(color: Colors.grey)),
                                if (b.linkedAccount != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.link, size: 13, color: MidManColors.gold),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Linked · ${b.linkedAccount!.username ?? b.linkedAccount!.email}',
                                          style: const TextStyle(fontSize: 12, color: MidManColors.gold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: MidManColors.danger),
                            tooltip: 'Remove beneficiary',
                            onPressed: () => _deleteBeneficiary(b),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
