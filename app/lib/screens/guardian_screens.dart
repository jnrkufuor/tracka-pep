import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';

/// Guardian approval in the player's app (canvas: Guardian flow).
///
/// Under 18, a parent, guardian or coach says yes before the account opens up,
/// and again before anything new (posting, sharing the card, being findable).
/// The guardian answers on a web page or by texting YES and the code back
/// (pep/players/guardian.py). The player sees where it stands and can send
/// the text again or change the number.
///
/// Texts are a PLACEHOLDER until an SMS provider is chosen: they're kept on the
/// server and don't reach phones. While that's so, [GuardianState.selfConfirm]
/// is true and the player can tick "they've already said yes".

const _kindWords = {
  'post': ('Posting clips', 'Other players can see what you post.'),
  'share_card': ('Sharing your player card', 'Only people with your link can open it.'),
  'search': ('Showing up in search', 'Other players your age can find your profile.'),
};

/// The card on Home while the guardian hasn't said yes.
class GuardianCard extends StatelessWidget {
  const GuardianCard({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me;
    if (me == null || !me.needsGuardian) return const SizedBox.shrink();
    final (title, sub) = switch (me.guardianStatus) {
      'declined' => ('Your guardian said not yet', 'Pep and training still work. Talk to them, then ask again.'),
      'revoked' => ('Your account is private again', 'Your guardian took back their approval. Training stays.'),
      'expired' => ('Your guardian didn\'t answer', 'Send the text again when they\'re ready.'),
      'none' || null => ('Ask your guardian', 'Add their number so they can say yes.'),
      _ => ('Waiting for your guardian', 'Once they say yes, everything opens up.'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        color: Tk.goldTile,
        border: const Color(0x38FFC21A),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuardianScreen())),
        child: Row(children: [
          const IconTile(icon: 'shield', color: Tk.gold, background: Color(0x22FFC21A), size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.ink)),
              Text(sub, style: const TextStyle(fontSize: 13, color: Tk.goldInk)),
            ]),
          ),
          const TIcon('chevron', size: 14, color: Tk.goldInk),
        ]),
      ),
    );
  }
}

/// Waiting for your guardian (and the "text didn't arrive" help).
class GuardianScreen extends StatefulWidget {
  const GuardianScreen({super.key});

  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> {
  GuardianState? g;
  bool failed = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final v = await context.read<AppState>().api.guardian();
      if (mounted) {
        setState(() {
          g = v;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  Future<void> _resend() async {
    setState(() => busy = true);
    try {
      final v = await context.read<AppState>().api.resendGuardian();
      if (!mounted) return;
      setState(() => g = v);
      showToast(context, 'Sent again', detail: 'To ${v.phone}', ok: true, aboveTabs: false);
    } catch (e) {
      if (mounted) showToast(context, "Couldn't send it", detail: '$e', ok: false, aboveTabs: false);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _changeNumber() async {
    final v = await showGuardianNumberSheet(context, g);
    if (v != null && mounted) setState(() => g = v);
  }

  Future<void> _selfConfirm(bool yes) async {
    final s = context.read<AppState>();
    await s.saveProfile({'guardianConsent': yes});
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final v = g;
    if (failed) return Scaffold(appBar: AppBar(), body: StateView.error(onRetry: _load));
    if (v == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ListView(padding: const EdgeInsets.all(20), children: const [Skeleton(height: 30, width: 240), SizedBox(height: 16), Skeleton(height: 160)]),
      );
    }
    final me = context.watch<AppState>().me;
    final approved = me != null && !me.needsGuardian;
    final noText = v.sendStatus == 'failed';
    Widget list(String label, List<String> items, {required bool open}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionLabel(label),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(children: [
              for (final t in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    TIcon(open ? 'check' : 'lock', size: 16, color: open ? context.accent.main : Tk.faint),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t, style: const TextStyle(fontSize: 14.5, color: Tk.ink))),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 18),
        ]);
    return Scaffold(
      appBar: AppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          if (mounted) await context.read<AppState>().refresh();
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
          Text(
            approved
                ? 'Your guardian said yes'
                : noText
                    ? "Your guardian hasn't got the text"
                    : v.status == 'none'
                        ? 'Ask your guardian'
                        : 'Waiting for your guardian',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            approved
                ? '${v.who[0].toUpperCase()}${v.who.substring(1)} can change what you can do at any time.'
                : noText
                    ? "We tried to text ${v.who} but it didn't go through. You can keep using Pep and training while you sort it out."
                    : v.phone == null
                        ? 'Add their number. We\'ll text them a link to say yes.'
                        : 'We texted ${v.who} on ${v.phone}. Once they say yes, everything opens up.',
            style: const TextStyle(fontSize: 14.5, height: 1.45, color: Tk.inkSoft),
          ),
          const SizedBox(height: 20),
          if (!approved) ...[
            list('You can use now', const ['Pep, your training and your schedule', 'Watching Pitchside'], open: true),
            list('After your guardian says yes', const ['Sending clips to Pep', 'Posting clips', 'Sharing your player card', 'Other players finding your profile'],
                open: false),
          ] else ...[
            list('What your guardian has said yes to', [
              'Your account',
              for (final e in _kindWords.entries)
                if (v.can(e.key == 'share_card' ? 'shareCard' : e.key)) e.value.$1,
            ], open: true),
            if (v.pendingKinds.isNotEmpty)
              InfoNote('Waiting for an answer on: ${v.pendingKinds.map((k) => _kindWords[k]?.$1.toLowerCase() ?? k).join(', ')}.'),
          ],
          if (noText) ...[
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _help('Check the number', '${v.phone}. Is it right?'),
                _help('Wait a few minutes', 'Texts can be slow on some networks.'),
                _help('Guardian has no signal?', 'They can reply YES with the code later. It works for 7 days.'),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          if (!approved) ...[
            if (v.phone != null)
              FilledButton(onPressed: busy || v.resendAt != null ? null : _resend, child: const Text('Send again')),
            const SizedBox(height: 6),
            OutlinedButton(onPressed: _changeNumber, child: Text(v.phone == null ? 'Add their number' : 'Change number')),
            const SizedBox(height: 16),
            const InfoNote('Is your guardian with you? They can reply to the text, or open the link on their phone.'),
            if (v.selfConfirm) ...[
              const SizedBox(height: 10),
              Panel(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: me?.profile.guardianConsent ?? false,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('They have already said yes', style: TextStyle(fontSize: 14.5)),
                  subtitle: const Text("Approval texts aren't switched on yet. Until they are, tick this once your guardian agrees.",
                      style: TextStyle(fontSize: 12.5, color: Tk.faint)),
                  onChanged: (x) => _selfConfirm(x ?? false),
                ),
              ),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _help(String t, String d) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Tk.ink)),
          Text(d, style: const TextStyle(fontSize: 13, color: Tk.muted)),
        ]),
      );
}

/// Add or change the guardian's number. Creating sends a text, so it has a button.
Future<GuardianState?> showGuardianNumberSheet(BuildContext context, GuardianState? g) {
  var phone = '';
  var relation = g?.relation ?? 'parent';
  var name = g?.name ?? '';
  return showEditSheet<GuardianState>(
    context,
    title: g?.phone == null ? "Your guardian's number" : 'Change number',
    child: StatefulBuilder(
      builder: (ctx, setState) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChips<String>(
          options: const {'parent': 'Parent', 'guardian': 'Guardian', 'coach': 'Coach'},
          value: relation,
          onChanged: (v) => setState(() => relation = v),
          scroll: false,
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Their first name', hintText: 'Ama'),
          onChanged: (v) => name = v,
        ),
        const SizedBox(height: 12),
        TextFormField(
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Their phone number', prefixText: '+233  '),
          onChanged: (v) => setState(() => phone = v),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: RegExp(r'\d').allMatches(phone).length < 7
                ? null
                : () async {
                    try {
                      final v = await ctx.read<AppState>().api.setGuardian(phone: phone, relation: relation, name: name);
                      if (ctx.mounted) Navigator.of(ctx).pop(v);
                    } catch (e) {
                      if (ctx.mounted) showToast(ctx, "Couldn't save that", detail: '$e', ok: false, aboveTabs: false);
                    }
                  },
            child: const Text('Send them the text'),
          ),
        ),
      ]),
    ),
  );
}

/// "Ask your guardian first": for posting, sharing the card or being findable.
/// Returns true if a request went (or was already waiting).
Future<bool> showAskGuardian(BuildContext context, String kind) async {
  final s = context.read<AppState>();
  final (what, sub) = _kindWords[kind]!;
  final ok = await showEditSheet<bool>(
    context,
    title: 'Ask your guardian first',
    child: Builder(
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$what needs a yes from your guardian. $sub We\'ll text them, and let you know when they answer.',
            style: const TextStyle(fontSize: 14.5, height: 1.45, color: Tk.inkSoft)),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Send request'))),
        SizedBox(width: double.infinity, child: TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now'))),
      ]),
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await s.api.askGuardian(kind);
    if (context.mounted) showToast(context, 'Request sent', detail: "We'll let you know when they answer.", ok: true);
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, "Couldn't send it", detail: '$e', ok: false);
    return false;
  }
}
