import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

SupabaseClient get supabase => Supabase.instance.client;

class AppException implements Exception {
  final String message;
  AppException(this.message);
  @override
  String toString() => message;
}

String _arabicError(String? code) {
  switch (code) {
    case 'invalid_code':
      return 'الكود غير صحيح';
    case 'too_many_attempts':
      return 'محاولات كثيرة. حاول بعد قليل';
    case 'forbidden':
      return 'ليس لديك صلاحية لهذه العملية';
    case 'invalid_name':
      return 'اسم اللاعب يجب أن يكون بين 2 و 40 حرفًا';
    case 'not_found':
      return 'اللاعب غير موجود';
    default:
      return 'حدث خطأ غير متوقع. حاول مرة أخرى';
  }
}

Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
  try {
    final res = await supabase.functions.invoke('squad', body: body);
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw AppException(_arabicError(null));
  } on AppException {
    rethrow;
  } on FunctionException catch (e) {
    final d = e.details;
    throw AppException(_arabicError(d is Map ? d['error']?.toString() : null));
  } catch (_) {
    throw AppException('تعذّر الاتصال. تحقق من الإنترنت');
  }
}

// ---------- الدخول والخروج ----------
Future<void> _startSession(Map<String, dynamic> r) async {
  final token = r['refresh_token'];
  if (token is! String) throw AppException(_arabicError(null));
  try {
    await supabase.auth.setSession(token);
  } catch (_) {
    throw AppException('تعذّر بدء الجلسة. حاول مرة أخرى');
  }
}

Future<void> playerLogin(String code) async =>
    _startSession(await _call({'action': 'player_login', 'code': code}));

Future<void> adminLogin(String code) async =>
    _startSession(await _call({'action': 'admin_login', 'code': code}));

Future<void> signOutSafe() async {
  try {
    await supabase.auth.signOut();
  } catch (_) {
    // تجاهل أخطاء الشبكة: الجلسة المحلية تُمسح على كل حال
  }
}

// ---------- البروفايل ----------
Future<Map<String, dynamic>?> fetchMyProfile() async {
  final user = supabase.auth.currentUser;
  if (user == null) return null;
  return await supabase.from('profiles').select().eq('id', user.id).maybeSingle();
}

// ---------- إدارة اللاعبين (أدمن) ----------
Future<List<Map<String, dynamic>>> fetchPlayers() async {
  final rows = await supabase.rpc('admin_list_players');
  return List<Map<String, dynamic>>.from(rows as List);
}

Future<String> uploadAvatar(Uint8List bytes, String ext) async {
  final path = 'players/${const Uuid().v4()}.$ext';
  final mime = ext == 'png'
      ? 'image/png'
      : ext == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
  await supabase.storage
      .from('avatars')
      .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
  return path;
}

Future<String> createPlayer(String name, String avatarPath) async {
  final r = await _call({
    'action': 'create_player',
    'name': name,
    'avatar_path': avatarPath,
  });
  return r['code'] as String;
}

Future<String> regenerateCode(String playerId) async {
  final r = await _call({'action': 'regenerate_code', 'player_id': playerId});
  return r['code'] as String;
}

Future<void> revokeCode(String playerId) async {
  await _call({'action': 'revoke_code', 'player_id': playerId});
}

Future<void> setPlayerActive(String playerId, bool active) async {
  await _call({'action': 'set_active', 'player_id': playerId, 'is_active': active});
}

// ---------- روابط الصور الموقّعة (الحاويات خاصة) ----------
class _Signed {
  final String url;
  final DateTime expires;
  _Signed(this.url, this.expires);
}

final Map<String, _Signed> _urlCache = {};

Future<String?> signedAvatarUrl(String path) async {
  final c = _urlCache[path];
  if (c != null && c.expires.isAfter(DateTime.now())) return c.url;
  try {
    final url = await supabase.storage.from('avatars').createSignedUrl(path, 3600);
    _urlCache[path] = _Signed(url, DateTime.now().add(const Duration(minutes: 50)));
    return url;
  } catch (_) {
    return null;
  }
}
