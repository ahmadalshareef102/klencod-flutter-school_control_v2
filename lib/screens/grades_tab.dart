import 'package:flutter/material.dart';
import '../app_state.dart';
import '../data_io.dart';
import '../dates.dart';
import '../db.dart';
import '../logic.dart';
import '../pdf_reports.dart';
import '../report_engine.dart';
import '../widgets.dart';

class GradesTab extends StatefulWidget {
  const GradesTab({super.key});
  @override
  State<GradesTab> createState() => _GradesTabState();
}

class _GradesTabState extends State<GradesTab> {
  bool monthly = false;
  int term = 0; // 0 الأول، 1 الثاني، 2 الكل
  Scope? scope;
  Rules? rules;
  MonthlyCfg? cfg;
  List<DbRow> rows = [];

  Future<void> _load() async {
    final sc = scope;
    rules = await Rules.load();
    cfg = await MonthlyCfg.load();
    if (sc == null || sc.subjectId == null) {
      if (mounted) setState(() => rows = []);
      return;
    }
    final raw = monthly
        ? await Db.monthlyRows(sc.classId, sc.section, sc.subjectId!, sc.month)
        : await Db.gradeRows(sc.classId, sc.section, sc.subjectId!);
    rows = [for (final e in raw) Map<String, Object?>.from(e)];
    if (mounted) setState(() {});
  }

  List<(String, String, double)> get fields {
    final r = rules, c = cfg;
    if (r == null || c == null) return [];
    if (monthly) {
      return [
        ('hw', c.labels[0], c.hw), ('att', c.labels[1], c.att),
        ('oral', c.labels[2], c.oral), ('written', c.labels[3], c.written),
      ];
    }
    final t1 = [('t1_work', 'المحصلة', r.maxW1), ('t1_exam', 'الاختبار', r.maxE1)];
    final t2 = [('t2_work', 'المحصلة', r.maxW2), ('t2_exam', 'الاختبار', r.maxE2)];
    if (term == 0) return t1;
    if (term == 1) return t2;
    return [
      ('t1_work', 'محصلة 1', r.maxW1), ('t1_exam', 'اختبار 1', r.maxE1),
      ('t2_work', 'محصلة 2', r.maxW2), ('t2_exam', 'اختبار 2', r.maxE2),
    ];
  }

  double _sum(DbRow r) => fields.fold<double>(
      0, (a, f) => a + ((r[f.$1] as num?)?.toDouble() ?? 0));
  double get _maxSum => fields.fold<double>(0, (a, f) => a + f.$3);

  Future<void> _menu() async {
    final v = await showOptions<String>(
        context,
        monthly ? 'خيارات الرصد الشهري' : 'خيارات الرصد الفصلي',
        [
          const Opt(Icons.print, 'طباعة كشف الرصد (PDF)', 'print'),
          const Opt(Icons.ios_share, 'مشاركة PDF', 'share'),
          const Opt(Icons.table_chart, 'تصدير Excel (xlsx)', 'xlsx'),
          const Opt(Icons.description_outlined, 'تصدير CSV', 'csv'),
          if (!monthly)
            const Opt(Icons.swap_vert, 'ترحيل الشهري إلى المحصلة', 'transfer',
                'متوسط الدرجات الشهرية المحوّلة'),
          const Opt(Icons.cleaning_services_outlined, 'تصفير الدرجات المعروضة', 'reset'),
        ]);
    if (v == null || !mounted) return;
    final sc = scope;
    if (sc == null || sc.subjectId == null) return toast(context, 'اختر المادة أولاً');
    try {
      switch (v) {
        case 'print':
        case 'share':
        case 'xlsx':
        case 'csv':
          final data = await buildReport(
              monthly ? RKind.monthlySheet : RKind.gradeSheet, sc,
              semester: term == 1 ? 1 : 0);
          if (v == 'print') await printPdf(await data.pdf(), data.table.title);
          if (v == 'share') {
            await printPdf(await data.pdf(), data.table.title, share: true);
          }
          if (v == 'xlsx') await exportTable(data.table, xlsx: true);
          if (v == 'csv') await exportTable(data.table, xlsx: false);
        case 'transfer':
          await _transfer();
        case 'reset':
          await _reset();
      }
    } catch (e) {
      if (mounted) toast(context, 'تعذر التنفيذ: $e');
    }
  }

  Future<void> _reset() async {
    final sc = scope!;
    if (!await confirmDialog(context, 'تصفير الدرجات المعروضة للصف والمادة المحددين؟',
        ok: 'تصفير', danger: true)) {
      return;
    }
    final d = await Db.get();
    final sec = sc.section == null ? '' : ' AND section=?';
    final args = <Object?>[sc.subjectId, sc.classId, if (sc.section != null) sc.section];
    if (monthly) {
      await d.rawDelete(
          'DELETE FROM monthly WHERE subject_id=? AND month=${sc.month} AND student_id IN '
          '(SELECT id FROM students WHERE class_id=?$sec)',
          args);
    } else {
      await d.rawDelete(
          'DELETE FROM grades WHERE subject_id=? AND student_id IN '
          '(SELECT id FROM students WHERE class_id=?$sec)',
          args);
    }
    _load();
  }

  Future<void> _transfer() async {
    final sc = scope!;
    var from = 1, to = 5, target = 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('ترحيل الشهري إلى المحصلة'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Pick<int>(
              label: 'من شهر',
              value: from,
              items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(monthName(m, AppState.hijri.value)))],
              onChanged: (v) => set(() => from = v!),
            ),
            const SizedBox(height: 8),
            Pick<int>(
              label: 'إلى شهر',
              value: to,
              items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(monthName(m, AppState.hijri.value)))],
              onChanged: (v) => set(() => to = v!),
            ),
            const SizedBox(height: 8),
            Pick<int>(
              label: 'الهدف',
              value: target,
              items: const [
                DropdownMenuItem(value: 0, child: Text('المحصلة - الفصل الأول')),
                DropdownMenuItem(value: 1, child: Text('المحصلة - الفصل الثاني')),
              ],
              onChanged: (v) => set(() => target = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ترحيل')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final c = cfg!, r = rules!;
    final d = await Db.get();
    final students = await Db.students(classId: sc.classId, section: sc.section);
    var n = 0;
    for (final s in students) {
      final ms = await d.query('monthly',
          where: 'student_id=? AND subject_id=? AND month BETWEEN ? AND ?',
          whereArgs: [s['id'], sc.subjectId, from, to]);
      final vals = <double>[];
      for (final m in ms) {
        final v = [m['hw'], m['att'], m['oral'], m['written']].map((e) => e as num?).toList();
        if (v.any((e) => e != null)) {
          vals.add(c.convert(v.fold<double>(0, (a, e) => a + (e ?? 0))));
        }
      }
      if (vals.isEmpty) continue;
      final avg = vals.reduce((a, b) => a + b) / vals.length;
      final max = target == 0 ? r.maxW1 : r.maxW2;
      final scaled = double.parse((avg / c.convertTo * max).toStringAsFixed(1));
      await Db.saveGrade(s['id'] as int, sc.subjectId!, target == 0 ? 't1_work' : 't2_work', scaled);
      n++;
    }
    if (mounted) toast(context, 'تم ترحيل متوسط الشهري لـ $n طالب');
  }

  void _onChange(DbRow r, (String, String, double) f, String t) {
    final sc = scope!;
    double? v;
    if (t.trim().isNotEmpty) {
      v = double.tryParse(t.trim());
      if (v == null || v < 0 || v > f.$3) {
        toast(context, 'الدرجة يجب أن تكون بين 0 و ${nf(f.$3)}');
        return;
      }
    }
    setState(() => r[f.$1] = v);
    if (monthly) {
      Db.saveMonthly(r['id'] as int, sc.subjectId!, sc.month, f.$1, v);
    } else {
      Db.saveGrade(r['id'] as int, sc.subjectId!, f.$1, v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fs = fields;
    final c = cfg;
    return Column(children: [
      PageHeader('رصد درجات الطلاب',
          subtitle: monthly
              ? 'الرصد الشهري (${c == null ? '' : '${nf(c.total)} ← ${nf(c.convertTo)}'})'
              : 'الرصد الفصلي',
          trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: _menu)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('فصلي'), icon: Icon(Icons.school_outlined)),
              ButtonSegment(value: true, label: Text('شهري'), icon: Icon(Icons.calendar_month)),
            ],
            selected: {monthly},
            onSelectionChanged: (s) {
              monthly = s.first;
              _load();
            },
          ),
          if (!monthly) ...[
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('الفصل الأول')),
                ButtonSegment(value: 1, label: Text('الفصل الثاني')),
                ButtonSegment(value: 2, label: Text('الكل')),
              ],
              selected: {term},
              onSelectionChanged: (s) => setState(() => term = s.first),
            ),
          ],
          const SizedBox(height: 10),
          ScopeBar(
            key: ValueKey(monthly),
            subject: true,
            month: monthly,
            onChanged: (s) {
              scope = s;
              _load();
            },
          ),
          if (monthly && c != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${c.labels.join(' + ')} = ${nf(c.total)} تتحول إلى ${nf(c.convertTo)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.primary),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: rows.isEmpty
            ? const Center(child: Text('لا يوجد طلاب في هذا الاختيار'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final sum = _sum(r);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Chip(
                              label: Text('${r['reg_no'] ?? ''}'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: cs.primaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text('${r['name']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold))),
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(monthly && c != null
                                ? 'المحوّلة: ${nf(c.convert(sum))}/${nf(c.convertTo)}'
                                : 'المجموع: ${nf(sum)}/${nf(_maxSum)}'),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          for (final f in fs)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 3),
                                child: TextFormField(
                                  key: ValueKey(
                                      '${r['id']}-${f.$1}-${scope?.subjectId}-${scope?.month}-$monthly-$term'),
                                  initialValue: nf(r[f.$1] as num?),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                      labelText: '${f.$2} (${nf(f.$3)})',
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 10)),
                                  onChanged: (t) => _onChange(r, f, t),
                                ),
                              ),
                            ),
                        ]),
                      ]),
                    ),
                  );
                },
              ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(.4),
            border: Border(top: BorderSide(color: cs.outlineVariant))),
        child: Row(children: [
          Expanded(
              child: Text('${rows.length} طالب • تُحفظ الدرجات تلقائياً عند الكتابة',
                  style: Theme.of(context).textTheme.bodySmall)),
          FilledButton.icon(
              onPressed: () => toast(context, 'تم حفظ جميع الدرجات'),
              icon: const Icon(Icons.check),
              label: const Text('حفظ')),
        ]),
      ),
    ]);
  }
}
