import 'package:flutter/material.dart';
import '../data_io.dart';
import '../dates.dart';
import '../db.dart';
import '../license.dart';
import '../logic.dart';
import '../report_engine.dart';
import '../widgets.dart';
import 'report_picker.dart';

class ExcelCenter extends StatefulWidget {
  final int initialTab; // 0 تصدير، 1 استيراد، 2 نماذج
  const ExcelCenter({super.key, this.initialTab = 0});
  @override
  State<ExcelCenter> createState() => _ExcelCenterState();
}

class _ExcelCenterState extends State<ExcelCenter> {
  late int tab = widget.initialTab;
  ReportSel? sel;
  List<int>? cols;
  RKind? colsKind;
  bool withTitle = false, busy = false;
  int importTarget = 0;
  Scope? impScope, tplScope;
  String log = '';

  // ---------------- تصدير ----------------
  Future<void> _customize() async {
    final s = sel;
    if (s?.scope == null) return;
    try {
      final data = await buildReport(s!.meta.kind, s.scope!,
          semester: s.semester, date: s.date);
      final heads = data.table.heads;
      final chosen = {
        for (var i = 0; i < heads.length; i++)
          if (cols == null || colsKind != s.meta.kind || cols!.contains(i)) i
      };
      var title = withTitle;
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
            title: const Text('تخصيص الترويسة والأعمدة'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(shrinkWrap: true, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تضمين عنوان التقرير واسم المدرسة'),
                  value: title,
                  onChanged: (v) => set(() => title = v),
                ),
                const Divider(),
                for (var i = 0; i < heads.length; i++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(heads[i]),
                    value: chosen.contains(i),
                    onChanged: (v) => set(() => v == true ? chosen.add(i) : chosen.remove(i)),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
            ],
          ),
        ),
      );
      if (ok == true && chosen.isNotEmpty) {
        setState(() {
          cols = chosen.toList()..sort();
          colsKind = s.meta.kind;
          withTitle = title;
        });
      }
    } catch (e) {
      if (mounted) toast(context, 'تعذر التحميل: $e');
    }
  }

  Future<void> _export(bool xlsx) async {
    final s = sel;
    if (s?.scope == null) return;
    setState(() => busy = true);
    try {
      final data = await buildReport(s!.meta.kind, s.scope!,
          semester: s.semester, date: s.date);
      var t = data.table;
      if (cols != null && colsKind == s.meta.kind) t = t.pick(cols!);
      await exportTable(t,
          xlsx: xlsx,
          withTitle: withTitle,
          school: await Db.setting('school'),
          year: await Db.setting('year'));
    } catch (e) {
      if (mounted) toast(context, 'تعذر التصدير: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // ---------------- استيراد ----------------
  Future<void> _import() async {
    try {
      final f = await pickAnyFile();
      if (f == null) return;
      final rows = parseTableFile(f);
      final msg = importTarget == 0
          ? await _importStudents(rows)
          : await _importGrades(rows);
      if (mounted) setState(() => log = msg);
    } catch (e) {
      if (mounted) setState(() => log = 'تعذر قراءة الملف: $e');
    }
  }

  int _idx(List<String> head, List<String> keys) {
    for (var i = 0; i < head.length; i++) {
      for (final k in keys) {
        if (head[i].contains(k)) return i;
      }
    }
    return -1;
  }

  String _cell(List<String> r, int i) =>
      (i >= 0 && i < r.length) ? r[i].trim() : '';

  Future<String> _importStudents(List<List<String>> rows) async {
    if (rows.isEmpty) return 'الملف فارغ';
    final classes = await Db.classes();
    final head = rows.first.map((e) => e.trim()).toList();
    final iName = _idx(head, ['الاسم', 'اسم']);
    final hasHeader = iName >= 0;
    final iGender = _idx(head, ['الجنس', 'جنس']);
    final iClass = _idx(head, ['الصف']);
    final iSec = _idx(head, ['الشعبة', 'شعبة']);
    final iPhone = _idx(head, ['هاتف', 'جوال']);
    final iNotes = _idx(head, ['ملاحظ']);
    final iReg = _idx(head, ['القيد', 'قيد', 'السجل']);
    var n = 0, skipped = 0;
    for (var k = hasHeader ? 1 : 0; k < rows.length; k++) {
      final r = rows[k];
      final name = _cell(r, hasHeader ? iName : 0);
      if (name.isEmpty) {
        skipped++;
        continue;
      }
      var cid = impScope?.classId ?? 1;
      final cText = _cell(r, iClass);
      if (cText.isNotEmpty) {
        for (final c in classes) {
          final cn = '${c['name']}';
          if (cn == cText || cn.contains(cText) || cText.contains(cn)) {
            cid = c['id'] as int;
            break;
          }
        }
      }
      final g = _cell(r, iGender);
      final female = g.contains('أنث') || g.contains('انث') || g.toLowerCase().startsWith('f');
      final reg = int.tryParse(_cell(r, iReg));
      try {
        await Db.addStudent({
        'name': name,
        'gender': female ? 'أنثى' : 'ذكر',
        'class_id': cid,
        'section': _cell(r, iSec).isEmpty ? (impScope?.section ?? 'أ') : _cell(r, iSec),
        'phone': _cell(r, iPhone),
        'notes': _cell(r, iNotes),
        'status': 'مستجد',
        'reg_date': isoDate(DateTime.now()),
        if (reg != null) 'reg_no': reg,
        });
        n++;
      } on LicenseLimitException catch (e) {
        return 'توقف الاستيراد بعد $n طالب لأنك بلغت الحد المسموح (${e.limit}). '
            'تواصل مع المطور لتفعيل التطبيق ثم أعد استيراد الباقي.';
      }
    }
    return 'تم استيراد $n طالب' + (skipped > 0 ? ' (تخطي $skipped صفاً فارغاً)' : '');
  }

  Future<String> _importGrades(List<List<String>> rows) async {
    final sc = impScope;
    if (sc == null || sc.subjectId == null) return 'اختر الصف والمادة أولاً';
    if (rows.isEmpty) return 'الملف فارغ';
    final rules = await Rules.load();
    final head = rows.first.map((e) => e.trim()).toList();
    final iReg = _idx(head, ['القيد', 'قيد']);
    final iName = _idx(head, ['الاسم', 'اسم']);
    final cols = {
      't1_work': (_idx(head, ['المحصلة 1', 'محصلة 1', 'المحصلة1']), rules.maxW1),
      't1_exam': (_idx(head, ['اختبار 1', 'الاختبار 1', 'اختبار1']), rules.maxE1),
      't2_work': (_idx(head, ['المحصلة 2', 'محصلة 2', 'المحصلة2']), rules.maxW2),
      't2_exam': (_idx(head, ['اختبار 2', 'الاختبار 2', 'اختبار2']), rules.maxE2),
    };
    if (iReg < 0 && iName < 0) return 'لم أجد عمود رقم القيد أو الاسم في الملف';
    final students = await Db.students(classId: sc.classId, section: sc.section);
    final byReg = {for (final s in students) '${s['reg_no']}': s['id'] as int};
    final byName = {for (final s in students) '${s['name']}'.trim(): s['id'] as int};
    var updated = 0, unmatched = 0, bad = 0;
    for (var k = 1; k < rows.length; k++) {
      final r = rows[k];
      final sid = byReg[_cell(r, iReg)] ?? byName[_cell(r, iName)];
      if (sid == null) {
        unmatched++;
        continue;
      }
      var any = false;
      for (final e in cols.entries) {
        final i = e.value.$1;
        final t = _cell(r, i);
        if (i < 0 || t.isEmpty) continue;
        final v = double.tryParse(t);
        if (v == null || v < 0 || v > e.value.$2) {
          bad++;
          continue;
        }
        await Db.saveGrade(sid, sc.subjectId!, e.key, v);
        any = true;
      }
      if (any) updated++;
    }
    return 'تم تحديث درجات $updated طالب'
        '${unmatched > 0 ? ' • لم يُطابَق $unmatched' : ''}'
        '${bad > 0 ? ' • قيم غير صالحة تم تجاهلها: $bad' : ''}';
  }

  // ---------------- نماذج ----------------
  Future<void> _studentTemplate(bool xlsx) => exportTable(
      ExportTable('قالب_الطلاب', [
        'الاسم', 'رقم القيد', 'الصف', 'الشعبة', 'الجنس', 'هاتف ولي الأمر', 'ملاحظات'
      ], [
        ['مثال: أحمد محمد علي حسن', '', 'الرابع أساسي', 'أ', 'ذكر', '', ''],
      ]),
      xlsx: xlsx);

  Future<void> _gradeTemplate() async {
    final sc = tplScope;
    if (sc == null || sc.subjectId == null) return toast(context, 'اختر الصف والمادة');
    final rows0 = await Db.gradeRows(sc.classId, sc.section, sc.subjectId!);
    final rows = [
      for (final r in rows0)
        [
          '${r['reg_no'] ?? ''}', '${r['name']}', nf(r['t1_work'] as num?),
          nf(r['t1_exam'] as num?), nf(r['t2_work'] as num?), nf(r['t2_exam'] as num?),
        ]
    ];
    await exportTable(
        ExportTable('قالب_رصد_${await Db.className(sc.classId)}',
            ['رقم القيد', 'الاسم', 'المحصلة 1', 'اختبار 1', 'المحصلة 2', 'اختبار 2'], rows),
        xlsx: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('مركز إكسل و CSV')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('تصدير'), icon: Icon(Icons.download)),
            ButtonSegment(value: 1, label: Text('استيراد'), icon: Icon(Icons.upload)),
            ButtonSegment(value: 2, label: Text('النماذج'), icon: Icon(Icons.table_chart)),
          ],
          selected: {tab},
          onSelectionChanged: (s) => setState(() => tab = s.first),
        ),
        const SizedBox(height: 14),
        if (tab == 0) ...[
          Text('تصدير التقارير والجداول المعتمدة',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('اختر نوع التقرير والصف للتصدير إلى Excel أو CSV.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          ReportPicker(onChanged: (s) => sel = s),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: _customize,
              icon: const Icon(Icons.tune),
              label: Text(cols == null
                  ? 'تخصيص الترويسة والأعمدة'
                  : 'تخصيص الترويسة والأعمدة (${cols!.length} عمود)')),
          const SizedBox(height: 8),
          if (busy) const LinearProgressIndicator(),
          FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: busy ? null : () => _export(true),
              icon: const Icon(Icons.table_chart),
              label: const Text('تصدير كملف Excel (.xlsx)')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: busy ? null : () => _export(false),
              icon: const Icon(Icons.description_outlined),
              label: const Text('تصدير كملف CSV (.csv) بترميز UTF-8')),
        ],
        if (tab == 1) ...[
          Text('استيراد من Excel أو CSV', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('يُقبل xlsx وcsv. حمّل النموذج من تبويب «النماذج» لضمان ترتيب الأعمدة.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          Pick<int>(
            label: 'ماذا تريد أن تستورد؟',
            value: importTarget,
            items: const [
              DropdownMenuItem(value: 0, child: Text('قائمة طلاب')),
              DropdownMenuItem(value: 1, child: Text('درجات مادة (فصلية)')),
            ],
            onChanged: (v) => setState(() => importTarget = v!),
          ),
          const SizedBox(height: 10),
          ScopeBar(
            key: ValueKey('imp$importTarget'),
            subject: importTarget == 1,
            onChanged: (s) => impScope = s,
          ),
          const SizedBox(height: 6),
          Text(
              importTarget == 0
                  ? 'سيُضاف الطلاب إلى الصف المختار إن لم يحدد الملف عمود «الصف».'
                  : 'تُطابَق الصفوف برقم القيد أو بالاسم، ويُرفض أي رقم يتجاوز السقف.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          FilledButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.upload_file),
              label: const Text('اختيار ملف وبدء الاستيراد')),
          if (log.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: cs.primaryContainer.withOpacity(.4),
              child: Padding(padding: const EdgeInsets.all(14), child: Text(log)),
            ),
          ],
        ],
        if (tab == 2) ...[
          Text('نماذج جاهزة', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('قالب الطلاب', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                        onPressed: () => _studentTemplate(true),
                        icon: const Icon(Icons.table_chart),
                        label: const Text('Excel')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => _studentTemplate(false),
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('CSV')),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('قالب رصد مادة بأسماء الطلاب',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ScopeBar(
                    key: const ValueKey('tpl'),
                    subject: true,
                    onChanged: (s) => tplScope = s),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                    onPressed: _gradeTemplate,
                    icon: const Icon(Icons.download),
                    label: const Text('تنزيل القالب (Excel)')),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
