import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'opportunities_screen.dart';
import 'pep_screen.dart';
import 'profile_screen.dart';
import 'videos_screen.dart';

/// The five tabs. Each keeps its scroll position when you switch (IndexedStack).
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int index = 0;

  static const tabs = [
    ('home', 'Home'),
    ('film', 'Videos'),
    ('ai', 'Pep'),
    ('trophy', 'Chances'),
    ('user', 'Profile'),
  ];

  void go(int i) => setState(() => index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: index, children: [
        HomeScreen(onOpenTab: go),
        const VideosScreen(),
        const PepScreen(),
        const OpportunitiesScreen(),
        const ProfileScreen(),
      ]),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: TColors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: TColors.lineSoft),
            ),
            padding: const EdgeInsets.all(5),
            child: Row(children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => go(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: index == i ? TColors.neon : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        LoopyIcon(tabs[i].$1, size: 23, color: index == i ? TColors.onNeon : TColors.inkSoft),
                        const SizedBox(height: 2),
                        Text(tabs[i].$2,
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: index == i ? TColors.onNeon : TColors.inkSoft)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
