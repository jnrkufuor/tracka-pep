import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/brand.dart';
import '../widgets/ds.dart';

/// Welcome (canvas: Welcome). Plain words, the main colour once, no scores.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = context.accent;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const TrackaLogo(),
            const Spacer(),
            Text('YOUR GAME, COACHED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: a.main)),
            const SizedBox(height: 14),
            EnterFade(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Film it.\nGet coached.\n'),
                  TextSpan(text: 'Keep growing.', style: TextStyle(color: a.main)),
                ]),
                style: t.displayLarge,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Film your football and Pep, your AI coach, shows you what went well, what to work on, '
              'and a plan for your week. You see how you compare with players your age.',
              style: TextStyle(color: Tk.inkSoft, fontSize: 16, height: 1.45),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(signUp: true))),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: const Text('Create your account'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen(signUp: false))),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              child: const Text('I already have an account'),
            ),
          ]),
        ),
      ),
    );
  }
}

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

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
            Text(widget.signUp ? 'Create your\naccount' : 'Welcome\nback', style: t.displayMedium),
            const SizedBox(height: 10),
            Text(
              widget.signUp ? 'Just an email and a password. Your profile comes next.' : "Log in to see your clips and Pep's notes.",
              style: const TextStyle(color: Tk.inkSoft),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email',
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _hide,
              autofillHints: [widget.signUp ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: widget.signUp ? 'At least 8 characters' : null,
                suffixIcon: IconButton(
                  tooltip: _hide ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: TIcon(_hide ? 'eye2' : 'lock', size: 20, color: Tk.muted),
                ),
              ),
              validator: (v) => (v ?? '').length >= 8 ? null : 'Use at least 8 characters',
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(widget.signUp ? 'Create account' : 'Log in'),
            ),
            if (widget.signUp) ...[
              const SizedBox(height: 18),
              const InfoNote("Under 18? You can sign up. We'll ask a parent or guardian to say yes before your account opens up."),
            ],
          ]),
        ),
      ),
    );
  }
}
