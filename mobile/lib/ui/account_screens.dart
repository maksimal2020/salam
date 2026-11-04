import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import 'ad_screen.dart';
import 'brand.dart';
import 'theme.dart';
import 'widgets.dart';

/// Открывает вход. Возвращает true, если пользователь вошёл.
Future<bool?> openAuth(BuildContext context, {bool register = false}) {
  return Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => AuthScreen(register: register)));
}

/// Кнопка аккаунта в шапке: вход или «Мои объявления».
Future<void> openAccount(BuildContext context) async {
  final app = context.app;
  if (app.user == null) {
    final ok = await openAuth(context);
    if (ok != true || !context.mounted) return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyAdsScreen()));
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.register = false});
  final bool register;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool _register;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  ApiError? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _register = widget.register;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final app = context.app;
    final email = _email.text.trim();
    if (!email.contains('@') || _password.text.length < 8) {
      setState(() => _error = ApiError(400, _password.text.length < 8 ? 'weak_password' : 'validation'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final j = await app.api.post('/auth/${_register ? 'register' : 'login'}', {
        'email': email,
        'password': _password.text,
        if (_register && _name.text.trim().isNotEmpty) 'displayName': _name.text.trim(),
      });
      final m = j as Map;
      await app.login(m['token'] as String, AppUser.fromJson(m['user']));
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return SectionScaffold(
      section: Section.ads,
      title: _register ? app.t('auth.register') : app.t('auth.login'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            if (_register) ...[
              TextField(key: const ValueKey('auth-name'), controller: _name, maxLength: 60, decoration: InputDecoration(labelText: app.t('auth.name'))),
              const SizedBox(height: 8),
            ],
            TextField(
              key: const ValueKey('auth-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(labelText: app.t('auth.email')),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('auth-password'),
              controller: _password,
              obscureText: true,
              autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(labelText: app.t('auth.password')),
            ),
            ErrorBox(error: _error),
            const SizedBox(height: 12),
            FilledButton(key: const ValueKey('auth-submit'), onPressed: _busy ? null : _submit, child: Text(_register ? app.t('auth.register') : app.t('auth.login'))),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('auth-switch'),
              onPressed: () => setState(() {
                _register = !_register;
                _error = null;
              }),
              child: Text(_register ? app.t('auth.haveAccount') : app.t('auth.noAccount')),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Мои объявления»: статусы, причины отказа, число откликов, отправленные отклики.
class MyAdsScreen extends StatelessWidget {
  const MyAdsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final user = app.user;
    return SectionScaffold(
      section: Section.ads,
      title: app.t('ads.mine'),
      body: SafeArea(
        child: user == null
            ? Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), child: Notice(child: Text(app.t('ads.loginToAct'))))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  Text('${user.email}${user.isModerator ? ' · ${app.t('mod.title')}' : ''}', key: const ValueKey('account-email')),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (user.isModerator)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModScreen())),
                        child: Text(app.t('mod.title')),
                      ),
                    TextButton(
                      key: const ValueKey('logout'),
                      onPressed: () async {
                        await app.logout();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: Text(app.t('auth.logout')),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Async<List<Listing>>(
                    cacheKey: 'mine|${user.id}',
                    load: () async {
                      final j = await app.api.get('/my/listings');
                      return ((j as Map)['listings'] as List).map(Listing.fromJson).toList();
                    },
                    builder: (context, list, reload) {
                      if (list.isEmpty) return EmptyNote(app.t('ads.empty'));
                      return Column(children: [
                        for (final l in list)
                          AppCard(
                            key: ValueKey('my-ad-${l.id}'),
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdScreen(id: l.id)));
                              reload();
                            },
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Badges([Tag(app.tk('ads.status', l.status)), Tag(app.tk('ads.cat', l.category))]),
                              const SizedBox(height: 6),
                              Text(l.title, style: Theme.of(context).textTheme.titleMedium),
                              Text('${app.t('ads.responses')}: ${l.responseCount}${l.expiresAt != null ? ' · ${app.t('ads.until', {'date': app.fmtDate(l.expiresAt)})}' : ''}', style: Theme.of(context).textTheme.bodySmall),
                              if (l.moderationNote != null) Text(app.t('ads.rejectedReason', {'reason': l.moderationNote!}), style: Theme.of(context).textTheme.bodySmall),
                            ]),
                          ),
                      ]);
                    },
                  ),
                  Async<List<SentResponse>>(
                    cacheKey: 'sent|${user.id}',
                    load: () async {
                      final j = await app.api.get('/my/responses');
                      return ((j as Map)['responses'] as List).map(SentResponse.fromJson).toList();
                    },
                    builder: (context, list, reload) {
                      if (list.isEmpty) return const SizedBox.shrink();
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SizedBox(height: 8),
                        Text(app.t('ads.respond'), style: Theme.of(context).textTheme.titleMedium),
                        for (final r in list)
                          Card(
                            margin: const EdgeInsets.only(top: 8),
                            child: ListTile(
                              title: Text(r.title),
                              subtitle: Text(r.message, maxLines: 3, overflow: TextOverflow.ellipsis),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdScreen(id: r.listingId))),
                            ),
                          ),
                      ]);
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

/// Очередь модератора: ждут проверки, с жалобами, недавно опубликованные.
class ModScreen extends StatefulWidget {
  const ModScreen({super.key});

  @override
  State<ModScreen> createState() => _ModScreenState();
}

class _ModScreenState extends State<ModScreen> {
  String _kind = 'pending';
  int _bump = 0;
  ApiError? _error;
  final Map<int, TextEditingController> _reasons = {};

  @override
  void dispose() {
    for (final c in _reasons.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _reasonFor(int id) => _reasons.putIfAbsent(id, () => TextEditingController());

  Future<void> _act(int id, String action, bool needsReason) async {
    final app = context.app;
    setState(() => _error = null);
    try {
      await app.api.post('/mod/listings/$id/$action', needsReason ? {'reason': _reasonFor(id).text.trim()} : <String, dynamic>{});
      if (mounted) setState(() => _bump++);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final user = app.user;
    if (user == null || !user.isModerator) {
      return SectionScaffold(
        section: Section.ads,
        title: app.t('mod.title'),
        body: Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), child: Notice(child: Text(app.t('error.notFound')))),
      );
    }
    return SectionScaffold(
      section: Section.ads,
      title: app.t('mod.title'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Async<ModQueue>(
              cacheKey: 'mod|$_kind|$_bump',
              load: () async => ModQueue.fromJson(await app.api.get('/mod/queue', query: {'kind': _kind})),
              builder: (context, q, reload) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChipChoice(
                    value: _kind,
                    onChanged: (v) => setState(() => _kind = v),
                    options: [for (final k in const ['pending', 'reported', 'recent']) Opt<String>(k, '${app.t('mod.$k')} (${q.count(k)})')],
                  ),
                  ErrorBox(error: _error),
                  if (q.listings.isEmpty) EmptyNote(app.t('mod.empty')),
                  for (final l in q.listings) _item(context, app, l),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, AppState app, Listing l) {
    return AppCard(
      key: ValueKey('mod-item-${l.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Badges([
            Tag(app.tk('ads.cat', l.category)),
            Tag(app.tk('ads.status', l.status)),
            if (l.reportCount > 0) Tag(app.t('mod.reports', {'n': l.reportCount}), color: Palette.danger),
          ]),
          const SizedBox(height: 6),
          Text(l.title, style: Theme.of(context).textTheme.titleMedium),
          Text('${l.authorEmail ?? ''} · ${l.city.name} · ${app.fmtDate(l.createdAt)}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(l.body),
          if (l.category == 'work')
            Text([l.extra['employer'], l.extra['pay'], l.extra['schedule'], l.extra['terms']].whereType<String>().join(' · '), style: Theme.of(context).textTheme.bodySmall),
          for (final r in l.reports) Text('— ${r.reason}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(key: ValueKey('mod-reason-${l.id}'), controller: _reasonFor(l.id), decoration: InputDecoration(labelText: app.t('mod.reason'))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (l.status != 'hidden')
              FilledButton(
                key: ValueKey('mod-approve-${l.id}'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => _act(l.id, 'approve', false),
                child: Text(app.t('mod.approve')),
              ),
            if (l.status == 'hidden')
              FilledButton(
                key: ValueKey('mod-restore-${l.id}'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => _act(l.id, 'restore', false),
                child: Text(app.t('mod.restore')),
              ),
            OutlinedButton(
              key: ValueKey('mod-reject-${l.id}'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => _act(l.id, 'reject', true),
              child: Text(app.t('mod.reject')),
            ),
            if (l.status != 'hidden')
              OutlinedButton(
                key: ValueKey('mod-hide-${l.id}'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => _act(l.id, 'hide', true),
                child: Text(app.t('mod.hide')),
              ),
          ]),
        ],
      ),
    );
  }
}
