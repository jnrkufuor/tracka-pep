import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../widgets/common.dart';

/// Trials, academies and tournaments: coming later.
/// The API route exists (GET /v1/opportunities) and returns nothing yet, so this
/// tab can fill in without an app update once the scouting side is designed.
class OpportunitiesScreen extends StatelessWidget {
  const OpportunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 28), children: [
          const Eyebrow('Coming soon', color: TColors.neon),
          const SizedBox(height: 6),
          Text('Chances', style: t.displayLarge),
          const SizedBox(height: 10),
          const Tape(),
          const SizedBox(height: 26),
          const TCard(
            neon: true,
            accent: 'trophy',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow('On its way', color: TColors.onNeon),
              SizedBox(height: 10),
              Text('Trials, academies and tournaments near you.',
                  style: TextStyle(fontFamily: TType.display, fontSize: 26, fontWeight: FontWeight.w700, height: 1.1)),
              SizedBox(height: 10),
              Text('We\'re building this next. For now, the best thing you can do is upload clips and record the timed drills, '
                  'so your profile is ready when it opens.'),
            ]),
          ),
          const SizedBox(height: 14),
          const TCard(
            child: Row(children: [
              LoopyIcon('lock', color: TColors.neon),
              SizedBox(width: 14),
              Expanded(
                child: Text('Your clips stay private. Nothing is shared with scouts unless you choose to, later, in Settings.',
                    style: TextStyle(color: TColors.inkSoft)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
