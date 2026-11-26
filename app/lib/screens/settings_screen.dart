import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/models.dart';
import '../config.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/ds.dart';
import 'card_screens.dart' show PrivacyScreen;
import 'guardian_screens.dart';
import 'home_screen.dart' show CustomiseHomeScreen;
import 'notifications_screen.dart' show NotificationSettingsScreen;
import 'profile_screen.dart' show MainColourPicker;

/// Settings (canvas: Settings and its sections). Every switch saves as you go.
///
///   Your app          Home screen, Notifications, Main colour, Accessibility,
///                     How Pep talks to you
///   Privacy and data  Privacy and safety, Your guardian, Your data
///   Help and legal    Help, report a problem, terms, privacy, licences
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const version = AppConfig.version;

  void _go(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me;
    final st = s.settings;
    final p = me?.profile;
    final minor = p?.age != null && p!.age! < 18;
    final initials = (p?.displayName ?? '?').split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join().toUpperCase();
    Widget row(String title, String sub, VoidCallback onTap, {Widget? trailing}) => ListTile(
          title: Text(title),
          subtitle: Text(sub),
          trailing: trailing ?? const TIcon('chevron', size: 14, color: Tk.faint),
          onTap: onTap,
        );
    final colour = MainColour.fromName(st.mainColour);
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        Panel(
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: context.accent.tile, borderRadius: BorderRadius.circular(14)),
              child: Text(initials, style: TextStyle(fontWeight: FontWeight.w800, color: context.accent.main)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p?.displayName ?? '', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Tk.ink)),
                Text(
                  minor ? 'Player account · ${me?.guardianStatus == 'approved' ? 'guardian approved' : 'waiting for your guardian'}' : 'Player account',
                  style: const TextStyle(fontSize: 12.5, color: Tk.muted),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Your app'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            row('Home screen', 'Pick your cards and their order', () => _go(context, const CustomiseHomeScreen())),
            row('Notifications', 'Pep, reviews, reminders · quiet 9 pm to 7 am', () => _go(context, const NotificationSettingsScreen())),
            row(
              'Main colour',
              colour.label,
              () => showEditSheet<void>(context, title: 'Main colour', child: const MainColourPicker()),
              trailing: Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: colour.main)),
            ),
            row('Accessibility', 'Text ${st.textSize.toUpperCase()} · ${st.highContrast ? 'higher contrast · ' : ''}${st.reduceMotion ? 'less motion' : 'full motion'}',
                () => _go(context, const AccessibilityScreen())),
            row('How Pep talks to you', '${st.pepVoice == 'street' ? 'Street talk' : 'Coach talk'} · English · ${st.units == 'mph' ? 'mph' : 'metres, km/h'}',
                () => _go(context, const VoiceScreen())),
          ]),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Privacy and data'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            row('Privacy and safety', 'Who can see your profile', () => _go(context, const PrivacyScreen())),
            if (minor) row('Your guardian', me?.guardianStatus == 'approved' ? 'Approved · can change these settings' : 'Waiting for their yes', () => _go(context, const GuardianScreen())),
            row('Your data', '${s.videos.length} clip${s.videos.length == 1 ? '' : 's'} · download or delete', () => _go(context, const DataScreen())),
          ]),
        ),
        const SizedBox(height: 18),
        const SectionLabel('Help and legal'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [row('Help', 'Report a problem, terms, privacy policy', () => _go(context, const HelpScreen()))]),
        ),
        const SizedBox(height: 18),
        OutlinedButton(onPressed: s.logOut, child: const Text('Sign out')),
        const SizedBox(height: 14),
        const Center(child: Text('Tracka $version', style: TextStyle(fontSize: 12, color: Tk.faint))),
      ]),
    );
  }
}

/// Settings › Accessibility.
class AccessibilityScreen extends StatelessWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('Accessibility', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        const SectionLabel('Text size'),
        SingleChips<String>(
          options: const {'s': 'S', 'm': 'M', 'l': 'L', 'xl': 'XL'},
          value: s.settings.textSize,
          onChanged: (v) => s.saveSettings({'textSize': v}),
          scroll: false,
        ),
        const SizedBox(height: 12),
        const Panel(child: Text('Look over your shoulder before the ball comes.', style: TextStyle(fontSize: 15, color: Tk.ink))),
        const SizedBox(height: 6),
        const Text("This adds to your phone's own text size.", style: TextStyle(fontSize: 12, color: Tk.faint)),
        const SizedBox(height: 18),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(children: [
            SwitchListTile(
              title: const Text('Higher contrast'),
              subtitle: const Text('Brighter text and lines on the dark background'),
              value: s.settings.highContrast,
              onChanged: (v) => s.saveSettings({'highContrast': v}),
            ),
            SwitchListTile(
              title: const Text('Less motion'),
              subtitle: const Text("Turn off fades and moving Pep. Your phone's own setting also works."),
              value: s.settings.reduceMotion,
              onChanged: (v) => s.saveSettings({'reduceMotion': v}),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Settings › How Pep talks to you.
class VoiceScreen extends StatelessWidget {
  const VoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final st = s.settings;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('How Pep talks to you', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        const SectionLabel('Voice'),
        SingleChips<String>(
          options: const {'street': 'Street talk', 'coach': 'Coach talk'},
          value: st.pepVoice,
          onChanged: (v) => s.saveSettings({'pepVoice': v}),
          scroll: false,
        ),
        const SizedBox(height: 8),
        Text(st.pepVoice == 'street' ? '"Charlie, you dey check your shoulder well!"' : '"Good scanning before you received the ball."',
            style: const TextStyle(fontSize: 13.5, color: Tk.muted, fontStyle: FontStyle.italic)),
        const SizedBox(height: 18),
        const SectionLabel('Units'),
        SingleChips<String>(
          options: const {'kmh': 'Metres, km/h', 'mph': 'Miles per hour'},
          value: st.units,
          onChanged: (v) => s.saveSettings({'units': v}),
          scroll: false,
        ),
        const SizedBox(height: 18),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(children: [
            const ListTile(title: Text('Language'), subtitle: Text('English. More languages later.')),
            const ListTile(title: Text('Plain football words'), subtitle: Text('No short-hand or slang in the app'), trailing: Text('Always on', style: TextStyle(fontSize: 12, color: Tk.faint))),
            SwitchListTile(
              title: const Text("Pep's AI notes"),
              subtitle: const Text('Pep watches each clip and writes tips. Off: notes come from your numbers only.'),
              value: st.coachNotes,
              onChanged: (v) => s.saveSettings({'coachNotes': v}),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Settings › Your data: Wi-Fi only, download everything, delete clips or the account.
class DataScreen extends StatelessWidget {
  const DataScreen({super.key});

  Future<void> _download(BuildContext context) async {
    final s = context.read<AppState>();
    try {
      final json = await s.api.exportMe();
      await Share.shareXFiles(
        [XFile.fromData(utf8.encode(json), name: 'tracka-my-data.json', mimeType: 'application/json')],
        subject: 'My Tracka data',
      );
    } catch (e) {
      if (context.mounted) showToast(context, "Couldn't get your data", detail: '$e', ok: false, aboveTabs: false);
    }
  }

  Future<void> _deleteClips(BuildContext context) async {
    final s = context.read<AppState>();
    final picked = <String>{};
    await showEditSheet<void>(
      context,
      title: 'Delete clips',
      child: StatefulBuilder(
        builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text("Pick the clips to delete. They're gone for good, with Pep's notes on them.", style: TextStyle(color: Tk.inkSoft)),
          for (final v in s.videos)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: picked.contains(v.id),
              title: Text(v.displayTitle),
              onChanged: (x) => setSheet(() => x == true ? picked.add(v.id) : picked.remove(v.id)),
            ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: picked.isEmpty
                ? null
                : () async {
                    for (final id in picked) {
                      await s.deleteVideo(id);
                    }
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) showToast(context, 'Deleted ${picked.length} clip${picked.length == 1 ? '' : 's'}', aboveTabs: false);
                  },
            child: Text(picked.isEmpty ? 'Pick clips' : 'Delete ${picked.length}'),
          ),
        ]),
      ),
    );
  }

  /// Delete the account. Under 18 with a guardian who approved it, the guardian
  /// has to agree (they get a text and a page); otherwise it's the player's choice.
  Future<void> _deleteAccount(BuildContext context) async {
    final s = context.read<AppState>();
    final me = s.me;
    final minor = me?.profile.age != null && me!.profile.age! < 18;
    if (minor && me.guardianStatus == 'approved') return _askGuardianToDelete(context);
    final ok = await showEditSheet<bool>(
      context,
      title: 'Delete your account?',
      child: Builder(
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text("Your profile, every clip and all of Pep's notes are deleted for good. You can't undo this.",
              style: TextStyle(fontSize: 14.5, height: 1.45, color: Tk.inkSoft)),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Tk.gold, side: const BorderSide(color: Tk.gold)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete everything'),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep my account')),
        ]),
      ),
    );
    if (ok == true) {
      try {
        await s.deleteAccount();
      } catch (e) {
        if (context.mounted) showToast(context, "Couldn't delete it", detail: '$e', ok: false, aboveTabs: false);
      }
    }
  }

  Future<void> _askGuardianToDelete(BuildContext context) async {
    final s = context.read<AppState>();
    GuardianState? g;
    try {
      g = await s.api.guardian();
    } catch (_) {}
    if (!context.mounted) return;
    final waiting = g?.pendingKinds.contains('delete') ?? false;
    final who = g?.who ?? 'your guardian';
    await showEditSheet<void>(
      context,
      title: waiting ? 'Waiting for $who' : 'Ask $who first',
      child: Builder(
        builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            waiting
                ? "We've asked $who to agree to deleting your account. Once they say yes, everything is deleted for good. "
                    'Until then nothing changes.'
                : "Your guardian approved your account, so they need to agree before it's deleted. We'll text them. "
                    "Once they say yes, your profile, clips and training are deleted for good.",
            style: const TextStyle(fontSize: 14.5, height: 1.45, color: Tk.inkSoft),
          ),
          const SizedBox(height: 16),
          if (waiting)
            OutlinedButton(
              onPressed: () async {
                await s.api.cancelDeleteRequest();
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (context.mounted) showToast(context, 'Request taken back', detail: 'Your account stays.', aboveTabs: false);
              },
              child: const Text("I've changed my mind"),
            )
          else
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Tk.gold, side: const BorderSide(color: Tk.gold)),
              onPressed: () async {
                try {
                  await s.api.askGuardian('delete');
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (context.mounted) showToast(context, 'We asked $who', detail: "We'll let you know when they answer.", aboveTabs: false);
                } catch (e) {
                  if (ctx.mounted) showToast(ctx, "Couldn't send it", detail: '$e', ok: false, aboveTabs: false);
                }
              },
              child: Text('Ask $who to delete it'),
            ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Keep my account')),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Text('Your data', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(children: [
            ListTile(title: const Text('Clips on Tracka'), trailing: Text('${s.videos.length}', style: const TextStyle(fontWeight: FontWeight.w700))),
            SwitchListTile(
              title: const Text('Upload on Wi-Fi only'),
              subtitle: const Text('Saves your data. Clips wait on your phone until Wi-Fi.'),
              value: s.settings.uploadOnWifiOnly,
              onChanged: (v) => s.saveSettings({'uploadOnWifiOnly': v}),
            ),
            ListTile(
              title: const Text('Download your data'),
              subtitle: const Text('Everything Tracka holds about you, in one file'),
              trailing: const TIcon('download', size: 18, color: Tk.faint),
              onTap: () => _download(context),
            ),
            ListTile(
              title: const Text('Delete clips'),
              subtitle: const Text('Choose clips'),
              trailing: const TIcon('trash', size: 18, color: Tk.faint),
              onTap: () => _deleteClips(context),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: Tk.gold, side: const BorderSide(color: Color(0x66FFC21A))),
          onPressed: () => _deleteAccount(context),
          child: const Text('Delete my account'),
        ),
        const SizedBox(height: 10),
        const InfoNote('Tracka never sells your data. Only your region is ever shown to others.'),
      ]),
    );
  }
}

/// Settings › Help and legal.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  Future<void> _report(BuildContext context) async {
    final s = context.read<AppState>();
    var text = '';
    var kind = 'problem';
    await showEditSheet<void>(
      context,
      title: 'Report a problem',
      child: StatefulBuilder(
        builder: (ctx, setSheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SingleChips<String>(
            options: const {'problem': 'Something broke', 'safety': 'Someone is unsafe', 'idea': 'An idea'},
            value: kind,
            onChanged: (v) => setSheet(() => kind = v),
            scroll: false,
          ),
          const SizedBox(height: 12),
          TextField(maxLines: 5, maxLength: 2000, decoration: const InputDecoration(hintText: 'What happened?'), onChanged: (v) => setSheet(() => text = v)),
          if (kind == 'safety') const SafetyNote('If someone is in danger right now, tell an adult you trust or call 112.'),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: text.trim().length < 3
                ? null
                : () async {
                    try {
                      await s.api.feedback(text.trim(), kind: kind, appVersion: SettingsScreen.version);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (context.mounted) showToast(context, 'Thanks for telling us', detail: 'We read every report.', aboveTabs: false);
                    } catch (e) {
                      if (ctx.mounted) showToast(ctx, "Couldn't send it", detail: '$e', ok: false, aboveTabs: false);
                    }
                  },
            child: const Text('Send'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
          Text('Help and legal', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 16),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              ListTile(
                title: const Text('Show me around'),
                subtitle: const Text("Pep's tour of Home, again"),
                onTap: () {
                  context.read<AppState>().startTour();
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
              ListTile(title: const Text('Report a problem'), subtitle: const Text('Something broke, someone is unsafe, or an idea'), onTap: () => _report(context)),
              ListTile(
                title: const Text('Terms of use'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _Legal('Terms of use'))),
              ),
              ListTile(
                title: const Text('Privacy policy'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _Legal('Privacy policy'))),
              ),
              ListTile(
                title: const Text('Open-source licences'),
                onTap: () => showLicensePage(context: context, applicationName: 'Tracka', applicationVersion: SettingsScreen.version),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          const InfoNote(InfoNote.pep),
        ]),
      );
}

class _Legal extends StatelessWidget {
  const _Legal(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
          Text(title, style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 14),
          const Text(
            'The full text is being reviewed by a lawyer and will be here before launch. In short: Tracka never sells '
            "personal data, under-18s need a guardian's approval, only your region is ever shown to others, and you can "
            'download or delete your data at any time in Settings › Your data.',
            style: TextStyle(fontSize: 15, height: 1.5, color: Tk.inkSoft),
          ),
        ]),
      );
}
