import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'app_state.dart';
import 'arabic_text.dart';
import 'cert.dart';
import 'data_io.dart';
import 'dates.dart';
import 'db.dart';
import 'logic.dart';
import 'pdf_reports.dart';
import 'results_service.dart';
import 'widgets.dart';

enum RKind {
  semesterCerts, notices, monthlySheet, yearWork, attendance, monthlyCerts, studentSemester,
  finalCerts, incomplete, sectionFull, noticesAll, gradeSheet, results,
  classList,
}

class RMeta {
  final RKind kind;
  final String title, desc;
  final IconData icon;
  final bool subject, month, semester, date, both;
  const RMeta(this.kind, this.title, this.desc, this.icon,
      {this.subject = false,
      this.month = false,
      this.semester = false,
      this.date = false,
      this.both = false});
}

const reportMetas = <RMeta>[
  RMeta(RKind.semesterCerts, 'شهادات نتيجة امتحان نهاية الفصل (طالب في الصفحة)',
      'شهادة رسمية بإطار زخرفي: المحصلة والاختبار والمجموع والتقدير والترتيب.',
      Icons.workspace_premium_outlined,
      semester: true),
  RMeta(RKind.notices, 'إشعارات درجات (4 طلاب في الصفحة)',
      'إشعار رسمي لولي الأمر: الدرجات الشهرية ومعدل الأشهر واختبار المنتصف والمجموع.',
      Icons.mail_outline,
      subject: true, semester: true),
  RMeta(RKind.monthlySheet, 'كشف الدرجات الشهري المعتمد',
      'مكونات الدرجة الشهرية والمجموع والمحوّلة لمادة وشهر.',
      Icons.calendar_view_month,
      subject: true, month: true),
  RMeta(RKind.yearWork, 'المحصلة الشاملة لأعمال السنة والاختبار',
      'درجات كل شهر ومعدل الأشهر واختبار الفصل والمجموع لمادة.',
      Icons.table_rows_outlined,
      subject: true, semester: true),
  RMeta(RKind.attendance, 'تقرير ملخص الحضور والمواظبة',
      'عدد أيام الحضور والغياب والتأخر والاستئذان ونسبة الحضور.',
      Icons.event_available_outlined,
      date: true),
  RMeta(RKind.monthlyCerts, 'تقرير الطالب الشهري (جميع المواد)',
      'شهادة شهرية لكل طالب بكل المواد ومكوناتها ونسبة الغياب (3 في الصفحة).',
      Icons.workspace_premium,
      month: true),
  RMeta(RKind.studentSemester, 'تقرير الطالب الفصلي (جميع المواد)',
      'تقرير فصلي كامل لكل طالب في صفحة: معدل الأشهر والاختبار والمجموع.',
      Icons.assignment_ind_outlined,
      semester: true),
  RMeta(RKind.finalCerts, 'شهادات النتيجة النهائية السنوية (طالب في الصفحة)',
      'شهادة العام الكامل بالفصلين: الدرجات والمجموع والتقدير والترتيب.',
      Icons.verified_outlined),
  RMeta(RKind.incomplete, 'كشف الدرجات غير المكتملة',
      'الطلاب والمواد التي لم تكتمل درجاتها بعد.', Icons.rule_folder_outlined,
      semester: true, both: true),
  RMeta(RKind.sectionFull, 'كشف الشعبة الكامل (جميع المواد × الشعبة)',
      'جدول واحد لكل المواد ومجموع الطالب ونسبته (فصل أو الفصلان معاً).',
      Icons.grid_on,
      semester: true, both: true),
  RMeta(RKind.noticesAll, 'إشعارات 2×2 لجميع المواد (تقرير فصلي)',
      'أربعة إشعارات فصلية في الصفحة بخطوط قص، لكل طالب كل المواد.',
      Icons.view_module_outlined,
      semester: true),
  RMeta(RKind.gradeSheet, 'كشف رصد درجات مادة',
      'المحصلة والاختبار والمجموع لمادة واحدة في فصل دراسي.', Icons.grading,
      subject: true, semester: true),
  RMeta(RKind.results, 'كشف النتائج مرتباً',
      'ترتيب الطلاب بالمجموع مع التقدير والنتيجة والمواد الراسب فيها.',
      Icons.leaderboard_outlined),
  RMeta(RKind.classList, 'قائمة أسماء الصف',
      'أسماء الطلاب مع أرقام القيد والجلوس وهاتف ولي الأمر.', Icons.groups_outlined),
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

class _Term {
  final List<List<String>> rows;
  final double? avg, exam;
  _Term(this.rows, this.avg, this.exam);
  double get total => (avg ?? 0) + (exam ?? 0);
  bool get has => avg != null || exam != null;
}

Future<(int, int)> _range(int sem) async {
  final f = int.tryParse(await Db.setting('sem${sem + 1}_from')) ?? 1;
  final t = int.tryParse(await Db.setting('sem${sem + 1}_to')) ?? f;
  return (f, t < f ? f : t);
}

/// درجات فصل لمادة: صفوف الأشهر ومعدلها المحوّل والاختبار.
Future<_Term> _term(int sid, int subjectId, int sem, Rules rules,
    MonthlyCfg cfg, (int, int) range, bool hijri) async {
  final d = await Db.get();
  final ms = await d.query('monthly',
      where: 'student_id=? AND subject_id=? AND month BETWEEN ? AND ?',
      whereArgs: [sid, subjectId, range.$1, range.$2]);
  final byMonth = {for (final m in ms) m['month'] as int: m};
  final g = await d.query('grades',
      where: 'student_id=? AND subject_id=?', whereArgs: [sid, subjectId]);
  final gr = g.isEmpty ? null : g.first;
  final rows = <List<String>>[];
  final convs = <double>[];
  for (var m = range.$1; m <= range.$2; m++) {
    final r = byMonth[m];
    String f(String k) {
      final v = r?[k] as num?;
      return v == null ? '-' : nf(v);
    }

    double? sum;
    if (r != null) {
      final vs = [r['hw'], r['att'], r['oral'], r['written']].map((e) => e as num?).toList();
      if (vs.any((e) => e != null)) sum = vs.fold<double>(0, (a, e) => a + (e ?? 0));
    }
    final conv = sum == null ? null : double.parse(cfg.convert(sum).toStringAsFixed(1));
    if (conv != null) convs.add(conv);
    rows.add([monthName(m, hijri), f('hw'), f('att'), f('oral'), f('written'),
      conv == null ? '-' : nf(conv)]);
  }
  final maxW = sem == 0 ? rules.maxW1 : rules.maxW2;
  double? avg;
  if (convs.isNotEmpty) {
    avg = double.parse(
        (convs.reduce((a, b) => a + b) / convs.length / cfg.convertTo * maxW)
            .toStringAsFixed(1));
  } else {
    avg = (gr?[sem == 0 ? 't1_work' : 't2_work'] as num?)?.toDouble();
  }
  final exam = (gr?[sem == 0 ? 't1_exam' : 't2_exam'] as num?)?.toDouble();
  return _Term(rows, avg, exam);
}

String _semName(int sem) =>
    sem == 0 ? 'الفصل الدراسي الأول' : sem == 1 ? 'الفصل الدراسي الثاني' : 'الفصلان معاً';

class _Calc {
  final List<List<String>> rows = [];
  double a = 0, b = 0, c = 0;
  int count = 0;
}

/// شهادات النتيجة بتصميم الإطار: [sem] 0/1 فصل، 2 سنوية.
Future<ReportData> _certReport(Scope sc, int sem, int? onlyStudent, String year) async {
  final rules = await Rules.load();
  final d = await Db.get();
  final cls = await Db.className(sc.classId);
  final subjects = await Db.subjectsOf(sc.classId);
  final all = await Db.students(classId: sc.classId, section: sc.section);
  final style = await loadCertStyle();
  final subjMax = sem == 2
      ? rules.subjectMax
      : sem == 0
          ? rules.maxW1 + rules.maxE1
          : rules.maxW2 + rules.maxE2;
  final calc = <int, _Calc>{};
  for (final st in all) {
    final k = _Calc();
    for (final sub in subjects) {
      final g = await d.query('grades',
          where: 'student_id=? AND subject_id=?', whereArgs: [st['id'], sub['id']]);
      double? n(String f) => g.isEmpty ? null : (g.first[f] as num?)?.toDouble();
      double? a, b;
      if (sem == 0) {
        a = n('t1_work');
        b = n('t1_exam');
      } else if (sem == 1) {
        a = n('t2_work');
        b = n('t2_exam');
      } else {
        final x = [n('t1_work'), n('t1_exam')], y = [n('t2_work'), n('t2_exam')];
        a = x.every((e) => e == null) ? null : x.fold<double>(0, (p, e) => p + (e ?? 0));
        b = y.every((e) => e == null) ? null : y.fold<double>(0, (p, e) => p + (e ?? 0));
      }
      final has = a != null || b != null;
      final c = (a ?? 0) + (b ?? 0);
      if (has) {
        k.a += a ?? 0;
        k.b += b ?? 0;
        k.c += c;
        k.count++;
      }
      k.rows.add(['${sub['name']}', nf(a), nf(b), has ? nf(c) : '',
        has ? rules.rating(subjMax == 0 ? 0 : c / subjMax * 100) : '']);
    }
    calc[st['id'] as int] = k;
  }
  final ranked = [for (final e in calc.entries) if (e.value.count > 0) e]
    ..sort((x, y) => y.value.c.compareTo(x.value.c));
  final ranks = competitionRanks([for (final e in ranked) e.value.c]);
  final rankOf = {for (var i = 0; i < ranked.length; i++) ranked[i].key: ranks[i]};

  final title = sem == 0
      ? 'نتيجة امتحان نهاية الفصل الدراسي الأول'
      : sem == 1
          ? 'نتيجة امتحان نهاية الفصل الدراسي الثاني'
          : 'نتيجة امتحان نهاية العام الدراسي';
  final heads = sem == 2
      ? ['الفصل الأول', 'الفصل الثاني', 'المجموع', 'التقدير']
      : ['المحصلة', 'الاختبار', 'المجموع', 'التقدير'];
  final data = <ResultCertData>[];
  final flat = <List<String>>[];
  for (final st in all) {
    final id = st['id'] as int;
    if (onlyStudent != null && id != onlyStudent) continue;
    final k = calc[id]!;
    final max = k.count * subjMax;
    final pct = max == 0 ? 0.0 : k.c / max * 100;
    final rank = rankOf[id];
    for (final r in k.rows) {
      flat.add(['${st['name']}', ...r]);
    }
    data.add(ResultCertData(
      name: '${st['name']}',
      regNo: '${st['reg_no'] ?? ''}',
      seat: '${st['seat_no'] ?? ''}',
      className: cls,
      section: '${st['section'] ?? ''}',
      address: '${st['address'] ?? ''}',
      photoPath: '${st['photo'] ?? ''}',
      heads: heads,
      rows: k.rows,
      totals: k.count == 0
          ? ['', '', '', '']
          : [nf(k.a), nf(k.b), nf(k.c), rules.rating(pct)],
      totalWords: k.count == 0 ? '' : arabicWords(k.c),
      rankText: rank == null ? '-' : ordinalAr(rank),
      percent: max == 0 ? '-' : pct.toStringAsFixed(1),
    ));
  }
  return ReportData(
      ExportTable('$title - $cls', ['الاسم', 'المادة', heads[0], heads[1], heads[2], heads[3]], flat),
      () => buildResultCerts(data, style, year, title),
      data.length);
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
      if (sc.subjectId == null) throw StateError('اختر المادة أولاً');
      final rules = await Rules.load();
      final subject = await _subjectName(sc.subjectId);
      final t1 = semester == 0;
      final wk = t1 ? 't1_work' : 't2_work', ex = t1 ? 't1_exam' : 't2_exam';
      final mw = t1 ? rules.maxW1 : rules.maxW2, me = t1 ? rules.maxE1 : rules.maxE2;
      final semLabel = _semName(t1 ? 0 : 1);
      final rows0 = await Db.gradeRows(sc.classId, sc.section, sc.subjectId!);
      String sum(num? a, num? b) =>
          (a == null && b == null) ? '' : nf((a ?? 0) + (b ?? 0));
      final h2 = ['م', 'الاسم', 'رقم القيد', 'المحصلة (${nf(mw)})', 'الاختبار (${nf(me)})', 'المجموع (${nf(mw + me)})'];
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

    case RKind.notices:
      if (sc.subjectId == null) throw StateError('اختر المادة أولاً');
      final rules = await Rules.load();
      final cfg = await MonthlyCfg.load();
      final sem = semester == 1 ? 1 : 0;
      final range = await _range(sem);
      final subject = await _subjectName(sc.subjectId);
      final semLabel = _semName(sem);
      final avgMax = sem == 0 ? rules.maxW1 : rules.maxW2;
      final examMax = sem == 0 ? rules.maxE1 : rules.maxE2;
      final data = <NoticeData>[];
      for (final st in students) {
        final t = await _term(st['id'] as int, sc.subjectId!, sem, rules, cfg, range, hijri);
        data.add(NoticeData('${st['name']}', '${st['reg_no'] ?? ''}', cls,
            '${st['section'] ?? ''}', t.rows, nf(t.avg ?? 0), nf(t.exam ?? 0), nf(t.total)));
      }
      final monthHeads = ['الشهر', ...cfg.labels, 'المحصلة'];
      final table = ExportTable('إشعارات $subject - $semLabel',
          ['الاسم', 'رقم القيد', 'معدل الأشهر', 'الاختبار', 'المجموع'],
          [for (final n in data) [n.name, n.regNo, n.avg, n.exam, n.total]]);
      return ReportData(
          table,
          () => buildNotices(data, school, year, semLabel, subject, monthHeads, avgMax, examMax),
          data.length);

    case RKind.noticesAll:
    case RKind.studentSemester:
      final rules = await Rules.load();
      final cfg = await MonthlyCfg.load();
      final sem = semester == 1 ? 1 : 0;
      final range = await _range(sem);
      final subjects = await Db.subjectsOf(sc.classId);
      final avgMax = sem == 0 ? rules.maxW1 : rules.maxW2;
      final examMax = sem == 0 ? rules.maxE1 : rules.maxE2;
      final semLabel = _semName(sem);
      final data = <SemAllData>[];
      final flat = <List<String>>[];
      for (final st in students) {
        final rows = <List<String>>[];
        var total = 0.0;
        var count = 0;
        for (final sub in subjects) {
          final t = await _term(st['id'] as int, sub['id'] as int, sem, rules, cfg, range, hijri);
          rows.add(['${sub['name']}', t.avg == null ? '' : nf(t.avg), t.exam == null ? '' : nf(t.exam), t.has ? nf(t.total) : '']);
          flat.add(['${st['name']}', '${sub['name']}', t.avg == null ? '' : nf(t.avg), t.exam == null ? '' : nf(t.exam), t.has ? nf(t.total) : '']);
          if (t.has) {
            total += t.total;
            count++;
          }
        }
        final max = count * (avgMax + examMax);
        data.add(SemAllData('${st['name']}', '${st['reg_no'] ?? ''}', cls, '${st['section'] ?? ''}', rows,
            '${nf(total)} / ${nf(max)}', max == 0 ? '-' : '${(total / max * 100).toStringAsFixed(1)}%'));
      }
      return ReportData(
          ExportTable('تقرير فصلي - $semLabel - $cls',
              ['الاسم', 'المادة', 'معدل الأشهر', 'الاختبار', 'المجموع'], flat),
          () => buildSemesterAll(data, school, year, semLabel, avgMax, examMax,
              kind == RKind.noticesAll ? 4 : 1),
          data.length);

    case RKind.yearWork:
      if (sc.subjectId == null) throw StateError('اختر المادة أولاً');
      final rules = await Rules.load();
      final cfg = await MonthlyCfg.load();
      final sem = semester == 1 ? 1 : 0;
      final range = await _range(sem);
      final subject = await _subjectName(sc.subjectId);
      final avgMax = sem == 0 ? rules.maxW1 : rules.maxW2;
      final examMax = sem == 0 ? rules.maxE1 : rules.maxE2;
      final heads = [
        'م', 'الاسم',
        for (var m = range.$1; m <= range.$2; m++) monthName(m, hijri),
        'معدل الأشهر (${nf(avgMax)})', 'الاختبار (${nf(examMax)})',
        'المجموع (${nf(avgMax + examMax)})',
      ];
      final rows = <List<String>>[];
      for (var i = 0; i < students.length; i++) {
        final st = students[i];
        final t = await _term(st['id'] as int, sc.subjectId!, sem, rules, cfg, range, hijri);
        rows.add(['${i + 1}', '${st['name']}', for (final r in t.rows) r.last,
          t.avg == null ? '' : nf(t.avg), t.exam == null ? '' : nf(t.exam), t.has ? nf(t.total) : '']);
      }
      final title = 'المحصلة الشاملة - $subject - ${_semName(sem)} - $cls';
      return ReportData(ExportTable(title, heads, rows),
          () => buildTableReport(title, heads, rows, school, year, landscape: true,
              flex: [0.8, 4, for (var i = 2; i < heads.length; i++) 1.4]),
          rows.length);

    case RKind.incomplete:
      final subjects = await Db.subjectsOf(sc.classId);
      final parts = <(String, String)>[
        if (semester != 1) ('t1_work', 'محصلة 1'),
        if (semester != 1) ('t1_exam', 'اختبار 1'),
        if (semester != 0) ('t2_work', 'محصلة 2'),
        if (semester != 0) ('t2_exam', 'اختبار 2'),
      ];
      final heads = ['م', 'الطالب', 'المادة', 'الناقص'];
      final rows = <List<String>>[];
      for (final st in students) {
        for (final sub in subjects) {
          final g = await d.query('grades',
              where: 'student_id=? AND subject_id=?', whereArgs: [st['id'], sub['id']]);
          final gr = g.isEmpty ? null : g.first;
          final miss = [for (final p in parts) if (gr == null || gr[p.$1] == null) p.$2];
          if (miss.isNotEmpty) {
            rows.add(['${rows.length + 1}', '${st['name']}', '${sub['name']}', miss.join('، ')]);
          }
        }
      }
      final title = 'كشف الدرجات غير المكتملة - ${_semName(semester)} - $cls';
      return ReportData(ExportTable(title, heads, rows),
          () => buildTableReport(title, heads, rows, school, year, flex: [1, 4, 3, 4]),
          rows.length);

    case RKind.sectionFull:
      final rules = await Rules.load();
      final subjects = await Db.subjectsOf(sc.classId);
      final perSubject = semester == 2
          ? rules.subjectMax
          : semester == 0
              ? rules.maxW1 + rules.maxE1
              : rules.maxW2 + rules.maxE2;
      final heads = [
        'م', 'الاسم', for (final s in subjects) '${s['name']}', 'المجموع', 'النسبة',
      ];
      final rows = <List<String>>[];
      for (var i = 0; i < students.length; i++) {
        final st = students[i];
        var total = 0.0;
        var count = 0;
        final cells = <String>[];
        for (final sub in subjects) {
          final g = await d.query('grades',
              where: 'student_id=? AND subject_id=?', whereArgs: [st['id'], sub['id']]);
          double? n(String k) => g.isEmpty ? null : (g.first[k] as num?)?.toDouble();
          final parts = semester == 0
              ? [n('t1_work'), n('t1_exam')]
              : semester == 1
                  ? [n('t2_work'), n('t2_exam')]
                  : [n('t1_work'), n('t1_exam'), n('t2_work'), n('t2_exam')];
          if (parts.every((e) => e == null)) {
            cells.add('');
          } else {
            final v = parts.fold<double>(0, (a, e) => a + (e ?? 0));
            cells.add(nf(v));
            total += v;
            count++;
          }
        }
        final max = count * perSubject;
        rows.add(['${i + 1}', '${st['name']}', ...cells, count == 0 ? '' : nf(total),
          max == 0 ? '' : '${(total / max * 100).toStringAsFixed(1)}%']);
      }
      final title = 'كشف الشعبة الكامل - ${_semName(semester)} - $cls';
      return ReportData(ExportTable(title, heads, rows),
          () => buildTableReport(title, heads, rows, school, year, landscape: true,
              flex: [0.7, 4, for (var i = 2; i < heads.length; i++) 1.3]),
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
      return _certReport(sc, 2, onlyStudent, year);

    case RKind.semesterCerts:
      return _certReport(sc, semester == 1 ? 1 : 0, onlyStudent, year);

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
