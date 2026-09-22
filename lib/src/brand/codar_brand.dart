import 'package:flutter/material.dart';

/// CODAR V2 presentation tokens. Business and reader contracts do not depend on this layer.
class CodarColors {
  static const background = Color(0xFF080A0D);
  static const surface = Color(0xFF13171C);
  static const elevated = Color(0xFF181D23);
  static const card = Color(0xFF1C2229);
  static const primaryText = Color(0xFFF4F1E9);
  static const secondaryText = Color(0xFFA9ABB0);
  static const muted = Color(0xFF70757D);
  static const divider = Color(0xFF282D34);
  static const gold = Color(0xFFC8A35A);
  static const brightGold = Color(0xFFE0BD72);
  static const darkGold = Color(0xFF8D713B);
  static const readerBackground = Color(0xFFF3EEDF);
  static const readerText = Color(0xFF25221D);

  // Compatibility aliases for existing presentation files.
  static const navy = surface;
  static const navyDeep = background;
  static const navySoft = elevated;
  static const charcoal = card;
  static const cream = primaryText;
  static const creamDark = secondaryText;
  static const creamInk = readerText;
  static const goldDeep = darkGold;
  static const goldWash = Color(0x33C8A35A);

  static ThemeData light() => _theme(Brightness.light);
  static ThemeData dark() => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: gold,
      onPrimary: background,
      secondary: brightGold,
      onSecondary: background,
      error: const Color(0xFFE58B83),
      onError: background,
      surface: dark ? surface : readerBackground,
      onSurface: dark ? primaryText : readerText,
      surfaceContainerHighest: dark ? card : Colors.white,
      onSurfaceVariant: dark ? secondaryText : const Color(0xFF5F5A51),
      outline: dark ? divider : const Color(0xFFD7CFBF),
      outlineVariant: dark ? divider : const Color(0xFFE2D9C9),
    );
    final base = ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: dark ? background : readerBackground,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme;
    return base.copyWith(
      textTheme: text.copyWith(
        displayLarge: text.displayLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
        ),
        titleLarge: text.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
          letterSpacing: -.25,
        ),
        bodyLarge: text.bodyLarge?.copyWith(
          color: scheme.onSurface,
          height: 1.45,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.35,
        ),
        labelMedium: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: .35,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: dark ? card : Colors.white.withValues(alpha: .72),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? elevated : Colors.white.withValues(alpha: .86),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: gold, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: dark ? divider : const Color(0xFFE1D8C8),
        space: 1,
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide.none,
        backgroundColor: dark ? elevated : Colors.white.withValues(alpha: .75),
        selectedColor: gold.withValues(alpha: .20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        labelStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        elevation: 0,
        height: 72,
        indicatorColor: gold.withValues(alpha: .16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? brightGold : muted,
            size: 21,
          ),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(
            color: secondaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: background,
        indicatorColor: gold.withValues(alpha: .16),
        labelType: NavigationRailLabelType.all,
        selectedIconTheme: const IconThemeData(color: brightGold),
        unselectedIconTheme: const IconThemeData(color: muted),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: brightGold),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: secondaryText,
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: primaryText,
        iconColor: gold,
        subtitleTextStyle: text.bodyMedium?.copyWith(color: secondaryText),
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        minLeadingWidth: 32,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
    );
  }
}

class CodarLogo extends StatelessWidget {
  const CodarLogo({
    super.key,
    this.height = 28,
    this.horizontal = false,
    this.symbolOnly = false,
    this.onDarkBackground,
  });
  final double height;
  final bool horizontal;
  final bool symbolOnly;
  final bool? onDarkBackground;
  @override
  Widget build(BuildContext context) {
    final dark =
        onDarkBackground ?? Theme.of(context).brightness == Brightness.dark;
    final asset = symbolOnly
        ? 'assets/brand/read_further/icons/codar_app_icon_1024.png'
        : horizontal
        ? (dark
              ? 'assets/brand/codar_logo_premium_v2_transparent.png'
              : 'assets/brand/read_further/codar_logo_horizontal_light_transparent.png')
        : (dark
              ? 'assets/brand/codar_logo_premium_v2_transparent.png'
              : 'assets/brand/read_further/codar_logo_stacked_light_transparent.png');
    return Semantics(
      label: 'Codar',
      image: true,
      child: Image.asset(
        asset,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) =>
            Text('CODAR', style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}

class CodarMarkLockup extends StatelessWidget {
  const CodarMarkLockup({
    super.key,
    this.markHeight = 40,
    this.vertical = false,
    this.onDarkBackground = true,
  });

  final double markHeight;
  final bool vertical;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      'CODAR',
      style: TextStyle(
        color: onDarkBackground
            ? CodarColors.primaryText
            : CodarColors.readerText,
        fontSize: vertical ? 26 : 17,
        fontWeight: FontWeight.w600,
        letterSpacing: vertical ? 6 : 3,
      ),
    );
    final children = [
      CodarLogo(
        height: markHeight,
        symbolOnly: true,
        onDarkBackground: onDarkBackground,
      ),
      SizedBox(width: vertical ? 0 : 9, height: vertical ? 8 : 0),
      label,
    ];
    return Flex(
      direction: vertical ? Axis.vertical : Axis.horizontal,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}

class CodarEmptyState extends StatelessWidget {
  const CodarEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: CodarColors.darkGold),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    ),
  );
}
