import 'package:flutter/material.dart';
import 'db.dart';

/// حالة عامة خفيفة: المظهر والتقويم وإشعار تغيّر البيانات.
class AppState {
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);
  static final hijri = ValueNotifier<bool>(true);
  static int hijriOffset = 0;

  static Future<void> load() async {
    final t = await Db.setting('theme');
    themeMode.value = t == 'light'
        ? ThemeMode.light
        : t == 'system'
            ? ThemeMode.system
            : ThemeMode.dark;
    hijri.value = (await Db.setting('calendar')) != 'gregorian';
    hijriOffset = int.tryParse(await Db.setting('hijri_offset')) ?? 0;
  }
}
