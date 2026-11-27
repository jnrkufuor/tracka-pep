import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/board.dart';
import '../widgets/ds.dart';
import '../widgets/pep.dart';
import '../widgets/pitch_picker.dart';
import '../widgets/profile_fields.dart';
import '../widgets/skill_areas_view.dart';
import 'card_screens.dart';
import 'pep_screen.dart' show FocusScreen, TestScreen;
import 'settings_screen.dart';
import 'video_screen.dart';
import 'videos_screen.dart';

/// Your profile and settings.
/// Me (canvas: Me). Your card, what scouts look for, your bests, your clips,
/// what you're working towards, your details, and who can see your profile.
/// Private by default; bands, never a 0-100 score.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  CardState? card;
  FocusState? focus;

  /// Growth · Clips · About (canvas Me: "tap Growth, Clips, About").
  String tab = 'growth';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<AppState>().api;
    try {
      final c = await api.card();
      if (mounted) setState(() => card = c);
    } catch (_) {}
    try {
      final f = await api.focus();
      if (mounted) setState(() => focus = f);
    } catch (_) {}
  }

  void _go(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)).then((_) => _load());

  static const _goals = {
    'fun': 'Play more, have fun',
    'school': 'Make my school team',
    'academy': 'Get into an academy',
    'standout': 'Stand out where I play',
    'better': 'Just get better',
    'looking': 'Just looking around',
  };
  static const _weak = ['Hard to use', 'Simple passes', 'OK for short passes', 'Good for most things', 'Strong as my best'];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me;
    if (me == null) return const SizedBox.shrink();
    final c = card;
    final areas = s.coach?.skillAreas;
    final seen = (areas?.measured ?? 0) > 0 || (focus?.bests.isNotEmpty ?? false);
    final children = <Widget>[
      Row(children: [
        Expanded(child: Text('Me', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 30))),
        _GlassButton(icon: 'share', label: 'Share', onTap: () => _go(const ShareCardScreen())),
        const SizedBox(width: 8),
        _GlassButton(icon: 'settings', label: null, semantics: 'Settings', onTap: () => showSettingsSheet(context)),
      ]),
      _MeCard(
        card: c?.card,
        profile: me.profile,
        linkOn: c?.linkOn ?? false,
        onPrivacy: () => _go(const PrivacyScreen()),
        onEdit: () => _go(const EditProfileScreen()),
      ),
      if (!seen) ...[
        const BPepNote(mood: PepMood.watching, title: "I haven't seen you play yet", text: "Do your first tests and I'll start filling this in."),
        BCta('Start your first test', onTap: () {
          final t = focus?.nextTest;
          _go(t == null ? const FocusScreen() : TestScreen(drill: t.drill, name: t.name));
        }),
        if (areas != null) SkillAreasView(areas: areas),
      ] else ...[
        BSeg<String>(
          options: const {'growth': 'Growth', 'clips': 'Clips', 'about': 'About'},
          value: tab,
          onChanged: (v) => setState(() => tab = v),
        ),
        ...switch (tab) {
          'clips' => _clips(s),
          'about' => _about(me.profile),
          _ => _growth(areas),
        },
      ],
    ];
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await s.refresh();
            await _load();
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 32), children: [
            for (final (i, w) in children.indexed) ...[if (i > 0) const SizedBox(height: 18), w],
          ]),
        ),
      ),
    );
  }

  List<Widget> _growth(SkillAreas? areas) {
    final bests = focus?.bests ?? const [];
    return [
      if (areas != null) SkillAreasView(areas: areas),
      if (bests.isNotEmpty) ...[
        const BLab('Your bests'),
        LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - 10) / 2;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final b in bests)
              SizedBox(
                width: w,
                child: Panel(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${b.value}${b.unit.isEmpty ? '' : ' ${b.unit}'}',
                        style: const TextStyle(fontFamily: TType.display, fontSize: 26, fontWeight: FontWeight.w700, color: Tk.ink)),
                    const SizedBox(height: 2),
                    Text(b.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Tk.lab)),
                    Text(b.unit == 's' ? 'Timed by Pep' : 'Counted by Pep', style: bNote),
                  ]),
                ),
              ),
          ]);
        }),
      ],
    ];
  }

  List<Widget> _clips(AppState s) {
    final ready = s.videos.where((v) => v.status == 'READY').toList();
    final portfolio = [for (final id in card?.portfolio ?? const <String>[]) ...ready.where((v) => v.id == id)];
    return [
      BLab('Portfolio', link: 'Manage', onLink: () => _go(const ShareCardScreen())),
      Transform.translate(
        offset: const Offset(0, -10),
        child: const Text('Your best clips, picked by you. This is what people see when you share your card.', style: bNote),
      ),
      _ClipStrip(videos: portfolio, empty: 'Pick your best clips in Share your card.'),
      BLab('All your clips', link: 'See all', onLink: () => _go(const VideosScreen())),
      Transform.translate(offset: const Offset(0, -10), child: const Text('Only you can see these until you post them.', style: bNote)),
      _ClipStrip(videos: s.videos.take(8).toList(), empty: 'No clips yet.'),
    ];
  }

  List<Widget> _about(Profile p) {
    Widget detail(String k, String v, {bool last = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.line))),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(fontSize: 14, color: Tk.muted))),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.ink))),
          ]),
        );
    final rows = <(String, String)>[
      ('Positions', p.positions.isEmpty ? '–' : p.positions.join(', ')),
      if (p.style != null) ('Your style', p.style!),
      ('Stronger foot', p.foot == null ? '–' : '${p.foot![0].toUpperCase()}${p.foot!.substring(1)}'),
      if (p.weakFoot != null) ('Weaker foot', '${p.weakFoot} · ${_weak[p.weakFoot! - 1]}'),
      ('Height', p.heightM == null ? '–' : '${(p.heightM! * 100).round()} cm'),
      ('Where you play', p.region ?? '–'),
      if (p.shirtName != null) ('Shirt', [p.shirtName!, if (p.shirtNumber != null) '${p.shirtNumber}'].join(' · ')),
      ('Born', p.birthDate == null ? '–' : DateFormat.yMMMd().format(p.birthDate!)),
    ];
    return [
      const BLab('Working towards'),
      Panel(
        onTap: () => _go(const EditProfileScreen()),
        child: Row(children: [
          const IconTile(icon: 'flag', color: Tk.gold, background: Tk.goldTile, size: 38),
          const SizedBox(width: 12),
          Expanded(child: Text(_goals[p.goal] ?? 'Pick a goal', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink))),
          const Text('Change', style: TextStyle(fontSize: 13, color: Tk.muted)),
        ]),
      ),
      const BLab('Player details'),
      Panel(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Column(children: [for (final (i, (k, v)) in rows.indexed) detail(k, v, last: i == rows.length - 1)]),
      ),
      const InfoNote('Compared with players your age, from your clips and tests. Video measurements can be off. Use them as a guide.'),
    ];
  }
}

/// The see-through round button on Me (canvas: "Share").
class _GlassButton extends StatelessWidget {
  const _GlassButton({required this.icon, required this.label, required this.onTap, this.semantics});

  final String icon;
  final String? label;
  final String? semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantics ?? label,
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: Container(
            height: 36,
            constraints: const BoxConstraints(minWidth: 36),
            padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x24FFFFFF)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              TIcon(icon, size: 15, color: Tk.ink),
              if (label != null) ...[const SizedBox(width: 7), Text(label!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Tk.ink))],
            ]),
          ),
        ),
      );
}

/// Your player card on Me (canvas: Me). Big faint shirt number behind,
/// your initials in a main-colour ring, position in big type, your style
/// and Pep's read side by side, what Pep sees, who can see it, edit.
class _MeCard extends StatelessWidget {
  const _MeCard({required this.card, required this.profile, required this.linkOn, required this.onPrivacy, required this.onEdit});

  final PlayerCard? card;
  final Profile profile;
  final bool linkOn;
  final VoidCallback onPrivacy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final c = card;
    final number = c?.shirtNumber ?? profile.shirtNumber;
    final shirt = c?.shirtName ?? profile.shirtName ?? profile.displayName;
    final initials = c?.initials ?? (shirt.isEmpty ? '?' : shirt.split(RegExp(r'[ .]+')).where((x) => x.isNotEmpty).take(2).map((x) => x[0]).join().toUpperCase());
    final position = c?.positionName ?? (profile.positions.isEmpty ? 'Footballer' : profile.positions.first);
    final line = [
      if ((c?.foot ?? profile.foot) != null) '${_cap(c?.foot ?? profile.foot!)} foot',
      if ((c?.region ?? profile.region) != null) c?.region ?? profile.region!,
      if (c?.level != null) c!.level!,
    ].join(' · ');
    final sees = c?.pepSees ?? const <String>[];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Color.alphaBlend(a.main.withValues(alpha: .14), const Color(0xFF111111))),
        gradient: LinearGradient(
          begin: const Alignment(-.8, -1),
          end: const Alignment(.8, 1),
          stops: const [0, .55],
          colors: [Color.alphaBlend(a.main.withValues(alpha: .10), const Color(0xFF111111)), const Color(0xFF111111)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (number != null)
          Positioned(
            right: -6,
            top: -22,
            child: ExcludeSemantics(
              child: Text('$number',
                  style: TextStyle(fontFamily: TType.display, fontSize: 150, height: 1, fontWeight: FontWeight.w800, color: a.main.withValues(alpha: .10))),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF1A1A1A), border: Border.all(color: a.main, width: 2.5)),
                child: Text(initials, style: const TextStyle(fontFamily: TType.display, fontSize: 23, fontWeight: FontWeight.w700, color: Tk.ink)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text([shirt.toUpperCase(), if (number != null) '$number'].join(' · '),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .9, color: a.main)),
                  const SizedBox(height: 3),
                  Text(position, style: const TextStyle(fontFamily: TType.display, fontSize: 24, height: 1.05, fontWeight: FontWeight.w700, color: Tk.ink)),
                  if (line.isNotEmpty) ...[const SizedBox(height: 3), Text(line, style: bNote)],
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _Half(label: 'Your style', labelColor: Tk.muted, bg: const Color(0xFF1C1F17), value: c?.style ?? profile.style ?? 'Pick one', dim: (c?.style ?? profile.style) == null)),
                const SizedBox(width: 8),
                Expanded(
                  child: _Half(
                    label: "Pep's read",
                    labelColor: Tk.pep,
                    bg: const Color(0xFF221A33),
                    value: sees.isEmpty ? 'After a few clips' : sees.first,
                    dim: sees.isEmpty,
                  ),
                ),
              ]),
            ),
            if (sees.length > 1) ...[
              const SizedBox(height: 12),
              const Row(children: [
                PepFace(PepMood.justHere, size: 16),
                SizedBox(width: 6),
                Text('PEP SEES', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .6, color: Tk.pep)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                // What Pep saw you do well in your colour; plain facts in grey (canvas Me).
                for (final (i, x) in sees.skip(1).indexed)
                  i < 2 ? BChip(x, color: a.main, background: a.tile) : BChip(x, color: Tk.lab, background: const Color(0xFF1A1A1A)),
              ]),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x14FFFFFF)))),
              child: Row(children: [
                Semantics(
                  button: true,
                  label: linkOn ? 'Shared by link. Change who can see it' : 'Private. Change who can see it',
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: onPrivacy,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: Tk.field, borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFF262626))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        TIcon(linkOn ? 'globe' : 'lock', size: 12, color: Tk.muted),
                        const SizedBox(width: 5),
                        Text(linkOn ? 'Shared by link' : 'Private', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Tk.muted)),
                      ]),
                    ),
                  ),
                ),
                const Spacer(),
                Pressable(
                  onTap: onEdit,
                  child: const Row(children: [
                    Text('Edit profile', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Tk.lab)),
                    SizedBox(width: 4),
                    TIcon('chevron', size: 12, color: Tk.lab),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _Half extends StatelessWidget {
  const _Half({required this.label, required this.labelColor, required this.bg, required this.value, required this.dim});

  final String label;
  final Color labelColor;
  final Color bg;
  final String value;
  final bool dim;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .6, color: labelColor)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(fontSize: dim ? 13 : 14, height: 1.25, fontWeight: dim ? FontWeight.w500 : FontWeight.w600, color: dim ? Tk.faint : Tk.ink)),
        ]),
      );
}

class _ClipStrip extends StatelessWidget {
  const _ClipStrip({required this.videos, required this.empty});

  final List<Video> videos;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) return Text(empty, style: const TextStyle(fontSize: 13.5, color: Tk.inkSoft));
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: videos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final v = videos[i];
          return InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoScreen(videoId: v.id))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 88,
                child: Stack(fit: StackFit.expand, children: [
                  if (v.thumbnailUrl != null)
                    Image.network(v.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Tk.card2))
                  else
                    const ColoredBox(color: Tk.card2),
                  if (v.processing) const ColoredBox(color: Color(0x88000000), child: Center(child: PepFace(PepMood.analysing, size: 22))),
                  Positioned(
                    left: 6,
                    right: 6,
                    bottom: 6,
                    child: Text(v.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Edit profile (canvas: Me › Edit). Saves as you go, like every edit
/// screen in the app: no Save or Cancel. Each change is sent a moment after
/// you stop typing; the little note at the top says when it's saved.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final Map<String, dynamic> _pending = {};
  Timer? _timer;
  String _status = 'Saves as you go';
  late Profile p;
  late List<String> positions;
  String? sex, foot, region, level, goal, style;
  int? weakFoot;
  double? height;
  DateTime? birth;

  static const _levels = {'fun': 'Just for fun', 'amateur': 'Amateur league', 'school': 'School team', 'club': 'Local club', 'academy': 'Academy', 'pro': 'Semi-pro or pro'};
  static const _goals = {'fun': 'Play more, have fun', 'school': 'Make my school team', 'academy': 'Get into an academy', 'standout': 'Stand out where I play', 'better': 'Just get better', 'looking': 'Just looking around'};

  @override
  void initState() {
    super.initState();
    p = context.read<AppState>().me!.profile;
    positions = [...p.positions];
    sex = p.sex;
    foot = p.foot;
    region = p.region;
    level = p.level;
    goal = p.goal;
    style = p.style;
    weakFoot = p.weakFoot;
    height = p.heightM;
    birth = p.birthDate;
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_pending.isNotEmpty) _flush();
    super.dispose();
  }

  void _set(String key, Object? value, {bool now = false}) {
    _pending[key] = value;
    _timer?.cancel();
    setState(() => _status = 'Saving…');
    _timer = Timer(Duration(milliseconds: now ? 0 : 700), _flush);
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final changes = {..._pending};
    _pending.clear();
    final s = context.read<AppState>();
    try {
      await s.saveProfile(changes);
      if (mounted) setState(() => _status = 'Saved');
    } catch (e) {
      if (mounted) {
        setState(() => _status = "Couldn't save");
        showToast(context, "Couldn't save that", detail: '$e', ok: false, aboveTabs: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = context.watch<AppState>().meta;
    Widget gap() => const SizedBox(height: 18);
    return Scaffold(
      appBar: AppBar(actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(child: Text(_status, style: TextStyle(fontSize: 12.5, color: _status == "Couldn't save" ? Tk.gold : Tk.faint))),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('Edit profile', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        const FieldLabel('Your name'),
        TextFormField(initialValue: p.displayName, textCapitalization: TextCapitalization.words, onChanged: (v) => _set('displayName', v.trim())),
        gap(),
        const FieldLabel('Name and number on your shirt'),
        Row(children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: p.shirtName,
              maxLength: 20,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(counterText: '', hintText: 'K. ASANTE'),
              onChanged: (v) => _set('shirtName', v.trim()),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              initialValue: p.shirtNumber?.toString(),
              keyboardType: TextInputType.number,
              maxLength: 2,
              decoration: const InputDecoration(counterText: '', hintText: 'No.'),
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null && n >= 1 && n <= 99) _set('shirtNumber', n);
              },
            ),
          ),
        ]),
        gap(),
        BirthDateField(value: birth, onChanged: (d) {
          setState(() => birth = d);
          _set('birthDate', DateFormat('yyyy-MM-dd').format(d), now: true);
        }),
        gap(),
        const FieldLabel('You play in'),
        SingleChips<String>(
          options: const {'male': "Boys' or men's", 'female': "Girls' or women's"},
          value: sex ?? '',
          scroll: false,
          onChanged: (v) {
            setState(() => sex = v);
            _set('sex', v, now: true);
          },
        ),
        gap(),
        const FieldLabel('Your positions'),
        PitchPicker(positions: positions, onChanged: (v) {
          setState(() => positions = v);
          if (v.isNotEmpty) _set('positions', v, now: true);
        }),
        gap(),
        const FieldLabel('Stronger foot'),
        SingleChips<String>(
          options: const {'left': 'Left', 'right': 'Right', 'both': 'Both'},
          value: foot ?? '',
          scroll: false,
          onChanged: (v) {
            setState(() => foot = v);
            _set('foot', v, now: true);
          },
        ),
        gap(),
        const FieldLabel('Weaker foot, 1 to 5'),
        SingleChips<int>(
          options: const {1: '1', 2: '2', 3: '3', 4: '4', 5: '5'},
          value: weakFoot ?? 0,
          scroll: false,
          onChanged: (v) {
            setState(() => weakFoot = v);
            _set('weakFoot', v, now: true);
          },
        ),
        gap(),
        const FieldLabel('Height'),
        HeightField(value: height, onChanged: (v) {
          setState(() => height = v);
          _set('heightM', v);
        }),
        gap(),
        const FieldLabel('Your style'),
        TextFormField(initialValue: style, maxLength: 40, decoration: const InputDecoration(counterText: '', hintText: 'Playmaker'), onChanged: (v) => _set('style', v.trim())),
        gap(),
        RegionPicker(regions: meta?.regions ?? const [], value: region, onChanged: (v) {
          setState(() => region = v);
          if (v != null) _set('region', v, now: true);
        }),
        const SizedBox(height: 12),
        TextFormField(initialValue: p.town, decoration: const InputDecoration(labelText: 'Town (private)'), onChanged: (v) => _set('town', v.trim())),
        const SizedBox(height: 12),
        TextFormField(initialValue: p.club, decoration: const InputDecoration(labelText: 'Club, academy or school'), onChanged: (v) => _set('club', v.trim())),
        gap(),
        const FieldLabel('Your level now'),
        SingleChips<String>(options: _levels, value: level ?? '', scroll: false, onChanged: (v) {
          setState(() => level = v);
          _set('level', v, now: true);
        }),
        gap(),
        const FieldLabel('Your goal'),
        SingleChips<String>(options: _goals, value: goal ?? '', scroll: false, onChanged: (v) {
          setState(() => goal = v);
          _set('goal', v, now: true);
        }),
        const SizedBox(height: 14),
        const InfoNote('Others only ever see your shirt name, position, age group and region. Your full name, date of birth and town stay private.'),
      ]),
    );
  }
}

/// Settings › Main colour (canvas: "Settings › Main colour"). Tap a colour and
/// the whole app re-colours at once; it saves straight away. Pep stays purple
/// and warnings stay gold whatever you pick.
class MainColourPicker extends StatelessWidget {
  const MainColourPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final current = MainColour.fromName(s.settings.mainColour);
    Future<void> pick(MainColour c) async {
      try {
        await s.saveSettings({'mainColour': c.name});
      } catch (_) {
        if (context.mounted) {
          showToast(context, "Couldn't save that", detail: 'Check your connection and try again.', aboveTabs: false, ok: false);
        }
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('The colour that marks you: your buttons, your progress and your player card.',
          style: TextStyle(fontSize: 14, color: Tk.muted, height: 1.45)),
      const SizedBox(height: 20),
      Wrap(spacing: 14, runSpacing: 16, children: [
        for (final c in MainColour.values)
          Semantics(
            button: true,
            selected: c == current,
            label: c.label,
            excludeSemantics: true,
            child: Pressable(
              onTap: () => pick(c),
              child: SizedBox(
                width: 64,
                child: Column(children: [
                  AnimatedContainer(
                    duration: Motion.of(context, Motion.select),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.main,
                      border: Border.all(color: c == current ? Tk.ink : Colors.transparent, width: 2.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(c.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: c == current ? Tk.ink : Tk.muted, fontWeight: c == current ? FontWeight.w700 : FontWeight.w500)),
                ]),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 22),
      const InfoNote('Pep always stays purple and warnings always stay gold. People you share your card with see your colour.'),
    ]);
  }
}
