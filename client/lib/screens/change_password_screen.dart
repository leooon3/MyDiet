import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/error_handler.dart'; // [IMPORTANTE]

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _changePassword() async {
    if (_passCtrl.text.isEmpty || _confirmCtrl.text.isEmpty) return;

    if (_passCtrl.text != _confirmCtrl.text) {
      _showError("Le password non coincidono");
      return;
    }
    // [SECURITY] Password minima aumentata a 12 caratteri
    if (_passCtrl.text.length < 12) {
      _showError("La password deve avere almeno 12 caratteri");
      return;
    }
    // [SECURITY] Verifica complessità password
    final hasUppercase = _passCtrl.text.contains(RegExp(r'[A-Z]'));
    final hasLowercase = _passCtrl.text.contains(RegExp(r'[a-z]'));
    final hasDigit = _passCtrl.text.contains(RegExp(r'[0-9]'));
    if (!hasUppercase || !hasLowercase || !hasDigit) {
      _showError("La password deve contenere maiuscole, minuscole e numeri");
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Utente non loggato");

      await user.updatePassword(_passCtrl.text);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Password aggiornata con successo!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        // [UX] Errore tradotto
        _showError(ErrorMapper.toUserMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Cambia Password")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Icon(Icons.lock_reset, size: 80, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  "Inserisci la tua nuova password.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Nuova Password",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Conferma Password",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _changePassword,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("AGGIORNA PASSWORD"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
