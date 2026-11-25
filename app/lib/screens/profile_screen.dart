import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/ds.dart';
import '../widgets/profile_fields.dart';
import '../widgets/skill_areas_view.dart';
import 'card_screens.dart';
import 'guardian_screens.dart';
import 'notifications_screen.dart' show NotificationSettingsScreen;

/// Your profile and settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me;
    if (me == null) return const SizedBox.shrink();
    final p = me.profile;
    final st = me.settings;
    final t = Theme.of(context).textTheme;
    final initials = p.displayName.split(' ').where((w) => w.isNotEmpty).map((w) => w[0]).take(2).join().toUpperCase();

    Future<void> setting(String key, Object value) async {
      try {
        await s.saveSettings({key: value});
      } catch (e) {
        if (context.mounted) showSnack(context, '$e');
      }
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 32), children: [
          Row(children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: TColors.surface3, borderRadius: BorderRadius.circular(20)),
              child: Text(initials, style: const TextStyle(fontFamily: TType.display, fontSize: 24, fontWeight: FontWeight.w700, color: TColors.neon)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.displayName, style: t.headlineMedium),
                Text([p.positions.join(' / '), if (p.age != null) '${p.age} yrs', if (p.region != null) p.region].join(' · '),
                    style: const TextStyle(color: TColors.inkSoft)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
                icon: const LoopyIcon('pencil', size: 20),
                label: const Text('Edit profile'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShareCardScreen())),
                icon: TIcon('share', size: 18, color: context.accent.on),
                label: const Text('Share'),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          TCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(children: [
              _Info('Height', p.heightM == null ? '–' : '${(p.heightM! * 100).round()} cm'),
              _Info('Stronger foot', p.foot ?? '–'),
              _Info('Club', (p.club ?? '').isEmpty ? '–' : p.club!),
              _Info('Born', p.birthDate == null ? '–' : DateFormat.yMMMd().format(p.birthDate!)),
              _Info('Email', me.email),
            ]),
          ),
          if (s.coach?.skillAreas != null) ...[
            const SizedBox(height: 26),
            SkillAreasView(areas: s.coach!.skillAreas!),
          ],
          const SizedBox(height: 26),
          const Eyebrow('Settings'),
          const SizedBox(height: 10),
          TCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(children: [
              ListTile(
                title: const Text('Speed in'),
                trailing: SizedBox(
                  width: 150,
                  child: Segmented<String>(
                    options: const {'kmh': 'km/h', 'mph': 'mph'},
                    value: st.units,
                    onChanged: (v) => setting('units', v),
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text('AI coach notes'),
                subtitle: const Text('Pep\'s AI watches each clip and writes tips. Off: notes come from your numbers only.'),
                value: st.coachNotes,
                onChanged: (v) => setting('coachNotes', v),
              ),
              ListTile(
                title: const Text('Notifications'),
                subtitle: const Text('Pep, reviews, reminders · quiet 9 pm to 7 am'),
                trailing: const TIcon('chevron', size: 14, color: Tk.faint),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationSettingsScreen())),
              ),
              ListTile(
                title: const Text('Main colour'),
                subtitle: Text(MainColour.fromName(st.mainColour).label),
                trailing: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: MainColour.fromName(st.mainColour).main),
                ),
                onTap: () => showEditSheet<void>(context, title: 'Main colour', child: const MainColourPicker()),
              ),
              SwitchListTile(
                title: const Text('Reduce motion'),
                subtitle: const Text('Less movement on screen. Your phone\'s own setting also works.'),
                value: st.reduceMotion,
                onChanged: (v) => setting('reduceMotion', v),
              ),
              SwitchListTile(
                title: const Text('Upload on Wi-Fi only'),
                subtitle: const Text('Saves your data. Clips wait until you\'re on Wi-Fi.'),
                value: st.uploadOnWifiOnly,
                onChanged: (v) => setting('uploadOnWifiOnly', v),
              ),
              ListTile(
                title: const Text('Privacy and safety'),
                subtitle: const Text('Who can see your profile'),
                trailing: const TIcon('chevron', size: 14, color: Tk.faint),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyScreen())),
              ),
              if (p.age != null && p.age! < 18)
                ListTile(
                  title: const Text('Your guardian'),
                  subtitle: Text(switch (me.guardianStatus) {
                    'approved' => 'Approved · can change these settings',
                    'pending' => 'Waiting for their yes',
                    _ => 'Not approved yet',
                  }),
                  trailing: const TIcon('chevron', size: 14, color: Tk.faint),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuardianScreen())),
                ),
            ]),
          ),
          const SizedBox(height: 26),
          const Eyebrow('Account'),
          const SizedBox(height: 10),
          TCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(children: [
              ListTile(
                leading: const LoopyIcon('logout', size: 22),
                title: const Text('Log out'),
                onTap: () => s.logOut(),
              ),
              ListTile(
                leading: const LoopyIcon('trash', size: 22, color: TColors.cherry),
                title: const Text('Delete my account', style: TextStyle(color: TColors.cherry)),
                subtitle: const Text('Deletes your profile, every clip and all of Pep\'s notes.'),
                onTap: () => _confirmDelete(context),
              ),
            ]),
          ),
          const SizedBox(height: 26),
          const Center(child: TrackaMark(size: 26, color: TColors.inkFaint)),
          const SizedBox(height: 6),
          const Center(child: Text('Tracka · Pep', style: TextStyle(color: TColors.inkFaint, fontSize: 12))),
        ]),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final s = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TColors.surface,
        title: const Text('Delete your account?'),
        content: const Text('Your profile, every clip and all of Pep\'s notes are deleted for good. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep my account')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: TColors.cherry),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await s.deleteAccount();
      } catch (e) {
        if (context.mounted) showSnack(context, '$e');
      }
    }
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(children: [
        Text(label, style: const TextStyle(color: TColors.inkSoft)),
        const Spacer(),
        Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final draft = ProfileDraft();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().me!.profile;
    draft
      ..name = p.displayName
      ..birthDate = p.birthDate
      ..positions = {...p.positions}
      ..sex = p.sex
      ..heightM = p.heightM
      ..foot = p.foot
      ..region = p.region
      ..club = p.club ?? ''
      ..guardianEmail = p.guardianEmail ?? ''
      ..guardianConsent = p.guardianConsent;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final nav = Navigator.of(context);
    try {
      await context.read<AppState>().saveProfile(draft.toJson());
      nav.pop();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = context.watch<AppState>().meta;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
          TextFormField(
            initialValue: draft.name,
            decoration: const InputDecoration(labelText: 'Your name'),
            onChanged: (v) => draft.name = v,
          ),
          const SizedBox(height: 14),
          BirthDateField(value: draft.birthDate, onChanged: (d) => setState(() => draft.birthDate = d)),
          const FieldLabel('Positions'),
          PositionsPicker(all: meta?.positions ?? const [], selected: draft.positions, onChanged: (v) => setState(() => draft.positions = v)),
          const SizedBox(height: 8),
          const FieldLabel('You play in'),
          Segmented<String>(
            options: const {'male': "Boys' / men's", 'female': "Girls' / women's"},
            value: draft.sex,
            onChanged: (v) => setState(() => draft.sex = v),
          ),
          const SizedBox(height: 8),
          const FieldLabel('Height'),
          HeightField(value: draft.heightM, onChanged: (v) => setState(() => draft.heightM = v)),
          const FieldLabel('Stronger foot'),
          Segmented<String>(
            options: const {'left': 'Left', 'right': 'Right', 'both': 'Both'},
            value: draft.foot,
            onChanged: (v) => setState(() => draft.foot = v),
          ),
          const SizedBox(height: 18),
          RegionPicker(regions: meta?.regions ?? const [], value: draft.region, onChanged: (v) => setState(() => draft.region = v)),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: draft.club,
            decoration: const InputDecoration(labelText: 'Club, academy or school'),
            onChanged: (v) => draft.club = v,
          ),
          if (draft.minor) ...[
            const SizedBox(height: 18),
            GuardianFields(draft: draft, onChanged: () => setState(() {})),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy || draft.positions.isEmpty ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Save'),
          ),
        ]),
      ),
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
