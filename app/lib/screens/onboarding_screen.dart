import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/profile_fields.dart';

/// Build your profile, one question per page. Pep needs your age (to compare
/// you with players your age), your positions (to know which skills matter
/// most) and your height (its ruler for measuring speed).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final draft = ProfileDraft();
  final _pages = PageController();
  int _step = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().me?.profile;
    if (p != null) {
      draft
        ..name = p.displayName
        ..birthDate = p.birthDate
        ..positions = {...p.positions}
        ..sex = p.sex
        ..heightM = p.heightM
        ..foot = p.foot
        ..region = p.region
        ..club = p.club ?? '';
    }
  }

  int get _steps => draft.minor ? 5 : 4;

  bool get _canContinue => switch (_step) {
        0 => draft.name.trim().length >= 2 && draft.birthDate != null,
        1 => draft.positions.isNotEmpty,
        2 => draft.sex != null,
        3 => true,
        _ => draft.guardianConsent && draft.guardianEmail.contains('@'),
      };

  Future<void> _next() async {
    if (_step < _steps - 1) {
      setState(() => _step++);
      _pages.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
      return;
    }
    setState(() => _busy = true);
    try {
      draft.heightM ??= 1.72;
      await context.read<AppState>().saveProfile(draft.toJson());
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
    _pages.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final meta = context.watch<AppState>().meta;
    final t = Theme.of(context).textTheme;
    Widget page(String eyebrow, String title, String? hint, List<Widget> children) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            Eyebrow(eyebrow, color: TColors.neon),
            const SizedBox(height: 10),
            Text(title, style: t.headlineLarge),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(hint, style: const TextStyle(color: TColors.inkSoft)),
            ],
            const SizedBox(height: 24),
            ...children,
          ],
        );

    return Scaffold(
      appBar: AppBar(
        leading: _step == 0 ? null : IconButton(onPressed: _back, icon: const LoopyIcon('back')),
        title: const TrackaLogo(size: 28),
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: (_step + 1) / _steps, minHeight: 6),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                page('Step 1 · You', 'What should Pep call you?', null, [
                  TextFormField(
                    initialValue: draft.name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Your name'),
                    onChanged: (v) => setState(() => draft.name = v),
                  ),
                  const SizedBox(height: 14),
                  BirthDateField(value: draft.birthDate, onChanged: (d) => setState(() => draft.birthDate = d)),
                  const SizedBox(height: 10),
                  const Text('Your age decides who Pep compares you with: under-15s with under-15s.',
                      style: TextStyle(color: TColors.inkFaint, fontSize: 12.5)),
                ]),
                page('Step 2 · Positions', 'Where do you play?', 'Pick up to four. The first is your main one.', [
                  PositionsPicker(
                    all: meta?.positions ?? const [],
                    selected: draft.positions,
                    onChanged: (s) => setState(() => draft.positions = s),
                  ),
                ]),
                page('Step 3 · Body', 'A bit about you', null, [
                  const FieldLabel('You play in'),
                  Segmented<String>(
                    options: const {'male': "Boys' / men's", 'female': "Girls' / women's"},
                    value: draft.sex,
                    onChanged: (v) => setState(() => draft.sex = v),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('Height'),
                  HeightField(value: draft.heightM, onChanged: (v) => setState(() => draft.heightM = v)),
                  const SizedBox(height: 18),
                  const FieldLabel('Stronger foot'),
                  Segmented<String>(
                    options: const {'left': 'Left', 'right': 'Right', 'both': 'Both'},
                    value: draft.foot,
                    onChanged: (v) => setState(() => draft.foot = v),
                  ),
                ]),
                page('Step 4 · Where', 'Where do you play your football?', 'Optional, but it helps later with trials near you.', [
                  RegionPicker(
                    regions: meta?.regions ?? const [],
                    value: draft.region,
                    onChanged: (v) => setState(() => draft.region = v),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    initialValue: draft.club,
                    decoration: const InputDecoration(labelText: 'Club, academy or school (optional)'),
                    onChanged: (v) => draft.club = v,
                  ),
                ]),
                if (draft.minor)
                  page('Step 5 · Guardian', 'One more thing', null, [
                    GuardianFields(draft: draft, onChanged: () => setState(() {})),
                  ]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: FilledButton(
              onPressed: _canContinue && !_busy ? _next : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(_step == _steps - 1 ? 'Meet Pep' : 'Continue'),
            ),
          ),
        ]),
      ),
    );
  }
}
