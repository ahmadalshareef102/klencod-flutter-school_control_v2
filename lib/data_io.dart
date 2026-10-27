import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// جدول عام للتصدير: عناوين وصفوف نصية.
class ExportTable {
  final String title;
  final List<String> heads;
  final List<List<String>> rows;
  const ExportTable(this.title, this.heads, this.rows);

  /// يعيد جدولاً بالأعمدة المحددة فقط.
  ExportTable pick(List<int> cols) => ExportTable(
      title,
      [for (final c in cols) heads[c]],
      [for (final r in rows) [for (final c in cols) r[c]]]);
}

// ================= CSV =================
String toCsv(List<List<String>> rows) {
  String esc(String s) => (s.contains(',') ||
          s.contains('"') ||
          s.contains('\n') ||
          s.contains(';'))
      ? '"${s.replaceAll('"', '""')}"'
      : s;
  return rows.map((r) => r.map(esc).join(',')).join('\r\n');
}

List<List<String>> parseCsv(String text) {
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  final firstLine = text.split('\n').first;
  final delim = (firstLine.contains(';') && !firstLine.contains(',')) ? ';' : ',';
  final rows = <List<String>>[];
  var row = <String>[];
  final cur = StringBuffer();
  var inQ = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQ) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          inQ = false;
        }
      } else {
        cur.write(c);
      }
    } else if (c == '"') {
      inQ = true;
    } else if (c == delim) {
      row.add(cur.toString());
      cur.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cur.toString());
      cur.clear();
      if (row.any((e) => e.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cur.write(c);
    }
  }
  row.add(cur.toString());
  if (row.any((e) => e.trim().isNotEmpty)) rows.add(row);
  return rows;
}

Uint8List csvBytes(List<List<String>> rows) =>
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(toCsv(rows))]);

// ================= XLSX (كتابة وقراءة داخلية) =================
String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _col(int i) {
  var s = '';
  var n = i + 1;
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

int _colIndex(String letters) {
  var n = 0;
  for (final c in letters.codeUnits) {
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

/// ينشئ ملف xlsx باتجاه RTL؛ الصف الأول بخط عريض عند [boldFirstRow].
Uint8List buildXlsx(String sheetName, List<List<String>> rows,
    {bool boldFirstRow = true}) {
  final sb = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetViews><sheetView workbookViewId="0" rightToLeft="1"/></sheetViews>'
      '<sheetData>');
  for (var r = 0; r < rows.length; r++) {
    sb.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      final ref = '${_col(c)}${r + 1}';
      final style = (boldFirstRow && r == 0) ? ' s="1"' : '';
      final n = double.tryParse(v);
      if (n != null &&
          v.trim().isNotEmpty &&
          (!v.startsWith('0') || v == '0' || v.startsWith('0.'))) {
        sb.write('<c r="$ref"$style><v>$v</v></c>');
      } else {
        sb.write('<c r="$ref" t="inlineStr"$style><is>'
            '<t xml:space="preserve">${_xml(v)}</t></is></c>');
      }
    }
    sb.write('</row>');
  }
  sb.write('</sheetData></worksheet>');

  const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  final files = <String, String>{
    '[Content_Types].xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
            '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
            '</Types>',
    '_rels/.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            '</Relationships>',
    'xl/workbook.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<workbook xmlns="$ns" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="${_xml(sheetName.length > 31 ? sheetName.substring(0, 31) : sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
            '</workbook>',
    'xl/_rels/workbook.xml.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
            '</Relationships>',
    'xl/styles.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<styleSheet xmlns="$ns">'
            '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
            '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
            '<fills count="2"><fill><patternFill patternType="none"/></fill>'
            '<fill><patternFill patternType="gray125"/></fill></fills>'
            '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
            '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
            '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
            '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
            '</styleSheet>',
    'xl/worksheets/sheet1.xml': sb.toString(),
  };
  final arc = Archive();
  files.forEach((name, content) {
    final b = utf8.encode(content);
    arc.addFile(ArchiveFile(name, b.length, b));
  });
  final out = ZipEncoder().encode(arc);
  return Uint8List.fromList(out ?? <int>[]);
}

String _unxml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// يقرأ أول ورقة من ملف xlsx ويعيدها كجدول نصي.
List<List<String>> readXlsx(Uint8List bytes) {
  final arc = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? find(bool Function(String) test) {
    for (final f in arc) {
      if (f.isFile && test(f.name)) return f;
    }
    return null;
  }

  String text(ArchiveFile? f) =>
      f == null ? '' : utf8.decode(f.content as List<int>, allowMalformed: true);

  final shared = <String>[];
  final sst = text(find((n) => n == 'xl/sharedStrings.xml'));
  for (final m in RegExp(r'<si>(.*?)</si>', dotAll: true).allMatches(sst)) {
    final inner = m.group(1) ?? '';
    final sbuf = StringBuffer();
    for (final t in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(inner)) {
      sbuf.write(_unxml(t.group(1) ?? ''));
    }
    shared.add(sbuf.toString());
  }
  final sheet = text(find((n) =>
      n == 'xl/worksheets/sheet1.xml' ||
      (n.startsWith('xl/worksheets/sheet') && n.endsWith('.xml'))));
  final rows = <List<String>>[];
  for (final rm in RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true).allMatches(sheet)) {
    final cells = <int, String>{};
    for (final cm in RegExp(r'<c\s+([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true)
        .allMatches(rm.group(1) ?? '')) {
      final attrs = cm.group(1) ?? '';
      final body = cm.group(2) ?? '';
      final ref = RegExp(r'r="([A-Z]+)\d+"').firstMatch(attrs)?.group(1);
      if (ref == null) continue;
      final type = RegExp(r't="(\w+)"').firstMatch(attrs)?.group(1);
      String v = '';
      if (type == 's') {
        final i = int.tryParse(
            RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1) ?? '');
        if (i != null && i < shared.length) v = shared[i];
      } else if (type == 'inlineStr') {
        final sbuf = StringBuffer();
        for (final t in RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true).allMatches(body)) {
          sbuf.write(_unxml(t.group(1) ?? ''));
        }
        v = sbuf.toString();
      } else {
        v = _unxml(RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1) ?? '');
        if (v.endsWith('.0')) v = v.substring(0, v.length - 2);
      }
      cells[_colIndex(ref)] = v;
    }
    if (cells.isEmpty) continue;
    final maxC = cells.keys.reduce((a, b) => a > b ? a : b);
    final row = [for (var i = 0; i <= maxC; i++) cells[i] ?? ''];
    if (row.any((e) => e.trim().isNotEmpty)) rows.add(row);
  }
  return rows;
}

// ================= ملفات: اختيار ومشاركة =================
class PickedFile {
  final String name;
  final Uint8List bytes;
  PickedFile(this.name, this.bytes);
}

Future<PickedFile?> pickAnyFile() async {
  final r = await FilePicker.platform.pickFiles(withData: true);
  if (r == null || r.files.isEmpty) return null;
  final f = r.files.first;
  final b = f.bytes;
  if (b == null) return null;
  return PickedFile(f.name, b);
}

/// يقرأ ملف جدول (xlsx أو csv) ويعيد صفوفه.
List<List<String>> parseTableFile(PickedFile f) {
  final n = f.name.toLowerCase();
  if (n.endsWith('.xlsx')) return readXlsx(f.bytes);
  return parseCsv(utf8.decode(f.bytes, allowMalformed: true));
}

Future<void> shareBytes(String fileName, List<int> bytes, {String? mime}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(file.path, mimeType: mime)], text: fileName);
}

Future<void> exportTable(ExportTable t,
    {required bool xlsx, bool withTitle = false, String school = '', String year = ''}) async {
  final rows = <List<String>>[
    if (withTitle) [t.title],
    if (withTitle) [[school, year].where((e) => e.isNotEmpty).join(' - ')],
    if (withTitle) <String>[],
    t.heads,
    ...t.rows,
  ];
  final safe = t.title.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
  if (xlsx) {
    await shareBytes('$safe.xlsx',
        buildXlsx(t.title, rows, boldFirstRow: !withTitle),
        mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  } else {
    await shareBytes('$safe.csv', csvBytes(rows), mime: 'text/csv');
  }
}
