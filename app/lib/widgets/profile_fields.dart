import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../theme/theme.dart';

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

  // Onboarding v2
  String firstName = '';
  String lastName = '';
  String shirtName = '';
  int? shirtNumber;
  String town = '';
  String? level;
  String? goal;
  String? style;
  int? weakFoot;
  String guardianPhone = '';
  String guardianRelation = 'parent';

  /// Positions in order: the first is the main one.
  List<String> positionOrder = [];

  /// What goes on the shirt: what they typed, or the suggestion; at most 20 letters.
  String get shirtNameToSave {
    final n = shirtName.trim().isEmpty ? suggestedShirtName : shirtName.trim().toUpperCase();
    return n.length > 20 ? n.substring(0, 20) : n;
  }

  /// "K. ASANTE" from "Kwame" "Asante".
  String get suggestedShirtName {
    final f = firstName.trim(), l = lastName.trim();
    if (l.isEmpty) return f.toUpperCase();
    return '${f.isEmpty ? '' : '${f[0]}. '}$l'.toUpperCase();
  }

  int? get age {
    final b = birthDate;
    if (b == null) return null;
    final now = DateTime.now();
    return now.year - b.year - ((now.month < b.month || (now.month == b.month && now.day < b.day)) ? 1 : 0);
  }

  bool get minor => (age ?? 99) < 18;

  /// What onboarding v2 sends (PATCH /v1/me). Only fields that were filled in.
  Map<String, dynamic> toJsonV2() => {
        'displayName': '${firstName.trim()} ${lastName.trim()}'.trim(),
        if (birthDate != null) 'birthDate': DateFormat('yyyy-MM-dd').format(birthDate!),
        if (sex != null) 'sex': sex,
        if (shirtNameToSave.isNotEmpty) 'shirtName': shirtNameToSave,
        if (shirtNumber != null) 'shirtNumber': shirtNumber,
        if (region != null) 'region': region,
        if (town.trim().isNotEmpty) 'town': town.trim(),
        if (level != null) 'level': level,
        if (goal != null) 'goal': goal,
        if (positionOrder.isNotEmpty) 'positions': positionOrder,
        if (style != null) 'style': style,
        if (foot != null) 'foot': foot,
        if (weakFoot != null) 'weakFoot': weakFoot,
        if (heightM != null) 'heightM': heightM,
        if (minor && guardianPhone.trim().isNotEmpty) 'guardianPhone': guardianPhone.trim(),
        if (minor) 'guardianRelation': guardianRelation,
        if (minor && guardianEmail.trim().isNotEmpty) 'guardianEmail': guardianEmail.trim(),
        if (minor) 'guardianConsent': guardianConsent,
      };

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

/// A small label above a field (same look as [SectionLabel]).
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 6),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.ink)),
      );
}

class BirthDateField extends StatelessWidget {
  const BirthDateField({super.key, required this.value, required this.onChanged});

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Tk.rField),
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
            style: TextStyle(color: value == null ? Tk.faint : Tk.ink)),
      ),
    );
  }
}

/// Height with a slider. Pep uses it as a ruler to measure speed from video.
class HeightField extends StatelessWidget {
  const HeightField({super.key, required this.value, required this.onChanged});

  final double? value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value ?? 1.72;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${(v * 100).round()}', style: TType.stat),
        const SizedBox(width: 6),
        const Padding(padding: EdgeInsets.only(bottom: 4), child: Text('cm', style: TextStyle(color: Tk.muted))),
      ]),
      Slider(
        value: v.clamp(1.3, 2.1),
        min: 1.3,
        max: 2.1,
        divisions: 80,
        onChanged: (x) => onChanged(double.parse(x.toStringAsFixed(2))),
      ),
      const Text('Pep uses your height as a ruler to measure speed from your videos.', style: TextStyle(color: Tk.faint, fontSize: 12.5)),
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
      dropdownColor: Tk.card2,
      decoration: const InputDecoration(labelText: 'Region'),
      items: [for (final r in regions) DropdownMenuItem(value: r, child: Text(r))],
      onChanged: onChanged,
    );
  }
}
