import 'package:flutter/material.dart';

/// Раздел в навигации: ключ для тестов, значки и подпись.
class AppNavDestination {
  const AppNavDestination({required this.key, required this.icon, required this.selectedIcon, required this.label});
  final Key key;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Самый мелкий шрифт подписи с учётом системного масштаба — как подписи вкладок iOS.
const double _kMinLabel = 10;

/// Подписи увеличиваются вместе с системным размером шрифта, но не больше чем в 1,3 раза:
/// иначе четыре подписи физически не помещаются в ширину телефона.
const double _kMaxLabelScale = 1.3;

/// Подогнанные подписи: общий размер шрифта, тексты (возможно, с переносом по слогам) и
/// высота блока подписи — одна на все разделы, чтобы значки стояли на одной линии.
class NavLabelFit {
  const NavLabelFit({required this.size, required this.labels, required this.blockHeight});
  final double size;
  final List<String> labels;
  final double blockHeight;
}

/// Подбирает подписи под ширину колонки [slotWidth].
///
/// Базовый размер растёт с шириной колонки (узкий телефон — мельче, широкий — крупнее), затем
/// уменьшается ровно настолько, чтобы самое длинное слово встало целиком, но не мельче
/// [_kMinLabel]. Слово, которое не влезает и так (казахское «Хабарландырулар» на узком
/// экране), делится по слогам с дефисом. Слова никогда не рвутся посередине без дефиса.
NavLabelFit fitNavLabels(BuildContext context, List<String> labels, double slotWidth, {required TextStyle style}) {
  final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _kMaxLabelScale);
  final dir = Directionality.of(context);
  final room = slotWidth - 8.5; // 8 — воздух между соседними подписями, 0,5 — запас на округление

  TextPainter paint(String s, double size, {double? maxWidth}) => TextPainter(
        text: TextSpan(text: s, style: style.copyWith(fontSize: size)),
        textDirection: dir,
        textAlign: TextAlign.center,
        textScaler: scaler,
      )..layout(maxWidth: maxWidth ?? double.infinity);

  double width(String s, double size) {
    final tp = paint(s, size);
    final w = tp.width;
    tp.dispose();
    return w;
  }

  final words = {for (final l in labels) ...l.split(' ')};
  var size = (slotWidth * 0.14).clamp(11.5, 14.0).toDouble();
  while (words.any((w) => width(w, size) > room)) {
    final next = size - 0.25;
    if (scaler.scale(next) < _kMinLabel) break;
    size = next;
  }
  String fitWord(String w) => width(w, size) <= room ? w : hyphenateNavWord(w, (part) => width(part, size) <= room);
  final fitted = [for (final l in labels) l.split(' ').map(fitWord).join(' ')];

  var block = 0.0;
  for (final l in fitted) {
    final tp = paint(l, size, maxWidth: room);
    if (tp.height > block) block = tp.height;
    tp.dispose();
  }
  return NavLabelFit(size: size, labels: fitted, blockHeight: block.ceilToDouble());
}

const _vowels = 'аеёиоуыэюяәіөүұӯӣАЕЁИОУЫЭЮЯӘІӨҮҰӮӢaeiouAEIOU';

/// Делит длинное слово дефисами на куски, каждый из которых (вместе с дефисом) проходит [fits].
/// Место разрыва — как можно правее, по возможности после гласной перед согласной
/// («Хабарландыру-лар»); в каждом куске не меньше трёх букв. Строка переносится после дефиса.
String hyphenateNavWord(String word, bool Function(String part) fits) {
  final out = <String>[];
  var rest = word;
  while (!fits(rest) && rest.length >= 6) {
    int? best;
    int? fallback;
    for (var i = rest.length - 3; i >= 3; i--) {
      if (!fits('${rest.substring(0, i)}-')) continue;
      fallback ??= i;
      if (_vowels.contains(rest[i - 1]) && !_vowels.contains(rest[i])) {
        best = i;
        break;
      }
    }
    final cut = best ?? fallback;
    if (cut == null) break;
    out.add('${rest.substring(0, cut)}-');
    rest = rest.substring(cut);
  }
  out.add(rest);
  return out.join();
}

/// Один раздел: значок в «таблетке» выбранного раздела и подпись по центру под ним.
/// Подпись стоит в блоке общей высоты и прижата к верху — значки всех разделов на одной линии.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.dest, required this.label, required this.selected, required this.onTap, required this.fit});
  final AppNavDestination dest;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final NavLabelFit fit;

  @override
  Widget build(BuildContext context) {
    final theme = NavigationBarTheme.of(context);
    final states = {if (selected) WidgetState.selected};
    final iconTheme = theme.iconTheme?.resolve(states) ?? const IconThemeData(size: 24);
    final style = (theme.labelTextStyle?.resolve(states) ?? const TextStyle()).copyWith(fontSize: fit.size);
    final animate = !MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: dest.label, // полное слово, без переноса
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: dest.key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: animate ? const Duration(milliseconds: 200) : Duration.zero,
                curve: Curves.easeOut,
                width: 64,
                height: 32,
                decoration: ShapeDecoration(shape: const StadiumBorder(), color: selected ? theme.indicatorColor : Colors.transparent),
                child: Icon(selected ? dest.selectedIcon : dest.icon, color: iconTheme.color, size: iconTheme.size),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: fit.blockHeight,
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: _kMaxLabelScale,
                  child: Text(label, textAlign: TextAlign.center, style: style, softWrap: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Самый широкий вариант подписи (выбранный раздел жирнее) — по нему считается раскладка.
/// Берётся итоговый стиль, как у самого Text: вместе с унаследованными межбуквенным
/// интервалом и высотой строки, иначе замер и отрисовка расходятся на пару пикселей.
TextStyle _measureStyle(BuildContext context) => DefaultTextStyle.of(context)
    .style
    .merge(NavigationBarTheme.of(context).labelTextStyle?.resolve({WidgetState.selected}) ?? const TextStyle(fontWeight: FontWeight.w800));

/// Нижняя панель для узких окон (телефон в портретной ориентации).
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.destinations, required this.selectedIndex, required this.onSelected});
  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = NavigationBarTheme.of(context);
    return Material(
      color: theme.backgroundColor ?? Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: theme.shadowColor,
      elevation: theme.elevation ?? 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: LayoutBuilder(builder: (context, c) {
            final slot = c.maxWidth / destinations.length;
            final fit = fitNavLabels(context, [for (final d in destinations) d.label], slot, style: _measureStyle(context));
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _NavItem(dest: destinations[i], label: fit.labels[i], selected: i == selectedIndex, onTap: () => onSelected(i), fit: fit),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// Боковая колонка для широких окон (планшет, раскладушка, альбомная ориентация).
/// Ширина подбирается по самому длинному слову подписей, в пределах 88–128.
class AppNavRail extends StatelessWidget {
  const AppNavRail({super.key, required this.destinations, required this.selectedIndex, required this.onSelected});
  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = NavigationBarTheme.of(context);
    return Material(
      color: theme.backgroundColor ?? Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: theme.shadowColor,
      elevation: theme.elevation ?? 8,
      child: Builder(builder: (context) {
        final style = _measureStyle(context).copyWith(fontSize: 13);
        final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: _kMaxLabelScale);
        var widest = 0.0;
        for (final d in destinations) {
          for (final w in d.label.split(' ')) {
            final tp = TextPainter(text: TextSpan(text: w, style: style), textDirection: Directionality.of(context), textScaler: scaler)..layout();
            if (tp.width > widest) widest = tp.width;
            tp.dispose();
          }
        }
        final width = (widest + 24).clamp(88.0, 128.0);
        final fit = fitNavLabels(context, [for (final d in destinations) d.label], width - 8, style: _measureStyle(context));
        return SafeArea(
          right: false,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _NavItem(dest: destinations[i], label: fit.labels[i], selected: i == selectedIndex, onTap: () => onSelected(i), fit: fit),
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
