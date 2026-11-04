import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Step { choose, detecting, confirm, manual }

/// Выбор города. Три режима:
///  • [onboarding] — после выбора языка, можно отложить;
///  • обычный — смена города из шапки: сохраняет город и закрывается;
///  • [pickOnly] — вернуть город вызвавшему экрану (например, для объявления), не меняя город приложения.
class CityPickerScreen extends StatefulWidget {
  const CityPickerScreen({super.key, this.onboarding = false, this.pickOnly = false});
  final bool onboarding;
  final bool pickOnly;

  @override
  State<CityPickerScreen> createState() => _CityPickerScreenState();
}

class _CityPickerScreenState extends State<CityPickerScreen> {
  _Step _step = _Step.choose;
  String? _message;
  City? _candidate;
  List<City>? _results;
  bool _searching = false;
  final _query = TextEditingController();
  final _debounce = Debouncer(250);
  int _seq = 0;

  @override
  void dispose() {
    _debounce.dispose();
    _query.dispose();
    super.dispose();
  }

  void _manual([String? messageKey]) {
    setState(() {
      _message = messageKey == null ? null : context.t(messageKey);
      _step = _Step.manual;
    });
  }

  Future<void> _detect() async {
    final app = context.app;
    setState(() {
      _message = null;
      _step = _Step.detecting;
    });
    // Разрешение на геолокацию запрашивается здесь, по нажатию кнопки, а не при запуске.
    final result = await app.detectCity();
    if (!mounted) return;
    if (result.candidate != null) {
      setState(() {
        _candidate = result.candidate;
        _step = _Step.confirm;
      });
    } else {
      _manual(result.messageKey);
    }
  }

  void _done(City c) {
    if (widget.pickOnly) {
      Navigator.of(context).pop(c);
      return;
    }
    context.app.setCity(c);
    if (!widget.onboarding) Navigator.of(context).pop();
  }

  void _skip() => context.app.skipCity();

  void _onQuery(String q) {
    _debounce.run(() async {
      final seq = ++_seq;
      if (q.trim().isEmpty) {
        if (mounted) setState(() => _results = null);
        return;
      }
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final j = await context.app.api.get('/cities', query: {'q': q});
        if (!mounted || seq != _seq) return;
        final list = (j is Map && j['cities'] is List) ? (j['cities'] as List).map(City.fromJson).toList() : <City>[];
        setState(() {
          _results = list;
          _searching = false;
        });
      } catch (_) {
        if (!mounted || seq != _seq) return;
        setState(() {
          _results = const [];
          _searching = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final onboarding = widget.onboarding;
    final compact = MediaQuery.viewInsetsOf(context).bottom > 0 || MediaQuery.sizeOf(context).height < 680;
    return SectionTheme(
      section: Section.where,
      child: Builder(builder: (context) {
        final body = SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              if (onboarding) ...[
                // При первом запуске заголовок длинный, поэтому он выводится в теле экрана, под цветной шапкой.
                Text(app.t('city.title'), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(app.t('city.subtitle'))),
              ],
              if (_message != null) Notice(key: const ValueKey('city-message'), child: Text(_message!)),
              if (_step == _Step.choose) ..._choose(app),
              if (_step == _Step.detecting)
                Padding(padding: const EdgeInsets.all(24), child: Center(child: Column(children: [const CircularProgressIndicator(), const SizedBox(height: 12), Text(app.t('city.detecting'))]))),
              if (_step == _Step.confirm && _candidate != null) ..._confirm(app, _candidate!),
              if (_step == _Step.manual) ..._manualSearch(app),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.lock_outline, size: 18, color: Palette.ink3)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(app.t('city.privacy'), style: Theme.of(context).textTheme.bodySmall)),
                ],
              ),
            ],
          ),
        );
        if (onboarding) {
          return Scaffold(
            body: Column(children: [HeroHeader(icon: Icons.place, compact: compact), Expanded(child: body)]),
          );
        }
        return Scaffold(appBar: SectionAppBar(title: app.t('city.change')), body: body);
      }),
    );
  }

  List<Widget> _choose(AppState app) => [
        FilledButton.icon(
          key: const ValueKey('city-detect'),
          onPressed: _detect,
          icon: const Icon(Icons.my_location),
          label: Text(app.t('city.detect')),
        ),
        const SizedBox(height: 12),
        OutlinedButton(key: const ValueKey('city-manual'), onPressed: () => _manual(), child: Text(app.t('city.manual'))),
        const SizedBox(height: 8),
        if (widget.onboarding)
          TextButton(key: const ValueKey('city-skip'), onPressed: _skip, child: Text(app.t('city.skip')))
        else
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(app.t('common.cancel'))),
      ];

  List<Widget> _confirm(AppState app, City c) => [
        Text(app.t('city.found', {'city': c.label}), key: const ValueKey('city-candidate'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        FilledButton(key: const ValueKey('city-confirm'), onPressed: () => _done(c), child: Text(app.t('city.confirmYes'))),
        const SizedBox(height: 12),
        OutlinedButton(key: const ValueKey('city-reject'), onPressed: () => _manual(), child: Text(app.t('city.confirmNo'))),
      ];

  List<Widget> _manualSearch(AppState app) => [
        TextField(
          key: const ValueKey('city-search'),
          controller: _query,
          autofocus: true,
          onChanged: _onQuery,
          decoration: InputDecoration(hintText: app.t('city.searchPlaceholder'), prefixIcon: const Icon(Icons.search)),
        ),
        const SizedBox(height: 8),
        if (_searching) const LinearProgressIndicator(minHeight: 2),
        if (_results != null && _results!.isEmpty && !_searching) EmptyNote(app.t('city.noResults')),
        if (_results != null)
          for (final c in _results!)
            ListTile(
              key: ValueKey('city-${c.id}'),
              title: Text(c.name),
              subtitle: Text(c.region),
              onTap: () => _done(c),
            ),
        const SizedBox(height: 8),
        // Wrap, а не Row: на узком экране «Назад» и «Пропустить» вместе могут не
        // поместиться в одну строку — тогда вторая кнопка переносится вниз
        // вместо того, чтобы вылезать за край.
        Wrap(spacing: 4, runSpacing: 4, children: [
          TextButton(
            onPressed: () => setState(() {
              _message = null;
              _step = _Step.choose;
            }),
            child: Text(app.t('common.back')),
          ),
          if (widget.onboarding) TextButton(onPressed: _skip, child: Text(app.t('city.skip'))),
        ]),
      ];
}
