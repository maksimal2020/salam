import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/app_scope.dart';
import '../util/links.dart';
import 'brand.dart';
import 'theme.dart';

// ------------------------------------------------------------------ загрузка данных

/// Загружает данные и перезагружает их при смене [cacheKey]. Прежние данные остаются на экране, пока идёт обновление.
class Async<T> extends StatefulWidget {
  const Async({super.key, required this.cacheKey, required this.load, required this.builder});

  final Object cacheKey;
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;

  @override
  State<Async<T>> createState() => _AsyncState<T>();
}

class _AsyncState<T> extends State<Async<T>> {
  T? _data;
  ApiError? _error;
  bool _loading = true;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _run(first: true);
  }

  @override
  void didUpdateWidget(Async<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) _run();
  }

  Future<void> _run({bool first = false}) async {
    final seq = ++_seq;
    _loading = true;
    _error = null;
    if (!first && mounted) setState(() {});
    try {
      final d = await widget.load();
      if (!mounted || seq != _seq) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = ApiError(0, 'network');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      if (_error != null) return ErrorBox(error: _error, onRetry: _run);
      return const Loading();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null) ErrorBox(error: _error, onRetry: _run),
        widget.builder(context, data, _run),
      ],
    );
  }
}

/// Задержка перед запросом, пока пользователь печатает.
class Debouncer {
  Debouncer(this.milliseconds);
  final int milliseconds;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void dispose() => _timer?.cancel();
}

// ------------------------------------------------------------------ состояния

const Map<String, String> kErrorKeys = {
  'network': 'error.network',
  'forbidden': 'ads.err.forbidden',
  'passport': 'ads.err.passport',
  'contact': 'ads.err.contact',
  'validation': 'ads.err.fields',
  'own_listing': 'ads.err.own',
  'invalid_credentials': 'auth.err.invalid',
  'email_taken': 'auth.err.exists',
  'weak_password': 'auth.err.weak',
  'unauthorized': 'ads.loginToAct',
  'not_found': 'error.notFound',
};

class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.error, this.onRetry});
  final ApiError? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final e = error;
    if (e == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Palette.dangerSoft, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.error_outline, color: Palette.danger, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t(kErrorKeys[e.code] ?? 'error.generic'), style: const TextStyle(color: Palette.danger, fontWeight: FontWeight.w600)),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(foregroundColor: Palette.danger, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                    child: Text(context.t('common.retry')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            Text(context.t('common.loading'), style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Palette.ink2))),
      );
}

/// Рамка с пояснением: обычная (цвет раздела), предупреждение о демо-данных или подтверждение.
class Notice extends StatelessWidget {
  const Notice({super.key, required this.child, this.demo = false, this.ok = false});
  final Widget child;
  final bool demo;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final Color bg = demo ? Palette.demoSoft : (ok ? Palette.verifiedSoft : tone.accentSoft);
    final Color fg = demo ? Palette.demo : (ok ? Palette.verified : tone.accent);
    final IconData icon = demo ? Icons.warning_amber_rounded : (ok ? Icons.check_circle_outline : Icons.info_outline);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, color: fg, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ карточки и метки

/// Белая карточка с мягкой тенью. Демо-запись получает пунктирную янтарную рамку, выполненный шаг — рамку цвета раздела.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.dashed = false, this.outlined = false});
  final Widget child;
  final VoidCallback? onTap;
  final bool dashed;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(28);
    final body = Padding(padding: const EdgeInsets.all(20), child: child);
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        boxShadow: const [BoxShadow(color: Palette.shadow, offset: Offset(0, 8), blurRadius: 24)],
        border: outlined ? Border.all(color: context.tone.accent, width: 2.5) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: onTap == null ? body : InkWell(borderRadius: radius, onTap: onTap, child: body),
      ),
    );
    if (dashed) card = DashedBorder(color: Palette.demoLine, radius: 28, child: card);
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: card);
  }
}

/// Скруглённая плитка со значком в цвете раздела (слева в карточке).
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.size = 54});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: tone.accentSoft, borderRadius: BorderRadius.circular(size * 19 / 54)),
        child: Icon(icon, color: tone.accent, size: size * 28 / 54),
      ),
    );
  }
}

/// Круглая стрелка «открыть» в правом нижнем углу карточки.
class ArrowDot extends StatelessWidget {
  const ArrowDot({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: context.tone.accent, shape: BoxShape.circle),
          child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
        ),
      );
}

/// Подпись происхождения над заголовком: «Официальная инструкция», «Совет редакции», «Объявление пользователя».
class SourceLabel extends StatelessWidget {
  const SourceLabel(this.text, this.icon, {super.key});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 16, color: context.tone.accent)),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: Theme.of(context).textTheme.labelMedium)),
          ],
        ),
      );
}

/// Таблетка статуса: значок, слово и (для «демо») пунктирная рамка — смысл не держится на одном цвете.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.fg, required this.bg, this.icon, this.dashed = false});
  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 15, color: fg)), const SizedBox(width: 5)],
          Flexible(child: Text(text, style: TextStyle(fontSize: 13, height: 1.25, fontWeight: FontWeight.w700, color: fg))),
        ],
      ),
    );
    if (dashed) pill = DashedBorder(color: Palette.demoLine, radius: 999, width: 1.5, dash: 5, gap: 3, child: pill);
    return pill;
  }
}

/// Проверено по официальному источнику или только демонстрация.
class Stamp extends StatelessWidget {
  const Stamp({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final verified = status == 'verified';
    return _Pill(
      text: context.t(verified ? 'badge.verified' : 'badge.demo'),
      icon: verified ? Icons.verified_user_outlined : Icons.warning_amber_rounded,
      fg: verified ? Palette.verified : Palette.demo,
      bg: verified ? Palette.verifiedSoft : Palette.demoSoft,
      dashed: !verified,
    );
  }
}

/// Нейтральная метка. С [color] — окрашенная (например, красная «жалоб: 2»).
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return _Pill(
      text: text,
      fg: c ?? Palette.ink2,
      bg: c == null ? Palette.chip : (c == Palette.danger ? Palette.dangerSoft : c.withAlpha(30)),
    );
  }
}

class Necessity extends StatelessWidget {
  const Necessity(this.value, {super.key});
  final String value;
  @override
  Widget build(BuildContext context) => value == 'mandatory'
      ? _Pill(text: context.t('badge.mandatory'), icon: Icons.priority_high, fg: Palette.danger, bg: Palette.dangerSoft)
      : Tag(context.t('badge.$value'));
}

class Badges extends StatelessWidget {
  const Badges(this.children, {super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: children);
}

// ------------------------------------------------------------------ источники и учреждения

/// Источники и дата проверки в мягком блоке цвета раздела.
class SourceList extends StatelessWidget {
  const SourceList({super.key, required this.sources, required this.checkedAt});
  final List<SourceLink> sources;
  final String? checkedAt;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.tone.accentSoft, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in sources) LinkText(s.title, () => openExternal(s.url), icon: Icons.open_in_new),
          if (sources.isNotEmpty) const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.event_available_outlined, size: 16, color: context.tone.accent)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  checkedAt != null ? app.t('common.checkedOn', {'date': app.fmtDate(checkedAt)}) : app.t('common.notChecked'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Подпись и значение; со значком — в карточке учреждения.
class Fact extends StatelessWidget {
  const Fact(this.label, this.child, {super.key, this.icon});
  final String label;
  final Widget child;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        child,
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: icon == null
          ? body
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 20, color: context.tone.accent)),
                const SizedBox(width: 10),
                Expanded(child: body),
              ],
            ),
    );
  }
}

/// Ссылка цвета раздела. Высота нажимаемой области не меньше 44.
class LinkText extends StatelessWidget {
  const LinkText(this.text, this.onTap, {super.key, this.icon});
  final String text;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final color = context.tone.accent;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: color))),
            if (icon != null) ...[const SizedBox(width: 6), Icon(icon, size: 16, color: color)],
          ],
        ),
      ),
    );
  }
}

/// 0.3 → «0,3», 2.0 → «2», 11.7 → «12» — не больше одного знака после запятой,
/// и округляем до целого за пределами одного км (дробная точность там не нужна).
String _fmtKm(double km) {
  if (km >= 10) return km.round().toString();
  final r = (km * 10).round() / 10;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString().replaceAll('.', ',');
}

class InstitutionCard extends StatelessWidget {
  const InstitutionCard({super.key, required this.inst});
  final Institution inst;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final city = app.city;
    final url = mapUrl(inst.map, inst.address, inst.city.name);
    final serves = inst.serves.map((s) {
      if (s.country) return app.t('where.allRussia');
      final c = s.city ?? '';
      return s.districts != null ? '$c: ${s.districts!.join(', ')}' : c;
    }).toList();

    return AppCard(
      dashed: inst.status != 'verified',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconTile(Icons.account_balance_outlined, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SourceLabel(app.t('badge.official'), Icons.shield_outlined),
                    Text(inst.name, style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Badges([
            Stamp(status: inst.status),
            Tag(app.t('mode.${inst.mode}')),
            if (inst.distanceKm != null)
              Tag(
                // Для approx (нет подтверждённых координат здания — считали от
                // центра города) честно показываем «≈», а не точную цифру.
                app.t(inst.distanceApprox ? 'where.distanceApprox' : 'where.distance', {'km': _fmtKm(inst.distanceKm!)}),
                color: inst.distanceApprox ? Palette.ink3 : Palette.verified,
              ),
          ]),
          const SizedBox(height: 14),
          Fact(
            app.t('common.address'),
            inst.address != null
                ? Text('${inst.address}, ${inst.city.region}')
                : Text(
                    // «Онлайн» без адреса — это не пробел в данных (как для in_person/both),
                    // а нормальное свойство услуги без физического места приёма.
                    app.t(inst.mode == 'online' ? 'where.onlineNoAddress' : 'where.addressUnconfirmed'),
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
            icon: Icons.place_outlined,
          ),
          if (inst.otherCity && city != null && inst.address != null)
            Notice(child: Text(app.t('where.servesNote', {'address': '${inst.address}, ${inst.city.name}', 'city': city.name}))),
          Fact(app.t('common.services'), Text(inst.services.map((s) => s.name).join('; ')), icon: Icons.assignment_outlined),
          Fact(app.t('where.serves'), Text(serves.join('; ')), icon: Icons.map_outlined),
          if (inst.citizenships != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(app.t('where.citizens', {'countries': inst.citizenships!.join(', ')}), style: Theme.of(context).textTheme.bodySmall),
            ),
          if (inst.hours != null) Fact(app.t('common.hours'), Text(inst.hours!), icon: Icons.schedule),
          if (inst.phone != null) Fact(app.t('common.phone'), LinkText(inst.phone!, () => openExternal(telUri(inst.phone!))), icon: Icons.call_outlined),
          if (inst.site != null)
            Fact(app.t('common.site'), LinkText(inst.site!.replaceFirst(RegExp(r'^https?://'), ''), () => openExternal(inst.site!)), icon: Icons.language),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (url != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => openExternal(url),
                icon: const Icon(Icons.map_outlined),
                label: Text(app.t('common.openMap')),
              ),
            if (inst.bookingUrl != null)
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => openExternal(inst.bookingUrl!),
                child: Text(app.t('common.booking')),
              ),
          ]),
          if (url != null && inst.address == null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(app.t('where.mapByName'), style: Theme.of(context).textTheme.bodySmall)),
          if (inst.note != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(inst.note!, style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 12),
          SourceList(sources: inst.sources, checkedAt: inst.checkedAt),
        ],
      ),
    );
  }
}

/// Выбор района города (нужен, когда учреждение зависит от района).
class DistrictSelect extends StatelessWidget {
  const DistrictSelect({super.key, required this.districts, required this.value, required this.onChanged});
  final List<District> districts;
  final String? value;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Notice(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(app.t('city.districtTitle'), style: Theme.of(context).textTheme.titleSmall),
          Text(app.t('city.districtHint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          PickerField<String>(
            label: app.t('city.districtTitle'),
            value: value,
            options: [
              Opt<String>(null, app.t('city.districtAny')),
              for (final d in districts) Opt<String>(d.id, d.name),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Когда проверенных адресов нет: честно говорим об этом и даём ссылку на официальный поиск, если она есть.
class NoPlaces extends StatelessWidget {
  const NoPlaces({super.key, required this.cityName, required this.officialSearch, required this.sources});
  final String cityName;
  final SourceLink? officialSearch;
  final List<SourceLink> sources;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EmptyNote(app.t('where.none', {'city': cityName})),
        if (officialSearch != null)
          OutlinedButton(
            onPressed: () => openExternal(officialSearch!.url),
            child: Text('${app.t('where.officialSearch')}: ${officialSearch!.title}', textAlign: TextAlign.center),
          )
        else
          Text(app.t('where.noOfficialSearch'), style: Theme.of(context).textTheme.bodySmall),
        if (sources.isNotEmpty) ...[const SizedBox(height: 8), SourceList(sources: sources, checkedAt: null)],
      ],
    );
  }
}

// ------------------------------------------------------------------ поля ввода

class Opt<T> {
  const Opt(this.value, this.label);
  final T? value;
  final String label;
}

/// Поле выбора из списка: открывает нижнюю панель. Не зависит от версии виджета Dropdown.
class PickerField<T> extends StatelessWidget {
  const PickerField({super.key, required this.label, required this.value, required this.options, required this.onChanged});
  final String label;
  final T? value;
  final List<Opt<T>> options;
  final void Function(T?) onChanged;

  @override
  Widget build(BuildContext context) {
    String shown = '';
    for (final o in options) {
      if (o.value == value) shown = o.label;
    }
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final picked = await showModalBottomSheet<_Picked<T>>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      minVerticalPadding: 12,
                      title: Text(o.label, style: TextStyle(fontWeight: o.value == value ? FontWeight.w800 : FontWeight.w500)),
                      trailing: o.value == value ? Icon(Icons.check_circle, color: ctx.tone.accent) : null,
                      onTap: () => Navigator.of(ctx).pop(_Picked<T>(o.value)),
                    ),
                ],
              ),
            ),
          ),
        );
        if (picked != null) onChanged(picked.value);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.expand_more)),
        child: Text(shown, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

class _Picked<T> {
  const _Picked(this.value);
  final T? value;
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged, this.controller});
  final String hint;
  final void Function(String) onChanged;
  final TextEditingController? controller;
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search)),
      );
}

/// Один переключаемый «таблеточный» тумблер (вкл/выкл), например «Рядом со мной».
/// Тот же визуальный язык и доступность, что у [ChipChoice] — просто на одно значение,
/// а не на список вариантов.
class ToggleChip extends StatelessWidget {
  const ToggleChip({super.key, required this.icon, required this.label, required this.selected, required this.onChanged});
  final IconData icon;
  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _ChoicePill(
        label: label,
        selected: selected,
        leading: selected ? null : icon,
        onTap: () => onChanged(!selected),
      );
}

/// Горизонтальный ряд выбора (категории, темы, ситуации). Выбранный пункт отмечен цветом, галочкой и состоянием для скринридера.
class ChipChoice extends StatelessWidget {
  const ChipChoice({super.key, required this.options, required this.value, required this.onChanged});
  final List<Opt<String>> options;
  final String value;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final o in options)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: _ChoicePill(label: o.label, selected: (o.value ?? '') == value, onTap: () => onChanged(o.value ?? '')),
              ),
          ],
        ),
      );
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({required this.label, required this.selected, required this.onTap, this.leading});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  /// Значок слева, когда пилюля НЕ выбрана (выбранная всегда показывает галочку).
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final accent = context.tone.accent;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? accent : Colors.white,
        shape: StadiumBorder(side: selected ? BorderSide.none : const BorderSide(color: Palette.line, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[const Icon(Icons.check, size: 18, color: Colors.white), const SizedBox(width: 6)]
                  else if (leading != null) ...[Icon(leading, size: 18, color: Palette.ink), const SizedBox(width: 6)],
                  Text(label, style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: selected ? Colors.white : Palette.ink)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка с текущим городом: открывает смену города. В шапке белая с нижней тенью, в содержимом — с тонкой рамкой.
class CityButton extends StatelessWidget {
  const CityButton({super.key, required this.onTap, this.onHeader = false});
  final VoidCallback onTap;
  final bool onHeader;

  @override
  Widget build(BuildContext context) {
    final city = context.app.city;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: onHeader ? null : Border.all(color: Palette.line, width: 1.5),
        boxShadow: onHeader ? const [BoxShadow(color: Color(0x1A000000), offset: Offset(0, 3))] : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.place, size: 22, color: context.tone.accent),
                  const SizedBox(width: 8),
                  Flexible(child: Text(city?.label ?? context.t('city.none'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Palette.ink))),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more, size: 22, color: Palette.ink2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget gap([double h = 12]) => SizedBox(height: h);
