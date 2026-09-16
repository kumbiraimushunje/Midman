import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../theme.dart';

class _ChatEntry {
  final String role; // "user" | "assistant"
  final String content;
  const _ChatEntry({required this.role, required this.content});
}

const _greeting = "Hi! Ask me anything about your requests, membership plans, or how MidMan works.";

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _messages = <_ChatEntry>[const _ChatEntry(role: 'assistant', content: _greeting)];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    final history = _messages.map((m) => {'role': m.role, 'content': m.content}).toList();

    setState(() {
      _messages.add(_ChatEntry(role: 'user', content: text));
      _sending = true;
    });
    _inputController.clear();
    _scrollToEnd();

    try {
      final reply = await ApiService.supportChat(message: text, history: history);
      if (!mounted) return;
      setState(() => _messages.add(_ChatEntry(role: 'assistant', content: reply.reply)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.add(_ChatEntry(role: 'assistant', content: "Sorry, something went wrong - $e")));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= _messages.length) {
                    return const _TypingBubble();
                  }
                  return _MessageBubble(entry: _messages[i]);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: !_sending,
                      textInputAction: TextInputAction.send,
                      decoration: const InputDecoration(hintText: 'Type your question...'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.arrow_forward),
                    style: IconButton.styleFrom(backgroundColor: MidManColors.gold, foregroundColor: Colors.black),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatEntry entry;
  const _MessageBubble({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isUser = entry.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? MidManColors.ink : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          entry.content,
          style: TextStyle(color: isUser ? Colors.white : MidManColors.textDark, fontSize: 14, height: 1.35),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const SizedBox(
          height: 14,
          width: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
