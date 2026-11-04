import 'package:flutter/material.dart';

import '../api/models.dart';
import '../state/app_scope.dart';
import 'brand.dart';
import 'theme.dart';

/// Цвета плиток: пять языков — пять цветов логотипа. Текст на оранжевой и жёлтой плитке тёмный.
const List<(Color bg, Color fg)> _tileColors = [
  (Palette.blue, Colors.white),
  (Palette.violet, Colors.white),
  (Palette.orange, Palette.ink),
  (Palette.pink, Colors.white),
  (Palette.yellow, Palette.ink),
];

/// Первый экран: знак, название и пять цветных плиток. Названия языков написаны на самих языках, перевод не нужен.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 6, bottom: 18), child: Align(alignment: AlignmentDirectional.centerStart, child: BrandIcon())),
                  // Название одно для всех языков и показывается до загрузки переводов, поэтому не из словаря.
                  Text('Salam!', style: text.headlineLarge),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.language, size: 20, color: Palette.ink2),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Тил · Забон · Language · Til', style: text.bodyLarge?.copyWith(color: Palette.ink2))),
                  ]),
                  const SizedBox(height: 24),
                  for (var i = 0; i < kLangs.length; i++) _LangTile(lang: kLangs[i], colors: _tileColors[i % _tileColors.length], onTap: () => app.setLang(kLangs[i].code)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LangTile extends StatelessWidget {
  const _LangTile({required this.lang, required this.colors, required this.onTap});
  final LangInfo lang;
  final (Color bg, Color fg) colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colors;
    final dark = fg == Palette.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(26), boxShadow: const [BoxShadow(color: Color(0x26000000), offset: Offset(0, 5))]),
        child: Material(
          type: MaterialType.transparency,
          child: Semantics(
            button: true,
            label: lang.native,
            excludeSemantics: true,
            onTap: onTap,
            child: InkWell(
              key: ValueKey('lang-${lang.code}'),
              borderRadius: BorderRadius.circular(26),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 70),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        // Подложка кода языка: светлая под тёмным текстом и тёмная под белым (иначе белое на светлом даёт 3:1 вместо 4.5:1).
                        decoration: BoxDecoration(color: dark ? const Color(0x70FFFFFF) : const Color(0x2E000000), borderRadius: BorderRadius.circular(17)),
                        child: Text(lang.code.toUpperCase(), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: fg)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Text(lang.native, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: fg))),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_forward, size: 20, color: Palette.ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Смена языка из меню (после первого запуска).
Future<void> showLanguageSheet(BuildContext context) {
  final app = context.app;
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(app.t('lang.title'), style: Theme.of(ctx).textTheme.titleMedium),
          ),
          for (final l in kLangs)
            ListTile(
              key: ValueKey('menu-lang-${l.code}'),
              title: Text(l.native),
              trailing: l.code == app.lang ? Icon(Icons.check_circle, color: ctx.tone.accent) : null,
              onTap: () {
                app.setLang(l.code);
                Navigator.of(ctx).pop();
              },
            ),
        ],
      ),
    ),
  );
}
