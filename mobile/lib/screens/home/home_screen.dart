import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../api_service.dart';
import '../../models/models.dart';
import '../../theme.dart';
import '../requests/authorizer_approvals_screen.dart';
import '../requests/category_picker_screen.dart';
import '../requests/new_request_screen.dart';
import '../requests/request_detail_screen.dart';
import '../requests/requests_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _promptController = TextEditingController();
  final _speech = stt.SpeechToText();
  bool _parsing = false;
  bool _listening = false;
  String? _error;
  String? _firstName;
  late Future<List<_HomeReminder>> _remindersFuture;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _remindersFuture = _loadReminders();
  }

  Future<void> _loadUser() async {
    try {
      final user = await ApiService.me();
      if (mounted) setState(() => _firstName = user.fullName.trim().split(' ').first);
    } catch (_) {
      // Non-fatal - the greeting just falls back to a generic one.
    }
  }

  /// Reminders are derived client-side from data already fetched elsewhere
  /// in the app (account status, requests, the inspection reminder
  /// subscription) rather than a dedicated backend aggregation endpoint -
  /// each piece failing independently (caught below) just drops that one
  /// reminder instead of blocking the whole section.
  Future<List<_HomeReminder>> _loadReminders() async {
    final reminders = <_HomeReminder>[];

    try {
      final user = await ApiService.me();
      if (user.kycStatus != 'verified') {
        reminders.add(_HomeReminder(
          icon: Icons.badge_outlined,
          text: user.kycStatus == 'rejected'
              ? 'Your identity verification was declined - upload a new document'
              : 'Verify your identity to get the most out of MidMan',
          color: MidManColors.warning,
        ));
      }
    } catch (_) {
      // Non-fatal.
    }

    try {
      final requests = await ApiService.myRequests();
      // Once an authorizer is set, paying is their action, not the
      // initiator's - so a beneficiary-initiated request drops out of this
      // reminder for the initiator and shows up in the authorizer's instead
      // (see the pendingMyPayment block below).
      final pendingRequests = requests.where((r) => r.status == 'payment_pending' && r.authorizerId == null).toList();
      if (pendingRequests.isNotEmpty) {
        final pending = pendingRequests.length;
        reminders.add(_HomeReminder(
          icon: Icons.payments_outlined,
          text: '$pending request${pending == 1 ? '' : 's'} awaiting payment',
          color: MidManColors.gold,
          // Jumps straight to the request if there's exactly one, otherwise the
          // customer picks which from Requests - RequestsScreen has no Scaffold
          // of its own (it's normally a HomeShell tab body), so it can't be
          // pushed as a standalone route without one.
          onTap: (context) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => pending == 1
                ? RequestDetailScreen(requestId: pendingRequests.first.id)
                : const Scaffold(body: RequestsScreen()),
          )),
        ));
      }
    } catch (_) {
      // Non-fatal.
    }

    try {
      final reminder = await ApiService.getInspectionReminder();
      if (reminder != null && reminder.active) {
        reminders.add(_HomeReminder(
          icon: Icons.notifications_active_outlined,
          text: 'Next property inspection reminder: ${DateFormat('d MMM yyyy').format(reminder.nextReminderAt.toLocal())}',
          color: MidManColors.gold,
        ));
      }
    } catch (_) {
      // Non-fatal.
    }

    try {
      final pendingAuthorizations = await ApiService.pendingMyAuthorization();
      if (pendingAuthorizations.isNotEmpty) {
        final pending = pendingAuthorizations.length;
        reminders.add(_HomeReminder(
          icon: Icons.how_to_reg_outlined,
          text: '$pending request${pending == 1 ? '' : 's'} need${pending == 1 ? 's' : ''} your approval',
          color: MidManColors.warning,
          onTap: (context) =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthorizerApprovalsScreen())),
        ));
      }
    } catch (_) {
      // Non-fatal.
    }

    try {
      final pendingPayments = await ApiService.pendingMyPayment();
      if (pendingPayments.isNotEmpty) {
        final pending = pendingPayments.length;
        reminders.add(_HomeReminder(
          icon: Icons.payments_outlined,
          text: '$pending request${pending == 1 ? '' : 's'} you authorized ${pending == 1 ? 'is' : 'are'} awaiting your payment',
          color: MidManColors.gold,
          onTap: (context) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RequestDetailScreen(requestId: pendingPayments.first.id),
          )),
        ));
      }
    } catch (_) {
      // Non-fatal.
    }

    return reminders;
  }

  @override
  void dispose() {
    _promptController.dispose();
    _speech.cancel();
    super.dispose();
  }

  /// Lazily initializes speech_to_text on first tap (rather than in
  /// initState) so the mic/speech-recognition permission prompt only
  /// appears once the customer actually asks to speak, not on page load.
  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      onError: (SpeechRecognitionError error) {
        if (mounted) {
          setState(() {
            _listening = false;
            _error = 'Voice input error: ${error.errorMsg}';
          });
        }
      },
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && mounted) {
          setState(() => _listening = false);
        }
      },
    );
    if (!available) {
      if (mounted) setState(() => _error = "Voice input isn't available on this device");
      return;
    }
    setState(() {
      _listening = true;
      _error = null;
    });
    await _speech.listen(
      onResult: (result) {
        _promptController.value = TextEditingValue(
          text: result.recognizedWords,
          selection: TextSelection.collapsed(offset: result.recognizedWords.length),
        );
      },
    );
  }

  Future<void> _handlePrompt(String value) async {
    if (value.trim().isEmpty) return;
    setState(() {
      _parsing = true;
      _error = null;
    });
    try {
      final result = await ApiService.parseRequestText(value.trim());
      if (!mounted) return;
      await _openPrefilledRequest(result);
      _promptController.clear();
    } catch (e) {
      setState(() => _error = 'Could not process that - $e');
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _uploadInvoice() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
    );
    if (result.isEmpty) return;
    final file = result.first;

    setState(() {
      _parsing = true;
      _error = null;
    });
    try {
      final aiResult = await ApiService.parseInvoiceDocument(bytes: await file.readAsBytes(), filename: file.name);
      if (!mounted) return;
      await _openPrefilledRequest(aiResult);
    } catch (e) {
      setState(() => _error = 'Could not read that document - $e');
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  Future<void> _openPrefilledRequest(AiParseResult result) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewRequestScreen(
          initialCategory: result.category,
          prefillTitle: result.title,
          prefillDescription: result.description,
          prefillAmount: result.amount,
          prefillBeneficiaryId: result.beneficiaryId,
          unmatchedBeneficiaryName: result.beneficiaryNameHint,
          aiHints: result.missingInfo,
        ),
      ),
    );
  }

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
              Expanded(
                child: Text(
                  _firstName == null ? 'Good to see you' : 'Good to see you, $_firstName',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
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
                const Text('How can I help you 😊', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, height: 1.3)),
                const SizedBox(height: 16),
                TextField(
                  controller: _promptController,
                  enabled: !_parsing,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText: 'Type or speak to me',
                    suffixIcon: _parsing
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _promptController,
                            builder: (context, value, _) => IconButton(
                              icon: Icon(
                                _listening || value.text.trim().isEmpty ? Icons.mic : Icons.arrow_forward,
                                color: _listening ? MidManColors.danger : MidManColors.gold,
                              ),
                              onPressed: _listening
                                  ? _toggleListening
                                  : value.text.trim().isEmpty
                                      ? _toggleListening
                                      : () => _handlePrompt(_promptController.text),
                            ),
                          ),
                  ),
                  onSubmitted: _handlePrompt,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: MidManColors.danger, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _parsing ? null : _uploadInvoice,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Or upload an invoice / quote'),
                    style: TextButton.styleFrom(foregroundColor: MidManColors.goldDark, padding: EdgeInsets.zero),
                  ),
                ),
              ],
            ),
          ),
          FutureBuilder<List<_HomeReminder>>(
            future: _remindersFuture,
            builder: (context, snapshot) {
              final reminders = snapshot.data ?? const [];
              if (reminders.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Reminders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    ...reminders.map((r) => _ReminderTile(reminder: r)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const _PromotionsCarousel(),
          const SizedBox(height: 24),
          const Text('Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.3,
            children: kServiceGroups
                .map((g) => _ServiceGroupCard(
                      group: g,
                      onTap: () {
                        // A group with exactly one category (e.g. Transportation,
                        // Other) has nothing to pick between - skip straight to
                        // the request form instead of a picker with one button.
                        if (g.categories.length == 1) {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => NewRequestScreen(initialCategory: g.categories.first.value)),
                          );
                        } else {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => CategoryPickerScreen(group: g)));
                        }
                      },
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ServiceGroupCard extends StatelessWidget {
  final ServiceGroup group;
  final VoidCallback onTap;

  const _ServiceGroupCard({required this.group, required this.onTap});

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
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: MidManColors.gold, shape: BoxShape.circle),
              child: Icon(group.icon, color: Colors.black, size: 20),
            ),
            const SizedBox(height: 8),
            Text(group.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _HomeReminder {
  final IconData icon;
  final String text;
  final Color color;
  final void Function(BuildContext context)? onTap;

  _HomeReminder({required this.icon, required this.text, required this.color, this.onTap});
}

class _ReminderTile extends StatelessWidget {
  final _HomeReminder reminder;
  const _ReminderTile({required this.reminder});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: reminder.onTap == null ? null : () => reminder.onTap!(context),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Icon(reminder.icon, size: 20, color: reminder.color),
              const SizedBox(width: 12),
              Expanded(child: Text(reminder.text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              if (reminder.onTap != null) const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _Promotion {
  final String title;
  final String subtitle;
  final IconData icon;
  const _Promotion({required this.title, required this.subtitle, required this.icon});
}

// TODO: placeholder marketing copy - swap for real campaigns/pricing before
// launch, same pattern as account_screen.dart's support contact details.
// Static for now since there's no promotions backend yet; kept as its own
// small carousel widget so it's a drop-in swap for one later.
const _kPromotions = [
  _Promotion(title: 'Refer a friend', subtitle: 'Give a friend MidMan, get a reward when they join', icon: Icons.people_alt_outlined),
  _Promotion(title: 'Try the AI concierge', subtitle: 'Just describe what you need - we\'ll fill in the rest', icon: Icons.auto_awesome_outlined),
];

class _PromotionsCarousel extends StatelessWidget {
  const _PromotionsCarousel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _kPromotions.length,
        separatorBuilder: (_, index) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final promo = _kPromotions[i];
          return Container(
            width: 240,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: MidManColors.ink, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(promo.icon, color: MidManColors.gold, size: 22),
                const SizedBox(height: 8),
                Text(promo.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 4),
                Text(promo.subtitle, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
    );
  }
}
