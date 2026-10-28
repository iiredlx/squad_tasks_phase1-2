import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api.dart';
import 'admin_dashboard.dart';
import 'home_screen.dart';
import 'player_profile_screen.dart';

class _Resolved {
  final String? role;
  final Map<String, dynamic>? profile;
  const _Resolved(this.role, this.profile);
}

/// يقرر أي شاشة تظهر: الرئيسية، لوحة الأدمن، أو بروفايل اللاعب.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<_Resolved> _future = _resolve();
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = supabase.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.signedOut) {
        if (mounted) setState(() => _future = _resolve());
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<_Resolved> _resolve() async {
    if (supabase.auth.currentSession == null) return const _Resolved(null, null);
    try {
      final p = await fetchMyProfile();
      // لا بروفايل أو الحساب موقوف أو الجلسة ملغاة من الأدمن
      if (p == null || p['is_active'] != true) {
        await signOutSafe();
        return const _Resolved(null, null);
      }
      return _Resolved(p['role'] as String?, p);
    } on AuthException {
      await signOutSafe();
      return const _Resolved(null, null);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST301' || e.code == '401') {
        await signOutSafe();
        return const _Resolved(null, null);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Resolved>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 48),
                    const SizedBox(height: 12),
                    const Text('تعذّر تحميل البيانات. تحقق من الإنترنت.'),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
                      onPressed: () => setState(() => _future = _resolve()),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final r = snap.data!;
        if (r.role == 'admin') return const AdminDashboard();
        if (r.role == 'player') return PlayerProfileScreen(profile: r.profile!);
        return const HomeScreen();
      },
    );
  }
}
