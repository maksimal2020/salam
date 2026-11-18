import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_scope.dart';
import 'account_screens.dart';
import 'ads_screen.dart';
import 'brand.dart';
import 'city_picker_screen.dart';
import 'data_screen.dart';
import 'docs_screen.dart';
import 'feedback_screen.dart';
import 'language_screen.dart';
import 'theme.dart';
import 'tips_screen.dart';
import 'where_screen.dart';
import 'widgets.dart';

void openCityPicker(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CityPickerScreen()));
}

/// Основная оболочка: цветная шапка с городом и языком, четыре раздела внизу. Цвет шапки, меню и кнопок зависит от раздела.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = <Widget>[DocsTab(), WhereTab(), TipsTab(), AdsTab()];

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final section = Section.values[_index];
    // Читается здесь, выше Scaffold: внутри него отступ клавиатуры уже учтён раскладкой.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final titles = [app.t('docs.title'), app.t('where.title'), app.t('tips.title'), app.t('ads.title')];
    return SectionTheme(
      section: section,
      child: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              _HomeHeader(title: titles[_index], keyboard: keyboard),
              if (app.offline)
                Container(
                  width: double.infinity,
                  color: Palette.demoSoft,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(children: [
                    const Icon(Icons.cloud_off, size: 20, color: Palette.demo),
                    const SizedBox(width: 10),
                    Expanded(child: Text(app.t('offline.notice'), style: const TextStyle(color: Palette.demo, fontWeight: FontWeight.w600))),
                  ]),
                ),
              Expanded(child: IndexedStack(index: _index, children: _tabs)),
            ],
          ),
          bottomNavigationBar: LayoutBuilder(builder: (context, constraints) {
            final insets = MediaQuery.paddingOf(context);
            final slot = (constraints.maxWidth - insets.left - insets.right) / 4;
            final nav = NavigationBarTheme.of(context);
            // В подсказке при долгом нажатии — слово без переноса.
            final fit = fitNavLabels(context, [app.t('nav.docs'), app.t('nav.where'), app.t('nav.tips'), app.t('nav.ads')], slot);
            return NavigationBarTheme(
              data: nav.copyWith(labelTextStyle: WidgetStateProperty.resolveWith((s) => nav.labelTextStyle?.resolve(s)?.copyWith(fontSize: fit.size))),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  NavigationDestination(key: const ValueKey('tab-docs'), icon: const Icon(Icons.description_outlined), selectedIcon: const Icon(Icons.description), label: fit.labels[0], tooltip: app.t('nav.docs')),
                  NavigationDestination(key: const ValueKey('tab-where'), icon: const Icon(Icons.place_outlined), selectedIcon: const Icon(Icons.place), label: fit.labels[1], tooltip: app.t('nav.where')),
                  NavigationDestination(key: const ValueKey('tab-tips'), icon: const Icon(Icons.lightbulb_outline), selectedIcon: const Icon(Icons.lightbulb), label: fit.labels[2], tooltip: app.t('nav.tips')),
                  NavigationDestination(key: const ValueKey('tab-ads'), icon: const Icon(Icons.campaign_outlined), selectedIcon: const Icon(Icons.campaign), label: fit.labels[3], tooltip: app.t('nav.ads')),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Самый мелкий шрифт подписи нижней панели с учётом системного масштаба: как подписи вкладок iOS.
const double _kMinNavLabel = 10;

/// Подписи нижней панели так, чтобы ни одно слово не рвалось посередине.
///
/// Material увеличивает подписи вместе с системным размером шрифта (не больше чем в 1,3 раза) и
/// не ограничивает число строк. При крупном шрифте «Объявления» не влезало в четверть экрана и
/// рвалось на «Объявлени / я». Здесь общий для всех четырёх подписей размер уменьшается ровно
/// настолько, чтобы каждое слово встало в свою колонку целиком, — но не мельче [_kMinNavLabel].
/// Слово, которое не влезает и так (казахское «Хабарландырулар» на узком экране), делится
/// по слогам с дефисом. Двухсловные подписи («Где оформить») по-прежнему идут в две строки.
({double size, List<String> labels}) fitNavLabels(BuildContext context, List<String> labels, double slotWidth) {
  final style = NavigationBarTheme.of(context).labelTextStyle?.resolve({WidgetState.selected}) ?? const TextStyle(fontSize: 12.5);
  final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3); // как внутри NavigationBar
  final dir = Directionality.of(context);
  final room = slotWidth - 8; // немного воздуха между соседними подписями

  double width(String s, double size) {
    final tp = TextPainter(text: TextSpan(text: s, style: style.copyWith(fontSize: size)), textDirection: dir, textScaler: scaler, maxLines: 1)
      ..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  final words = {for (final l in labels) ...l.split(' ')};
  var size = style.fontSize ?? 12.5;
  while (words.any((w) => width(w, size) > room)) {
    final next = size - 0.25;
    if (scaler.scale(next) < _kMinNavLabel) break;
    size = next;
  }
  String fitWord(String w) => width(w, size) <= room ? w : hyphenateNavWord(w, (part) => width(part, size) <= room);
  return (size: size, labels: [for (final l in labels) l.split(' ').map(fitWord).join(' ')]);
}

const _vowels = 'аеёиоуыэюяәіөүұӯӣАЕЁИОУЫЭЮЯӘІӨҮҰӮӢaeiouAEIOU';

/// Делит длинное слово дефисами на куски, каждый из которых (вместе с дефисом) проходит [fits].
/// Место разрыва — как можно правее, по возможности после гласной перед согласной
/// («Хабарланды-рулар»); в каждом куске не меньше трёх букв.
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
  // Перенос строки допустим после дефиса — части встанут в разные строки сами.
  return out.join();
}

/// Шапка: знак, язык, профиль и меню; город всегда на виду; крупный заголовок раздела.
/// На низком экране и при открытой клавиатуре шапка сжимается, чтобы оставить место списку.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.title, required this.keyboard});
  final String title;
  final bool keyboard;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final tone = context.tone;
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 680;
    final text = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: tone.overlay,
      child: ColoredBox(
        color: tone.header,
        child: Stack(
          children: [
            Positioned.fill(child: SectionBackdrop(tone: tone)),
            Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 16, 0),
                    child: Row(
                      children: [
                        // Знак с названием — одна кнопка: заново пройти первый запуск (язык, потом город).
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Tooltip(
                              message: app.t('app.restart'),
                              excludeFromSemantics: true,
                              child: Semantics(
                                button: true,
                                label: '${app.t('app.name')}. ${app.t('app.restart')}',
                                excludeSemantics: true,
                                onTap: app.restartOnboarding,
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: InkWell(
                                    key: const ValueKey('logo-button'),
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: app.restartOnboarding,
                                    child: Padding(
                                      padding: const EdgeInsetsDirectional.fromSTEB(0, 4, 8, 4),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        const BrandTile(),
                                        const SizedBox(width: 10),
                                        Flexible(
                                          child: Text(app.t('app.name'), style: text.titleLarge?.copyWith(color: tone.onHeader, fontSize: 20, letterSpacing: -0.4)),
                                        ),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _HeaderPill(
                          key: const ValueKey('lang-button'),
                          tooltip: app.t('lang.title'),
                          onTap: () => showLanguageSheet(context),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.language, size: 20, color: tone.onHeader),
                            const SizedBox(width: 6),
                            Text(app.lang.toUpperCase(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tone.onHeader)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        _HeaderPill(
                          key: const ValueKey('account-button'),
                          tooltip: app.t('auth.account'),
                          round: true,
                          onTap: () => openAccount(context),
                          child: Icon(Icons.person_outline, size: 22, color: tone.onHeader),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          tooltip: app.t('nav.more'),
                          onSelected: (v) {
                            if (v == 'data') Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DataScreen()));
                            if (v == 'feedback') Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FeedbackScreen()));
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem<String>(value: 'data', child: Text(app.t('nav.more'))),
                            PopupMenuItem<String>(value: 'feedback', child: Text(app.t('feedback.title'))),
                          ],
                          child: _HeaderPill(round: true, child: Icon(Icons.more_horiz, size: 22, color: tone.onHeader)),
                        ),
                      ],
                    ),
                  ),
                  if (!keyboard) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, compact ? 8 : 12, 20, 0),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: CityButton(key: const ValueKey('city-chip'), onHeader: true, onTap: () => openCityPicker(context)),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, compact ? 8 : 16, 20, 0),
                      child: Text(title, style: text.headlineMedium?.copyWith(color: tone.onHeader, fontSize: compact ? 28 : 36, height: compact ? 1.2 : 42 / 36)),
                    ),
                  ],
                  SizedBox(height: keyboard ? 40 : 44),
                ],
              ),
            ),
            const Positioned(left: 0, right: 0, bottom: 0, child: SheetCap(height: 30)),
          ],
        ),
      ),
    );
  }
}

/// Круглая или «таблеточная» кнопка на цветной шапке. Нажимаемая область не меньше 44 на 44.
class _HeaderPill extends StatelessWidget {
  const _HeaderPill({super.key, required this.child, this.onTap, this.tooltip, this.round = false});
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      constraints: BoxConstraints(minWidth: 44, minHeight: 44, maxHeight: round ? 44 : double.infinity),
      padding: EdgeInsets.symmetric(horizontal: round ? 0 : 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: context.tone.headerPill, borderRadius: BorderRadius.circular(999)),
      child: child,
    );
    if (onTap == null) return pill;
    // Подпись и действие заданы явно: внутренний текст («RU») скринридеру отдельно не нужен.
    return Tooltip(
      message: tooltip ?? '',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(customBorder: const StadiumBorder(), onTap: onTap, child: pill),
      ),
    );
  }
}
