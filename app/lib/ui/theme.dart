import 'package:flutter/material.dart';

/// KhataBol's look: ledger ink on paper.
///
/// Indigo (dyed cloth, register ink) is the one brand colour. Green and the
/// red of a bahi-khata cover carry meaning only: green is money to receive,
/// red is money to pay. Everything else stays neutral so those two stand out
/// in bright market light.
@immutable
class KColors extends ThemeExtension<KColors> {
  const KColors({
    required this.ink,
    required this.onInk,
    required this.paper,
    required this.surface,
    required this.text,
    required this.muted,
    required this.line,
    required this.lena,
    required this.lenaSoft,
    required this.dena,
    required this.denaSoft,
    required this.lenaOnInk,
    required this.denaOnInk,
  });

  final Color ink;
  final Color onInk;
  final Color paper;
  final Color surface;
  final Color text;
  final Color muted;
  final Color line;

  /// Money to receive ("Lena hai").
  final Color lena;
  final Color lenaSoft;

  /// Money to pay ("Dena hai").
  final Color dena;
  final Color denaSoft;

  /// The same two meanings, readable on an [ink] background.
  final Color lenaOnInk;
  final Color denaOnInk;

  static const light = KColors(
    ink: Color(0xFF243282),
    onInk: Colors.white,
    paper: Color(0xFFF1F3F7),
    surface: Colors.white,
    text: Color(0xFF161925),
    muted: Color(0xFF5E6577),
    line: Color(0xFFE2E5EC),
    lena: Color(0xFF0B7A53),
    lenaSoft: Color(0xFFE2F3EB),
    dena: Color(0xFFB42318),
    denaSoft: Color(0xFFFBE8E6),
    lenaOnInk: Color(0xFF8BE7C1),
    denaOnInk: Color(0xFFFFB3AA),
  );

  static const dark = KColors(
    ink: Color(0xFF2E3C94),
    onInk: Colors.white,
    paper: Color(0xFF0E1117),
    surface: Color(0xFF181C25),
    text: Color(0xFFECEEF4),
    muted: Color(0xFF9CA3B5),
    line: Color(0xFF272C38),
    lena: Color(0xFF52CC9E),
    lenaSoft: Color(0xFF15302A),
    dena: Color(0xFFFF8D80),
    denaSoft: Color(0xFF3A1D1B),
    lenaOnInk: Color(0xFF8BE7C1),
    denaOnInk: Color(0xFFFFB3AA),
  );

  static KColors of(BuildContext context) => Theme.of(context).extension<KColors>()!;

  /// Green for money to receive, red for money to pay, muted when settled.
  Color forBalance(num balance) => balance > 0 ? lena : (balance < 0 ? dena : muted);

  Color softForBalance(num balance) => balance > 0 ? lenaSoft : (balance < 0 ? denaSoft : line);

  @override
  KColors copyWith() => this;

  @override
  KColors lerp(KColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

const _font = 'Figtree';

/// Digits of equal width, so amounts line up in a column.
const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme(Brightness brightness) {
  final k = brightness == Brightness.dark ? KColors.dark : KColors.light;
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: k.ink, brightness: brightness).copyWith(
    primary: dark ? const Color(0xFFAFBBFF) : k.ink,
    onPrimary: dark ? const Color(0xFF101A55) : k.onInk,
    surface: k.surface,
    onSurface: k.text,
    onSurfaceVariant: k.muted,
    outline: k.muted,
    outlineVariant: k.line,
    error: k.dena,
    surfaceContainerLowest: k.surface,
    surfaceContainerLow: k.surface,
    surfaceContainer: k.surface,
    surfaceContainerHigh: k.surface,
    surfaceContainerHighest: k.paper,
  );

  final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme, fontFamily: _font);
  final t = base.textTheme;
  final text = t.copyWith(
    headlineLarge: t.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, color: k.text),
    headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6, color: k.text),
    headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4, color: k.text),
    titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3, color: k.text),
    titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: k.text),
    titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: k.text),
    bodyLarge: t.bodyLarge?.copyWith(color: k.text),
    bodyMedium: t.bodyMedium?.copyWith(color: k.text),
    bodySmall: t.bodySmall?.copyWith(color: k.muted, fontSize: 12.5),
    labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    labelMedium: t.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: k.muted),
    labelSmall: t.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: k.muted),
  );

  final radius12 = BorderRadius.circular(12);
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: c, width: w));

  return base.copyWith(
    extensions: [k],
    textTheme: text,
    scaffoldBackgroundColor: k.paper,
    canvasColor: k.paper,
    dividerColor: k.line,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: k.paper,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      foregroundColor: k.text,
      titleTextStyle: text.titleLarge?.copyWith(fontSize: 22, fontFamily: _font),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: k.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: scheme.primary.withValues(alpha: 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: _font,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? scheme.primary : k.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? scheme.primary : k.muted)),
    ),
    cardTheme: CardThemeData(
      color: k.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 12,
      titleTextStyle: text.titleMedium?.copyWith(fontSize: 16, fontFamily: _font),
      subtitleTextStyle: text.bodySmall?.copyWith(fontSize: 13, fontFamily: _font),
      iconColor: k.muted,
    ),
    dividerTheme: DividerThemeData(color: k.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: k.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(k.line),
      enabledBorder: border(k.line),
      focusedBorder: border(scheme.primary, 1.8),
      errorBorder: border(k.dena),
      focusedErrorBorder: border(k.dena, 1.8),
      labelStyle: TextStyle(color: k.muted, fontFamily: _font),
      floatingLabelStyle: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontFamily: _font),
      hintStyle: TextStyle(color: k.muted.withValues(alpha: 0.7), fontFamily: _font),
      helperStyle: TextStyle(color: k.muted, fontFamily: _font),
      prefixIconColor: k.muted,
      suffixIconColor: k.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: k.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: _font, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w700)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: k.ink,
      foregroundColor: k.onInk,
      elevation: 2,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: const TextStyle(fontFamily: _font, fontSize: 15, fontWeight: FontWeight.w700),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: k.surface,
      selectedColor: scheme.primary,
      side: BorderSide(color: k.line),
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: TextStyle(fontFamily: _font, fontWeight: FontWeight.w600, color: k.text),
      secondaryLabelStyle: TextStyle(fontFamily: _font, fontWeight: FontWeight.w700, color: scheme.onPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: k.surface,
        selectedBackgroundColor: scheme.primary,
        selectedForegroundColor: scheme.onPrimary,
        foregroundColor: k.text,
        side: BorderSide(color: k.line),
        textStyle: const TextStyle(fontFamily: _font, fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 46),
      ).copyWith(visualDensity: VisualDensity.standard),
      selectedIcon: const SizedBox.shrink(),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: k.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: k.line,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: k.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      titleTextStyle: text.titleLarge?.copyWith(fontFamily: _font),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: k.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: TextStyle(fontFamily: _font, color: k.text, fontSize: 15),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2A3042) : const Color(0xFF1C2033),
      contentTextStyle: const TextStyle(fontFamily: _font, color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}
