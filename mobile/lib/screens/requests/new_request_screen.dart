import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';

const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic'};

/// The "smart request form": pick a category, optionally who it's for, then
/// fill in the details the AI/staff need. Category and description can be
/// pre-filled (e.g. tapping a service tile, or typing into the AI prompt on
/// the home screen).
class NewRequestScreen extends StatefulWidget {
  final String? initialCategory;
  final String? prefillDescription;
  final String? prefillTitle;
  final num? prefillAmount;
  final String? prefillBeneficiaryId;
  final String? unmatchedBeneficiaryName;
  final List<String> aiHints;

  const NewRequestScreen({
    super.key,
    this.initialCategory,
    this.prefillDescription,
    this.prefillTitle,
    this.prefillAmount,
    this.prefillBeneficiaryId,
    this.unmatchedBeneficiaryName,
    this.aiHints = const [],
  });

  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  String? _category;
  String? _beneficiaryId;
  List<Beneficiary> _beneficiaries = [];
  bool _loading = false;
  bool _loadingBeneficiaries = true;
  String? _error;
  PlatformFile? _attachedFile;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _beneficiaryId = widget.prefillBeneficiaryId;
    if (widget.prefillDescription != null) {
      _descriptionController.text = widget.prefillDescription!;
    }
    if (widget.prefillTitle != null) {
      _titleController.text = widget.prefillTitle!;
    }
    if (widget.prefillAmount != null) {
      _amountController.text = widget.prefillAmount.toString();
    }
    _loadBeneficiaries();
  }

  Future<void> _loadBeneficiaries() async {
    try {
      final list = await ApiService.listBeneficiaries();
      if (mounted) setState(() => _beneficiaries = list);
    } catch (_) {
      // Non-fatal - the form still works without beneficiaries loaded.
    } finally {
      if (mounted) setState(() => _loadingBeneficiaries = false);
    }
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf', 'doc', 'docx'],
    );
    if (files.isNotEmpty) {
      setState(() => _attachedFile = files.first);
    }
  }

  Future<void> _submit() async {
    if (_category == null || _titleController.text.trim().isEmpty) {
      setState(() => _error = 'Please choose a category and a short title');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final request = await ApiService.createServiceRequest(
        category: _category!,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        beneficiaryId: _beneficiaryId,
        amount: _amountController.text.trim().isEmpty ? null : num.tryParse(_amountController.text.trim()),
      );

      final attached = _attachedFile;
      if (attached != null) {
        final ext = (attached.extension ?? '').toLowerCase();
        await ApiService.uploadEvidence(
          requestId: request.id,
          bytes: await attached.readAsBytes(),
          filename: attached.name,
          fileType: _imageExtensions.contains(ext) ? 'photo' : 'document',
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Request')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.aiHints.isNotEmpty || widget.unmatchedBeneficiaryName != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFF1EEE7), borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.auto_awesome, size: 16, color: MidManColors.gold),
                        SizedBox(width: 8),
                        Text('I filled in what I could - please check:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                    if (widget.unmatchedBeneficiaryName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '• Sounds like this is for "${widget.unmatchedBeneficiaryName}", but I couldn\'t find them in your Family list - add them there first, or just describe who it\'s for below.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ...widget.aiHints.map((h) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('• $h', style: const TextStyle(fontSize: 12)),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: kServiceCategories
                  .map((c) => DropdownMenuItem(value: c.value, child: Text(c.label)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 16),
            if (_loadingBeneficiaries)
              const LinearProgressIndicator()
            else if (_beneficiaries.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _beneficiaryId,
                decoration: const InputDecoration(labelText: 'Who is this for? (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Myself')),
                  ..._beneficiaries.map((b) => DropdownMenuItem(value: b.id, child: Text('${b.fullName} (${b.relationshipType})'))),
                ],
                onChanged: (v) => setState(() => _beneficiaryId = v),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'What needs to be done?', hintText: 'e.g. Term 3 school fees'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Details (optional)', hintText: 'School name, deadline, anything we should know'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount, if known (optional)'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(_attachedFile == null ? 'Attach invoice / document / photo (optional)' : _attachedFile!.name),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit request'),
            ),
          ],
        ),
      ),
    );
  }
}
