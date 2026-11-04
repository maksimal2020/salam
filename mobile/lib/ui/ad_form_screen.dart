import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import 'ads_screen.dart';
import 'brand.dart';
import 'city_picker_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Подача и редактирование объявления. Закрывается, вернув id сохранённого объявления.
class AdFormScreen extends StatelessWidget {
  const AdFormScreen({super.key, this.editId});
  final int? editId;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return SectionScaffold(
      section: Section.ads,
      title: editId == null ? app.t('ads.new') : app.t('ads.edit'),
      body: SafeArea(
        child: editId == null
            ? const _AdForm(existing: null)
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  Async<Listing>(
                    cacheKey: 'edit|$editId',
                    load: () async => Listing.fromJson(await app.api.get('/listings/$editId')),
                    builder: (context, a, reload) => _AdForm(existing: a, embedded: true),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AdForm extends StatefulWidget {
  const _AdForm({required this.existing, this.embedded = false});
  final Listing? existing;
  final bool embedded;

  @override
  State<_AdForm> createState() => _AdFormState();
}

class _AdFormState extends State<_AdForm> {
  late String _category;
  late String _lang;
  late int _days;
  City? _city;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _price = TextEditingController();
  final _employer = TextEditingController();
  final _pay = TextEditingController();
  final _schedule = TextEditingController();
  final _terms = TextEditingController();
  ApiError? _error;
  bool _busy = false;
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final app = context.app;
    final a = widget.existing;
    if (a != null) {
      _category = a.category;
      _lang = a.lang;
      _days = a.durationDays;
      _city = a.city;
      _title.text = a.title;
      _body.text = a.body;
      _price.text = a.price ?? '';
      _employer.text = a.extra['employer'] ?? '';
      _pay.text = a.extra['pay'] ?? '';
      _schedule.text = a.extra['schedule'] ?? '';
      _terms.text = a.extra['terms'] ?? '';
    } else {
      _category = 'housing';
      _lang = app.lang;
      _days = 14;
      _city = app.city;
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _price, _employer, _pay, _schedule, _terms]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCity() async {
    final c = await Navigator.of(context).push<City>(MaterialPageRoute<City>(builder: (_) => const CityPickerScreen(pickOnly: true)));
    if (c != null && mounted) setState(() => _city = c);
  }

  String? _orNull(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _submit() async {
    final app = context.app;
    final work = _category == 'work';
    final invalid = _title.text.trim().length < 5 ||
        _body.text.trim().length < 10 ||
        _city == null ||
        (work && (_employer.text.trim().isEmpty || _pay.text.trim().isEmpty));
    if (invalid) {
      setState(() => _error = ApiError(400, 'validation'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = {
      'category': _category,
      'title': _title.text.trim(),
      'body': _body.text.trim(),
      'lang': _lang,
      'city_id': _city!.id,
      'price': (work || _category == 'free') ? null : _orNull(_price),
      'duration_days': _days,
      if (work) 'extra': {'employer': _employer.text.trim(), 'pay': _pay.text.trim(), 'schedule': _orNull(_schedule), 'terms': _orNull(_terms)},
    };
    try {
      final editId = widget.existing?.id;
      final j = editId == null ? await app.api.post('/listings', payload) : await app.api.patch('/listings/$editId', payload);
      if (!mounted) return;
      Navigator.of(context).pop(j is Map ? (j['id'] as num?)?.toInt() : editId);
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
    final work = _category == 'work';
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Notice(child: Text(app.t('ads.safety'))),
        const SizedBox(height: 8),
        PickerField<String>(
          key: const ValueKey('ad-category'),
          label: app.t('ads.field.category'),
          value: _category,
          options: [for (final c in kCategories) Opt<String>(c, app.tk('ads.cat', c))],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('ad-title-input'), controller: _title, maxLength: 120, decoration: InputDecoration(labelText: app.t('ads.field.title'))),
        if (work) ...[
          TextField(key: const ValueKey('ad-employer'), controller: _employer, maxLength: 200, decoration: InputDecoration(labelText: app.t('ads.field.employer'))),
          TextField(key: const ValueKey('ad-pay'), controller: _pay, maxLength: 200, decoration: InputDecoration(labelText: app.t('ads.field.pay'))),
          TextField(key: const ValueKey('ad-schedule'), controller: _schedule, maxLength: 200, decoration: InputDecoration(labelText: app.t('ads.field.schedule'))),
          TextField(key: const ValueKey('ad-terms'), controller: _terms, maxLength: 200, decoration: InputDecoration(labelText: app.t('ads.field.terms'))),
        ],
        TextField(key: const ValueKey('ad-body'), controller: _body, minLines: 5, maxLines: 10, maxLength: 4000, decoration: InputDecoration(labelText: app.t('ads.field.body'))),
        if (!work && _category != 'free')
          TextField(key: const ValueKey('ad-price'), controller: _price, maxLength: 80, decoration: InputDecoration(labelText: app.t('ads.field.price'))),
        const SizedBox(height: 8),
        Text(app.t('ads.field.city'), style: Theme.of(context).textTheme.labelMedium),
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            key: const ValueKey('ad-city'),
            avatar: const Icon(Icons.place_outlined, size: 18),
            label: Text(_city?.label ?? app.t('city.none'), overflow: TextOverflow.ellipsis),
            onPressed: _pickCity,
          ),
        ),
        const SizedBox(height: 12),
        PickerField<String>(
          key: const ValueKey('ad-lang-select'),
          label: app.t('ads.lang'),
          value: _lang,
          options: [for (final l in kLangs) Opt<String>(l.code, l.native)],
          onChanged: (v) => setState(() => _lang = v ?? _lang),
        ),
        const SizedBox(height: 12),
        PickerField<int>(
          key: const ValueKey('ad-days'),
          label: app.t('ads.field.duration'),
          value: _days,
          options: [for (final d in const [7, 14, 30]) Opt<int>(d, app.t('ads.days', {'n': d}))],
          onChanged: (v) => setState(() => _days = v ?? _days),
        ),
        ErrorBox(error: _error),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('ad-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(widget.existing == null ? app.t('ads.new') : app.t('common.save')),
        ),
      ],
    );
    return widget.embedded ? form : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), child: form);
  }
}
