import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import 'players_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من حساب الأدمن؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('خروج')),
        ],
      ),
    );
    if (ok == true) await signOutSafe();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = <_Tile>[
      _Tile('إدارة اللاعبين', Icons.groups, () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlayersScreen()));
      }),
      const _Tile('المهام', Icons.checklist, null),
      const _Tile('طلبات الإنجاز', Icons.fact_check, null),
      const _Tile('المتابعة', Icons.insights, null),
      const _Tile('التقويم', Icons.calendar_month, null),
      const _Tile('الإعدادات', Icons.settings, null),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الأدمن'),
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: [for (final t in tiles) _TileCard(t)],
      ),
    );
  }
}

class _Tile {
  final String title;
  final IconData icon;
  final VoidCallback? onTap; // null = يُفعَّل في مرحلة لاحقة
  const _Tile(this.title, this.icon, this.onTap);
}

class _TileCard extends StatelessWidget {
  final _Tile tile;
  const _TileCard(this.tile);

  @override
  Widget build(BuildContext context) {
    final enabled = tile.onTap != null;
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: tile.onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tile.icon, size: 40, color: kAccent),
              const SizedBox(height: 10),
              Text(tile.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (!enabled)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('قريبًا', style: TextStyle(fontSize: 12, color: Colors.white60)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
