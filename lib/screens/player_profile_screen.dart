import 'package:flutter/material.dart';

import '../services/api.dart';
import '../widgets/avatar.dart';

/// بروفايل اللاعب — في المرحلة 1 يعرض الاسم والصورة فقط.
/// قائمة المهام والإنجازات تُضاف في المرحلتين 2 و3.
class PlayerProfileScreen extends StatelessWidget {
  final Map<String, dynamic> profile;
  const PlayerProfileScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final name = profile['display_name'] as String;
    return Scaffold(
      appBar: AppBar(
        title: const Text('بروفايلي'),
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: () => signOutSafe(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PlayerAvatar(path: profile['avatar_path'] as String?, name: name, radius: 56),
            const SizedBox(height: 16),
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            const Text('لا توجد مهام مسندة إليك بعد', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
