import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final AuthService _auth = AuthService();
  bool _isLogin = true;
  bool _isLoading = false;

  Future<void> _googleLogin() async {
    setState(() => _isLoading = true);
    try {
      await _auth.signInWithGoogle();
      if (mounted) {
        // Replace LoginScreen with MainScreen instead of popping
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Errore Google: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        // LOGIN FLOW
        await _auth.signIn(_emailCtrl.text.trim(), _passCtrl.text.trim());

        // Modification 1: Security Check
        final user = _auth.currentUser;
        if (user != null && !user.emailVerified) {
          await _auth.signOut(); // Logout immediately
          throw Exception(
            "Email non verificata. Controlla la tua casella di posta.",
          );
        }

        if (mounted) {
          // Replace LoginScreen with MainScreen instead of popping
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MainScreen()),
          );
        }
      } else {
        // REGISTRATION FLOW
        await _auth.signUp(_emailCtrl.text.trim(), _passCtrl.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Registrazione avvenuta! Controlla la posta per verificare l'email.",
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
          // Switch to login mode instead of closing
          setState(() => _isLogin = true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Errore: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? "Accedi" : "Registrati")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: "Email"),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passCtrl,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              FilledButton(
                onPressed: _submit,
                child: Text(_isLogin ? "Accedi" : "Registrati"),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: const Text("Accedi con Google"),
              onPressed: _isLoading ? null : _googleLogin,
            ),
            TextButton(
              onPressed: () => setState(() => _isLogin = !_isLogin),
              child: Text(
                _isLogin
                    ? "Non hai un account? Registrati"
                    : "Hai già un account? Accedi",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
