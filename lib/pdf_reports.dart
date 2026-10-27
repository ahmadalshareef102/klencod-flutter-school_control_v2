import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'logic.dart';

class SheetStudent {
  final int? seat;
  final String name, className, gender;
  final int? committee;
  SheetStudent(this.seat, this.name, this.className, this.gender,
      [this.committee]);
}

class CommitteeSheet {
  final int no;
  final String className;
  final List<SheetStudent> students;
  CommitteeSheet(this.no, this.className, this.students);
}

Future<pw.ThemeData> _theme() async {
  final r = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
  final b = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Bold.ttf'));
  return pw.ThemeData.withFont(base: r, bold: b);
}

pw.Widget _t(String s,
        {double size = 11,
        bool bold = false,
        pw.TextAlign align = pw.TextAlign.center}) =>
    pw.Text(s,
        textDirection: pw.TextDirection.rtl,
        textAlign: align,
        style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));

pw.Widget _cell(String s, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 3),
    child: _t(s, bold: bold, size: 10));

/// يعرض الأعمدة من اليمين لليسار بعكس ترتيبها المنطقي.
List<T> _rtl<T>(List<T> l) => l.reversed.toList();

pw.Widget _header(String school, String year) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: _rtl([
        pw.Column(children: [
          _t('الجمهورية اليمنية', bold: true),
          _t('وزارة التربية والتعليم'),
        ]),
        _t('بسم الله الرحمن الرحيم', bold: true, size: 12),
        pw.Column(children: [
          _t('المدرسة: ${school.isEmpty ? '................' : school}'),
          _t('العام الدراسي: $year'),
        ]),
      ]),
    );

pw.Widget _signatures() => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: _rtl([
        _t('رئيس الكنترول: ...............'),
        _t('مدير المدرسة: ...............'),
      ]),
    );

/// كشوف مناداة الطلاب في اللجان: صفحة لكل لجنة.
Future<Uint8List> buildCallSheets(
    List<CommitteeSheet> sheets, String school, String year) async {
  final doc = pw.Document(theme: await _theme());
  for (final sh in sheets) {
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (_) => pw.Column(children: [
        _header(school, year),
        pw.SizedBox(height: 10),
        _t('كشف مناداة الطلاب في اللجنة (${sh.no}) - ${sh.className}',
            bold: true, size: 14),
        pw.SizedBox(height: 8),
      ]),
      footer: (_) => _signatures(),
      build: (_) {
        const heads = ['م', 'اسم الطالب', 'رقم الجلوس', 'التوقيع', 'الحالة', 'ملاحظات'];
        final widths = _rtl([
          const pw.FixedColumnWidth(24),
          const pw.FlexColumnWidth(4),
          const pw.FixedColumnWidth(60),
          const pw.FlexColumnWidth(2),
          const pw.FixedColumnWidth(60),
          const pw.FlexColumnWidth(2),
        ]);
        return [
          pw.Table(
            border: pw.TableBorder.all(width: 0.6),
            columnWidths: {for (var i = 0; i < widths.length; i++) i: widths[i]},
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: _rtl([for (final h in heads) _cell(h, bold: true)]),
              ),
              for (var i = 0; i < sh.students.length; i++)
                pw.TableRow(
                  children: _rtl([
                    _cell('${i + 1}'),
                    _cell(sh.students[i].name),
                    _cell('${sh.students[i].seat ?? '-'}'),
                    _cell(''),
                    _cell('حاضر / غائب'),
                    _cell(''),
                  ]),
                ),
            ],
          ),
        ];
      },
    ));
  }
  return doc.save();
}

/// بطاقات أرقام الجلوس (10 بطاقات في الصفحة).
Future<Uint8List> buildSeatCards(
    List<SheetStudent> students, String school, String year) async {
  final doc = pw.Document(theme: await _theme());
  for (var start = 0; start < students.length; start += 10) {
    final chunk = students.skip(start).take(10).toList();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.GridView(
        crossAxisCount: 2,
        childAspectRatio: 2.6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        children: [
          for (final s in chunk)
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.8),
                  borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  _t('بطاقة رقم جلوس - ${school.isEmpty ? '' : school}',
                      bold: true, size: 10),
                  _t(s.name, bold: true, size: 12),
                  _t('رقم الجلوس: ${s.seat ?? '-'}', size: 12, bold: true),
                  _t('${s.className}   •   اللجنة: ${s.committee ?? '-'}',
                      size: 10),
                  _t(year, size: 9),
                ],
              ),
            ),
        ],
      ),
    ));
  }
  if (students.isEmpty) doc.addPage(pw.Page(build: (_) => _t('لا يوجد طلاب')));
  return doc.save();
}

Future<void> printPdf(Uint8List bytes, String name, {bool share = false}) =>
    share
        ? Printing.sharePdf(bytes: bytes, filename: '$name.pdf')
        : Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

/// جدول عام: [heads] و[rows] بالترتيب المنطقي (يُعرض من اليمين لليسار).
pw.Widget _grid(List<String> heads, List<List<String>> rows,
    List<pw.TableColumnWidth> widths) {
  final w = _rtl(widths);
  return pw.Table(
    border: pw.TableBorder.all(width: 0.6),
    columnWidths: {for (var i = 0; i < w.length; i++) i: w[i]},
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: _rtl([for (final h in heads) _cell(h, bold: true)]),
      ),
      for (final r in rows) pw.TableRow(children: _rtl([for (final c in r) _cell(c)])),
    ],
  );
}

/// كشف النتائج مرتباً: ترتيب، اسم، جلوس، مجموع، نسبة، تقدير، نتيجة، مواد الرسوب.
Future<Uint8List> buildResultSheet(String className, List<List<String>> rows,
    String school, String year) async {
  final doc = pw.Document(theme: await _theme());
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    header: (_) => pw.Column(children: [
      _header(school, year),
      pw.SizedBox(height: 10),
      _t('كشف النتائج - $className', bold: true, size: 14),
      pw.SizedBox(height: 8),
    ]),
    footer: (_) => _signatures(),
    build: (_) => [
      _grid(
        ['الترتيب', 'اسم الطالب', 'رقم الجلوس', 'المجموع', 'النسبة', 'التقدير', 'النتيجة', 'المواد الراسب فيها'],
        rows,
        const [
          pw.FixedColumnWidth(40), pw.FlexColumnWidth(4), pw.FixedColumnWidth(50),
          pw.FixedColumnWidth(45), pw.FixedColumnWidth(45), pw.FixedColumnWidth(50),
          pw.FixedColumnWidth(50), pw.FlexColumnWidth(3),
        ],
      ),
    ],
  ));
  return doc.save();
}

/// الخلاصة الإحصائية العامة (أفقي).
Future<Uint8List> buildStatsSheet(List<String> heads, List<List<String>> rows,
    String school, String year) async {
  final doc = pw.Document(theme: await _theme());
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(28),
    header: (_) => pw.Column(children: [
      _header(school, year),
      pw.SizedBox(height: 10),
      _t('الخلاصة العامة لنتائج الطلاب على مستوى المدرسة', bold: true, size: 14),
      pw.SizedBox(height: 8),
    ]),
    footer: (_) => _signatures(),
    build: (_) => [
      _grid(heads, rows, [
        const pw.FlexColumnWidth(3),
        for (var i = 1; i < heads.length; i++) const pw.FlexColumnWidth(1.2),
      ]),
    ],
  ));
  return doc.save();
}

// ===================== المرحلة 2.0: شهادات وإشعارات وتقارير عامة =====================

class MonthlyRowData {
  final String subject;
  final double? hw, att, oral, written;
  MonthlyRowData(this.subject, this.hw, this.att, this.oral, this.written);
  bool get has => hw != null || att != null || oral != null || written != null;
  double get total => (hw ?? 0) + (att ?? 0) + (oral ?? 0) + (written ?? 0);
}

class MonthlyCertData {
  final String name, className, absence;
  final int? seat;
  final List<MonthlyRowData> rows;
  MonthlyCertData(this.name, this.seat, this.className, this.absence, this.rows);
}

class FinalCertData {
  final String name, className, failed;
  final int? seat;
  final List<List<String>> rows; // مادة، ف1، ف2، مجموع
  final List<String> summary;
  FinalCertData(this.name, this.seat, this.className, this.rows, this.summary,
      this.failed);
}

class NoticeData {
  final String name, regNo, className, section;
  final List<String> values;
  NoticeData(this.name, this.regNo, this.className, this.section, this.values);
}

String _nn(num? v) => nf(v);

pw.Widget _boxed(pw.Widget child) => pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.8),
          borderRadius: pw.BorderRadius.circular(4)),
      child: child,
    );

pw.Widget _monthlyBlock(MonthlyCertData c, String school, String year,
    String monthLabel, List<String> labels, List<double> maxes, double convertTo) {
  final totalMax = maxes.fold<double>(0, (a, b) => a + b);
  final heads = ['المادة', ...labels, 'المجموع', 'المحوّلة'];
  final rows = <List<String>>[
    for (final r in c.rows)
      [
        r.subject, _nn(r.hw), _nn(r.att), _nn(r.oral), _nn(r.written),
        r.has ? _nn(r.total) : '',
        r.has ? _nn(totalMax == 0 ? 0 : r.total / totalMax * convertTo) : '',
      ],
    ['النهاية العظمى', ...maxes.map(_nn), _nn(totalMax), _nn(convertTo)],
  ];
  final withData = c.rows.where((r) => r.has).toList();
  final conv = withData.fold<double>(
      0, (a, r) => a + (totalMax == 0 ? 0 : r.total / totalMax * convertTo));
  final summary = withData.isEmpty
      ? 'لم تُرصد درجات لهذا الشهر'
      : 'المجموع الكلي: ${_nn(conv)} من ${_nn(withData.length * convertTo)}';
  return pw.SizedBox(
    width: 540,
    child: _boxed(pw.Column(children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: _rtl([
          _t(school.isEmpty ? '' : school, size: 9),
          _t('شهادة درجات شهر $monthLabel', bold: true, size: 12),
          _t('العام الدراسي: $year', size: 9),
        ]),
      ),
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: _rtl([
          _t('الطالب: ${c.name}', size: 10, bold: true),
          _t('رقم الجلوس: ${c.seat ?? '-'}', size: 10),
          _t(c.className, size: 10),
          _t(c.absence, size: 10),
        ]),
      ),
      pw.SizedBox(height: 4),
      _grid(heads, rows, <pw.TableColumnWidth>[
        const pw.FlexColumnWidth(3),
        const pw.FixedColumnWidth(54), const pw.FixedColumnWidth(54),
        const pw.FixedColumnWidth(54), const pw.FixedColumnWidth(54),
        const pw.FixedColumnWidth(48), const pw.FixedColumnWidth(48),
      ]),
      pw.SizedBox(height: 3),
      _t(summary, size: 9, bold: true),
      pw.SizedBox(height: 6),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: _rtl([
          _t('رائد الفصل: ..........', size: 8),
          _t('ولي الأمر: ..........', size: 8),
          _t('مسؤول الكنترول: ..........', size: 8),
          _t('المدير: ..........', size: 8),
        ]),
      ),
    ])),
  );
}

/// شهادات الدرجات الشهرية: ثلاث شهادات في صفحة A4.
Future<Uint8List> buildMonthlyCerts(
    List<MonthlyCertData> data,
    String school,
    String year,
    String monthLabel,
    List<String> labels,
    List<double> maxes,
    double convertTo) async {
  final doc = pw.Document(theme: await _theme());
  if (data.isEmpty) {
    doc.addPage(pw.Page(build: (_) => _t('لا يوجد طلاب')));
  }
  for (var i = 0; i < data.length; i += 3) {
    final chunk = data.skip(i).take(3).toList();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (_) => pw.Column(children: [
        for (final c in chunk)
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.FittedBox(
                  child: _monthlyBlock(
                      c, school, year, monthLabel, labels, maxes, convertTo)),
            ),
          ),
        for (var k = chunk.length; k < 3; k++) pw.Expanded(child: pw.SizedBox()),
      ]),
    ));
  }
  return doc.save();
}

/// إشعارات الدرجات: أربعة طلاب في الصفحة.
Future<Uint8List> buildNotices(List<NoticeData> data, String school, String year,
    String semester, String subject, List<String> heads) async {
  final doc = pw.Document(theme: await _theme());
  if (data.isEmpty) {
    doc.addPage(pw.Page(build: (_) => _t('لا يوجد طلاب')));
  }
  pw.Widget block(NoticeData n) => pw.SizedBox(
        width: 540,
        child: _boxed(pw.Column(children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: _rtl([
              _t(school, size: 9),
              _t('إشعار درجات - $semester', bold: true, size: 12),
              _t('العام: $year', size: 9),
            ]),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: _rtl([
              _t('الطالب: ${n.name}', bold: true, size: 10),
              _t('رقم القيد: ${n.regNo}', size: 10),
              _t('${n.className} - ${n.section}', size: 10),
              _t('المادة: $subject', size: 10, bold: true),
            ]),
          ),
          pw.SizedBox(height: 4),
          _grid(heads, [n.values],
              <pw.TableColumnWidth>[for (final _ in heads) const pw.FlexColumnWidth(1)]),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: _rtl([
              _t('معلم المادة: ..........', size: 8),
              _t('ولي الأمر: ..........', size: 8),
              _t('المدير: ..........', size: 8),
            ]),
          ),
        ])),
      );
  for (var i = 0; i < data.length; i += 4) {
    final chunk = data.skip(i).take(4).toList();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (_) => pw.Column(children: [
        for (final n in chunk)
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.FittedBox(child: block(n)),
            ),
          ),
        for (var k = chunk.length; k < 4; k++) pw.Expanded(child: pw.SizedBox()),
      ]),
    ));
  }
  return doc.save();
}

/// شهادات النتيجة: طالب في كل صفحة.
Future<Uint8List> buildFinalCerts(List<FinalCertData> data, String school,
    String year, List<double> maxes) async {
  final doc = pw.Document(theme: await _theme());
  if (data.isEmpty) {
    doc.addPage(pw.Page(build: (_) => _t('لا يوجد طلاب')));
  }
  for (final c in data) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => pw.Column(children: [
        _header(school, year),
        pw.SizedBox(height: 16),
        _t('شهادة نتيجة الطالب', bold: true, size: 18),
        pw.SizedBox(height: 14),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: _rtl([
            _t('الطالب: ${c.name}', bold: true, size: 13),
            _t('رقم الجلوس: ${c.seat ?? '-'}', size: 12),
            _t('الصف: ${c.className}', size: 12),
          ]),
        ),
        pw.SizedBox(height: 14),
        _grid(
          ['المادة', 'الفصل الأول', 'الفصل الثاني', 'المجموع'],
          [
            ...c.rows,
            ['النهاية العظمى', _nn(maxes[0]), _nn(maxes[1]), _nn(maxes[2])],
          ],
          <pw.TableColumnWidth>[
            const pw.FlexColumnWidth(3), const pw.FlexColumnWidth(1.3),
            const pw.FlexColumnWidth(1.3), const pw.FlexColumnWidth(1.3),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: _rtl([for (final s in c.summary) _t(s, bold: true, size: 12)]),
        ),
        if (c.failed.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _t('المواد الراسب فيها: ${c.failed}', size: 11),
        ],
        pw.Spacer(),
        _signatures(),
      ]),
    ));
  }
  return doc.save();
}

/// تقرير جدولي عام (قوائم، كشوف رصد، حضور...).
Future<Uint8List> buildTableReport(String title, List<String> heads,
    List<List<String>> rows, String school, String year,
    {bool landscape = false, List<double>? flex}) async {
  final doc = pw.Document(theme: await _theme());
  final w = <pw.TableColumnWidth>[
    for (var i = 0; i < heads.length; i++)
      pw.FlexColumnWidth(flex != null && i < flex.length ? flex[i] : 1),
  ];
  doc.addPage(pw.MultiPage(
    pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    header: (_) => pw.Column(children: [
      _header(school, year),
      pw.SizedBox(height: 10),
      _t(title, bold: true, size: 14),
      pw.SizedBox(height: 8),
    ]),
    footer: (_) => _signatures(),
    build: (_) => [_grid(heads, rows, w)],
  ));
  return doc.save();
}

/// بطاقة بيانات طالب.
Future<Uint8List> buildStudentCard(String name, List<List<String>> kv,
    String school, String year) async {
  final doc = pw.Document(theme: await _theme());
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => pw.Column(children: [
      _header(school, year),
      pw.SizedBox(height: 16),
      _t('بطاقة بيانات الطالب', bold: true, size: 16),
      pw.SizedBox(height: 4),
      _t(name, bold: true, size: 14),
      pw.SizedBox(height: 14),
      _grid(['البيان', 'القيمة'], kv,
          <pw.TableColumnWidth>[const pw.FlexColumnWidth(1), const pw.FlexColumnWidth(2)]),
      pw.Spacer(),
      _signatures(),
    ]),
  ));
  return doc.save();
}
