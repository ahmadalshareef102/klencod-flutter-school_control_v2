import 'package:flutter_test/flutter_test.dart';
import 'package:school_control/arabic_text.dart';
import 'package:school_control/dates.dart';
import 'package:school_control/license.dart';
import 'package:school_control/logic.dart';

const rules = Rules(
  passPercent: 50, maxFailedSecondRound: 2,
  excellent: 85, veryGood: 75, good: 65, ok: 50,
  maxW1: 20, maxE1: 30, maxW2: 20, maxE2: 30,
);

void main() {
  splitTests();
  rankTests();
  monthlyTests();
  arabicTests();
  licenseTests();
  test('طالب ناجح في كل المواد', () {
    final r = compute([
      SubjectScore('عربي', 20, 30, 20, 30),
      SubjectScore('رياضيات', 15, 25, 15, 25),
    ], rules);
    expect(r.status, 'ناجح');
    expect(r.rating, 'ممتاز');
  });

  test('رسوب في مادة واحدة يعني دوراً ثانياً', () {
    final r = compute([
      SubjectScore('عربي', 20, 30, 20, 30),
      SubjectScore('رياضيات', 5, 10, 5, 10),
    ], rules);
    expect(r.status, 'دور ثانٍ');
    expect(r.failed, ['رياضيات']);
  });

  test('بدون أي درجات يكون الطالب غائباً', () {
    final r = compute([SubjectScore('عربي', null, null, null, null)], rules);
    expect(r.status, 'غائب');
  });
}

void splitTests() {
  test('تقسيم متوازن للجان', () {
    expect(splitSizes(60, 25), [20, 20, 20]);
    expect(splitSizes(26, 25), [13, 13]);
    expect(splitSizes(0, 25), isEmpty);
  });
}

void rankTests() {
  test('ترتيب تنافسي مع التعادل', () {
    expect(competitionRanks([90, 90, 80, 70, 70]), [1, 1, 3, 4, 4]);
  });
}

void monthlyTests() {
  test('تحويل الدرجة الشهرية من 100 إلى 20', () {
    const cfg = MonthlyCfg(20, 20, 20, 40, 20, ['أ', 'ب', 'ج', 'د']);
    expect(cfg.total, 100);
    expect(cfg.convert(50), 10);
    expect(cfg.convert(100), 20);
  });

  test('التاريخ الهجري يقع في عام 1448 في أكتوبر 2026', () {
    expect(toHijri(DateTime(2026, 10, 26)).y, 1448);
  });
}

void arabicTests() {
  test('تفقيط المجموع كما في الشهادة', () {
    expect(arabicWords(435), 'أربعمائة وخمس وثلاثون');
    expect(arabicWords(50), 'خمسون');
    expect(arabicWords(112), 'مائة واثنتا عشرة');
    expect(arabicWords(1000), 'ألف');
    expect(arabicWords(96.5), 'ست وتسعون ونصف');
  });

  test('الترتيب بالحروف', () {
    expect(ordinalAr(6), 'السادس');
    expect(ordinalAr(1), 'الأول');
    expect(ordinalAr(25), '25');
  });
}

void licenseTests() {
  test('توقيع كود التفعيل ثابت ومطابق للمولّد', () {
    expect(License.sign('ABCD1234EF567890', 'U', '0'), '30A08449400245D3');
    expect(License.sign('ABCD1234EF567890', '500', '20271231'), '4950B0484EB260DA');
  });
}
