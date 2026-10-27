import 'package:flutter/material.dart';
import 'app_state.dart';
import 'shell.dart';

const navy = Color(0xFF102A43);
const blue = Color(0xFF1976D2);
const pageBg = Color(0xFFF5F7FB);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.load();
  runApp(const ControlApp());
}

ThemeData buildTheme(Brightness b, String font) {
  final family = font == 'cairo' ? 'Cairo' : null;
  final dark = b == Brightness.dark;
  final cs = ColorScheme.fromSeed(seedColor: blue, brightness: b);
  final cardColor = dark ? const Color(0xFF162033) : Colors.white;
  final border = dark ? const Color(0xFF24324A) : const Color(0xFFE3EAF2);
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    fontFamily: family,
    scaffoldBackgroundColor: dark ? const Color(0xFF0B1220) : pageBg,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF0B1220) : pageBg,
      foregroundColor: dark ? Colors.white : navy,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1E2A40) : const Color(0xFFEFF3F9),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF111A2C) : Colors.white,
      labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: family, fontSize: 11, color: cs.onSurface)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF162033) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF162033) : Colors.white,
    ),
  );
}

class ControlApp extends StatelessWidget {
  const ControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppState.font,
      builder: (_, font, __) => ValueListenableBuilder<ThemeMode>(
        valueListenable: AppState.themeMode,
        builder: (_, mode, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'الكنترول المدرسي',
          themeMode: mode,
          theme: buildTheme(Brightness.light, font),
          darkTheme: buildTheme(Brightness.dark, font),
          builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl, child: child ?? const SizedBox()),
          home: const Shell(),
        ),
      ),
    );
  }
}