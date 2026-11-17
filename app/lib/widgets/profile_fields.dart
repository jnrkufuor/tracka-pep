import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/theme.dart';
import 'common.dart';

/// Profile form pieces, shared by onboarding (one step at a time) and Edit profile (all at once).
/// Each holds no state of its own: the parent keeps a [ProfileDraft] and rebuilds.
class ProfileDraft {
  String name = '';
  DateTime? birthDate;
  Set<String> positions = {};
  String? sex;
  double? heightM;
  String? foot;
  String? region;
  String club = '';
  String guardianEmail = '';
  bool guardianConsent = false;

  int? get age {
    final b = birthDate;
    if (b == null) return null;
    final now = DateTime.now();
    return now.year - b.year - ((now.month < b.month || (now.month == b.month && now.day < b.day)) ? 1 : 0);
  }

  bool get minor => (age ?? 99) < 18;

  Map<String, dynamic> toJson() => {
        'displayName': name.trim(),
        if (birthDate != null) 'birthDate': DateFormat('yyyy-MM-dd').format(birthDate!),
        'positions': positions.toList(),
        if (sex != null) 'sex': sex,
        if (heightM != null) 'heightM': heightM,
        if (foot != null) 'foot': foot,
        if (region != null) 'region': region,
        'club': club.trim(),
        if (minor && guardianEmail.trim().isNotEmpty) 'guardianEmail': guardianEmail.trim(),
        if (minor) 'guardianConsent': guardianConsent,
      };
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 10, top: 6), child: Eyebrow(text));
}

class BirthDateField extends StatelessWidget {
  const BirthDateField({super.key, required this.value, required this.onChanged});

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(TRadius.sm),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime(now.year - 16),
          firstDate: DateTime(now.year - 60),
          lastDate: DateTime(now.year - 6),
          initialEntryMode: DatePickerEntryMode.calendarOnly,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Date of birth'),
        child: Text(value == null ? 'Choose a date' : DateFormat.yMMMMd().format(value!),
            style: TextStyle(color: value == null ? TColors.inkFaint : TColors.ink)),
      ),
    );
  }
}

class PositionsPicker extends StatelessWidget {
  const PositionsPicker({super.key, required this.all, required this.selected, required this.onChanged});

  final List<String> all;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  static const names = {
    'GK': 'Goalkeeper', 'CB': 'Centre-back', 'LB': 'Left-back', 'RB': 'Right-back', 'LWB': 'Left wing-back',
    'RWB': 'Right wing-back', 'CDM': 'Defensive mid', 'CM': 'Central mid', 'CAM': 'Attacking mid',
    'LM': 'Left mid', 'RM': 'Right mid', 'LW': 'Left wing', 'RW': 'Right wing', 'CF': 'Centre-forward', 'ST': 'Striker',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final p in all)
        ChoiceChipT(
          label: '$p · ${names[p] ?? p}',
          selected: selected.contains(p),
          onTap: () {
            final next = {...selected};
            if (!next.remove(p)) {
              if (next.length >= 4) return; // up to four positions
              next.add(p);
            }
            onChanged(next);
          },
        ),
    ]);
  }
}

class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  final Map<T, String> options;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: TColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: TColors.line),
      ),
      child: Row(children: [
        for (final e in options.entries)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: value == e.key ? TColors.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(e.value,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13, color: value == e.key ? TColors.bg : TColors.inkSoft)),
              ),
            ),
          ),
      ]),
    );
  }
}

class HeightField extends StatelessWidget {
  const HeightField({super.key, required this.value, required this.onChanged});

  final double? value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value ?? 1.72;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        KitNumber((v * 100).round(), size: 54),
        const SizedBox(width: 6),
        const Padding(padding: EdgeInsets.only(bottom: 6), child: Text('cm', style: TextStyle(color: TColors.inkSoft))),
      ]),
      Slider(
        value: v.clamp(1.3, 2.1),
        min: 1.3,
        max: 2.1,
        divisions: 80,
        activeColor: TColors.neon,
        inactiveColor: TColors.surface3,
        onChanged: (x) => onChanged(double.parse(x.toStringAsFixed(2))),
      ),
      const Text('Pep uses your height as a ruler to measure speed from your videos.',
          style: TextStyle(color: TColors.inkFaint, fontSize: 12.5)),
    ]);
  }
}

class RegionPicker extends StatelessWidget {
  const RegionPicker({super.key, required this.regions, required this.value, required this.onChanged});

  final List<String> regions;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: TColors.surface2,
      decoration: const InputDecoration(labelText: 'Region'),
      items: [for (final r in regions) DropdownMenuItem(value: r, child: Text(r))],
      onChanged: onChanged,
    );
  }
}

class GuardianFields extends StatelessWidget {
  const GuardianFields({super.key, required this.draft, required this.onChanged});

  final ProfileDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text(
        'You\'re under 18, so a parent or guardian needs to agree before you upload clips. '
        'We\'ll email them to let them know about your account.',
        style: TextStyle(color: TColors.inkSoft),
      ),
      const SizedBox(height: 16),
      TextFormField(
        initialValue: draft.guardianEmail,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: "Parent or guardian's email"),
        onChanged: (v) {
          draft.guardianEmail = v;
          onChanged();
        },
      ),
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: draft.guardianConsent,
        activeColor: TColors.neon,
        checkColor: TColors.onNeon,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('My parent or guardian agrees to me using Tracka and uploading my clips'),
        onChanged: (v) {
          draft.guardianConsent = v ?? false;
          onChanged();
        },
      ),
    ]);
  }
}
