import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'app_state.dart';
import 'data_io.dart';
import 'dates.dart';
import 'db.dart';
import 'logic.dart';
import 'pdf_reports.dart';
import 'results_service.dart';
import 'widgets.dart';

enum RKind {
  notices, monthlyCerts, finalCerts, results, gradeSheet, monthlySheet,
  classList, attendance,
}

class RMeta {
  final RKind kind;
  final String title, desc;
  final IconData icon;
  final bool subject, month, semester, date;
  const RMeta(this.kind, this.title, this.desc, this.icon,
      {this.subject = false,
      this.month = false,
      this.semester = false,
      this.date = false});
}

const reportMetas = <RMeta>[
  RMeta(RKind.notices, 'إشعارات درجات (4 طلاب في الصفحة)',
      'إشعار رسمي لولي الأمر بدرجات المادة والفصل المختارين.', Icons.mail_outline,
      subject: true, semester: true),
  RMeta(RKind.monthlyCerts, 'شهادات درجات شهرية (3 في الصفحة)',
      'شهادة شهرية لكل طالب بكل المواد ومكوناتها ونسبة الغياب.',
      Icons.workspace_premium,
      month: true),
  RMeta(RKind.finalCerts, 'شهادات النتيجة (طالب في الصفحة)',
      'شهادة نتيجة كاملة: درجات المواد والمجموع والتقدير والترتيب.',
      Icons.verified_outlined),
  RMeta(RKind.results, 'كشف النتائج مرتباً',
      'ترتيب الطلاب بالمجموع مع التقدير والنتيجة والمواد الراسب فيها.',
      Icons.leaderboard_outlined),
  RMeta(RKind.gradeSheet, 'كشف رصد درجات مادة',
      'المحصلة والاختبار والمجموع لمادة واحدة في فصل دراسي.', Icons.grading,
      subject: true, semester: true),
  RMeta(RKind.monthlySheet, 'كشف الدرجات الشهرية لمادة',
      'مكونات الدرجة الشهرية والمجموع والمحوّلة لمادة وشهر.',
      Icons.calendar_view_month,
      subject: true, month: true),
  RMeta(RKind.classList, 'قائمة أسماء الصف',
      'أسماء الطلاب مع أرقام القيد والجلوس وهاتف ولي الأمر.', Icons.groups_outlined),
  RMeta(RKind.attendance, 'تقرير الحضور الشهري',
      'عدد أيام الحضور والغياب والتأخر والاستئذان ونسبة الحضور.',
      Icons.event_available_outlined,
      date: true),
];

class ReportData {
  final ExportTable table;
  final Future<Uint8List> Function() pdf;
  final int count;
  ReportData(this.table, this.pdf, this.count);
}

Future<String> _subjectName(int? id) async {
  if (id == null) return '';
  final r = await (await Db.get()).query('subjects', where: 'id=?', whereArgs: [id]);
  return r.isEmpty ? '' : r.first['name'] as String;
}

Future<ReportData> buildReport(RKind kind, Scope sc,
    {int semester = 0, DateTime? date, int? onlyStudent}) async {
  final school = await Db.setting('school');
  final year = await Db.setting('year');
  final cls = await Db.className(sc.classId);
  final hijri = AppState.hijri.value;
  final students = (await Db.students(classId: sc.classId, section: sc.section))
      .where((s) => onlyStudent == null || s['id'] == onlyStudent)
      .toList();
  final d = await Db.get();

  switch (kind) {
    case RKind.classList:
      final heads = ['م', 'الاسم', 'رقم القيد', 'رقم الجلوس', 'الجنس', 'الشعبة', 'هاتف ولي الأمر'];
      final rows = <List<String>>[];
      for (var i = 0; i < students.length; i++) {
        final s = students[i];
        rows.add([
          '${i + 1}', '${s['name'] ?? ''}', '${s['reg_no'] ?? ''}',
          '${s['seat_no'] ?? ''}', '${s['gender'] ?? ''}',
          '${s['section'] ?? ''}', '${s['phone'] ?? ''}',
        ]);
      }
      final title = 'قائمة طلاب $cls';
      return ReportData(
          ExportTable(title, heads, rows),
          () => buildTableReport(title, heads, rows, school, year,
              flex: [1, 5, 2, 2, 1.5, 1.5, 3]),
          rows.length);

    case RKind.results:
      final res = await classResults(sc.classId, section: sc.section);
      final heads = ['الترتيب', 'الاسم', 'رقم الجلوس', 'المجموع', 'النسبة', 'التقدير', 'النتيجة', 'المواد الراسب فيها'];
      final rows = [
        for (final r in res)
          [
            '${r.rank ?? '-'}', '${r.student['name']}', '${r.student['seat_no'] ?? '-'}',
            nf(r.result.total), '${r.result.percent.toStringAsFixed(1)}%',
            r.result.rating, r.result.status, r.result.failed.join('، '),
          ]
      ];
      return ReportData(ExportTable('نتائج $cls', heads, rows),
          () => buildResultSheet(cls, rows, school, year), rows.length);

    case RKind.gradeSheet:
    case RKind.notices:
      if (sc.subjectId == null) throw StateError('اختر المادة أولاً');
      final rules = await Rules.load();
      final subject = await _subjectName(sc.subjectId);
      final t1 = semester == 0;
      final wk = t1 ? 't1_work' : 't2_work', ex = t1 ? 't1_exam' : 't2_exam';
      final mw = t1 ? rules.maxW1 : rules.maxW2, me = t1 ? rules.maxE1 : rules.maxE2;
      final semLabel = t1 ? 'الفصل الدراسي الأول' : 'الفصل الدراسي الثاني';
      final rows0 = await Db.gradeRows(sc.classId, sc.section, sc.subjectId!);
      String sum(num? a, num? b) =>
          (a == null && b == null) ? '' : nf((a ?? 0) + (b ?? 0));
      final heads = ['المحصلة (${nf(mw)})', 'الاختبار (${nf(me)})', 'المجموع (${nf(mw + me)})'];
      if (kind == RKind.notices) {
        final data = [
          for (final r in rows0)
            NoticeData('${r['name']}', '${r['reg_no'] ?? ''}', cls,
                '${r['section'] ?? ''}', [
              nf(r[wk] as num?), nf(r[ex] as num?), sum(r[wk] as num?, r[ex] as num?),
            ])
        ];
        final table = ExportTable('إشعارات $subject - $semLabel', ['الاسم', 'رقم القيد', ...heads], [
          for (final n in data) [n.name, n.regNo, ...n.values]
        ]);
        return ReportData(
            table, () => buildNotices(data, school, year, semLabel, subject, heads), data.length);
      }
      final h2 = ['م', 'الاسم', 'رقم القيد', ...heads];
      final rows = <List<String>>[];
      for (var i = 0; i < rows0.length; i++) {
        final r = rows0[i];
        rows.add(['${i + 1}', '${r['name']}', '${r['reg_no'] ?? ''}', nf(r[wk] as num?),
          nf(r[ex] as num?), sum(r[wk] as num?, r[ex] as num?)]);
      }
      final title = 'كشف رصد $subject - $semLabel - $cls';
      return ReportData(ExportTable(title, h2, rows),
          () => buildTableReport(title, h2, rows, school, year, flex: [1, 5, 2, 2, 2, 2]),
          rows.length);

    case RKind.monthlySheet:
      if (sc.subjectId == null) throw StateError('اختر المادة أولاً');
      final cfg = await MonthlyCfg.load();
      final subject = await _subjectName(sc.subjectId);
      final label = monthName(sc.month, hijri);
      final rows0 = await Db.monthlyRows(sc.classId, sc.section, sc.subjectId!, sc.month);
      final heads = [
        'م', 'الاسم', 'رقم القيد',
        for (var i = 0; i < 4; i++) '${cfg.labels[i]} (${nf(cfg.maxes[i])})',
        'المجموع (${nf(cfg.total)})', 'المحوّلة (${nf(cfg.convertTo)})',
      ];
      final rows = <List<String>>[];
      for (var i = 0; i < rows0.length; i++) {
        final r = rows0[i];
        final v = [r['hw'], r['att'], r['oral'], r['written']].map((e) => e as num?).toList();
        final any = v.any((e) => e != null);
        final total = v.fold<double>(0, (a, e) => a + (e ?? 0));
        rows.add(['${i + 1}', '${r['name']}', '${r['reg_no'] ?? ''}',
          for (final e in v) nf(e), any ? nf(total) : '', any ? nf(cfg.convert(total)) : '']);
      }
      final title = 'كشف الدرجات الشهرية - $subject - شهر $label - $cls';
      return ReportData(ExportTable(title, heads, rows),
          () => buildTableReport(title, heads, rows, school, year,
              flex: [1, 5, 2, 2, 2, 2, 2, 2, 2]),
          rows.length);

    case RKind.monthlyCerts:
      final cfg = await MonthlyCfg.load();
      final label = monthName(sc.month, hijri);
      final subjects = await Db.subjectsOf(sc.classId);
      final recorded = await Db.count(
          'SELECT COUNT(DISTINCT date) FROM attendance WHERE student_id IN '
          '(SELECT id FROM students WHERE class_id=?)',
          [sc.classId]);
      final data = <MonthlyCertData>[];
      final flat = <List<String>>[];
      for (final s in students) {
        final sid = s['id'] as int;
        final absent = await Db.count(
            "SELECT COUNT(*) FROM attendance WHERE student_id=? AND status='غائب'",
            [sid]);
        final abs = recorded > 0
            ? 'أيام الغياب: $absent (${(absent / recorded * 100).toStringAsFixed(1)}%)'
            : 'أيام الغياب: $absent';
        final rows = <MonthlyRowData>[];
        for (final sub in subjects) {
          final m = await d.query('monthly',
              where: 'student_id=? AND subject_id=? AND month=?',
              whereArgs: [sid, sub['id'], sc.month]);
          double? n(String k) => m.isEmpty ? null : (m.first[k] as num?)?.toDouble();
          final r = MonthlyRowData(sub['name'] as String, n('hw'), n('att'), n('oral'), n('written'));
          rows.add(r);
          flat.add(['${s['name']}', r.subject, nf(r.hw), nf(r.att), nf(r.oral),
            nf(r.written), r.has ? nf(r.total) : '', r.has ? nf(cfg.convert(r.total)) : '']);
        }
        data.add(MonthlyCertData('${s['name']}', s['seat_no'] as int?, cls, abs, rows));
      }
      final heads = ['الاسم', 'المادة', ...cfg.labels, 'المجموع', 'المحوّلة'];
      return ReportData(
          ExportTable('شهادات شهر $label - $cls', heads, flat),
          () => buildMonthlyCerts(data, school, year, label, cfg.labels, cfg.maxes, cfg.convertTo),
          data.length);

    case RKind.finalCerts:
      final rules = await Rules.load();
      final res = await classResults(sc.classId, section: sc.section);
      final data = <FinalCertData>[];
      final flat = <List<String>>[];
      for (final r in res) {
        if (onlyStudent != null && r.student['id'] != onlyStudent) continue;
        final tr = await transcript(r.student['id'] as int, sc.classId);
        final rows = [
          for (final t in tr) [t.subject, nf(t.t1), nf(t.t2), (t.t1 == null && t.t2 == null) ? '' : nf(t.total)]
        ];
        for (final row in rows) {
          flat.add(['${r.student['name']}', ...row]);
        }
        data.add(FinalCertData('${r.student['name']}', r.student['seat_no'] as int?, cls, rows, [
          'المجموع: ${nf(r.result.total)} / ${nf(r.result.max)}',
          'النسبة: ${r.result.percent.toStringAsFixed(1)}%',
          'التقدير: ${r.result.rating}',
          'النتيجة: ${r.result.status}',
          if (r.rank != null) 'الترتيب: ${r.rank}',
        ], r.result.failed.join('، ')));
      }
      final maxes = [rules.maxW1 + rules.maxE1, rules.maxW2 + rules.maxE2, rules.subjectMax];
      return ReportData(
          ExportTable('شهادات النتيجة - $cls', ['الاسم', 'المادة', 'الفصل الأول', 'الفصل الثاني', 'المجموع'], flat),
          () => buildFinalCerts(data, school, year, maxes),
          data.length);

    case RKind.attendance:
      final day = date ?? DateTime.now();
      final prefix = '${day.year}-${two(day.month)}-';
      final heads = ['م', 'الاسم', 'حاضر', 'غائب', 'متأخر', 'مستأذن', 'أيام مسجلة', 'نسبة الحضور'];
      final rows = <List<String>>[];
      for (var i = 0; i < students.length; i++) {
        final s = students[i];
        final res = await d.rawQuery(
            'SELECT status, COUNT(*) c FROM attendance WHERE student_id=? AND date LIKE ? GROUP BY status',
            [s['id'], '$prefix%']);
        int c(String st) {
          for (final e in res) {
            if (e['status'] == st) return e['c'] as int;
          }
          return 0;
        }
        final p = c('حاضر'), a = c('غائب'), l = c('متأخر'), x = c('مستأذن');
        final tot = p + a + l + x;
        rows.add(['${i + 1}', '${s['name']}', '$p', '$a', '$l', '$x', '$tot',
          tot == 0 ? '-' : '${((p + l) / tot * 100).toStringAsFixed(0)}%']);
      }
      final title = 'تقرير الحضور - ${gregMonths[day.month - 1]} ${day.year} - $cls';
      return ReportData(ExportTable(title, heads, rows),
          () => buildTableReport(title, heads, rows, school, year,
              flex: [1, 5, 1.5, 1.5, 1.5, 1.5, 2, 2]),
          rows.length);
  }
}
