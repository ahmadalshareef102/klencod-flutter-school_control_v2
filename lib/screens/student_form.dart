import 'package:flutter/material.dart';
import '../app_state.dart';
import '../dates.dart';
import '../db.dart';
import '../widgets.dart';

class StudentForm extends StatefulWidget {
  final int? id;
  final int? presetClass;
  const StudentForm({super.key, this.id, this.presetClass});
  @override
  State<StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends State<StudentForm> {
  final name = TextEditingController();
  final regNo = TextEditingController();
  final section = TextEditingController(text: 'أ');
  final phone = TextEditingController();
  final guardian = TextEditingController();
  final notes = TextEditingController();
  String gender = 'ذكر', status = 'مستجد', year = '';
  int classId = 1;
  DateTime? birth;
  DateTime regDate = DateTime.now();
  List<DbRow> classes = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? _parse(Object? v) => v == null ? null : DateTime.tryParse('$v');

  Future<void> _load() async {
    classes = await Db.classes();
    year = await Db.setting('year');
    classId = widget.presetClass ?? 1;
    if (widget.id != null) {
      final r = await (await Db.get())
          .query('students', where: 'id=?', whereArgs: [widget.id]);
      if (r.isNotEmpty) {
        final s = r.first;
        name.text = '${s['name'] ?? ''}';
        regNo.text = '${s['reg_no'] ?? ''}';
        section.text = '${s['section'] ?? 'أ'}';
        phone.text = '${s['phone'] ?? ''}';
        guardian.text = '${s['guardian'] ?? ''}';
        notes.text = '${s['notes'] ?? ''}';
        gender = '${s['gender'] ?? 'ذكر'}';
        status = '${s['status'] ?? 'مستجد'}';
        classId = s['class_id'] as int;
        birth = _parse(s['birth']);
        regDate = _parse(s['reg_date']) ?? DateTime.now();
      }
    }
    if (mounted) setState(() => loading = false);
  }

  String _fmt(DateTime d) =>
      fmtDate(d, hijri: AppState.hijri.value, offset: AppState.hijriOffset);

  Future<void> _pick(bool isBirth) async {
    final init = (isBirth ? birth : regDate) ?? DateTime(2015);
    final d = await showDatePicker(
        context: context,
        initialDate: init,
        firstDate: DateTime(1980),
        lastDate: DateTime(2100));
    if (d != null) setState(() => isBirth ? birth = d : regDate = d);
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) return toast(context, 'اكتب اسم الطالب');
    final reg = regNo.text.trim().isEmpty ? null : int.tryParse(regNo.text.trim());
    if (regNo.text.trim().isNotEmpty && reg == null) {
      return toast(context, 'رقم القيد يجب أن يكون رقماً');
    }
    final m = <String, Object?>{
      'name': name.text.trim(),
      'gender': gender,
      'class_id': classId,
      'section': section.text.trim().isEmpty ? 'أ' : section.text.trim(),
      'status': status,
      'phone': phone.text.trim(),
      'guardian': guardian.text.trim(),
      'notes': notes.text.trim(),
      'birth': birth == null ? null : isoDate(birth!),
      'reg_date': isoDate(regDate),
      if (reg != null) 'reg_no': reg,
    };
    if (widget.id == null) {
      await Db.addStudent(m);
    } else {
      await Db.updateStudent(widget.id!, m);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'إضافة طالب جديد' : 'تعديل بيانات الطالب'),
        actions: [
          TextButton.icon(
              onPressed: _save, icon: const Icon(Icons.check), label: const Text('حفظ')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'اسم الطالب رباعي')),
        const SizedBox(height: 12),
        TextField(
            controller: regNo,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'رقم القيد / السجل', helperText: 'اتركه فارغاً للترقيم التلقائي')),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ذكر', label: Text('ذكر'), icon: Icon(Icons.male)),
            ButtonSegment(value: 'أنثى', label: Text('أنثى'), icon: Icon(Icons.female)),
          ],
          selected: {gender},
          onSelectionChanged: (s) => setState(() => gender = s.first),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 3,
            child: Pick<int>(
              label: 'الصف',
              value: classId,
              items: [
                for (final c in classes)
                  DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}'))
              ],
              onChanged: (v) => setState(() => classId = v!),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
                controller: section,
                decoration: const InputDecoration(labelText: 'الفصل / الشعبة')),
          ),
        ]),
        const SizedBox(height: 12),
        Pick<String>(
          label: 'حالة القيد',
          value: status,
          items: [
            for (final s in ['مستجد', 'معيد', 'محوّل'])
              DropdownMenuItem(value: s, child: Text(s))
          ],
          onChanged: (v) => setState(() => status = v!),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
                onPressed: () => _pick(false),
                icon: const Icon(Icons.event),
                label: Text('تاريخ التسجيل\n${_fmt(regDate)}', textAlign: TextAlign.center)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
                onPressed: () => _pick(true),
                icon: const Icon(Icons.cake_outlined),
                label: Text('تاريخ الميلاد\n${birth == null ? 'غير محدد' : _fmt(birth!)}',
                    textAlign: TextAlign.center)),
          ),
        ]),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'العام الدراسي'),
          child: Text(year),
        ),
        const SizedBox(height: 12),
        TextField(
            controller: guardian,
            decoration: const InputDecoration(labelText: 'اسم ولي الأمر')),
        const SizedBox(height: 12),
        TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'رقم ولي الأمر')),
        const SizedBox(height: 12),
        TextField(
            controller: notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ملاحظات')),
        const SizedBox(height: 20),
        FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('حفظ الطالب')),
      ]),
    );
  }
}
