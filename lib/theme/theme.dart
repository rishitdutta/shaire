import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Semantic positive/negative colors (money in / money out).
///
/// Success re-uses the brand green so the whole app speaks one green instead
/// of a brand pastel plus an unrelated forest green. As *text or icons* the
/// exact [AppTheme.primaryColor] fails contrast on light surfaces, so the
/// text variant is the same hue and saturation, darkened. Errors use a
/// desaturated, washed-out red rather than Material's fully saturated one.
class AppSemanticColors {
  const AppSemanticColors._();

  /// Exact brand primary, for *surfaces* (success snackbars, chips, avatars).
  static const Color positiveFill = AppTheme.primaryColor;

  /// Dark brand ink for text placed on [positiveFill].
  static const Color onPositiveFill = Color(0xFF14351D);

  /// Washed-out red for error *surfaces* (snackbars, destructive buttons).
  /// White text on it still clears 4.5:1.
  static const Color negativeFill = Color(0xFFA65B53);

  static Color positive(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFF477326) // brand hue, inked for AA on light
          : positiveFill; // the primary colour itself on dark surfaces

  static Color negative(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFB0554D)
          : const Color(0xFFE39A92);

  /// Amber for drafts / pending states.
  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light
          ? const Color(0xFF8A6100)
          : const Color(0xFFFFCF68);
}

class AppTheme {
  // Define common colors
  static const Color primaryColor = Color(0xFF99CF70);
  static const Color primaryDarkColor = Color(0xFF85B762);
  static const Color accentColor = Color(0xFFBBE3A3);
  static const Color errorColor = Color(0xFFB0554D);

  /// Same washed-out red, lifted for dark surfaces.
  static const Color errorColorDark = Color(0xFFE39A92);

  // Deep ink green: white-on-#99CF70 fails WCAG contrast (~1.9:1); this
  // keeps the brand hue while staying comfortably AA/AAA on the light
  // primary fill.
  static const Color _lightOnPrimaryColor = Color(0xFF14351D);

  // Light theme colors
  static const Color _lightTextPrimaryColor =
      Color(0xFF161616); // Dark text in light mode
  static const Color _lightTextSecondaryColor =
      Color(0xFF555555); // Secondary text in light mode
  static const Color _lightBackgroundColor =
      Color.fromARGB(255, 238, 241, 237); // Light background
  static const Color _lightCardColor = Colors.white;
  static const Color _lightDividerColor = Color(0xFFDDDDDD);

  // Dark theme colors
  static const Color _darkTextPrimaryColor =
      Color(0xFFE2E7E0); // Light text in dark mode
  static const Color _darkTextSecondaryColor =
      Color(0xFFAAAAAA); // Secondary text in dark mode
  static const Color _darkBackgroundColor =
      Color(0xFF161616); // Dark background you requested
  static const Color _darkCardColor =
      Color(0xFF212121); // Slightly lighter than background for cards
  static const Color _darkDividerColor = Color(0xFF424242);

  // Define text themes
  static TextTheme _buildTextTheme(
      TextTheme base, Color textColor, Color secondaryTextColor) {
    return base.copyWith(
      // Headings - Using Outfit font
      displayLarge: GoogleFonts.outfit(
        textStyle: base.displayLarge?.copyWith(color: textColor),
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
      displayMedium: GoogleFonts.outfit(
        textStyle: base.displayMedium?.copyWith(color: textColor),
        fontSize: 28,
        fontWeight: FontWeight.bold,
      ),
      displaySmall: GoogleFonts.outfit(
        textStyle: base.displaySmall?.copyWith(color: textColor),
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
      headlineLarge: GoogleFonts.outfit(
        textStyle: base.headlineLarge?.copyWith(color: textColor),
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.outfit(
        textStyle: base.headlineMedium?.copyWith(color: textColor),
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: GoogleFonts.outfit(
        textStyle: base.headlineSmall?.copyWith(color: textColor),
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.outfit(
        textStyle: base.titleLarge?.copyWith(color: textColor),
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: GoogleFonts.outfit(
        textStyle: base.titleMedium?.copyWith(color: textColor),
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      titleSmall: GoogleFonts.outfit(
        textStyle: base.titleSmall?.copyWith(color: textColor),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),

      // Body - Using Inter font
      bodyLarge: GoogleFonts.inter(
        textStyle: base.bodyLarge?.copyWith(color: textColor),
        fontSize: 16,
        fontWeight: FontWeight.normal,
      ),
      bodyMedium: GoogleFonts.inter(
        textStyle: base.bodyMedium?.copyWith(color: textColor),
        fontSize: 14,
        fontWeight: FontWeight.normal,
      ),
      bodySmall: GoogleFonts.inter(
        textStyle: base.bodySmall?.copyWith(color: secondaryTextColor),
        fontSize: 12,
        fontWeight: FontWeight.normal,
      ),
      labelLarge: GoogleFonts.inter(
        textStyle: base.labelLarge?.copyWith(color: textColor),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      labelMedium: GoogleFonts.inter(
        textStyle: base.labelMedium?.copyWith(color: textColor),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      labelSmall: GoogleFonts.inter(
        textStyle: base.labelSmall?.copyWith(color: secondaryTextColor),
        fontSize: 10,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  // Light theme
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: primaryColor,
      secondary: accentColor,
      error: errorColor,
      onPrimary: _lightOnPrimaryColor,
      onSecondary: _lightTextPrimaryColor,
      onError: Colors.white,
      primaryContainer: accentColor,
      onPrimaryContainer: _lightOnPrimaryColor,
      surface: _lightCardColor,
      onSurface: _lightTextPrimaryColor,
      surfaceContainerHighest: Color(0xFFEDF1E9),
      onSurfaceVariant: _lightTextSecondaryColor,
      outline: _lightDividerColor,
      outlineVariant: _lightDividerColor,
    ),
    scaffoldBackgroundColor: _lightBackgroundColor,
    cardColor: _lightCardColor,
    dividerColor: _lightDividerColor,
    dividerTheme: const DividerThemeData(
      color: _lightDividerColor,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: _lightTextPrimaryColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      iconTheme: const IconThemeData(color: _lightTextPrimaryColor),
      titleTextStyle: GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: _lightTextPrimaryColor,
      ),
    ),
    iconTheme: const IconThemeData(
      color: _lightTextSecondaryColor,
    ),
    textTheme: _buildTextTheme(
      ThemeData.light().textTheme,
      _lightTextPrimaryColor,
      _lightTextSecondaryColor,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: _lightOnPrimaryColor,
        backgroundColor: primaryColor,
        elevation: 0,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: const BorderSide(color: primaryColor, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _lightDividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _lightDividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorColor, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: GoogleFonts.inter(
        color: _lightTextSecondaryColor,
        fontSize: 14,
      ),
      labelStyle: GoogleFonts.inter(
        color: _lightTextSecondaryColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.grey[200],
      disabledColor: Colors.grey[300],
      selectedColor: primaryColor.withValues(alpha: 0.2),
      secondarySelectedColor: primaryColor.withValues(alpha: 0.2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      labelStyle: GoogleFonts.inter(
        fontSize: 14,
        color: _lightTextPrimaryColor,
      ),
      secondaryLabelStyle: GoogleFonts.inter(
        fontSize: 14,
        color: primaryColor,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    bottomAppBarTheme: const BottomAppBarThemeData(
      color: Colors.white,
      elevation: 8,
    ),
    cardTheme: const CardThemeData(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      elevation: 1,
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: _lightOnPrimaryColor,
      elevation: 4,
      shape: CircleBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2B2B2B),
      contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 14),
      actionTextColor: accentColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: _lightCardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titleTextStyle: GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: _lightTextPrimaryColor,
      ),
      contentTextStyle: GoogleFonts.inter(
        fontSize: 15,
        height: 1.4,
        color: _lightTextSecondaryColor,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _lightCardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.3),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryColor,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: primaryDarkColor,
      selectionColor: Color(0x5599CF70),
      selectionHandleColor: primaryDarkColor,
    ),
  );

  // Dark theme
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: accentColor,
      error: errorColorDark,
      onPrimary: _lightTextPrimaryColor, // Dark text on primary buttons
      onSecondary: _lightTextPrimaryColor,
      onError: _lightTextPrimaryColor,
      primaryContainer: Color(0xFF2F4A26),
      onPrimaryContainer: accentColor,
      surface: _darkCardColor,
      onSurface: _darkTextPrimaryColor,
      surfaceContainerHighest: Color(0xFF2A2A2A),
      onSurfaceVariant: _darkTextSecondaryColor,
      outline: _darkDividerColor,
      outlineVariant: _darkDividerColor,
    ),
    scaffoldBackgroundColor: _darkBackgroundColor,
    cardColor: _darkCardColor,
    dividerColor: _darkDividerColor,
    dividerTheme: const DividerThemeData(
      color: _darkDividerColor,
      thickness: 1,
      space: 1,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: _darkTextPrimaryColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      iconTheme: const IconThemeData(color: _darkTextPrimaryColor),
      titleTextStyle: GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: _darkTextPrimaryColor,
      ),
    ),
    iconTheme: const IconThemeData(
      color: _darkTextSecondaryColor,
    ),
    textTheme: _buildTextTheme(
      ThemeData.dark().textTheme,
      _darkTextPrimaryColor,
      _darkTextSecondaryColor,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: _lightTextPrimaryColor, // Dark text on light buttons
        backgroundColor: primaryColor,
        elevation: 0,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accentColor,
        side: const BorderSide(color: accentColor, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: GoogleFonts.inter(
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF2A2A2A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _darkDividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _darkDividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: accentColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorColorDark, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: GoogleFonts.inter(
        color: _darkTextSecondaryColor,
        fontSize: 14,
      ),
      labelStyle: GoogleFonts.inter(
        color: _darkTextSecondaryColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.grey[800],
      disabledColor: Colors.grey[700],
      selectedColor: primaryColor.withValues(alpha: 0.3),
      secondarySelectedColor: primaryColor.withValues(alpha: 0.3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      labelStyle: GoogleFonts.inter(
        fontSize: 14,
        color: _darkTextPrimaryColor,
      ),
      secondaryLabelStyle: GoogleFonts.inter(
        fontSize: 14,
        color: accentColor,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    bottomAppBarTheme: const BottomAppBarThemeData(
      color: _darkCardColor,
      elevation: 8,
    ),
    cardTheme: const CardThemeData(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      elevation: 1,
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: _lightTextPrimaryColor, // Dark text on primary color
      elevation: 4,
      shape: CircleBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFFEFEFEF),
      contentTextStyle:
          GoogleFonts.inter(color: const Color(0xFF1A1A1A), fontSize: 14),
      actionTextColor: const Color(0xFF2F6B3C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      insetPadding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF2A2A2A),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titleTextStyle: GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: _darkTextPrimaryColor,
      ),
      contentTextStyle: GoogleFonts.inter(
        fontSize: 15,
        height: 1.4,
        color: _darkTextSecondaryColor,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _darkCardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.3),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryColor,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: primaryColor,
      selectionColor: Color(0x4499CF70),
      selectionHandleColor: primaryColor,
    ),
  );
}

class ThemeNotifier extends ChangeNotifier {
  // Start in system mode so the first frame matches the platform look;
  // the load completes almost instantly and overrides it if the user has
  // previously chosen a theme explicitly.
  ThemeMode _themeMode = ThemeMode.system;
  bool _isDisposed = false;

  ThemeMode get themeMode => _themeMode;

  ThemeNotifier() {
    _loadThemeFromPreferences();
  }

  void toggleTheme() {
    final isDark = _effectiveIsDark;
    _themeMode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    _saveThemeToPreferences();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    _saveThemeToPreferences();
  }

  bool get _effectiveIsDark {
    switch (_themeMode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    }
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  Future<void> _loadThemeFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final isDarkMode = prefs.getBool('isDarkMode');
    if (isDarkMode != null) {
      _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light;
      _notify();
    }
  }

  Future<void> _saveThemeToPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _effectiveIsDark);
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
