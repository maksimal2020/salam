import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Четыре раздела приложения. У каждого свой цвет, своя форма в шапке и свой набор акцентов.
enum Section { docs, where, tips, ads }

/// Форма на шапке раздела: берётся из логотипа.
enum HeaderShape { quarter, circle, arch, inverseQuarter }

/// Цвета, которые не зависят от раздела. Смысл статуса всегда передаётся ещё значком и словом, не только цветом.
class Palette {
  static const ink = Color(0xFF1B1B2B);
  static const ink2 = Color(0xFF4B4B63);
  static const ink3 = Color(0xFF5D5D76);
  static const bg = Color(0xFFFFF9F1);
  static const line = Color(0xFFEEE6D8);

  /// Рамки полей и флажков: 3.4:1 к белому, порог для элементов управления — 3:1.
  static const control = Color(0xFF858B95);
  static const chip = Color(0xFFF3EDE2);
  static const shadow = Color(0x121B1B2B);

  static const verified = Color(0xFF14733F);
  static const verifiedSoft = Color(0xFFE3F5EA);
  static const demo = Color(0xFF7A4A00);
  static const demoSoft = Color(0xFFFFF4D6);
  static const demoLine = Color(0xFFC27A00);
  static const danger = Color(0xFFB42318);
  static const dangerSoft = Color(0xFFFDE8E6);

  /// Фирменные цвета логотипа и плиток языков. Используются только как заливка с контрастным текстом.
  static const blue = Color(0xFF3A5BFF);
  static const blueDark = Color(0xFF2440C0);
  static const violet = Color(0xFF7C4DFF);
  static const orange = Color(0xFFFF8A3D);
  static const pink = Color(0xFFE8397A);
  static const yellow = Color(0xFFFFC93C);
}

/// Цвета текущего раздела. Лежит в теме как расширение, поэтому достаётся через `context.tone`.
@immutable
class SectionTone extends ThemeExtension<SectionTone> {
  const SectionTone({
    required this.header,
    required this.onHeader,
    required this.headerPill,
    required this.accent,
    required this.accentSoft,
    required this.navTile,
    required this.shape,
    required this.shapeColor,
  });

  /// Заливка шапки и цвет текста на ней.
  final Color header;
  final Color onHeader;

  /// Подложка круглых кнопок и «таблеток» в шапке.
  final Color headerPill;

  /// Цвет кнопок, ссылок и значков на белом (контраст не ниже 5:1) и его мягкий фон.
  final Color accent;
  final Color accentSoft;

  /// Подложка выбранного пункта нижнего меню.
  final Color navTile;
  final HeaderShape shape;
  final Color shapeColor;

  bool get lightText => onHeader == Colors.white;

  /// Значки строки состояния: светлые на тёмной шапке и наоборот.
  SystemUiOverlayStyle get overlay => lightText ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

  static const _docs = SectionTone(
    header: Palette.blue,
    onHeader: Colors.white,
    headerPill: Color(0x26000000),
    accent: Color(0xFF2F4FE6),
    accentSoft: Color(0xFFEAEEFF),
    navTile: Color(0xFFEAEEFF),
    shape: HeaderShape.quarter,
    shapeColor: Color(0x24FFFFFF),
  );
  static const _where = SectionTone(
    header: Palette.violet,
    onHeader: Colors.white,
    headerPill: Color(0x26000000),
    accent: Color(0xFF6A3DEB),
    accentSoft: Color(0xFFF0EAFF),
    navTile: Color(0xFFF0EAFF),
    shape: HeaderShape.circle,
    shapeColor: Color(0x24FFFFFF),
  );
  static const _tips = SectionTone(
    header: Palette.orange,
    onHeader: Palette.ink,
    headerPill: Color(0x66FFFFFF),
    accent: Color(0xFFB84A00),
    accentSoft: Color(0xFFFFF0E3),
    navTile: Color(0xFFFFE9D4),
    shape: HeaderShape.arch,
    shapeColor: Color(0x4DFFFFFF),
  );
  static const _ads = SectionTone(
    header: Palette.pink,
    onHeader: Colors.white,
    headerPill: Color(0x26000000),
    accent: Color(0xFFC21D62),
    accentSoft: Color(0xFFFFE9F1),
    navTile: Color(0xFFFFE9F1),
    shape: HeaderShape.inverseQuarter,
    shapeColor: Color(0x24FFFFFF),
  );

  static SectionTone of(Section s) {
    switch (s) {
      case Section.docs:
        return _docs;
      case Section.where:
        return _where;
      case Section.tips:
        return _tips;
      case Section.ads:
        return _ads;
    }
  }

  @override
  SectionTone copyWith({
    Color? header,
    Color? onHeader,
    Color? headerPill,
    Color? accent,
    Color? accentSoft,
    Color? navTile,
    HeaderShape? shape,
    Color? shapeColor,
  }) =>
      SectionTone(
        header: header ?? this.header,
        onHeader: onHeader ?? this.onHeader,
        headerPill: headerPill ?? this.headerPill,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        navTile: navTile ?? this.navTile,
        shape: shape ?? this.shape,
        shapeColor: shapeColor ?? this.shapeColor,
      );

  @override
  SectionTone lerp(ThemeExtension<SectionTone>? other, double t) {
    if (other is! SectionTone) return this;
    return SectionTone(
      header: Color.lerp(header, other.header, t)!,
      onHeader: Color.lerp(onHeader, other.onHeader, t)!,
      headerPill: Color.lerp(headerPill, other.headerPill, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      navTile: Color.lerp(navTile, other.navTile, t)!,
      shape: t < 0.5 ? shape : other.shape,
      shapeColor: Color.lerp(shapeColor, other.shapeColor, t)!,
    );
  }
}

extension ToneContext on BuildContext {
  /// Цвета раздела, в теме которого находится виджет. Вне темы раздела — синий раздел «Документы».
  SectionTone get tone => Theme.of(this).extension<SectionTone>() ?? SectionTone.of(Section.docs);
}

const String _inter = 'Inter';
const String _display = 'InterDisplay';

TextStyle _s(double size, FontWeight w, {Color color = Palette.ink, double? height, double? spacing, String family = _inter}) =>
    TextStyle(fontFamily: family, fontSize: size, fontWeight: w, color: color, height: height, letterSpacing: spacing);

TextTheme _textTheme() => TextTheme(
      // Крупные заголовки шапки: Inter Display ExtraBold с плотным трекингом, как в макете.
      headlineLarge: _s(44, FontWeight.w800, height: 48 / 44, spacing: -1.5, family: _display),
      headlineMedium: _s(36, FontWeight.w800, height: 42 / 36, spacing: -1.1, family: _display),
      headlineSmall: _s(26, FontWeight.w800, height: 32 / 26, spacing: -0.6, family: _display),
      titleLarge: _s(22, FontWeight.w800, height: 28 / 22, spacing: -0.3),
      titleMedium: _s(19, FontWeight.w800, height: 25 / 19, spacing: -0.2),
      titleSmall: _s(16, FontWeight.w700, height: 22 / 16),
      bodyLarge: _s(17, FontWeight.w400, height: 1.4),
      bodyMedium: _s(16, FontWeight.w400, height: 1.4),
      bodySmall: _s(14, FontWeight.w400, color: Palette.ink3, height: 1.4),
      labelLarge: _s(16, FontWeight.w800),
      labelMedium: _s(13.5, FontWeight.w600, color: Palette.ink2),
      labelSmall: _s(12.5, FontWeight.w600, color: Palette.ink2),
    );

OutlineInputBorder _field(Color c, double w) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));

/// Светлая тема раздела. Тёмной темы в утверждённом дизайне нет, поэтому приложение всегда светлое (см. app.dart).
ThemeData buildTheme(Section section) {
  final t = SectionTone.of(section);
  final scheme = ColorScheme.light(
    primary: t.accent,
    onPrimary: Colors.white,
    primaryContainer: t.accentSoft,
    onPrimaryContainer: Palette.ink,
    secondary: t.accent,
    onSecondary: Colors.white,
    secondaryContainer: t.accentSoft,
    onSecondaryContainer: Palette.ink,
    tertiary: Palette.demo,
    onTertiary: Colors.white,
    tertiaryContainer: Palette.demoSoft,
    onTertiaryContainer: Palette.demo,
    error: Palette.danger,
    onError: Colors.white,
    errorContainer: Palette.dangerSoft,
    onErrorContainer: Palette.danger,
    surface: Colors.white,
    onSurface: Palette.ink,
    onSurfaceVariant: Palette.ink2,
    outline: Palette.control,
    outlineVariant: Palette.line,
    surfaceTint: Colors.transparent,
  );
  final text = _textTheme();
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    fontFamily: _inter,
    textTheme: text,
    scaffoldBackgroundColor: Palette.bg,
    canvasColor: Palette.bg,
    visualDensity: VisualDensity.standard,
    extensions: [t],
    appBarTheme: AppBarTheme(
      backgroundColor: t.header,
      foregroundColor: t.onHeader,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      systemOverlayStyle: t.overlay,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: _field(Palette.control, 1.5),
      enabledBorder: _field(Palette.control, 1.5),
      focusedBorder: _field(t.accent, 2.5),
      errorBorder: _field(Palette.danger, 1.5),
      focusedErrorBorder: _field(Palette.danger, 2.5),
      labelStyle: _s(16, FontWeight.w500, color: Palette.ink2),
      hintStyle: _s(16, FontWeight.w400, color: Palette.ink3),
      prefixIconColor: Palette.ink2,
      suffixIconColor: Palette.ink2,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: buttonShape,
        backgroundColor: t.accent,
        foregroundColor: Colors.white,
        textStyle: _s(16, FontWeight.w800),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: buttonShape,
        foregroundColor: t.accent,
        backgroundColor: Colors.white,
        side: BorderSide(color: t.accent, width: 2),
        textStyle: _s(16, FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: t.accent,
        textStyle: _s(16, FontWeight.w700),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      side: const BorderSide(color: Palette.line, width: 1.5),
      shape: const StadiumBorder(),
      labelStyle: _s(15, FontWeight.w600),
      iconTheme: IconThemeData(color: t.accent, size: 20),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(color: s.contains(WidgetState.selected) ? t.accent : Palette.control, width: 2),
      ),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? t.accent : Colors.white),
      checkColor: const WidgetStatePropertyAll(Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Palette.ink,
      elevation: 12,
      height: 80,
      indicatorColor: t.navTile,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? t.accent : Palette.ink2, size: 26),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => _s(12.5, s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600, color: s.contains(WidgetState.selected) ? Palette.ink : Palette.ink2),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent, linearTrackColor: t.accentSoft),
    dividerTheme: const DividerThemeData(color: Palette.line, space: 1),
    listTileTheme: ListTileThemeData(iconColor: t.accent, titleTextStyle: _s(16, FontWeight.w600)),
  );
}

final Map<Section, ThemeData> _themes = {};

/// Тема раздела, собранная один раз: переключение вкладок не пересобирает ThemeData.
ThemeData themeFor(Section s) => _themes.putIfAbsent(s, () => buildTheme(s));
