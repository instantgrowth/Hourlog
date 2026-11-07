import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------- Model ----------
class Entry {
  Entry({
    required this.id,
    required this.start,
    required this.end,
    required this.project,
    required this.rate,
  });
  final String id;
  final DateTime start, end;
  final String project;
  final double rate;

  Duration get dur => end.difference(start);
  double get earn => dur.inMinutes / 60 * rate;

  Map<String, dynamic> toJson() => {
        'id': id,
        's': start.toIso8601String(),
        'e': end.toIso8601String(),
        'p': project,
        'r': rate,
      };
  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'],
        start: DateTime.parse(j['s']),
        end: DateTime.parse(j['e']),
        project: j['p'],
        rate: (j['r'] as num).toDouble(),
      );
}

// ---------- Store ----------
class Store extends ChangeNotifier {
  List<Entry> entries = [];
  List<String> projects = ['Uncategorized'];
  double rate = 13;
  String currency = '\$';
  double dayGoal = 8;
  double weekGoal = 40;
  DateTime? active;
  String activeProject = 'Uncategorized';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('data');
    if (raw == null) return;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    entries = (m['entries'] as List)
        .map((e) => Entry.fromJson(e as Map<String, dynamic>))
        .toList();
    projects = List<String>.from(m['projects']);
    rate = (m['rate'] as num).toDouble();
    currency = m['currency'];
    dayGoal = (m['dayGoal'] as num).toDouble();
    weekGoal = (m['weekGoal'] as num).toDouble();
    active = m['active'] == null ? null : DateTime.parse(m['active']);
    activeProject = m['activeProject'] ?? 'Uncategorized';
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'data',
        jsonEncode({
          'entries': entries.map((e) => e.toJson()).toList(),
          'projects': projects,
          'rate': rate,
          'currency': currency,
          'dayGoal': dayGoal,
          'weekGoal': weekGoal,
          'active': active?.toIso8601String(),
          'activeProject': activeProject,
        }));
  }

  void changed() {
    entries.sort((a, b) => b.start.compareTo(a.start));
    notifyListeners();
    save();
  }

  void punchIn() {
    active = DateTime.now();
    changed();
  }

  void punchOut() {
    if (active == null) return;
    final now = DateTime.now();
    if (now.difference(active!).inMinutes >= 1) {
      entries.add(Entry(
        id: now.microsecondsSinceEpoch.toString(),
        start: active!,
        end: now,
        project: activeProject,
        rate: rate,
      ));
    }
    active = null;
    changed();
  }

  void addEntry(DateTime s, DateTime e, String project) {
    entries.add(Entry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      start: s,
      end: e,
      project: project,
      rate: rate,
    ));
    changed();
  }

  void removeEntry(String id) {
    entries.removeWhere((e) => e.id == id);
    changed();
  }

  void addProject(String name) {
    if (name.trim().isEmpty || projects.contains(name.trim())) return;
    projects.add(name.trim());
    changed();
  }

  void removeProject(String name) {
    if (name == 'Uncategorized') return;
    projects.remove(name);
    changed();
  }

  void setSettings({double? rate, String? currency, double? day, double? week}) {
    if (rate != null) this.rate = rate;
    if (currency != null) this.currency = currency;
    if (day != null) dayGoal = day;
    if (week != null) weekGoal = week;
    changed();
  }

  Iterable<Entry> between(DateTime a, DateTime b) =>
      entries.where((e) => !e.start.isBefore(a) && e.start.isBefore(b));
  Duration total(Iterable<Entry> l) =>
      l.fold(Duration.zero, (a, e) => a + e.dur);
  double money(Iterable<Entry> l) => l.fold(0.0, (a, e) => a + e.earn);

  String m(double v) => '$currency${v.toStringAsFixed(2)}';
}

String fmt(Duration d) => '${d.inHours}h ${d.inMinutes % 60}m';
const months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December'
];
const wd = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
String t12(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  return '$h:$mm ${d.hour >= 12 ? 'PM' : 'AM'}';
}

// ---------- App ----------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.load();
  runApp(HourLogApp(store: store));
}

class HourLogApp extends StatelessWidget {
  const HourLogApp({super.key, required this.store});
  final Store store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HourLog',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF5B8C00),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: HomePage(store: store),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});
  final Store store;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 3 - 1; // start on Time Card (index 2)

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final pages = <Widget>[
      OverviewPage(s: s),
      ProjectsPage(s: s),
      TimeCardPage(s: s),
      TimeSheetsPage(s: s),
      SettingsPage(s: s),
    ];
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (_, __) => IndexedStack(index: tab, children: pages),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.folder_open), label: 'Projects'),
          NavigationDestination(icon: Icon(Icons.access_time), label: 'Time Card'),
          NavigationDestination(icon: Icon(Icons.description_outlined), label: 'Time Sheets'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

// ---------- Shared widgets ----------
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.color, required this.icon, required this.title, required this.sub});
  final Color color;
  final IconData icon;
  final String title, sub;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Icon(icon, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text(sub, style: const TextStyle(color: Colors.black54)),
            ]),
          ),
        ]),
      );
}

Widget heading(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Text(t, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
    );

// ---------- Time Card ----------
class TimeCardPage extends StatefulWidget {
  const TimeCardPage({super.key, required this.s});
  final Store s;
  @override
  State<TimeCardPage> createState() => _TimeCardPageState();
}

class _TimeCardPageState extends State<TimeCardPage> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.s.active != null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayList = s.between(today, DateTime(now.year, now.month, now.day + 1));
    var dayTotal = s.total(todayList);
    var dayMoney = s.money(todayList);
    final running = s.active != null ? now.difference(s.active!) : Duration.zero;
    final periodStart = DateTime(now.year, now.month, 1);
    final periodMoney = s.money(s.between(periodStart, DateTime(now.year, now.month + 1, 1)));

    return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
      heading('Time Card'),
      Row(children: [
        Expanded(child: StatCard(color: const Color(0xFFEFEDFF), icon: Icons.access_time, title: fmt(dayTotal + running), sub: 'Day total')),
        const SizedBox(width: 12),
        Expanded(child: StatCard(color: const Color(0xFFF3FFE0), icon: Icons.monetization_on_outlined, title: s.m(periodMoney + dayMoney * 0), sub: 'Month earnings')),
      ]),
      const SizedBox(height: 28),
      if (s.projects.length > 1 && s.active == null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<String>(
            value: s.activeProject,
            decoration: const InputDecoration(labelText: 'Project', border: OutlineInputBorder()),
            items: s.projects.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: (v) {
              s.activeProject = v!;
              s.changed();
            },
          ),
        ),
      InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => s.active == null ? s.punchIn() : s.punchOut(),
        child: Container(
          height: 190,
          decoration: BoxDecoration(
            color: s.active == null ? const Color(0xFFD9F57F) : const Color(0xFFFFD6D6),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(s.active == null ? 'Punch in' : 'Punch out',
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: s.active == null ? const Color(0xFF4C7A00) : const Color(0xFFB00020))),
              if (s.active != null) ...[
                const SizedBox(height: 8),
                Text(_clock(running), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
                Text('since ${t12(s.active!)}'),
              ],
            ]),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: Text('OR', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black54))),
      ),
      InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddEntryPage(s: s))),
        child: Container(
          height: 150,
          decoration: BoxDecoration(color: const Color(0xFFD1C9FF), borderRadius: BorderRadius.circular(24)),
          child: const Center(
            child: Text('Add Entry', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: Color(0xFF6A5CAF))),
          ),
        ),
      ),
    ]);
  }

  String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }
}

// ---------- Add entry ----------
class AddEntryPage extends StatefulWidget {
  const AddEntryPage({super.key, required this.s});
  final Store s;
  @override
  State<AddEntryPage> createState() => _AddEntryPageState();
}

class _AddEntryPageState extends State<AddEntryPage> {
  late DateTime start;
  late DateTime end;
  String project = 'Uncategorized';

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    start = DateTime(n.year, n.month, n.day, 9);
    end = DateTime(n.year, n.month, n.day, 17);
  }

  Future<DateTime?> pick(DateTime init) async {
    final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(init));
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final dur = end.difference(start);
    return Scaffold(
      appBar: AppBar(title: const Text('Add Entry')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(
          title: const Text('Start'),
          subtitle: Text('${start.day}/${start.month}/${start.year}  ${t12(start)}'),
          trailing: const Icon(Icons.edit_calendar),
          onTap: () async {
            final v = await pick(start);
            if (v != null) setState(() => start = v);
          },
        ),
        ListTile(
          title: const Text('End'),
          subtitle: Text('${end.day}/${end.month}/${end.year}  ${t12(end)}'),
          trailing: const Icon(Icons.edit_calendar),
          onTap: () async {
            final v = await pick(end);
            if (v != null) setState(() => end = v);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: project,
          decoration: const InputDecoration(labelText: 'Project', border: OutlineInputBorder()),
          items: widget.s.projects.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: (v) => setState(() => project = v!),
        ),
        const SizedBox(height: 16),
        Text(dur.isNegative ? 'End must be after start' : 'Total: ${fmt(dur)}  •  ${widget.s.m(dur.inMinutes / 60 * widget.s.rate)}',
            style: TextStyle(fontSize: 18, color: dur.isNegative ? Colors.red : Colors.black87)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: dur.inMinutes <= 0
              ? null
              : () {
                  widget.s.addEntry(start, end, project);
                  Navigator.pop(context);
                },
          child: const Padding(padding: EdgeInsets.all(14), child: Text('Save', style: TextStyle(fontSize: 18))),
        ),
      ]),
    );
  }
}

// ---------- Overview ----------
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.s});
  final Store s;

  Widget ring(String title, IconData icon, Duration done, double goalH, double money, Color c) {
    final p = goalH == 0 ? 0.0 : (done.inMinutes / 60 / goalH).clamp(0.0, 1.0);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFF7F7F7), borderRadius: BorderRadius.circular(22)),
        child: Column(children: [
          Row(children: [Icon(icon, color: c), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 16),
          SizedBox(
            width: 130,
            height: 130,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(child: CircularProgressIndicator(value: p, strokeWidth: 8, color: c, backgroundColor: c.withOpacity(0.2))),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(fmt(done), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('of ${goalH.toStringAsFixed(0)}h', style: const TextStyle(color: Colors.black54)),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          Text(s.m(money), style: const TextStyle(fontSize: 16, color: Colors.black54)),
        ]),
      ),
    );
  }

  Widget monthCard(DateTime first) {
    final l = s.between(first, DateTime(first.year, first.month + 1, 1));
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFF7F7F7), borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fmt(s.total(l)), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(s.m(s.money(l)), style: const TextStyle(fontSize: 20, color: Colors.black54, fontWeight: FontWeight.w600)),
          Text(months[first.month - 1], style: const TextStyle(color: Colors.black54)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final weekStart = today.subtract(Duration(days: n.weekday - 1));
    final dayL = s.between(today, DateTime(n.year, n.month, n.day + 1));
    final weekL = s.between(weekStart, DateTime(weekStart.year, weekStart.month, weekStart.day + 7));
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
      heading('Overview'),
      Row(children: [
        ring('Day', Icons.today, s.total(dayL), s.dayGoal, s.money(dayL), const Color(0xFF8E7CF0)),
        const SizedBox(width: 12),
        ring('Week', Icons.date_range, s.total(weekL), s.weekGoal, s.money(weekL), const Color(0xFF5B8C00)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        monthCard(DateTime(n.year, n.month - 1, 1)),
        const SizedBox(width: 12),
        monthCard(DateTime(n.year, n.month, 1)),
      ]),
    ]);
  }
}

// ---------- Time Sheets ----------
class TimeSheetsPage extends StatefulWidget {
  const TimeSheetsPage({super.key, required this.s});
  final Store s;
  @override
  State<TimeSheetsPage> createState() => _TimeSheetsPageState();
}

class _TimeSheetsPageState extends State<TimeSheetsPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final list = s.between(month, DateTime(month.year, month.month + 1, 1)).toList();
    final days = list.map((e) => '${e.start.year}-${e.start.month}-${e.start.day}').toSet().length;
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
      heading('Time Sheets'),
      Row(children: [
        IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1, 1)), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text('${months[month.month - 1]} ${month.year}',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF4C7A00))),
        ),
        IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1, 1)), icon: const Icon(Icons.chevron_right)),
      ]),
      Row(children: [
        Expanded(child: StatCard(color: const Color(0xFFF5F5F5), icon: Icons.calendar_month, title: '$days', sub: 'Days worked')),
        const SizedBox(width: 12),
        Expanded(child: StatCard(color: const Color(0xFFF5F5F5), icon: Icons.access_time, title: fmt(s.total(list)), sub: 'Total time')),
      ]),
      const SizedBox(height: 12),
      StatCard(color: const Color(0xFFF5F5F5), icon: Icons.monetization_on_outlined, title: s.m(s.money(list)), sub: 'Total earnings'),
      const SizedBox(height: 12),
      if (list.isEmpty)
        const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No entries this month')))
      else
        ...list.map((e) => Dismissible(
              key: ValueKey(e.id),
              direction: DismissDirection.endToStart,
              background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
              onDismissed: (_) => s.removeEntry(e.id),
              child: ListTile(
                leading: Container(
                  width: 52,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(border: Border.all(color: Colors.black38), borderRadius: BorderRadius.circular(8)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(wd[e.start.weekday - 1], style: const TextStyle(fontSize: 11)),
                    Text('${e.start.day}', style: const TextStyle(fontSize: 20)),
                  ]),
                ),
                title: Text('${t12(e.start)} - ${t12(e.end)}'),
                subtitle: Text(e.project),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fmt(e.dur), style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(s.m(e.earn)),
                ]),
              ),
            )),
    ]);
  }
}

// ---------- Projects ----------
class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key, required this.s});
  final Store s;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
      heading('Projects'),
      ...s.projects.map((p) {
        final l = s.entries.where((e) => e.project == p);
        return Card(
          elevation: 0,
          color: const Color(0xFFF7F7F7),
          child: ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(p),
            subtitle: Text('${fmt(s.total(l))}  •  ${s.m(s.money(l))}'),
            trailing: p == 'Uncategorized'
                ? null
                : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => s.removeProject(p)),
          ),
        );
      }),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('New project'),
        onPressed: () async {
          final v = await askText(context, 'New project', '');
          if (v != null) s.addProject(v);
        },
      ),
    ]);
  }
}

// ---------- Settings ----------
Future<String?> askText(BuildContext context, String title, String initial, {bool number = false}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('OK')),
      ],
    ),
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.s});
  final Store s;

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      heading('Settings'),
      ListTile(
        leading: const Icon(Icons.attach_money),
        title: const Text('Hourly rate'),
        subtitle: Text(s.m(s.rate)),
        onTap: () async {
          final v = await askText(context, 'Hourly rate', s.rate.toString(), number: true);
          final d = double.tryParse(v ?? '');
          if (d != null) s.setSettings(rate: d);
        },
      ),
      ListTile(
        leading: const Icon(Icons.currency_exchange),
        title: const Text('Currency symbol'),
        subtitle: Text(s.currency),
        onTap: () async {
          final v = await askText(context, 'Currency symbol', s.currency);
          if (v != null && v.isNotEmpty) s.setSettings(currency: v);
        },
      ),
      ListTile(
        leading: const Icon(Icons.today),
        title: const Text('Daily goal (hours)'),
        subtitle: Text(s.dayGoal.toStringAsFixed(0)),
        onTap: () async {
          final v = await askText(context, 'Daily goal (hours)', s.dayGoal.toString(), number: true);
          final d = double.tryParse(v ?? '');
          if (d != null) s.setSettings(day: d);
        },
      ),
      ListTile(
        leading: const Icon(Icons.date_range),
        title: const Text('Weekly goal (hours)'),
        subtitle: Text(s.weekGoal.toStringAsFixed(0)),
        onTap: () async {
          final v = await askText(context, 'Weekly goal (hours)', s.weekGoal.toString(), number: true);
          final d = double.tryParse(v ?? '');
          if (d != null) s.setSettings(week: d);
        },
      ),
      const Divider(),
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('HourLog v1.0'),
        subtitle: Text('Data is stored on this device only.'),
      ),
    ]);
  }
}
