import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Оборачивает экран в тему раздела: кнопки, поля, флажки и шапка берут его цвет.
class SectionTheme extends StatelessWidget {
  const SectionTheme({super.key, required this.section, required this.child});
  final Section section;
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(data: themeFor(section), child: child);
}

// ------------------------------------------------------------------ логотип

/// Знак «S!» на белой плитке: для шапки.
class BrandTile extends StatelessWidget {
  const BrandTile({super.key, this.size = 38});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * 13 / 38)),
          child: Image.asset('assets/brand/mark_color.png', width: size * 27 / 38, cacheWidth: 160),
        ),
      );
}

/// Иконка приложения целиком (градиент, белая S и жёлтый «!»): для первого экрана.
class BrandIcon extends StatelessWidget {
  const BrandIcon({super.key, this.size = 88});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 24 / 88),
            boxShadow: const [BoxShadow(color: Color(0x1F1B1B2B), offset: Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 24 / 88),
            // 384×384: крупнее приложение иконку не рисует. Оригинал 1024 (assets/brand/icon.png) —
            // только для flutter_launcher_icons, в сборку не входит.
            child: Image.asset('assets/brand/icon_384.png', width: size, height: size, cacheWidth: 384),
          ),
        ),
      );
}

// ------------------------------------------------------------------ шапки

/// Фон шапки с формой раздела. Форма только украшение, скринридер её не видит.
class SectionBackdrop extends StatelessWidget {
  const SectionBackdrop({super.key, required this.tone});
  final SectionTone tone;

  @override
  Widget build(BuildContext context) {
    final c = tone.shapeColor;
    final Widget shape;
    switch (tone.shape) {
      case HeaderShape.quarter:
        shape = Positioned(
          right: 0,
          top: 0,
          width: 210,
          height: 210,
          child: DecoratedBox(decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(210)))),
        );
      case HeaderShape.circle:
        shape = Positioned(right: -70, top: -80, width: 250, height: 250, child: DecoratedBox(decoration: BoxDecoration(color: c, shape: BoxShape.circle)));
      case HeaderShape.arch:
        shape = Positioned(
          right: 28,
          bottom: -70,
          width: 180,
          height: 250,
          child: DecoratedBox(decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.vertical(top: Radius.circular(90)))),
        );
      case HeaderShape.inverseQuarter:
        shape = Positioned(
          right: 0,
          bottom: 0,
          width: 210,
          height: 210,
          child: DecoratedBox(decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.only(topLeft: Radius.circular(210)))),
        );
    }
    return ExcludeSemantics(child: ClipRect(child: Stack(children: [shape])));
  }
}

/// Светлый «лист», который закрывает нижний край шапки скруглением.
class SheetCap extends StatelessWidget {
  const SheetCap({super.key, this.height = 32});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Palette.bg, borderRadius: BorderRadius.vertical(top: Radius.circular(height))),
        ),
      );
}

/// Верхняя полоса внутренних экранов: цветная, с белой круглой кнопкой «назад» и заголовком.
class SectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SectionAppBar({super.key, required this.title});
  final String title;

  static const double _toolbar = 68;
  static const double _cap = 28;

  @override
  Size get preferredSize => const Size.fromHeight(_toolbar + _cap);

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    return AppBar(
      backgroundColor: tone.header,
      foregroundColor: tone.onHeader,
      toolbarHeight: _toolbar,
      systemOverlayStyle: tone.overlay,
      automaticallyImplyLeading: false,
      leadingWidth: 64,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: BackButton(
          style: ButtonStyle(
            backgroundColor: const WidgetStatePropertyAll(Colors.white),
            foregroundColor: const WidgetStatePropertyAll(Palette.ink),
            fixedSize: const WidgetStatePropertyAll(Size(44, 44)),
            shape: const WidgetStatePropertyAll(CircleBorder()),
          ),
        ),
      ),
      titleSpacing: 4,
      title: Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: tone.onHeader, fontSize: 24, height: 30 / 24)),
      flexibleSpace: SectionBackdrop(tone: tone),
      bottom: const PreferredSize(preferredSize: Size.fromHeight(_cap), child: SheetCap(height: _cap)),
    );
  }
}

/// Внутренний экран: тема раздела, цветная полоса сверху, при необходимости нижняя панель.
class SectionScaffold extends StatelessWidget {
  const SectionScaffold({super.key, required this.section, required this.title, required this.body, this.bottom});
  final Section section;
  final String title;
  final Widget body;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => SectionTheme(
        section: section,
        child: Builder(
          builder: (context) => Scaffold(
            appBar: SectionAppBar(title: title),
            body: SafeArea(top: false, child: body),
            bottomNavigationBar: bottom,
          ),
        ),
      );
}

/// Крупная шапка с белым кругом и значком: для первого запуска (выбор города).
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.icon, this.compact = false, this.onBack, this.backLabel});
  final IconData icon;

  /// Низкий экран или открытая клавиатура: круг меньше, отступы короче.
  final bool compact;

  /// Если задано — слева вверху появляется кнопка «Назад» (белый круг со стрелкой, как в шапках разделов).
  final VoidCallback? onBack;
  final String? backLabel;

  @override
  Widget build(BuildContext context) {
    final tone = context.tone;
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: tone.overlay,
      child: ColoredBox(
        color: tone.header,
        child: Stack(
          children: [
            Positioned.fill(child: SectionBackdrop(tone: tone)),
            Padding(
              padding: EdgeInsets.only(top: top + (compact ? 12 : 24), bottom: compact ? 44 : 56),
              child: Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: compact ? 64 : 108,
                    height: compact ? 64 : 108,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x1F000000), offset: Offset(0, 8))],
                    ),
                    child: Icon(icon, size: compact ? 32 : 54, color: tone.accent),
                  ),
                ),
              ),
            ),
            if (onBack != null)
              PositionedDirectional(
                top: top + 8,
                start: 12,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: IconButton(
                    key: const ValueKey('hero-back'),
                    tooltip: backLabel,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: const BackButtonIcon(),
                    color: Palette.ink,
                    onPressed: onBack,
                  ),
                ),
              ),
            const Positioned(left: 0, right: 0, bottom: 0, child: SheetCap()),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ прогресс и рамки

/// Кольцо прогресса. Число в центре задаёт [child]; кольцо само ничего не говорит скринридеру.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.color, required this.track, required this.child, this.size = 76, this.stroke = 10});
  final double value;
  final Color color;
  final Color track;
  final Widget child;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(value.clamp(0.0, 1.0), color, track, stroke),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.track, this.stroke);
  final double value;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (value <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track || old.stroke != stroke;
}

/// Пунктирная рамка со скруглением: так отмечены демо-записи (не только цветом, но и формой линии).
class DashedBorder extends StatelessWidget {
  const DashedBorder({super.key, required this.color, required this.radius, required this.child, this.width = 2, this.dash = 7, this.gap = 4});
  final Color color;
  final double radius;
  final double width;
  final double dash;
  final double gap;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        foregroundPainter: _DashedPainter(color, radius, width, dash, gap),
        child: child,
      );
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color, this.radius, this.width, this.dash, this.gap);
  final Color color;
  final double radius;
  final double width;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(width / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.radius != radius || old.width != width || old.dash != dash || old.gap != gap;
}
