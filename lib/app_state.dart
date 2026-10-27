import 'package:flutter/material.dart';
import 'db.dart';

/// حالة عامة خفيفة: المظهر والتقويم وإشعار تغيّر البيانات.
class AppState {
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);
  static final hijri = ValueNotifier<bool>(true);
  /// 'system' = خط النظام، 'cairo' = خط Cairo المضمّن.
  static final font = ValueNotifier<String>('system');
  static int hijriOffset = 0;

  static Future<void> load() async {
    final t = await Db.setting('theme');
    themeMode.value = t == 'light'
        ? ThemeMode.light
        : t == 'system'
            ? ThemeMode.system
            : ThemeMode.dark;
    font.value = (await Db.setting('font')) == 'cairo' ? 'cairo' : 'system';
    hijri.value = (await Db.setting('calendar')) != 'gregorian';
    hijriOffset = int.tryParse(await Db.setting('hijri_offset')) ?? 0;
  }
}
