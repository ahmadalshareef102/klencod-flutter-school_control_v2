import 'dart:convert';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data_io.dart';
import '../dates.dart';
import '../db.dart';
import '../widgets.dart';
import 'excel_center.dart';
import 'rules_screen.dart';
import 'subjects_screen.dart';

Future<void> backupNow(BuildContext context) async {
  try {
    final json = jsonEncode(await Db.exportAll());
    await shareBytes('control_backup_${isoDate(DateTime.now())}.json',
        utf8.encode(json),
        mime: 'application/json');
  } catch (e) {
    if (context.mounted) toast(context, 'تعذر إنشاء النسخة الاحتياطية: $e');
  }
}

Future<void> restoreBackup(BuildContext context) async {
  try {
    final f = await pickAnyFile();
    if (f == null) return;
    final data = jsonDecode(utf8.decode(f.bytes)) as Map<String, dynamic>;
    if (!context.mounted) return;
    final ok = await confirmDialog(
        context, 'ستُستبدل كل البيانات الحالية بمحتوى النسخة الاحتياطية. متابعة؟',
        ok: 'استعادة', danger: true);
    if (!ok) return;
    await Db.importAll(data);
    await AppState.load();
    if (context.mounted) toast(context, 'تمت استعادة النسخة الاحتياطية');
  } catch (e) {
    if (context.mounted) toast(context, 'ملف غير صالح: $e');
  }
}

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  String teacher = '', school = '', year = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    teacher = await Db.setting('teacher');
    school = await Db.setting('school');
    year = await Db.setting('year');
    if (mounted) setState(() {});
  }

  Future<void> _go(Widget w) async {
    await open(context, w);
    _load();
  }

  Future<void> _editProfile() async {
    final t = TextEditingController(text: teacher);
    final s = TextEditingController(text: school);
    final y = TextEditingController(text: year);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بيانات المعلم والمدرسة'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: t, decoration: const InputDecoration(labelText: 'اسم المعلم / رئيس الكنترول')),
            const SizedBox(height: 8),
            TextField(controller: s, decoration: const InputDecoration(labelText: 'اسم المدرسة')),
            const SizedBox(height: 8),
            TextField(controller: y, decoration: const InputDecoration(labelText: 'العام الدراسي')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) {
      await Db.setSetting('teacher', t.text.trim());
      await Db.setSetting('school', s.text.trim());
      await Db.setSetting('year', y.text.trim());
      _load();
    }
  }

  Future<void> _theme() async {
    final v = await showOptions<String>(context, 'المظهر', const [
      Opt(Icons.dark_mode, 'داكن', 'dark'),
      Opt(Icons.light_mode, 'فاتح', 'light'),
      Opt(Icons.phone_android, 'حسب النظام', 'system'),
    ]);
    if (v == null) return;
    AppState.themeMode.value = v == 'light'
        ? ThemeMode.light
        : v == 'system'
            ? ThemeMode.system
            : ThemeMode.dark;
    await Db.setSetting('theme', v);
  }

  Future<void> _calendar() async {
    final v = await showOptions<String>(context, 'التقويم', const [
      Opt(Icons.mosque_outlined, 'هجري', 'hijri'),
      Opt(Icons.calendar_today, 'ميلادي', 'gregorian'),
      Opt(Icons.tune, 'ضبط إزاحة التاريخ الهجري', 'offset',
          'لتصحيح فرق يوم عن رؤية الهلال'),
    ]);
    if (v == null) return;
    if (v == 'offset') {
      final o = await showOptions<int>(context, 'إزاحة التاريخ الهجري', [
        for (final i in [-2, -1, 0, 1, 2])
          Opt(Icons.swap_horiz, i == 0 ? 'بدون إزاحة' : (i > 0 ? '+$i يوم' : '$i يوم'), i),
      ]);
      if (o != null) {
        AppState.hijriOffset = o;
        await Db.setSetting('hijri_offset', '$o');
      }
    } else {
      AppState.hijri.value = v == 'hijri';
      await Db.setSetting('calendar', v);
    }
    if (mounted) setState(() {});
  }

  Future<void> _backupMenu() async {
    final v = await showOptions<String>(context, 'النسخ الاحتياطي', const [
      Opt(Icons.cloud_upload_outlined, 'إنشاء نسخة احتياطية ومشاركتها', 'backup',
          'ملف JSON تحفظه في الملفات أو تشاركه'),
      Opt(Icons.cloud_download_outlined, 'استعادة من نسخة احتياطية', 'restore'),
    ]);
    if (v == 'backup') await backupNow(context);
    if (v == 'restore') {
      await restoreBackup(context);
      _load();
    }
  }

  Future<void> _wipe() async {
    if (await confirmDialog(context,
        'حذف كل الطلاب والدرجات والحضور؟ (تبقى الإعدادات والمواد). يُنصح بنسخة احتياطية أولاً.',
        ok: 'حذف الكل', danger: true)) {
      await Db.wipeData();
      if (mounted) toast(context, 'تم حذف البيانات');
    }
  }

  Widget _tile(IconData i, String t, String s, VoidCallback f, {Color? color}) => Card(
        child: ListTile(
          leading: Icon(i, color: color),
          title: Text(t),
          subtitle: Text(s),
          trailing: const Icon(Icons.chevron_left),
          onTap: f,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      const PageHeader('الإعدادات'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                CircleAvatar(
                    radius: 28,
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.person, color: cs.onPrimaryContainer)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(teacher.isEmpty ? 'أضف اسمك' : teacher,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${school.isEmpty ? 'اسم المدرسة' : school} | $year',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
                FilledButton.tonalIcon(
                    onPressed: _editProfile,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('تعديل')),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          _tile(Icons.menu_book, 'المواد الدراسية', 'إضافة وتعديل وحذف ونسخ المواد لكل صف',
              () => _go(const SubjectsScreen()), color: Colors.blue),
          const SizedBox(height: 8),
          _tile(Icons.rule, 'قواعد الدرجات والنتائج',
              'السقوف ونسبة النجاح والتقديرات والدرجات الشهرية واللجان',
              () => _go(const RulesScreen()), color: Colors.orange),
          const SizedBox(height: 8),
          _tile(Icons.brightness_6, 'المظهر', 'داكن أو فاتح أو حسب النظام', _theme,
              color: Colors.purple),
          const SizedBox(height: 8),
          _tile(Icons.calendar_month, 'التقويم',
              AppState.hijri.value ? 'هجري (إزاحة ${AppState.hijriOffset})' : 'ميلادي',
              _calendar, color: Colors.teal),
          const SizedBox(height: 8),
          _tile(Icons.table_chart, 'مركز Excel و CSV', 'استيراد وتصدير ونماذج',
              () => _go(const ExcelCenter()), color: Colors.green),
          const SizedBox(height: 8),
          _tile(Icons.cloud_sync_outlined, 'نسخ احتياطي واستعادة',
              'احفظ بياناتك قبل تغيير الجهاز', _backupMenu, color: Colors.cyan),
          const SizedBox(height: 8),
          _tile(Icons.delete_sweep_outlined, 'حذف كل البيانات', 'الطلاب والدرجات والحضور',
              _wipe, color: Colors.red),
          const SizedBox(height: 16),
          Text('الكنترول المدرسي • الإصدار 2.0.0',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    ]);
  }
}
