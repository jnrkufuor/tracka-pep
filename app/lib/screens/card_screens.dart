import 'package:material_ui/material_ui.dart';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'guardian_screens.dart';

/// Your player card and who can see it (canvas: Share your card, What others
/// see, Who can see your profile). Private by default; a link you can turn
/// off or replace. Under 18, sharing needs your guardian's yes. What the card
/// may show is decided on the server (pep/players/card.py), never here.

Band? _band(String label) {
  for (final b in Band.values) {
    if (b.label == label) return b;
  }
  return null;
}

/// The card itself. [full] adds skills and clips (What others see).
class PlayerCardView extends StatelessWidget {
  const PlayerCardView({super.key, required this.card, this.full = false});

  final PlayerCard card;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final c = card;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: a.tile, borderRadius: BorderRadius.circular(18)),
              child: Text(c.shirtNumber?.toString() ?? c.initials,
                  style: TextStyle(fontFamily: TType.display, fontSize: 28, fontWeight: FontWeight.w800, color: a.main)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text([c.shirtName, if (c.shirtNumber != null) '${c.shirtNumber}'].join(' · '),
                    style: const TextStyle(fontFamily: TType.display, fontSize: 18, fontWeight: FontWeight.w800, color: Tk.ink)),
                if (c.positionName != null) Text(c.positionName!, style: const TextStyle(fontSize: 14, color: Tk.inkSoft)),
                if (c.line.isNotEmpty) Text(c.line, style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
              ]),
            ),
          ]),
          if (c.style != null || c.pepSees.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (c.style != null) _Tag('Your style · ${c.style}', color: Tk.stone),
              for (final p in c.pepSees) _Tag(p, color: Tk.pep),
            ]),
          ],
          if (c.bests.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(children: [
              for (final b in c.bests.take(3))
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${b.value}${b.unit.isEmpty ? '' : ' ${b.unit}'}',
                        style: const TextStyle(fontFamily: TType.display, fontSize: 20, fontWeight: FontWeight.w800, color: Tk.ink)),
                    Text(b.label, style: const TextStyle(fontSize: 12, color: Tk.muted)),
                  ]),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          const Text('Measured by Pep', style: TextStyle(fontSize: 11.5, color: Tk.faint)),
        ]),
      ),
      if (full && c.skills.isNotEmpty) ...[
        const SizedBox(height: 18),
        const SectionLabel('What scouts look for'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            for (final s in c.skills)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                      if (s.average != null) Text('Average: ${s.average}', style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
                    ]),
                  ),
                  if (_band(s.band) != null) BandPill(_band(s.band)!),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Text('Compared with ${c.comparedWith}. Only skills Pep has measured are shown.',
            style: const TextStyle(fontSize: 12, color: Tk.faint)),
      ],
      if (full && c.clips.isNotEmpty) ...[
        const SizedBox(height: 18),
        const SectionLabel('Portfolio'),
        for (final v in c.clips)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const TIcon('play', size: 18, color: Tk.faint),
                const SizedBox(width: 12),
                Expanded(child: Text(v.title.isEmpty ? 'Clip' : v.title, style: const TextStyle(fontSize: 14.5, color: Tk.ink))),
                Text(v.date, style: const TextStyle(fontSize: 12, color: Tk.muted)),
              ]),
            ),
          ),
      ],
      if (full && c.under18) ...[
        const SizedBox(height: 12),
        const InfoNote('Under 18. Contact goes through your guardian. No direct messages. Region only, never a home address.'),
      ],
    ]);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.45)), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
      );
}

/// Me › Share your card.
class ShareCardScreen extends StatefulWidget {
  const ShareCardScreen({super.key});

  @override
  State<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<ShareCardScreen> {
  CardState? c;
  bool failed = false;
  final _cardKey = GlobalKey();

  /// Save image: draws the card (as shown above) into a PNG and opens the share sheet,
  /// so it can go on WhatsApp Status. The picture shows only what the card shows.
  Future<void> _saveImage(CardState v) async {
    try {
      final boundary = _cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) throw StateError('no image');
      await Share.shareXFiles(
        [XFile.fromData(png.buffer.asUint8List(), name: 'tracka-card.png', mimeType: 'image/png')],
        text: v.linkOn && v.url != null ? 'My Tracka player card: ${v.url}' : 'My Tracka player card',
      );
    } catch (e) {
      if (mounted) showToast(context, "Couldn't make the image", detail: '$e', ok: false, aboveTabs: false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await context.read<AppState>().api.card();
      if (mounted) setState(() => c = v);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> _do(Future<CardState> Function() f, {String? done}) async {
    try {
      final v = await f();
      if (!mounted) return;
      setState(() => c = v);
      if (done != null) showToast(context, done, aboveTabs: false);
    } catch (e) {
      if (mounted) showToast(context, "Couldn't save that", detail: '$e', ok: false, aboveTabs: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final v = c;
    if (failed) return Scaffold(appBar: AppBar(), body: StateView.error(onRetry: _load));
    if (v == null) {
      return Scaffold(appBar: AppBar(), body: ListView(padding: const EdgeInsets.all(20), children: const [Skeleton(height: 180)]));
    }
    final minor = s.me?.profile.age != null && s.me!.profile.age! < 18;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('Share your card', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        const Text('Send it to a coach, a scout or your friends.', style: TextStyle(fontSize: 13.5, color: Tk.muted)),
        const SizedBox(height: 18),
        RepaintBoundary(
          key: _cardKey,
          child: ColoredBox(
            color: Tk.bg,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                PlayerCardView(card: v.card),
                const SizedBox(height: 6),
                const Text('tracka.app', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: Tk.faint)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (!v.canShare) ...[
          Panel(
            color: Tk.goldTile,
            border: const Color(0x38FFC21A),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ask your guardian first', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Tk.ink)),
              const SizedBox(height: 4),
              const Text("Sharing your card needs a yes from your guardian. We'll text them, and let you know when they answer.",
                  style: TextStyle(fontSize: 13.5, color: Tk.goldInk)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  if (s.me?.needsGuardian ?? false) {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuardianScreen()));
                  } else {
                    await showAskGuardian(context, 'share_card');
                  }
                },
                child: const Text('Send request'),
              ),
            ]),
          ),
        ] else ...[
          if (v.linkOn && v.url != null) ...[
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Share.share('My Tracka player card: ${v.url}', subject: 'My Tracka player card'),
                  icon: TIcon('share', size: 18, color: context.accent.on),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: v.url!));
                    if (context.mounted) showToast(context, 'Link copied', aboveTabs: false);
                  },
                  child: const Text('Copy link'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: () => _saveImage(v),
            icon: const TIcon('download', size: 18, color: Tk.ink),
            label: const Text('Save image'),
          ),
          const SizedBox(height: 8),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Column(children: [
              SwitchListTile(
                title: const Text('Your link'),
                subtitle: Text(v.linkOn ? 'On: anyone with the link can see your card' : 'Off: nobody can see your card'),
                value: v.linkOn,
                onChanged: (on) => _do(() => s.api.setCardLink(on), done: on ? 'Link on' : 'Link off'),
              ),
              if (v.url != null)
                ListTile(
                  title: const Text('Make a new link'),
                  subtitle: const Text('The old link stops working'),
                  onTap: () => _do(() => s.api.setCardLink(true, newLink: true), done: 'New link made'),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        const SectionLabel('Show on your card'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(children: [
            for (final (k, t) in const [('bests', 'Your bests'), ('skills', 'Measured skills'), ('clips', 'Portfolio clips')])
              SwitchListTile(
                title: Text(t),
                value: v.show[k] ?? true,
                onChanged: (x) => _do(() => s.api.updateCard(show: {k: x})),
              ),
            ListTile(
              title: const Text('Pick your portfolio clips'),
              subtitle: Text(v.portfolio.isEmpty ? 'None yet' : '${v.portfolio.length} picked'),
              trailing: const TIcon('chevron', size: 14, color: Tk.faint),
              onTap: () => _pickClips(v),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PublicCardScreen(card: v.card))),
          child: const Text("See what they'll see"),
        ),
        const SizedBox(height: 14),
        InfoNote(minor
            ? 'Your profile stays private. Only people with your link can open it, and you can turn the link off any time. Your guardian decides if you can share.'
            : 'Your profile stays private. Only people with your link can open it, and you can turn the link off any time.'),
      ]),
    );
  }

  Future<void> _pickClips(CardState v) async {
    final s = context.read<AppState>();
    final ready = s.videos.where((x) => x.status == 'READY').toList();
    final picked = [...v.portfolio];
    await showEditSheet<void>(
      context,
      title: 'Portfolio clips',
      child: StatefulBuilder(
        builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your best clips, picked by you. Up to 6. This is what people see when you share your card.',
              style: TextStyle(fontSize: 13.5, color: Tk.muted)),
          const SizedBox(height: 10),
          if (ready.isEmpty) const Text('Send Pep a clip first.', style: TextStyle(color: Tk.inkSoft)),
          for (final x in ready)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: picked.contains(x.id),
              title: Text(x.displayTitle),
              onChanged: (on) {
                setSheet(() {
                  if (on == true && picked.length < 6) picked.add(x.id);
                  if (on == false) picked.remove(x.id);
                });
                _do(() => s.api.updateCard(portfolio: picked));
              },
            ),
        ]),
      ),
    );
  }
}

/// What others see: the card as someone with the link sees it.
class PublicCardScreen extends StatelessWidget {
  const PublicCardScreen({super.key, required this.card});

  final PlayerCard card;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text("What they'll see")),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          const Text('This is what people with your link see.', style: TextStyle(fontSize: 13.5, color: Tk.muted)),
          const SizedBox(height: 14),
          PlayerCardView(card: card, full: true),
          const SizedBox(height: 14),
          const InfoNote("Measured by Tracka from your own clips. Video measurements can be off, and Pep's notes come from an AI. "
              'Use them as a guide, not a final judgement.'),
        ]),
      );
}

/// Settings › Privacy and safety: who can see your profile, and what's always private.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  CardState? c;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().api.card().then((v) {
      if (mounted) setState(() => c = v);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final me = s.me;
    final minor = me?.profile.age != null && me!.profile.age! < 18;
    Widget always(String t, String d) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            const TIcon('lock', size: 16, color: Tk.faint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontSize: 14.5, color: Tk.ink)),
                Text(d, style: const TextStyle(fontSize: 12.5, color: Tk.muted)),
              ]),
            ),
          ]),
        );
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('Who can see your profile', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 18),
        if (c != null)
          SingleChips<String>(
            options: const {'private': 'Only you', 'link': 'People with your link'},
            value: c!.linkOn ? 'link' : 'private',
            scroll: false,
            onChanged: (v) async {
              if (v == 'link' && !c!.canShare) {
                if (me?.needsGuardian ?? false) {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuardianScreen()));
                } else {
                  await showAskGuardian(context, 'share_card');
                }
                return;
              }
              try {
                final x = await s.api.setCardLink(v == 'link');
                if (mounted) setState(() => c = x);
              } catch (e) {
                if (context.mounted) showToast(context, "Couldn't save that", detail: '$e', ok: false, aboveTabs: false);
              }
            },
          )
        else
          const Skeleton(height: 40),
        const SizedBox(height: 10),
        const Panel(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Scouts on Tracka', style: TextStyle(fontSize: 14.5, color: Tk.ink)),
                Text('Coming later, with checked scouts only', style: TextStyle(fontSize: 12.5, color: Tk.muted)),
              ]),
            ),
            Text('Off', style: TextStyle(color: Tk.faint)),
          ]),
        ),
        const SizedBox(height: 10),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: SwitchListTile(
            title: const Text('Show up in search'),
            subtitle: Text(minor ? 'Other players your age can find you. Your guardian has to agree.' : 'Other players can find you on Pitchside.'),
            value: me?.settings.findable ?? false,
            onChanged: (v) async {
              await s.saveSettings({'findable': v});
              if (v && minor && context.mounted) {
                final g = await s.api.guardian().catchError((_) => GuardianState(needed: true, status: 'none'));
                if (!g.can('search') && context.mounted) await showAskGuardian(context, 'search');
              }
              if (mounted) setState(() {});
            },
          ),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Always private'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(children: [
            always('Full name and date of birth', 'People see your shirt name and age group'),
            always('Exact location', 'Only your region is shown'),
            always("Clips you haven't posted", 'Pep watches them for you, nobody else'),
            if (minor) always('No direct messages', 'Contact goes through your guardian'),
          ]),
        ),
        if (minor) ...[
          const SizedBox(height: 14),
          const InfoNote("You're under 18, so your guardian has to agree before anyone outside Tracka can see your profile."),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuardianScreen())),
            child: const Text('Your guardian'),
          ),
        ],
      ]),
    );
  }
}
