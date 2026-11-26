/// Zaman araçları: kronometre, zamanlayıcı, alarm, dünya saati, geri
/// sayım, gece/masa saati.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:studio_core/apps/apps.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../common.dart';
import '../platform/notify.dart';

String two(int v) => v.toString().padLeft(2, '0');

String clock(Duration d, {bool centis = true}) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60, cs = (d.inMilliseconds % 1000) ~/ 10;
  final base = h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  return centis ? '$base.${two(cs)}' : base;
}

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

// ------------------------------------------------------------- kronometre

class StopwatchTool extends StatefulWidget {
  final ToolContext t;
  const StopwatchTool(this.t, {super.key});

  @override
  State<StopwatchTool> createState() => _StopwatchToolState();
}

class _StopwatchToolState extends State<StopwatchTool> {
  int _startMs = 0; // çalışırken başlangıç anı
  int _acc = 0; // birikmiş süre (ms)
  bool _running = false;
  List<int> _laps = [];
  Timer? _tick;

  ToolContext get t => widget.t;

  int get _elapsed => _acc + (_running ? _nowMs() - _startMs : 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await t.store.readMap('state');
    _acc = (m['acc'] as num?)?.toInt() ?? 0;
    _startMs = (m['start'] as num?)?.toInt() ?? 0;
    _running = m['running'] == true;
    _laps = [for (final v in (m['laps'] as List?) ?? const []) (v as num).toInt()];
    if (_running) _startTick();
    if (mounted) setState(() {});
  }

  void _save() => t.store.writeMap('state', {'acc': _acc, 'start': _startMs, 'running': _running, 'laps': _laps});

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (mounted) setState(() {});
    });
  }

  void _toggle() {
    setState(() {
      if (_running) {
        _acc = _elapsed;
        _running = false;
        _tick?.cancel();
      } else {
        _startMs = _nowMs();
        _running = true;
        _startTick();
      }
    });
    _save();
  }

  void _lapOrReset() {
    setState(() {
      if (_running) {
        _laps.insert(0, _elapsed);
      } else {
        _acc = 0;
        _laps = [];
      }
    });
    _save();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    return ToolList(children: [
      BigReadout(clock(Duration(milliseconds: _elapsed))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _elapsed == 0 ? null : _lapOrReset,
              child: Text(L(t, _running ? 'lap' : 'reset')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _running ? Colors.redAccent : s.play),
              onPressed: _toggle,
              child: Text(L(t, _running ? 'stop' : 'start')),
            ),
          ),
        ]),
      ),
      for (var i = 0; i < _laps.length; i++)
        ListTile(
          leading: Text('${L(t, 'lap')} ${_laps.length - i}'),
          title: Text(clock(Duration(milliseconds: _laps[i]))),
          trailing: Text(
            '+${clock(Duration(milliseconds: _laps[i] - (i + 1 < _laps.length ? _laps[i + 1] : 0)))}',
            style: const TextStyle(color: Colors.white60),
          ),
        ),
    ]);
  }
}

// ----------------------------------------------------------- zamanlayıcı

class TimerTool extends StatefulWidget {
  final ToolContext t;
  const TimerTool(this.t, {super.key});

  @override
  State<TimerTool> createState() => _TimerToolState();
}

class _TimerToolState extends State<TimerTool> {
  static const _notifyId = 7001;
  int _total = 5 * 60 * 1000;
  int _endMs = 0; // çalışırken bitiş anı
  int _left = 5 * 60 * 1000; // duraklatılmışken kalan
  bool _running = false;
  bool _done = false;
  Timer? _tick;
  final _beep = TonePlayer();

  ToolContext get t => widget.t;

  int get _remaining => _running ? (_endMs - _nowMs()).clamp(0, 1 << 40) : _left;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await t.store.readMap('state');
    _total = (m['total'] as num?)?.toInt() ?? _total;
    _left = (m['left'] as num?)?.toInt() ?? _total;
    _endMs = (m['end'] as num?)?.toInt() ?? 0;
    _running = m['running'] == true && _endMs > _nowMs();
    if (_running) _startTick();
    if (mounted) setState(() {});
  }

  void _save() => t.store.writeMap('state', {'total': _total, 'left': _left, 'end': _endMs, 'running': _running});

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      if (_running && _remaining <= 0) {
        _finish();
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _finish() async {
    _tick?.cancel();
    setState(() {
      _running = false;
      _done = true;
      _left = _total;
    });
    _save();
    await _beep.play(makeWav([for (var i = 0; i < 6; i++) ...[(880.0, 180), (0.0, 120)]]));
  }

  Future<void> _start() async {
    if (Notify.supported && !await t.store.readBool('notifyAsked')) {
      if (!mounted) return;
      final ok = await rationaleOnce(context, t, 'notify', Icons.notifications_active_rounded);
      if (ok) await Notify.requestPermission();
      await t.store.writeBool('notifyAsked', true);
    }
    setState(() {
      _done = false;
      _endMs = _nowMs() + _left;
      _running = true;
    });
    _startTick();
    _save();
    await Notify.schedule(_notifyId, L(t, 'times_up'), clock(Duration(milliseconds: _total), centis: false),
        DateTime.fromMillisecondsSinceEpoch(_endMs));
  }

  Future<void> _pause() async {
    _tick?.cancel();
    setState(() {
      _left = _remaining;
      _running = false;
    });
    _save();
    await Notify.cancel(_notifyId);
  }

  Future<void> _reset() async {
    _tick?.cancel();
    await _beep.stop();
    setState(() {
      _running = false;
      _done = false;
      _left = _total;
    });
    _save();
    await Notify.cancel(_notifyId);
  }

  void _setTotal(int ms) {
    if (_running) return;
    setState(() {
      _total = ms.clamp(1000, 24 * 3600 * 1000);
      _left = _total;
      _done = false;
    });
    _save();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _beep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLook.of(context);
    final rem = _remaining;
    final frac = _total == 0 ? 0.0 : rem / _total;
    return ToolList(children: [
      if (_done) AppInfoCard(L(t, 'times_up'), icon: Icons.alarm_on_rounded),
      Center(
        child: SizedBox(
          width: 240,
          height: 240,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: frac.clamp(0.0, 1.0),
                strokeWidth: 10,
                color: s.accent,
                backgroundColor: Colors.white12,
              ),
            ),
            Text(clock(Duration(milliseconds: rem + 999), centis: false),
                style: TextStyle(color: s.number, fontSize: 48, fontWeight: FontWeight.w900)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (!_running)
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final m in [1, 3, 5, 10, 15, 25, 30, 45, 60])
            ActionChip(label: Text('$m ${L(t, 'minutes')}'), onPressed: () => _setTotal(m * 60000)),
        ]),
      if (!_running)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          // Dar ekranda ve büyük yazıda alt satıra geçer.
          child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            for (final (label, ms) in [('−1m', -60000), ('−10s', -10000), ('+10s', 10000), ('+1m', 60000)])
              OutlinedButton(onPressed: () => _setTotal(_total + ms), child: Text(label)),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: OutlinedButton(onPressed: _reset, child: Text(L(t, 'reset')))),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _running ? Colors.orange : s.play),
              onPressed: _running ? _pause : _start,
              child: Text(L(t, _running ? 'pause' : 'start')),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ alarm

class _Alarm {
  int id;
  int hour;
  int minute;
  List<int> days; // 1=Pzt … 7=Paz; boşsa bir kez
  String label;
  bool on;
  _Alarm(this.id, this.hour, this.minute, this.days, this.label, this.on);

  Map<String, Object?> toJson() => {'id': id, 'h': hour, 'm': minute, 'd': days, 'l': label, 'on': on};
  static _Alarm from(Map<String, Object?> j) => _Alarm(
        (j['id'] as num).toInt(),
        (j['h'] as num).toInt(),
        (j['m'] as num).toInt(),
        [for (final v in (j['d'] as List?) ?? const []) (v as num).toInt()],
        '${j['l'] ?? ''}',
        j['on'] == true,
      );

  /// Önümüzdeki [horizon] gün içindeki çalma anları (yerel saat).
  List<DateTime> upcoming(DateTime now, {int horizon = 30}) {
    final out = <DateTime>[];
    for (var i = 0; i <= horizon; i++) {
      final d = DateTime(now.year, now.month, now.day + i, hour, minute);
      if (!d.isAfter(now)) continue;
      if (days.isEmpty || days.contains(d.weekday)) {
        out.add(d);
        if (days.isEmpty) break;
      }
    }
    return out;
  }
}

class AlarmTool extends StatefulWidget {
  final ToolContext t;
  const AlarmTool(this.t, {super.key});

  @override
  State<AlarmTool> createState() => _AlarmToolState();
}

class _AlarmToolState extends State<AlarmTool> {
  List<_Alarm> _alarms = [];
  static const _slots = 40; // her alarm için ayrılan bildirim kimliği sayısı

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _alarms = [for (final m in await t.store.readList('alarms')) _Alarm.from(m)];
    if (mounted) setState(() {});
    await _rescheduleAll();
  }

  Future<void> _save() async {
    await t.store.writeList('alarms', [for (final a in _alarms) a.toJson()]);
    await _rescheduleAll();
  }

  /// Tekrarlı alarmlar 30 gün ilerisine kadar tek tek planlanır; araç her
  /// açıldığında yenilenir.
  Future<void> _rescheduleAll() async {
    if (!Notify.supported) return;
    final now = DateTime.now();
    for (final a in _alarms) {
      for (var k = 0; k < _slots; k++) {
        await Notify.cancel(8000 + a.id * _slots + k);
      }
      if (!a.on) continue;
      final times = a.upcoming(now);
      for (var k = 0; k < times.length && k < _slots; k++) {
        await Notify.schedule(8000 + a.id * _slots + k, a.label.isEmpty ? '⏰ ${two(a.hour)}:${two(a.minute)}' : a.label,
            '${two(a.hour)}:${two(a.minute)}', times[k]);
      }
    }
  }

  Future<void> _edit([_Alarm? a]) async {
    if (Notify.supported && !await t.store.readBool('notifyAsked')) {
      if (!mounted) return;
      final ok = await rationaleOnce(context, t, 'notify', Icons.notifications_active_rounded);
      if (ok) await Notify.requestPermission();
      await t.store.writeBool('notifyAsked', true);
    }
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: a == null ? const TimeOfDay(hour: 7, minute: 0) : TimeOfDay(hour: a.hour, minute: a.minute),
    );
    if (time == null || !mounted) return;
    setState(() {
      if (a == null) {
        var id = 0;
        while (_alarms.any((x) => x.id == id)) {
          id++;
        }
        _alarms.add(_Alarm(id, time.hour, time.minute, [], '', true));
      } else {
        a.hour = time.hour;
        a.minute = time.minute;
        a.on = true;
      }
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final s = AppLook.of(context);
    // narrowWeekdays: Pazar ile başlar; DateTime.weekday 1=Pzt…7=Paz.
    String dayName(int wd) => loc.narrowWeekdays[wd % 7];
    return ToolList(children: [
      if (!Notify.supported) notAvailable(t),
      for (final a in _alarms)
        AppPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              InkWell(
                onTap: () => _edit(a),
                child: Text(loc.formatTimeOfDay(TimeOfDay(hour: a.hour, minute: a.minute)),
                    style: TextStyle(
                        fontSize: 40, fontWeight: FontWeight.w800, color: a.on ? Colors.white : Colors.white38)),
              ),
              const Spacer(),
              Switch(
                value: a.on,
                onChanged: (v) {
                  setState(() => a.on = v);
                  _save();
                },
              ),
              IconButton(
                tooltip: L(t, 'delete'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  a.on = false;
                  await _rescheduleAll();
                  setState(() => _alarms.remove(a));
                  await _save();
                },
              ),
            ]),
            Wrap(spacing: 4, children: [
              for (final wd in [1, 2, 3, 4, 5, 6, 7])
                FilterChip(
                  label: Text(dayName(wd)),
                  selected: a.days.contains(wd),
                  selectedColor: s.accent.withValues(alpha: 0.4),
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        a.days.add(wd);
                      } else {
                        a.days.remove(wd);
                      }
                    });
                    _save();
                  },
                ),
            ]),
            TextFormField(
              initialValue: a.label,
              decoration: InputDecoration(labelText: L(t, 'label')),
              onFieldSubmitted: (v) {
                a.label = v;
                _save();
              },
              onChanged: (v) => a.label = v,
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: AppButton(label: L(t, 'add'), icon: Icons.add_alarm_rounded, onPressed: () => _edit()),
      ),
      AppInfoCard(L(t, 'alarm_note'), icon: Icons.info_outline_rounded),
    ]);
  }
}

// ------------------------------------------------------------- dünya saati

bool _tzReady = false;
void _initTz() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

class WorldClockTool extends StatefulWidget {
  final ToolContext t;
  const WorldClockTool(this.t, {super.key});

  @override
  State<WorldClockTool> createState() => _WorldClockToolState();
}

class _WorldClockToolState extends State<WorldClockTool> {
  static const _defaults = [
    'Europe/Istanbul', 'Europe/London', 'America/New_York', 'Asia/Tokyo', 'Asia/Dubai', 'Australia/Sydney',
  ];
  List<String> _zones = [];
  Timer? _tick;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _initTz();
    t.store.readStrings('zones').then((z) {
      if (mounted) setState(() => _zones = z.isEmpty ? [..._defaults] : z);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _city(String id) => id.split('/').last.replaceAll('_', ' ');

  Future<void> _add() async {
    final all = tz.timeZoneDatabase.locations.keys.where((k) => k.contains('/') && !k.startsWith('Etc')).toList()..sort();
    final picked = await showDialog<String>(context: context, builder: (c) => _ZonePicker(all: all, hint: t.tx('search')));
    if (picked != null && !_zones.contains(picked)) {
      setState(() => _zones.add(picked));
      await t.store.writeStrings('zones', _zones);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final now = DateTime.now();
    return ToolList(children: [
      BigReadout(loc.formatTimeOfDay(TimeOfDay.fromDateTime(now)), caption: loc.formatFullDate(now)),
      for (final z in _zones)
        Builder(builder: (context) {
          final l = tz.timeZoneDatabase.locations[z];
          if (l == null) return const SizedBox();
          final n = tz.TZDateTime.now(l);
          final off = n.timeZoneOffset - now.timeZoneOffset;
          final h = off.inMinutes / 60;
          final diff = h == 0 ? '±0' : '${h > 0 ? '+' : ''}${formatNumber(h, digits: 2)} h';
          return Dismissible(
            key: ValueKey(z),
            onDismissed: (_) {
              setState(() => _zones.remove(z));
              t.store.writeStrings('zones', _zones);
            },
            child: AppPanel(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_city(z), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('$diff · ${n.timeZoneName}', style: const TextStyle(color: Colors.white60)),
                  ]),
                ),
                Text('${two(n.hour)}:${two(n.minute)}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              ]),
            ),
          );
        }),
      Padding(
        padding: const EdgeInsets.all(16),
        child: AppButton(label: L(t, 'add'), icon: Icons.add_location_alt_rounded, onPressed: _add),
      ),
    ]);
  }
}

class _ZonePicker extends StatefulWidget {
  final List<String> all;
  final String hint;
  const _ZonePicker({required this.all, required this.hint});

  @override
  State<_ZonePicker> createState() => _ZonePickerState();
}

class _ZonePickerState extends State<_ZonePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = [for (final z in widget.all) if (z.toLowerCase().contains(_q.toLowerCase())) z];
    return AlertDialog(
      title: TextField(
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint, prefixIcon: const Icon(Icons.search_rounded)),
        onChanged: (v) => setState(() => _q = v),
      ),
      content: SizedBox(
        width: 400,
        height: 420,
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => ListTile(
            title: Text(list[i].split('/').last.replaceAll('_', ' ')),
            subtitle: Text(list[i]),
            onTap: () => Navigator.pop(context, list[i]),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- geri sayım

class CountdownTool extends StatefulWidget {
  final ToolContext t;
  const CountdownTool(this.t, {super.key});

  @override
  State<CountdownTool> createState() => _CountdownToolState();
}

class _CountdownToolState extends State<CountdownTool> {
  List<Map<String, Object?>> _events = [];
  Timer? _tick;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    t.store.readList('events').then((e) {
      if (mounted) setState(() => _events = e);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (date == null || !mounted) {
      name.dispose();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L(t, 'event')),
        content: AppTextField(controller: name, label: L(t, 'name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.core('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.core('ok'))),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _events.add({'name': name.text.trim().isEmpty ? L(t, 'event') : name.text.trim(), 'at': date.toIso8601String()}));
      await t.store.writeList('events', _events);
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final sorted = [..._events]..sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
    return ToolList(children: [
      for (final e in sorted)
        Builder(builder: (context) {
          final at = DateTime.tryParse('${e['at']}') ?? now;
          final diff = at.difference(now);
          final past = diff.isNegative;
          final d = diff.abs();
          return Dismissible(
            key: ValueKey('${e['name']}${e['at']}'),
            onDismissed: (_) {
              setState(() => _events.remove(e));
              t.store.writeList('events', _events);
            },
            child: AppPanel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(loc.formatFullDate(at), style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 6),
                Text(
                  '${d.inDays} ${L(t, 'days')} ${d.inHours % 24} ${L(t, 'hours')} ${d.inMinutes % 60} ${L(t, 'minutes')} ${d.inSeconds % 60} ${L(t, 'seconds')}${past ? ' ${L(t, 'passed')}' : ''}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: past ? Colors.white54 : AppLook.of(context).number),
                ),
              ]),
            ),
          );
        }),
      Padding(
        padding: const EdgeInsets.all(16),
        child: AppButton(label: L(t, 'add'), icon: Icons.event_available_rounded, onPressed: _add),
      ),
    ]);
  }
}

// ---------------------------------------------------------- gece saati

class NightClockTool extends StatefulWidget {
  final ToolContext t;
  const NightClockTool(this.t, {super.key});

  @override
  State<NightClockTool> createState() => _NightClockToolState();
}

class _NightClockToolState extends State<NightClockTool> {
  bool _red = true;
  bool _awake = true;
  double _dim = 0.6;
  Timer? _tick;

  ToolContext get t => widget.t;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _setAwake(true);
  }

  void _setAwake(bool v) {
    _awake = v;
    WakelockPlus.toggle(enable: v).catchError((Object _) {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    WakelockPlus.disable().catchError((Object _) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final loc = MaterialLocalizations.of(context);
    final color = (_red ? Colors.redAccent : Colors.white).withValues(alpha: 1 - _dim * 0.85);
    return Column(children: [
      Expanded(
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text('${two(now.hour)}:${two(now.minute)}',
                    style: TextStyle(color: color, fontSize: 140, fontWeight: FontWeight.w300, height: 1)),
                Text(loc.formatFullDate(now), style: TextStyle(color: color, fontSize: 22)),
              ]),
            ),
          ),
        ),
      ),
      Container(
        color: Colors.black,
        child: Column(children: [
          Slider(value: _dim, onChanged: (v) => setState(() => _dim = v)),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            FilterChip(label: Text(L(t, 'night_red')), selected: _red, onSelected: (v) => setState(() => _red = v)),
            FilterChip(
              label: Text(L(t, 'keep_awake')),
              selected: _awake,
              onSelected: (v) => setState(() => _setAwake(v)),
            ),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    ]);
  }
}
