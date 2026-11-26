import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import '../widgets/pitch_picker.dart';
import '../widgets/profile_fields.dart';
import '../widgets/skill_areas_view.dart';
import 'card_screens.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await context.read<AppState>().api.card();
      if (mounted) setState(() => card = c);
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
    final p = me.profile;
    final c = card;
    final ready = s.videos.where((v) => v.status == 'READY').toList();
    final portfolio = [for (final id in c?.portfolio ?? const <String>[]) ...ready.where((v) => v.id == id)];
    Widget detail(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(fontSize: 14, color: Tk.muted))),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.ink))),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await s.refresh();
            await _load();
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 32), children: [
            Row(children: [
              Text('Me', style: Theme.of(context).textTheme.headlineLarge),
              const Spacer(),
              IconButton(tooltip: 'Share your card', onPressed: () => _go(const ShareCardScreen()), icon: const TIcon('share', size: 20, color: Tk.ink)),
              IconButton(tooltip: 'Settings', onPressed: () => _go(const SettingsScreen()), icon: const TIcon('settings', size: 21, color: Tk.ink)),
            ]),
            const SizedBox(height: 10),
            if (c != null) PlayerCardView(card: c.card) else const Skeleton(height: 170),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _go(const EditProfileScreen()), child: const Text('Edit profile'))),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _go(const PrivacyScreen()),
                  child: Text(c?.linkOn ?? false ? 'Shared by link' : 'Private'),
                ),
              ),
            ]),
            if (s.coach?.skillAreas != null) ...[
              const SizedBox(height: 24),
              SkillAreasView(areas: s.coach!.skillAreas!),
            ],
            const SizedBox(height: 22),
            SectionLabel('Portfolio', trailing: Pressable(onTap: () => _go(const ShareCardScreen()), child: const Text('Manage', style: TextStyle(fontSize: 13, color: Tk.muted)))),
            const Text('Your best clips, picked by you. This is what people see when you share your card.', style: TextStyle(fontSize: 12.5, color: Tk.faint)),
            const SizedBox(height: 10),
            _ClipStrip(videos: portfolio, empty: 'Pick your best clips in Share your card.'),
            const SizedBox(height: 22),
            SectionLabel('All your clips', trailing: Pressable(onTap: () => _go(const VideosScreen()), child: const Text('See all', style: TextStyle(fontSize: 13, color: Tk.muted)))),
            const Text('Only you can see these until you post them.', style: TextStyle(fontSize: 12.5, color: Tk.faint)),
            const SizedBox(height: 10),
            _ClipStrip(videos: s.videos.take(8).toList(), empty: 'No clips yet.'),
            const SizedBox(height: 22),
            const SectionLabel('Working towards'),
            Panel(
              onTap: () => _go(const EditProfileScreen()),
              child: Row(children: [
                const IconTile(icon: 'flag', color: Tk.gold, background: Tk.goldTile, size: 38),
                const SizedBox(width: 12),
                Expanded(child: Text(_goals[p.goal] ?? 'Pick a goal', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink))),
                const Text('Change', style: TextStyle(fontSize: 13, color: Tk.muted)),
              ]),
            ),
            const SizedBox(height: 22),
            const SectionLabel('Player details'),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                detail('Positions', p.positions.isEmpty ? '–' : [p.positions.first, ...p.positions.skip(1)].join(', ')),
                if (p.style != null) detail('Your style', p.style!),
                detail('Stronger foot', p.foot == null ? '–' : '${p.foot![0].toUpperCase()}${p.foot!.substring(1)}'),
                if (p.weakFoot != null) detail('Weaker foot', '${p.weakFoot} · ${_weak[p.weakFoot! - 1]}'),
                detail('Height', p.heightM == null ? '–' : '${p.heightM!.toStringAsFixed(2)} m'),
                detail('Where you play', [if (p.region != null) p.region!].join(', ').isEmpty ? '–' : p.region!),
                if (p.shirtName != null) detail('Shirt', [p.shirtName!, if (p.shirtNumber != null) '${p.shirtNumber}'].join(' · ')),
                detail('Born', p.birthDate == null ? '–' : DateFormat.yMMMd().format(p.birthDate!)),
              ]),
            ),
            const SizedBox(height: 14),
            const InfoNote('Compared with players your age, from your clips and tests. Video measurements can be off. Use them as a guide.'),
          ]),
        ),
      ),
    );
  }
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
                  if (v.processing) const ColoredBox(color: Color(0x88000000), child: Center(child: TIcon('pep', size: 20, color: Tk.pep))),
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
