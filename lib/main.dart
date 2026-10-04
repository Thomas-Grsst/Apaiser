import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// Palette de l'artefact Zen
const kInk = Color(0xFF3B2630);
const kMuted = Color(0xFF7A5F69);
const kBerry = Color(0xFFA8325A);
const kBerryDark = Color(0xFF7E1F42);
const kPink = Color(0xFFFDE4EB);
const kPinkSoft = Color(0xFFFFF9FB);
const kPinkLine = Color(0xFFF2D7DF);
const kPinkLine2 = Color(0xFFF6E3E9);
const kRose = Color(0xFFF48FAE);
const kSun = Color(0xFFFFF6D1);
const kSunLine = Color(0xFFF3DC86);
const kSunInk = Color(0xFF7A5600);
const kSunIcon = Color(0xFFC99A00);
const kDisabled = Color(0xFFE9C3CF);

class Level {
  final int id;
  final String label;
  final Color color;
  const Level(this.id, this.label, this.color);
}

const levels = [
  Level(1, 'Agacé', Color(0xFFFFD95A)),
  Level(2, 'Énervé', Color(0xFFFFB27A)),
  Level(3, 'Très énervé', Color(0xFFF48FAE)),
  Level(4, 'À bout', Color(0xFFD64576)),
  Level(5, 'Triste', Color(0xFF8FB8E8)),
];

Level levelById(int id) =>
    levels.firstWhere((l) => l.id == id, orElse: () => levels[1]);

// Temps pour redescendre après avoir déposé quelque chose
const cooldown = Duration(minutes: 15);

const defaultPhrases = [
  "Je n'ai pas besoin de répondre tout de suite.",
  'Respire. Ce moment va passer.',
  'On est dans la même équipe.',
  'Est-ce que ça comptera encore dans une semaine ?',
  'Je peux être énervé et rester gentil.',
  'Je reparlerai de ça quand je serai calme.',
];

class Note {
  final int id;
  final String text;
  final int level;
  final int at; // millisecondes epoch
  bool calm;
  Note(this.id, this.text, this.level, this.at, this.calm);

  Map<String, dynamic> toJson() =>
      {'id': id, 'text': text, 'level': level, 'at': at, 'calm': calm};
  factory Note.fromJson(Map<String, dynamic> j) =>
      Note(j['id'], j['text'], j['level'], j['at'], j['calm'] ?? false);
}

// Notification permanente « le temps de redescendre » : le compte à rebours
// est géré par Android (chronomètre), il continue même app fermée.
class CooldownNotifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _ongoingId = 1;
  static const _doneId = 2;

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_zen'),
      ),
    );
  }

  static Future<void> start(int endMs) async {
    await _android?.requestNotificationsPermission();
    final remaining = endMs - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return;

    await _plugin.show(
      id: _ongoingId,
      title: 'Le temps de redescendre',
      body: 'Prends ce moment pour toi.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'zen_timer',
          'Minuteur',
          channelDescription: 'Le compte à rebours pour redescendre',
          icon: 'ic_stat_zen',
          color: kBerry,
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          when: endMs,
          usesChronometer: true,
          chronometerCountDown: true,
          timeoutAfter: remaining,
          category: AndroidNotificationCategory.stopwatch,
        ),
      ),
    );

    final exact = await _android?.canScheduleExactNotifications() ?? false;
    await _plugin.zonedSchedule(
      id: _doneId,
      title: "C'est bon, tu es redescendu.",
      body: 'Tu peux y retourner, calmement.',
      scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, endMs),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'zen_done',
          'Fin du minuteur',
          channelDescription: 'Prévient quand le temps de redescendre est passé',
          icon: 'ic_stat_zen',
          color: kBerry,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> stop() async {
    await _plugin.cancel(id: _ongoingId);
    await _plugin.cancel(id: _doneId);
  }

  static Future<void> clearOngoing() => _plugin.cancel(id: _ongoingId);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CooldownNotifier.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const ZenApp());
}

class ZenApp extends StatelessWidget {
  const ZenApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: GoogleFonts.nunito().fontFamily,
      colorScheme: ColorScheme.fromSeed(seedColor: kBerry, surface: Colors.white),
      scaffoldBackgroundColor: Colors.white,
    );
    return MaterialApp(
      title: 'Zen',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: base.textTheme.apply(bodyColor: kInk, displayColor: kInk),
      ),
      home: const ZenHome(),
    );
  }
}

class ZenHome extends StatefulWidget {
  const ZenHome({super.key});
  @override
  State<ZenHome> createState() => _ZenHomeState();
}

class _ZenHomeState extends State<ZenHome> {
  int tab = 0;
  SharedPreferences? prefs;
  List<Note> notes = [];
  List<String> phrases = List.of(defaultPhrases);
  int cur = 0;

  // Minuteur « le temps de redescendre » (fin en ms epoch, survit à la fermeture)
  int? calmUntil;
  bool calmDone = false;
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  int get remainingMs =>
      calmUntil == null ? 0 : calmUntil! - DateTime.now().millisecondsSinceEpoch;

  void startCooldown() {
    calmUntil = DateTime.now().add(cooldown).millisecondsSinceEpoch;
    calmDone = false;
    prefs?.setInt('calmUntil', calmUntil!);
    CooldownNotifier.start(calmUntil!);
    _tick();
  }

  void stopCooldown() {
    ticker?.cancel();
    CooldownNotifier.stop();
    prefs?.remove('calmUntil');
    setState(() {
      calmUntil = null;
      calmDone = false;
    });
  }

  void _tick() {
    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (remainingMs <= 0) {
        ticker?.cancel();
        prefs?.remove('calmUntil');
        CooldownNotifier.clearOngoing();
        HapticFeedback.mediumImpact();
        setState(() {
          calmUntil = null;
          calmDone = true;
        });
      } else {
        setState(() {});
      }
    });
    setState(() {});
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final rawNotes = p.getString('notes');
    final rawPhrases = p.getStringList('phrases');
    final until = p.getInt('calmUntil');
    if (until != null) {
      if (until > DateTime.now().millisecondsSinceEpoch) {
        calmUntil = until;
        CooldownNotifier.start(until);
        _tick();
      } else {
        p.remove('calmUntil');
      }
    }
    setState(() {
      prefs = p;
      if (rawNotes != null) {
        notes = (jsonDecode(rawNotes) as List)
            .map((e) => Note.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (rawPhrases != null) phrases = rawPhrases;
    });
  }

  void _save() {
    prefs?.setString('notes', jsonEncode(notes.map((n) => n.toJson()).toList()));
    prefs?.setStringList('phrases', phrases);
  }

  void update(VoidCallback fn) {
    setState(fn);
    _save();
  }

  static const heads = [
    ["Ce qui m'énerve", 'Écris-le ici, ça sort de ta tête.'],
    ['Redescends doucement', 'Tes phrases pour retrouver ton calme.'],
    ['Respire un coup', 'Une minute pour toi, avant de répondre.'],
  ];

  @override
  Widget build(BuildContext context) {
    final body = switch (tab) {
      0 => VentTab(state: this),
      1 => CalmTab(state: this),
      _ => const BreathTab(),
    };
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ZEN',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                color: kBerry)),
                        const SizedBox(height: 4),
                        Text(heads[tab][0],
                            style: const TextStyle(
                                fontSize: 28, height: 1.15, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(heads[tab][1],
                            style: const TextStyle(fontSize: 15, color: kMuted)),
                      ],
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: kSun, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.wb_sunny_outlined, color: kSunIcon),
                  ),
                ],
              ),
            ),
            if (calmUntil != null || calmDone) _cooldownCard(),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFFBEAF0), width: 1.5)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                _navBtn(0, Icons.edit_outlined, 'Défouloir'),
                const SizedBox(width: 8),
                _navBtn(1, Icons.favorite_border, 'Apaiser'),
                const SizedBox(width: 8),
                _navBtn(2, Icons.air, 'Respirer'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cooldownCard() {
    final done = calmDone;
    final left = Duration(milliseconds: remainingMs.clamp(0, cooldown.inMilliseconds));
    final mm = left.inMinutes.toString().padLeft(2, '0');
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
    final progress = 1 - left.inMilliseconds / cooldown.inMilliseconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 6, 14),
        decoration: BoxDecoration(
          color: kSun,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kSunLine, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(done ? Icons.check_circle_outline : Icons.hourglass_bottom,
                color: kSunInk),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(done ? "C'est bon, tu es redescendu." : 'Le temps de redescendre',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800, color: kSunInk)),
                  const SizedBox(height: 4),
                  if (done)
                    const Text('Tu peux y retourner, calmement.',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))
                  else ...[
                    Text('$mm:$ss',
                        style: const TextStyle(
                            fontSize: 26,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            fontFeatures: [FontFeature.tabularFigures()])),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        color: kRose,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: done ? 'Fermer' : 'Arrêter le minuteur',
              onPressed: stopCooldown,
              icon: const Icon(Icons.close, size: 20, color: kSunInk),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navBtn(int i, IconData icon, String label) {
    final on = tab == i;
    final color = on ? kBerry : kMuted;
    return Expanded(
      child: Material(
        color: on ? kPink : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            FocusScope.of(context).unfocus();
            setState(() => tab = i);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Widgets partagés ----------

InputDecoration fieldDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFB9A3AD)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: kPinkLine, width: 1.5)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: kBerry, width: 1.5)),
    );

class PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final double? width;
  const PrimaryButton({super.key, this.onPressed, required this.child, this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: kBerry,
          disabledBackgroundColor: kDisabled,
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        child: child,
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final bool done;
  final Color? bg;
  final Color? border;
  const GhostButton(
      {super.key,
      required this.onPressed,
      required this.child,
      this.done = false,
      this.bg,
      this.border});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: done ? kSun : (bg ?? Colors.white),
          foregroundColor: done ? kSunInk : kBerry,
          side: BorderSide(
              color: done ? kSunLine : (border ?? kPinkLine), width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        child: child,
      ),
    );
  }
}

Widget dot(Color c, [double size = 10]) => Container(
    width: size, height: size, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

// ---------- Défouloir ----------

class VentTab extends StatefulWidget {
  final _ZenHomeState state;
  const VentTab({super.key, required this.state});
  @override
  State<VentTab> createState() => _VentTabState();
}

class _VentTabState extends State<VentTab> {
  final ctrl = TextEditingController();
  int level = 2;
  String? toast;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _deposit() {
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    final s = widget.state;
    final ph = s.phrases;
    final pick = ph.isEmpty
        ? 'Respire. Ce moment va passer.'
        : ph[Random().nextInt(ph.length)];
    final id = s.notes.isEmpty ? 1 : s.notes.map((n) => n.id).reduce(max) + 1;
    s.update(() {
      s.notes.insert(0, Note(id, text, level, DateTime.now().millisecondsSinceEpoch, false));
    });
    s.startCooldown();
    ctrl.clear();
    FocusScope.of(context).unfocus();
    setState(() => toast = pick);
  }

  String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    const jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    final label = diff == 0
        ? "Aujourd'hui"
        : diff == 1
            ? 'Hier'
            : diff < 7
                ? jours[d.weekday - 1]
                : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return '$label · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final calmCount = s.notes.where((n) => n.calm).length;
    final total = s.notes.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration:
              BoxDecoration(color: kPink, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Qu'est-ce qui t'énerve, là ?",
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: kBerryDark)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 16, height: 1.45, color: kInk),
                decoration: fieldDecoration('Écris-le tel quel. Personne ne le lira.'),
              ),
              const SizedBox(height: 14),
              const Text('À quel point ?',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: kBerryDark)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final lv in levels) _pill(lv),
                ],
              ),
              const SizedBox(height: 14),
              PrimaryButton(
                onPressed: ctrl.text.trim().isEmpty ? null : _deposit,
                child: const Text('Déposer ici'),
              ),
            ],
          ),
        ),
        if (toast != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
            decoration:
                BoxDecoration(color: kSun, borderRadius: BorderRadius.circular(20)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("C'est déposé. Une phrase pour toi :",
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800, color: kSunInk)),
                      const SizedBox(height: 4),
                      Text(toast!,
                          style: const TextStyle(
                              fontSize: 18, height: 1.35, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () => setState(() => toast = null),
                  icon: const Icon(Icons.close, color: Color(0xFF9C8790), size: 20),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Expanded(
              child: Text("Ce que j'ai déposé",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Text(
                '$total déposé${total > 1 ? 's' : ''} · $calmCount apaisé${calmCount > 1 ? 's' : ''}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: kMuted)),
          ],
        ),
        const SizedBox(height: 20),
        if (s.notes.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kPinkLine, width: 1.5),
            ),
            child: const Text("Rien pour l'instant. Tant mieux.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: kMuted)),
          ),
        for (final n in s.notes) ...[
          _noteCard(n),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _pill(Level lv) {
    final on = level == lv.id;
    return Material(
      color: on ? kPink : Colors.white,
      shape: StadiumBorder(
          side: BorderSide(color: on ? kBerry : kPinkLine, width: 1.5)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => setState(() => level = lv.id),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot(lv.color),
              const SizedBox(width: 8),
              Text(lv.label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: on ? kBerry : const Color(0xFF5B4350))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noteCard(Note n) {
    final s = widget.state;
    final lv = levelById(n.level);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: n.calm ? const Color(0xFFFFFCF0) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: n.calm ? const Color(0xFFF5E6AE) : kPinkLine2, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            dot(lv.color),
            const SizedBox(width: 8),
            Text('${n.calm ? 'Apaisé' : lv.label}  ·  ${_when(n.at)}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: kMuted)),
          ]),
          const SizedBox(height: 12),
          Text(n.text,
              style: TextStyle(
                fontSize: 16,
                height: 1.45,
                color: n.calm ? const Color(0xFF9C8790) : kInk,
                decoration: n.calm ? TextDecoration.lineThrough : null,
                decorationColor: const Color(0xFFE7C9D3),
              )),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GhostButton(
                done: n.calm,
                onPressed: () => s.update(() => n.calm = !n.calm),
                child: Text(n.calm ? 'Apaisé ✓' : "C'est passé"),
              ),
              IconButton(
                tooltip: 'Supprimer',
                onPressed: () => s.update(() => s.notes.remove(n)),
                icon: const Icon(Icons.delete_outline, color: Color(0xFF9C8790), size: 22),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- Apaiser ----------

class CalmTab extends StatefulWidget {
  final _ZenHomeState state;
  const CalmTab({super.key, required this.state});
  @override
  State<CalmTab> createState() => _CalmTabState();
}

class _CalmTabState extends State<CalmTab> {
  final ctrl = TextEditingController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final p = ctrl.text.trim();
    if (p.isEmpty) return;
    final s = widget.state;
    s.update(() {
      s.phrases.add(p);
      s.cur = s.phrases.length - 1;
    });
    ctrl.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final has = s.phrases.isNotEmpty;
    if (s.cur >= s.phrases.length) s.cur = 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 230),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration:
              BoxDecoration(color: kSun, borderRadius: BorderRadius.circular(28)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('PHRASE DU MOMENT',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: kSunInk)),
              const SizedBox(height: 18),
              const SizedBox(
                height: 28,
                child: Text('“',
                    style: TextStyle(
                        fontSize: 56, height: .9, fontWeight: FontWeight.w800, color: kRose)),
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  has ? s.phrases[s.cur] : 'Ajoute ta première phrase en dessous.',
                  key: ValueKey('${s.cur}-${s.phrases.length}'),
                  style: const TextStyle(
                      fontSize: 26, height: 1.3, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(has ? '${s.cur + 1} sur ${s.phrases.length}' : '',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: kSunInk)),
                  ),
                  GhostButton(
                    border: kSunLine,
                    onPressed: () {
                      if (has) s.update(() => s.cur = (s.cur + 1) % s.phrases.length);
                    },
                    child: const Row(children: [
                      Icon(Icons.shuffle, size: 18),
                      SizedBox(width: 8),
                      Text('Une autre'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text("Ajouter une phrase qui m'aide",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _add(),
                style: const TextStyle(fontSize: 16, color: kInk),
                decoration: fieldDecoration('Ex. : je réponds demain.'),
              ),
            ),
            const SizedBox(width: 8),
            PrimaryButton(
              width: 52,
              onPressed: ctrl.text.trim().isEmpty ? null : _add,
              child: const Icon(Icons.add, size: 24),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Mes phrases',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        for (var i = 0; i < s.phrases.length; i++) ...[
          Material(
            color: i == s.cur ? kPink : kPinkSoft,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => s.update(() => s.cur = i),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 2, 2),
                child: Row(
                  children: [
                    dot(kRose, 8),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(s.phrases[i],
                            style: const TextStyle(fontSize: 15, height: 1.4)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Retirer la phrase',
                      onPressed: () => s.update(() {
                        s.phrases.removeAt(i);
                        if (s.cur >= s.phrases.length) s.cur = 0;
                      }),
                      icon: const Icon(Icons.close, size: 18, color: Color(0xFF9C8790)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ---------- Respirer ----------

class BreathTab extends StatefulWidget {
  const BreathTab({super.key});
  @override
  State<BreathTab> createState() => _BreathTabState();
}

class _BreathTabState extends State<BreathTab> {
  Timer? timer;
  bool running = false;
  int t = 0;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (running) {
      timer?.cancel();
      setState(() => running = false);
    } else {
      setState(() {
        running = true;
        t = 0;
      });
      HapticFeedback.lightImpact();
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => t++);
        final c = t % 14;
        if (c == 0 || c == 4 || c == 8) HapticFeedback.lightImpact();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = t % 14;
    var phase = 'Prêt ?';
    var count = '';
    var scale = .62;
    var dur = const Duration(milliseconds: 600);
    if (running) {
      if (c < 4) {
        phase = 'Inspire';
        count = '${4 - c}';
        scale = 1;
        dur = const Duration(seconds: 4);
      } else if (c < 8) {
        phase = 'Bloque';
        count = '${8 - c}';
        scale = 1;
        dur = const Duration(seconds: 4);
      } else {
        phase = 'Expire';
        count = '${14 - c}';
        scale = .62;
        dur = const Duration(seconds: 6);
      }
    }
    final cycles = t ~/ 14;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        SizedBox(
          height: 300,
          child: Center(
            child: AnimatedScale(
              scale: scale,
              duration: dur,
              curve: Curves.easeInOut,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  color: kPink,
                  shape: BoxShape.circle,
                  border: Border.all(color: kSun, width: 10),
                  boxShadow: const [
                    BoxShadow(color: Color(0xFFFFFBEA), spreadRadius: 18),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(phase,
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w800, color: kBerry)),
                    if (count.isNotEmpty)
                      Text(count,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: kBerryDark)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Center(
          child: SizedBox(
            width: 290,
            child: Text(
              'Inspire 4 secondes, bloque 4, expire 6. Trois ou quatre tours suffisent souvent à redescendre.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.5, color: kMuted),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: kSun, borderRadius: BorderRadius.circular(999)),
            child: Text(
              '$cycles tour${cycles > 1 ? 's' : ''} complété${cycles > 1 ? 's' : ''}',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: kSunInk),
            ),
          ),
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          onPressed: _toggle,
          child: Text(running ? 'Arrêter' : 'Commencer'),
        ),
      ],
    );
  }
}
