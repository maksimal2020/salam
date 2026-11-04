import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import 'account_screens.dart';
import 'ad_form_screen.dart';
import 'brand.dart';
import 'theme.dart';
import 'widgets.dart';

/// Объявление целиком. Автор видит статус и отклики, остальные — форму отклика и жалобу.
/// Контакты автора не показываются: связь только через форму.
class AdScreen extends StatefulWidget {
  const AdScreen({super.key, required this.id});
  final int id;

  @override
  State<AdScreen> createState() => _AdScreenState();
}

class _AdScreenState extends State<AdScreen> {
  int _bump = 0;
  final _message = TextEditingController();
  final _contact = TextEditingController();
  final _reason = TextEditingController();
  bool _sent = false;
  bool _reportOpen = false;
  bool _reported = false;
  bool _busy = false;
  ApiError? _error;

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _respond() async {
    final app = context.app;
    final text = _message.text.trim();
    if (text.length < 2) {
      setState(() => _error = ApiError(400, 'validation'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.api.post('/listings/${widget.id}/respond', {'message': text, 'contact': _contact.text.trim().isEmpty ? null : _contact.text.trim()});
      if (!mounted) return;
      setState(() {
        _sent = true;
        _busy = false;
        _message.clear();
        _contact.clear();
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _busy = false;
      });
    }
  }

  Future<void> _report() async {
    final app = context.app;
    final text = _reason.text.trim();
    if (text.length < 3) {
      setState(() => _error = ApiError(400, 'validation'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.api.post('/listings/${widget.id}/report', {'reason': text});
      if (!mounted) return;
      setState(() {
        _reported = true;
        _reportOpen = false;
        _busy = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _busy = false;
      });
    }
  }

  Future<void> _withdraw() async {
    final app = context.app;
    try {
      await app.api.post('/listings/${widget.id}/withdraw', <String, dynamic>{});
      if (mounted) Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(MaterialPageRoute<int>(builder: (_) => AdFormScreen(editId: widget.id)));
    if (mounted) setState(() => _bump++);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return SectionScaffold(
      section: Section.ads,
      title: app.t('nav.ads'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Async<Listing>(
              cacheKey: '${widget.id}|${app.user?.id ?? 0}|$_bump',
              load: () async => Listing.fromJson(await app.api.get('/listings/${widget.id}')),
              builder: (context, a, reload) => _content(context, app, a),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AppState app, Listing a) {
    final mine = app.user != null && a.hasOwnerFields;
    final live = a.status == 'published';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Badges([
          Tag(app.t('badge.user')),
          Tag(app.tk('ads.cat', a.category)),
          Tag('${app.t('ads.lang')}: ${langNative(a.lang)}'),
          if (mine) Tag(app.tk('ads.status', a.status)),
        ]),
        const SizedBox(height: 10),
        Text(a.title, key: const ValueKey('ad-title'), style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('${a.city.label}${a.price != null && a.price!.isNotEmpty ? ' · ${a.price}' : ''}'),
        if (a.category == 'work') ...[
          const SizedBox(height: 10),
          for (final k in const ['employer', 'pay', 'schedule', 'terms'])
            if (a.extra[k] != null) Fact(app.t('ads.field.$k'), Text(a.extra[k]!)),
        ],
        const SizedBox(height: 10),
        Text(a.body),
        if (a.publishedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${app.t('ads.published', {'date': app.fmtDate(a.publishedAt)})}${a.expiresAt != null ? ' · ${app.t('ads.until', {'date': app.fmtDate(a.expiresAt)})}' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (mine && a.status == 'pending') Notice(child: Text(app.t('ads.pendingNote'))),
        if (mine && a.moderationNote != null) Notice(child: Text(app.t('ads.rejectedReason', {'reason': a.moderationNote!}))),
        if (mine)
          Wrap(spacing: 8, children: [
            if (const ['pending', 'published', 'rejected'].contains(a.status))
              OutlinedButton(key: const ValueKey('ad-edit'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: _edit, child: Text(app.t('ads.edit'))),
            if (const ['pending', 'published'].contains(a.status))
              OutlinedButton(key: const ValueKey('ad-withdraw'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: _withdraw, child: Text(app.t('ads.withdraw'))),
          ]),
        ErrorBox(error: _error),
        if (mine) _Responses(id: a.id),
        if (!mine && live) ..._actions(context, app),
      ],
    );
  }

  List<Widget> _actions(BuildContext context, AppState app) {
    if (app.user == null) {
      return [
        Notice(
          child: InkWell(
            key: const ValueKey('login-to-respond'),
            onTap: () async {
              await openAuth(context);
              if (mounted) setState(() => _bump++);
            },
            child: Text(app.t('ads.loginToAct'), style: TextStyle(color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
          ),
        ),
      ];
    }
    return [
      if (!_sent) ...[
        const SizedBox(height: 12),
        Text(app.t('ads.respond'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('respond-message'),
          controller: _message,
          minLines: 3,
          maxLines: 6,
          maxLength: 2000,
          decoration: InputDecoration(labelText: app.t('ads.respondMessage')),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('respond-contact'),
          controller: _contact,
          maxLength: 200,
          decoration: InputDecoration(labelText: app.t('ads.respondContact')),
        ),
        Text(app.t('ads.respondHint'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        FilledButton(key: const ValueKey('respond-send'), onPressed: _busy ? null : _respond, child: Text(app.t('ads.respond'))),
      ] else
        Notice(ok: true, child: Text(app.t('ads.respondSent'), key: const ValueKey('respond-sent'))),
      const SizedBox(height: 8),
      if (!_reported && !_reportOpen)
        TextButton(key: const ValueKey('report-open'), onPressed: () => setState(() => _reportOpen = true), child: Text(app.t('ads.report'))),
      if (_reportOpen) ...[
        TextField(
          key: const ValueKey('report-reason'),
          controller: _reason,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(labelText: app.t('ads.reportReason')),
        ),
        OutlinedButton(key: const ValueKey('report-send'), onPressed: _busy ? null : _report, child: Text(app.t('ads.report'))),
      ],
      if (_reported) Notice(ok: true, child: Text(app.t('ads.reportSent'), key: const ValueKey('report-sent'))),
    ];
  }
}

class _Responses extends StatelessWidget {
  const _Responses({required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(app.t('ads.responses'), style: Theme.of(context).textTheme.titleMedium),
        Async<List<AdResponse>>(
          cacheKey: 'responses|$id',
          load: () async {
            final j = await app.api.get('/my/listings/$id/responses');
            return ((j as Map)['responses'] as List).map(AdResponse.fromJson).toList();
          },
          builder: (context, list, reload) {
            if (list.isEmpty) return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(app.t('ads.noResponses')));
            return Column(children: [
              for (final r in list)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.message),
                      if (r.contact != null) Text(r.contact!, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(app.fmtDate(r.createdAt), style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}
