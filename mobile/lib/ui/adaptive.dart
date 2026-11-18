import 'package:flutter/widgets.dart';

/// Классы ширины окна Material 3 — единственный набор точек перелома в приложении.
/// Решение принимается по ширине окна, а не по типу устройства: телефон в альбомной
/// ориентации, планшет в разделённом экране и раскладушка дают честную ширину.
enum WindowSizeClass { compact, medium, expanded, large, extraLarge }

WindowSizeClass windowSizeClassFor(double width) => switch (width) {
      < 600 => WindowSizeClass.compact,
      < 840 => WindowSizeClass.medium,
      < 1200 => WindowSizeClass.expanded,
      < 1600 => WindowSizeClass.large,
      _ => WindowSizeClass.extraLarge,
    };

/// Ограничивает содержимое удобной для чтения шириной и ставит его по центру.
/// На телефоне (уже [maxWidth]) ничего не меняет — дочерний виджет получает те же ограничения.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child});
  final Widget child;

  /// Около 70 знаков основного текста в строке.
  static const double maxWidth = 720;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth <= maxWidth) return child;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: maxWidth, height: c.hasBoundedHeight ? c.maxHeight : null, child: child),
        );
      });
}
