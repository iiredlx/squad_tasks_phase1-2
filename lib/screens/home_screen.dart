import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import 'admin_login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'أدخل كود الحساب');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await playerLogin(code);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // في الواجهة العربية (RTL) تظهر actions في أعلى اليسار
        actions: [
          IconButton(
            tooltip: 'دخول الأدمن',
            icon: const Icon(Icons.admin_panel_settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: kAccent.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.military_tech, size: 54, color: kAccent),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Squad Tasks',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text('أدخل كود حسابك للدخول', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 28),
                TextField(
                  controller: _code,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(fontSize: 18, letterSpacing: 1.5),
                  decoration: InputDecoration(
                    hintText: 'XXXX-XXXX-XXXX-XXXX',
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('دخول'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
