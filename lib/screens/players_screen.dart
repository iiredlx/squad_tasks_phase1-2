import 'package:flutter/material.dart';

import '../services/api.dart';
import '../widgets/avatar.dart';
import '../widgets/code_dialog.dart';
import 'add_player_screen.dart';

class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  late Future<List<Map<String, dynamic>>> _future = fetchPlayers();

  void _reload() => setState(() => _future = fetchPlayers());

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _act(Map<String, dynamic> p, String action) async {
    final id = p['id'] as String;
    final name = p['display_name'] as String;
    try {
      if (action == 'regen') {
        if (!await _confirm('توليد كود جديد', 'سيتوقف الكود الحالي وتُنهى جلسات $name. متابعة؟')) return;
        final code = await regenerateCode(id);
        if (!mounted) return;
        await showCodeDialog(context, name, code);
      } else if (action == 'revoke') {
        if (!await _confirm('إلغاء الكود', 'سيُنهى دخول $name فورًا ولن يستطيع الدخول حتى تولّد له كودًا جديدًا. متابعة؟')) return;
        await revokeCode(id);
        _toast('تم إلغاء الكود');
      } else if (action == 'toggle') {
        final active = p['is_active'] == true;
        if (!await _confirm(active ? 'إيقاف اللاعب' : 'تفعيل اللاعب',
            active ? 'سيتم إيقاف $name وإنهاء جلساته. متابعة؟' : 'سيتم تفعيل $name. متابعة؟')) return;
        await setPlayerActive(id, !active);
        _toast(active ? 'تم إيقاف اللاعب' : 'تم تفعيل اللاعب');
      }
      _reload();
    } on AppException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _add() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddPlayerScreen()),
    );
    if (added == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة اللاعبين')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add),
        label: const Text('إضافة لاعب'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('فشل تحميل اللاعبين'),
                  TextButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
                ],
              ),
            );
          }
          final players = snap.data!;
          if (players.isEmpty) {
            return const Center(child: Text('لا يوجد لاعبون بعد. اضغط «إضافة لاعب».'));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: players.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final p = players[i];
                final active = p['is_active'] == true;
                final hasCode = p['has_active_code'] == true;
                return Card(
                  child: ListTile(
                    leading: PlayerAvatar(
                      path: p['avatar_path'] as String?,
                      name: p['display_name'] as String,
                    ),
                    title: Text(p['display_name'] as String),
                    subtitle: Text(
                      '${active ? 'نشط' : 'موقوف'} • ${hasCode ? 'كود فعّال' : 'بدون كود'}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (a) => _act(p, a),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'regen', child: Text('توليد كود جديد')),
                        if (hasCode) const PopupMenuItem(value: 'revoke', child: Text('إلغاء الكود')),
                        PopupMenuItem(value: 'toggle', child: Text(active ? 'إيقاف اللاعب' : 'تفعيل اللاعب')),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
