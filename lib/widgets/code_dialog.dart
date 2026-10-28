import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// يعرض الكود مرة واحدة فقط (الخادم يخزّن بصمة الكود لا الكود نفسه).
Future<void> showCodeDialog(BuildContext context, String playerName, String code) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text('كود دخول $playerName'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              code,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 20, letterSpacing: 1.5, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'انسخ الكود وأرسله للاعب الآن. لن يظهر مرة أخرى، ويمكنك توليد كود جديد لاحقًا.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('نسخ'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('تم نسخ الكود')),
              );
            }
          },
        ),
        TextButton.icon(
          icon: const Icon(Icons.share),
          label: const Text('مشاركة'),
          onPressed: () => Share.share('كود دخولك إلى Squad Tasks:\n$code'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('تم'),
        ),
      ],
    ),
  );
}
