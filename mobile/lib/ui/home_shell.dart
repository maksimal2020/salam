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
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              NavigationDestination(key: const ValueKey('tab-docs'), icon: const Icon(Icons.description_outlined), selectedIcon: const Icon(Icons.description), label: app.t('nav.docs')),
              NavigationDestination(key: const ValueKey('tab-where'), icon: const Icon(Icons.place_outlined), selectedIcon: const Icon(Icons.place), label: app.t('nav.where')),
              NavigationDestination(key: const ValueKey('tab-tips'), icon: const Icon(Icons.lightbulb_outline), selectedIcon: const Icon(Icons.lightbulb), label: app.t('nav.tips')),
              NavigationDestination(key: const ValueKey('tab-ads'), icon: const Icon(Icons.campaign_outlined), selectedIcon: const Icon(Icons.campaign), label: app.t('nav.ads')),
            ],
          ),
        ),
      ),
    );
  }
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
                        const BrandTile(),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(app.t('app.name'), style: text.titleLarge?.copyWith(color: tone.onHeader, fontSize: 20, letterSpacing: -0.4)),
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
