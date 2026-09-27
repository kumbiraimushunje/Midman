import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_service.dart';
import '../../city_data.dart';
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
  final String? prefillBeneficiaryId;
  final String? unmatchedBeneficiaryName;
  final List<String> aiHints;

  const NewRequestScreen({
    super.key,
    this.initialCategory,
    this.prefillDescription,
    this.prefillTitle,
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
  final _extraFieldControllers = <String, TextEditingController>{};
  String? _category;
  String? _serviceType;
  String? _beneficiaryId;
  String? _city;
  List<Beneficiary> _beneficiaries = [];
  bool _loading = false;
  bool _loadingBeneficiaries = true;
  List<Authorizer> _authorizers = [];
  String? _authorizerId; // which authorizer is picked for the "as beneficiary" submit button
  String? _error;
  PlatformFile? _attachedFile;
  MidManUser? _me;

  ServiceCategoryOption? get _categoryOption => _category == null ? null : findServiceCategory(_category!);

  /// Which categories show up depends on the chosen city (see city_data.dart) -
  /// every city currently allows every active category, but the request-
  /// creation endpoint enforces whatever city_availability.py lists, so this
  /// stays ready for cities to actually differ once that's populated.
  List<ServiceCategoryOption> get _availableCategories {
    final allowed = categoriesAvailableInCity(_city);
    if (allowed == null) return kServiceCategories;
    return kServiceCategories.where((c) => allowed.contains(c.value)).toList();
  }

  bool get _readyToPickCategory => _city != null;

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
    _syncExtraFieldControllers();
    _loadBeneficiaries();
    _loadAuthorizers();
    _loadMe();
  }

  Future<void> _loadAuthorizers() async {
    try {
      final list = await ApiService.listMyAuthorizers();
      if (mounted) {
        setState(() {
          _authorizers = list;
          if (list.isNotEmpty) _authorizerId = list.first.id;
        });
      }
    } catch (_) {
      // Non-fatal - the form still works as a direct request without it.
    }
  }

  Future<void> _loadMe() async {
    try {
      final me = await ApiService.me();
      if (mounted) setState(() => _me = me);
    } catch (_) {
      // Non-fatal - if this fails the server still enforces the rule on submit.
    }
  }

  void _onCityChanged(String? value) {
    setState(() {
      _city = value;
      _category = null;
      _serviceType = null;
      _syncExtraFieldControllers();
    });
  }

  void _syncExtraFieldControllers() {
    final fields = _categoryOption?.extraFields ?? const [];
    for (final name in fields) {
      _extraFieldControllers.putIfAbsent(name, () => TextEditingController());
    }
    _extraFieldControllers.removeWhere((name, controller) {
      final stale = !fields.contains(name);
      if (stale) controller.dispose();
      return stale;
    });
  }

  void _onCategoryChanged(String? value) {
    setState(() {
      _category = value;
      _serviceType = null;
      _syncExtraFieldControllers();
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    for (final c in _extraFieldControllers.values) {
      c.dispose();
    }
    super.dispose();
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

  /// The extra structured fields (e.g. Airport Transfers' Flight number,
  /// Passenger, ...) don't have their own backend columns - they're folded
  /// into the description as clearly labeled lines so staff still see them.
  String? _composedDescription() {
    final base = _descriptionController.text.trim();
    final extras = _extraFieldControllers.entries
        .map((e) => MapEntry(e.key, e.value.text.trim()))
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}: ${e.value}')
        .join('\n');
    final combined = [extras, base].where((s) => s.isNotEmpty).join('\n\n');
    return combined.isEmpty ? null : combined;
  }

  Future<void> _submit({required String? authorizerId}) async {
    if (_city == null || _category == null || _titleController.text.trim().isEmpty) {
      setState(() => _error = 'Please choose a city, a category and a short title');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final request = await ApiService.createServiceRequest(
        city: _city,
        category: _category!,
        serviceType: _serviceType,
        title: _titleController.text.trim(),
        description: _composedDescription(),
        beneficiaryId: _beneficiaryId,
        authorizerId: authorizerId,
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
            if (_me != null && !userCanCreateRequest(_me!)) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MidManColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: MidManColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Your role (${businessRoleLabel(_me!.businessRole)}) can't create requests - "
                        "ask your company's Administrator.",
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
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
              initialValue: _city,
              decoration: const InputDecoration(labelText: 'City'),
              hint: const Text('Choose city for available services'),
              items: kZimbabweCities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: _onCityChanged,
            ),
            const SizedBox(height: 16),
            if (_readyToPickCategory)
              DropdownButtonFormField<String>(
                initialValue: _availableCategories.any((c) => c.value == _category) ? _category : null,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _availableCategories
                    .map((c) => DropdownMenuItem(value: c.value, child: Text(c.label)))
                    .toList(),
                onChanged: _onCategoryChanged,
              )
            else
              InputDecorator(
                decoration: const InputDecoration(labelText: 'Category'),
                child: Text('Choose a city above first', style: TextStyle(color: Colors.grey.shade600)),
              ),
            if ((_categoryOption?.serviceTypes ?? const []).isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _serviceType,
                decoration: const InputDecoration(labelText: 'Specific service'),
                items: _categoryOption!.serviceTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _serviceType = v),
              ),
            ],
            if (_categoryOption?.notice != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: MidManColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: MidManColors.warning),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_categoryOption!.notice!, style: const TextStyle(fontSize: 12))),
                  ],
                ),
              ),
            ],
            for (final name in _categoryOption?.extraFields ?? const []) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _extraFieldControllers[name],
                decoration: InputDecoration(labelText: name),
              ),
            ],
            if (_category == 'property_inspection') ...[
              const SizedBox(height: 16),
              const _InspectionReminderCard(),
            ],
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
              decoration: InputDecoration(
                labelText: 'What needs to be done?',
                hintText: _categoryOption?.titleHint ?? 'e.g. Briefly describe what you need',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Details (optional)',
                hintText: _categoryOption?.detailsHint ?? 'Anything else we should know',
              ),
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
            // For Family Care & Child Support with an available authorizer, the
            // "How should this be sent?" card's two buttons are the submit
            // action, and they're the last thing on the page - there's no
            // separate generic submit button in that case.
            if (isFamilyCareCategory(_category) && _authorizers.isNotEmpty)
              _AuthorizerCard(
                authorizers: _authorizers,
                selectedAuthorizerId: _authorizerId,
                busy: _loading,
                enabled: _me == null || userCanCreateRequest(_me!),
                onAuthorizerChanged: (v) => setState(() => _authorizerId = v),
                onSubmitDirect: () => _submit(authorizerId: null),
                onSubmitAsBeneficiary: () => _submit(authorizerId: _authorizerId ?? _authorizers.first.id),
              )
            else
              ElevatedButton(
                onPressed: (_loading || (_me != null && !userCanCreateRequest(_me!))) ? null : () => _submit(authorizerId: null),
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

/// Lets a customer who has an authorizer (someone who's listed them as a
/// beneficiary) choose between a direct request and raising it "as a
/// beneficiary" - which needs that authorizer's sign-off before MidMan
/// reviews it. Only shown for Family Care & Child Support categories. Each
/// button submits immediately - there's no separate confirm step.
class _AuthorizerCard extends StatelessWidget {
  final List<Authorizer> authorizers;
  final String? selectedAuthorizerId;
  final bool busy;
  final bool enabled;
  final ValueChanged<String?> onAuthorizerChanged;
  final VoidCallback onSubmitDirect;
  final VoidCallback onSubmitAsBeneficiary;

  const _AuthorizerCard({
    required this.authorizers,
    required this.selectedAuthorizerId,
    required this.busy,
    required this.enabled,
    required this.onAuthorizerChanged,
    required this.onSubmitDirect,
    required this.onSubmitAsBeneficiary,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && !busy;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How should this be sent?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (authorizers.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedAuthorizerId,
              decoration: const InputDecoration(labelText: 'If sent as beneficiary, to'),
              items: authorizers
                  .map((a) => DropdownMenuItem(value: a.id, child: Text('${a.fullName} (their ${a.relationshipType})')))
                  .toList(),
              onChanged: canTap ? onAuthorizerChanged : null,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: canTap ? onSubmitDirect : null,
                  child: busy
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Send Request'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: canTap ? onSubmitAsBeneficiary : null,
                  child: busy
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Start request as beneficiary'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Optional recurring email nudge to book the next inspection - "choose
/// timer monthly... for email reminders, optional." Self-contained: it
/// loads and saves its own state independently of the surrounding form, so
/// the customer can set or cancel it without needing to submit a request.
class _InspectionReminderCard extends StatefulWidget {
  const _InspectionReminderCard();

  @override
  State<_InspectionReminderCard> createState() => _InspectionReminderCardState();
}

class _InspectionReminderCardState extends State<_InspectionReminderCard> {
  late Future<InspectionReminder?> _future;
  bool _enabled = false;
  String _frequency = 'monthly';
  final _propertyLabelController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<InspectionReminder?> _load() async {
    final reminder = await ApiService.getInspectionReminder();
    if (reminder != null && reminder.active && mounted) {
      setState(() {
        _enabled = true;
        _frequency = reminder.frequency;
        _propertyLabelController.text = reminder.propertyLabel ?? '';
      });
    }
    return reminder;
  }

  @override
  void dispose() {
    _propertyLabelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.setInspectionReminder(
        frequency: _frequency,
        propertyLabel: _propertyLabelController.text.trim().isEmpty ? null : _propertyLabelController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reminder saved')));
        setState(() => _future = _load());
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.cancelInspectionReminder();
      if (mounted) setState(() => _enabled = false);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<InspectionReminder?>(
      future: _future,
      builder: (context, snapshot) {
        final existing = snapshot.data;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, size: 18, color: MidManColors.gold),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Remind me to book my next inspection', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  Switch(value: _enabled, onChanged: _busy ? null : (v) => setState(() => _enabled = v)),
                ],
              ),
              if (existing != null && existing.active && !_busy)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Next reminder: ${DateFormat('d MMM yyyy').format(existing.nextReminderAt.toLocal())}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              if (_enabled) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _frequency,
                  decoration: const InputDecoration(labelText: 'How often'),
                  items: kReminderFrequencies.map((f) => DropdownMenuItem(value: f.value, child: Text(f.label))).toList(),
                  onChanged: _busy ? null : (v) => setState(() => _frequency = v ?? _frequency),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _propertyLabelController,
                  decoration: const InputDecoration(labelText: 'Which property? (optional)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: MidManColors.danger, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _busy ? null : _save,
                        child: _busy
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save reminder'),
                      ),
                    ),
                    if (existing != null && existing.active) ...[
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: _busy ? null : _cancel,
                        child: const Text('Cancel reminder', style: TextStyle(color: MidManColors.danger)),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
