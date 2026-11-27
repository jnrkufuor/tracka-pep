import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/brand.dart';
import '../widgets/ds.dart';

// Sign up and log in (canvas: 1 · Onboarding › Welcome, Sign up: phone,
// Sign up: email, Log in).
//
// The boards lead with a phone number and offer Google, Apple and Facebook.
// Email works today; the others say "Coming soon" until they're wired up
// (texts need the SMS provider; social sign-in needs Firebase Authentication).
// The screens are built as designed now, so switching each one on later is a
// change to its button, not a redesign.

/// One place that says a sign-in method isn't ready yet.
void _comingSoon(BuildContext context, String what) =>
    showToast(context, 'Coming soon', detail: '$what is on its way. Use email for now.', ok: false, aboveTabs: false);

// ─────────────────────────────────────────── Welcome

/// Welcome (canvas: Welcome). A pitch at the top with the logo, a player card
/// with what Tracka does floating around it, "Keep moving forward.", then the
/// ways to start.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = context.accent;
    final mq = MediaQuery.of(context);
    // The board is 900 tall. On shorter phones the picture gives up height
    // first, so the buttons always fit without scrolling.
    final heroH = (mq.size.height - 440 - mq.padding.top - mq.padding.bottom).clamp(280.0, 460.0);
    void go(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      backgroundColor: Tk.bg,
      // Fills the screen with the buttons at the bottom; on a short phone or
      // with very large text it scrolls instead of cutting anything off.
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: mq.size.height),
          child: IntrinsicHeight(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Hero(height: heroH, topInset: mq.padding.top),
              Transform.translate(
                offset: const Offset(0, -14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    EnterFade(child: Text('Keep moving\nforward.', style: t.displayMedium)),
                    const SizedBox(height: 10),
                    const Text(
                      'Track your progress, train with purpose and take the next step in your football.',
                      style: TextStyle(fontSize: 15, height: 1.45, color: Tk.muted),
                    ),
                  ]),
                ),
              ),
              const Spacer(),
              Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + mq.padding.bottom),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _Cta(icon: 'you', label: 'Start with your phone number', onTap: () => go(const PhoneScreen())),
                  const SizedBox(height: 10),
                  _Cta(icon: 'mail', label: 'Continue with email', ghost: true, onTap: () => go(const AuthScreen(signUp: true))),
                  const SizedBox(height: 10),
                  const _SocialRow(),
                  const SizedBox(height: 12),
                  _SwitchLine(lead: 'Already have an account?', action: 'Log in', onTap: () => go(const AuthScreen(signUp: false)), colour: a.main),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The top of Welcome: the pitch, the logo, a player card and four chips.
class _Hero extends StatelessWidget {
  const _Hero({required this.height, required this.topInset});

  final double height;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    // The screen's width, not a LayoutBuilder: the page measures its height
    // first (IntrinsicHeight), and a LayoutBuilder can't be measured that way.
    final w = MediaQuery.sizeOf(context).width;
    return SizedBox(
      height: height + topInset,
      child: Builder(builder: (context) {
        final k = height / 460; // board positions are for a 460-tall picture
        double y(double v) => topInset + v * k;
        final cardW = math.min(w * 0.43, 168.0) * (0.85 + 0.15 * k);
        return Stack(clipBehavior: Clip.hardEdge, children: [
          const Positioned.fill(child: CustomPaint(painter: PitchPainter())),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, 0.45, 1],
                  colors: [Color(0x99000000), Color(0x40000000), Tk.bg],
                ),
              ),
            ),
          ),
          Positioned(left: 24, top: topInset + 16, child: const TrackaLogo(size: 30)),
          // The player card, tilted, in the middle.
          Positioned(
            left: (w - cardW) / 2,
            top: y(194),
            child: Transform.rotate(angle: -3 * math.pi / 180, child: _PlayerCard(size: cardW, accent: a.main, onAccent: a.on)),
          ),
          Positioned(
            left: math.max(w * 0.03, w / 2 - 170),
            top: y(150),
            child: _Chip(icon: 'cone', tile: a.tile, iconColour: a.main, small: "Today's drill", text: 'Scan before you receive', size: 13),
          ),
          Positioned(
            right: math.max(w * 0.02, w / 2 - 186),
            top: y(232),
            child: _Chip(icon: 'check', tile: a.main, iconColour: a.on, round: true, small: 'This week', text: '3 of 4 sessions', size: 12),
          ),
          Positioned(
            left: math.max(w * 0.03, w / 2 - 178),
            top: y(292),
            child: _Chip(icon: 'up', tile: a.tile, iconColour: a.main, small: 'Sprint test', text: 'New PB', size: 10.5),
          ),
          Positioned(
            right: math.max(w * 0.03, w / 2 - 164),
            top: y(358),
            child: _Chip(icon: 'trophy', tile: Tk.goldTile, iconColour: Tk.gold, small: 'Juggling', text: '42 in a row', size: 12.5),
          ),
        ]);
      }),
    );
  }
}

/// A grass pitch at night, drawn rather than photographed: mowing stripes and
/// a chalk line. No photo means no brand logos and nothing to download.
class PitchPainter extends CustomPainter {
  const PitchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1C3A22));
    // Mowing stripes, slightly angled, alternating shades.
    final stripe = Paint()..color = const Color(0xFF214528);
    const n = 7;
    final sw = size.width / n;
    for (var i = 0; i < n + 2; i += 2) {
      final p = Path()
        ..moveTo(i * sw - 40, 0)
        ..lineTo((i + 1) * sw - 40, 0)
        ..lineTo((i + 1) * sw + 40, size.height)
        ..lineTo(i * sw + 40, size.height)
        ..close();
      canvas.drawPath(p, stripe);
    }
    // A touchline and the curve of a centre circle, in chalk.
    final chalk = Paint()
      ..color = const Color(0x8CFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawLine(Offset(size.width * 0.06, 0), Offset(size.width * 0.16, size.height), chalk);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(size.width * 0.78, size.height * 1.05), radius: size.width * 0.42),
      math.pi * 1.05,
      math.pi * 0.55,
      false,
      chalk,
    );
    // A soft light from above, like floodlights.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.6),
          radius: 0.9,
          colors: [Color(0x26FFFFFF), Color(0x00FFFFFF)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.size, required this.accent, required this.onAccent});

  final double size;
  final Color accent;
  final Color onAccent;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Tk.card2,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 24))],
        ),
        child: Column(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: const ColoredBox(
                color: Color(0xFF1E1E1E),
                child: SizedBox.expand(child: CustomPaint(painter: _SilhouettePainter())),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999)),
              child: Text('CM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: onAccent)),
            ),
            const Spacer(),
            const Text('#8', style: TextStyle(fontFamily: TType.display, fontSize: 18, fontWeight: FontWeight.w600, color: Tk.ink)),
          ]),
        ]),
      );
}

/// A head and shoulders, like the board's placeholder photo.
class _SilhouettePainter extends CustomPainter {
  const _SilhouettePainter();

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = const Color(0xFF2C2C2C);
    final u = s.width / 108;
    final bottom = s.height;
    canvas.drawCircle(Offset(s.width / 2, bottom - 52 * u), 16 * u, p);
    final body = Path()
      ..moveTo(s.width / 2 - 32 * u, bottom)
      ..cubicTo(s.width / 2 - 29 * u, bottom - 22 * u, s.width / 2 - 17 * u, bottom - 34 * u, s.width / 2, bottom - 34 * u)
      ..cubicTo(s.width / 2 + 17 * u, bottom - 34 * u, s.width / 2 + 29 * u, bottom - 22 * u, s.width / 2 + 32 * u, bottom)
      ..close();
    canvas.drawPath(body, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A floating chip on the Welcome picture: a small icon, a label, a line.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.tile,
    required this.iconColour,
    required this.small,
    required this.text,
    required this.size,
    this.round = false,
  });

  final String icon;
  final Color tile;
  final Color iconColour;
  final String small;
  final String text;
  final double size;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final t = size * 1.75;
    return MediaQuery.withNoTextScaling(
      // Decoration: keeps its size so it can't cover the headline with big text.
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.85, vertical: size * 0.6),
        decoration: BoxDecoration(
          color: const Color(0xF0121212),
          border: Border.all(color: Tk.lineStrong, width: 1.5),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 34, offset: Offset(0, 14))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: t,
            height: t,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(round ? 999 : 7)),
            child: TIcon(icon, size: t * 0.55, color: iconColour, stroke: 4),
          ),
          SizedBox(width: size * 0.55),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(small, style: TextStyle(fontSize: size * 0.82, fontWeight: FontWeight.w500, color: Tk.muted)),
            Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: Tk.ink)),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────── shared pieces

/// The board's big rounded buttons: main colour, or dark with a border.
class _Cta extends StatelessWidget {
  const _Cta({required this.label, required this.onTap, this.icon, this.ghost = false, this.busy = false, this.size = 15});

  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final bool ghost;
  final bool busy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final fg = ghost ? Tk.ink : a.on;
    return Semantics(
      button: true,
      child: Pressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: Tk.btnMain),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ghost ? Tk.field : (onTap == null ? a.main.withValues(alpha: 0.45) : a.main),
            borderRadius: BorderRadius.circular(999),
            border: ghost ? Border.all(color: const Color(0xFF333333), width: 1.5) : null,
          ),
          child: busy
              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[TIcon(icon!, size: 16, color: fg, stroke: 4), const SizedBox(width: 8)],
                  Flexible(
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: size, fontWeight: FontWeight.w600, color: fg)),
                  ),
                ]),
        ),
      ),
    );
  }
}

class _SocialRow extends StatelessWidget {
  const _SocialRow();

  @override
  Widget build(BuildContext context) => Row(children: [
        for (final (i, name) in const ['Google', 'Apple', 'Facebook'].indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _Cta(label: name, ghost: true, size: 14, onTap: () => _comingSoon(context, '$name sign-in'))),
        ],
      ]);
}

class _SwitchLine extends StatelessWidget {
  const _SwitchLine({required this.lead, required this.action, required this.onTap, required this.colour});

  final String lead;
  final String action;
  final VoidCallback onTap;
  final Color colour;

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(
          onPressed: onTap,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$lead ', style: const TextStyle(fontWeight: FontWeight.w500, color: Tk.faint)),
              TextSpan(text: action, style: TextStyle(fontWeight: FontWeight.w600, color: colour)),
            ]),
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
}

/// The page header on the sign-in screens: a small label, then the question.
Widget _title(BuildContext context, String label, String title) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Tk.muted)),
      const SizedBox(height: 6),
      Text(title, style: Theme.of(context).textTheme.headlineLarge),
    ]);

/// +233 and the number (canvas: Sign up: phone).
class _PhoneField extends StatelessWidget {
  const _PhoneField();

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Tk.field, borderRadius: BorderRadius.circular(Tk.rField), border: Border.all(color: Tk.lineStrong)),
          child: const Text('+233', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Tk.ink)),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: TextField(
            keyboardType: TextInputType.phone,
            autofillHints: [AutofillHints.telephoneNumberNational],
            decoration: InputDecoration(labelText: 'Phone number', hintText: '24 123 4567'),
          ),
        ),
      ]);
}

// ─────────────────────────────────────────── Sign up: phone

/// Sign up with a phone number (canvas: Sign up: phone). Built as designed;
/// sending the code switches on with the SMS provider.
class PhoneScreen extends StatelessWidget {
  const PhoneScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
            _title(context, 'Sign up', "What's your number?"),
            const SizedBox(height: 26),
            const _PhoneField(),
            const SizedBox(height: 10),
            const Text("We'll text you a 6-digit code.", style: TextStyle(fontSize: 13.5, color: Tk.muted)),
            const SizedBox(height: 14),
            const InfoNote('Signing up by text is coming soon. Use your email for now: it takes a minute.'),
            const SizedBox(height: 22),
            _Cta(label: 'Send code', onTap: () => _comingSoon(context, 'Signing up by text')),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen(signUp: true))),
                child: const Text('Use email instead'),
              ),
            ),
          ]),
        ),
      );
}

// ─────────────────────────────────────────── Sign up: email · Log in

/// Sign up with email (canvas: Sign up: email) and Log in (canvas: Log in,
/// Phone and Email tabs).
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.signUp});

  final bool signUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  bool _byPhone = false; // Log in: the Phone / Email switch

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_byPhone) return _comingSoon(context, 'Logging in by text');
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final nav = Navigator.of(context);
    try {
      if (widget.signUp) {
        await state.signUp(_email.text.trim(), _password.text);
      } else {
        await state.logIn(_email.text.trim(), _password.text);
      }
      nav.popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showToast(context, widget.signUp ? "Couldn't create your account" : "Couldn't log you in", detail: '$e', ok: false, aboveTabs: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The password rules from the board, ticked as you type.
  Widget _rule(String text, bool ok) => Padding(
        padding: const EdgeInsets.only(right: 14, top: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TIcon(ok ? 'check' : 'close', size: 14, color: ok ? context.accent.main : Tk.faint, stroke: 5),
          const SizedBox(width: 5),
          Flexible(child: Text(text, style: TextStyle(fontSize: 13, color: ok ? Tk.ink : Tk.faint))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final a = context.accent;
    final p = _password.text;
    final up = widget.signUp;
    void swap(Widget page) => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
            _title(context, up ? 'Sign up' : 'Log in', up ? 'Your email and a password' : 'Welcome back'),
            const SizedBox(height: 22),
            if (!up) ...[
              SingleChips<bool>(options: const {true: 'Phone', false: 'Email'}, value: _byPhone, onChanged: (v) => setState(() => _byPhone = v), scroll: false),
              const SizedBox(height: 18),
            ],
            if (_byPhone) ...[
              const _PhoneField(),
              const SizedBox(height: 10),
              const Text("We'll text you a code to log in.", style: TextStyle(fontSize: 13.5, color: Tk.muted)),
              const SizedBox(height: 10),
              const InfoNote('Logging in by text is coming soon. Use your email for now.'),
            ] else ...[
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email', hintText: 'kwame.mensah@gmail.com'),
                validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: _hide,
                autofillHints: [up ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(
                  labelText: up ? 'Create a password' : 'Password',
                  suffixIcon: TextButton(onPressed: () => setState(() => _hide = !_hide), child: Text(_hide ? 'Show' : 'Hide')),
                ),
                validator: (v) => !up || (v ?? '').length >= 8 ? null : 'Use at least 8 characters',
                onFieldSubmitted: (_) => _submit(),
              ),
              if (up)
                Wrap(children: [
                  _rule('At least 8 characters', p.length >= 8),
                  _rule('A number', RegExp(r'\d').hasMatch(p)),
                  _rule('A letter', RegExp(r'[A-Za-z]').hasMatch(p)),
                ])
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => _comingSoon(context, 'Resetting your password'), child: const Text('Forgot password?')),
                ),
            ],
            const SizedBox(height: 24),
            _Cta(label: up ? 'Create account' : (_byPhone ? 'Send code' : 'Log in'), busy: _busy, onTap: _busy ? null : _submit),
            if (up) ...[
              const SizedBox(height: 6),
              Center(child: TextButton(onPressed: () => swap(const PhoneScreen()), child: const Text('Use phone number instead'))),
              const SizedBox(height: 10),
              const InfoNote("Under 18? You can sign up. We'll ask a parent or guardian to say yes before your account opens up."),
            ] else ...[
              const SizedBox(height: 18),
              const Row(children: [
                Expanded(child: Divider(color: Tk.line)),
                Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: Tk.faint))),
                Expanded(child: Divider(color: Tk.line)),
              ]),
              const SizedBox(height: 18),
              const _SocialRow(),
              const SizedBox(height: 10),
              _SwitchLine(lead: 'New here?', action: 'Sign up', onTap: () => swap(const AuthScreen(signUp: true)), colour: a.main),
            ],
          ]),
        ),
      ),
    );
  }
}
