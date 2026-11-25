import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const TrackaLogo(),
            const Spacer(),
            const Eyebrow('Your game, coached', color: TColors.neon),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Film it.\nGet coached.\n'),
                TextSpan(text: 'Get better.', style: t.displayLarge!.copyWith(color: TColors.neon)),
              ]),
              style: t.displayLarge,
            ),
            const SizedBox(height: 18),
            const Tape(),
            const SizedBox(height: 22),
            const Text(
              'Upload your clips and Pep, your AI coach, measures your speed, touches and movement, '
              'scores you against players your age, and tells you exactly what to practise.',
              style: TextStyle(color: TColors.inkSoft, fontSize: 16, height: 1.45),
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
      if (mounted) showSnack(context, '$e');
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
              widget.signUp ? 'Just an email and a password. Your profile comes next.' : 'Log in to see your clips and Pep\'s notes.',
              style: const TextStyle(color: TColors.inkSoft),
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
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: LoopyIcon(_hide ? 'eye' : 'lock', size: 22, color: TColors.inkSoft),
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
              const Text(
                'Under 18? You can sign up, and we\'ll ask for a parent or guardian\'s email before you upload clips.',
                style: TextStyle(color: TColors.inkFaint, fontSize: 12.5),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
