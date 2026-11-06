import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../state/app_scope.dart';
import 'brand.dart';
import 'theme.dart';
import 'widgets.dart';

/// Обратная связь: сообщить о неточности (проверим и исправим) или предложить, что добавить.
/// Доступна без входа в аккаунт; если пользователь вошёл, его e-mail сохраняется автоматически.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _message = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  ApiError? _error;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final app = context.app;
    final text = _message.text.trim();
    if (text.length < 5) {
      setState(() => _error = ApiError(400, 'validation'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.api.post('/feedback', {
        'message': text,
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'lang': app.lang,
      });
      if (!mounted) return;
      setState(() {
        _sent = true;
        _busy = false;
        _message.clear();
        _email.clear();
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return SectionScaffold(
      section: Section.docs,
      title: app.t('feedback.title'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Text(app.t('feedback.intro')),
            const SizedBox(height: 16),
            if (_sent)
              Container(
                key: const ValueKey('feedback-sent'),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Palette.verifiedSoft, borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, color: Palette.verified),
                  const SizedBox(width: 12),
                  Expanded(child: Text(app.t('feedback.sent'), style: const TextStyle(color: Palette.verified, fontWeight: FontWeight.w600))),
                ]),
              )
            else ...[
              TextField(
                key: const ValueKey('feedback-message'),
                controller: _message,
                minLines: 5,
                maxLines: 10,
                maxLength: 4000,
                decoration: InputDecoration(labelText: app.t('feedback.messageLabel'), hintText: app.t('feedback.messagePlaceholder')),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('feedback-email'),
                controller: _email,
                maxLength: 200,
                decoration: InputDecoration(labelText: app.t('feedback.emailLabel')),
              ),
              ErrorBox(error: _error),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('feedback-submit'),
                onPressed: _busy ? null : _submit,
                child: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(app.t('feedback.submit')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
