import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../widgets/code_dialog.dart';

class AddPlayerScreen extends StatefulWidget {
  const AddPlayerScreen({super.key});

  @override
  State<AddPlayerScreen> createState() => _AddPlayerScreenState();
}

class _AddPlayerScreenState extends State<AddPlayerScreen> {
  final _name = TextEditingController();
  Uint8List? _bytes;
  String _ext = 'jpg';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final lower = x.path.toLowerCase();
    setState(() {
      _bytes = bytes;
      _ext = lower.endsWith('.png') ? 'png' : (lower.endsWith('.webp') ? 'webp' : 'jpg');
      _error = null;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2 || name.length > 40) {
      setState(() => _error = 'اسم اللاعب يجب أن يكون بين 2 و 40 حرفًا');
      return;
    }
    if (_bytes == null) {
      setState(() => _error = 'اختر صورة اللاعب');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final path = await uploadAvatar(_bytes!, _ext);
      final code = await createPlayer(name, path);
      if (!mounted) return;
      await showCodeDialog(context, name, code);
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'فشل رفع الصورة. حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة لاعب')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: GestureDetector(
              onTap: _busy ? null : _pick,
              child: CircleAvatar(
                radius: 56,
                backgroundImage: _bytes == null ? null : MemoryImage(_bytes!),
                child: _bytes == null ? const Icon(Icons.add_a_photo, size: 36) : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(child: Text('صورة اللاعب', style: TextStyle(color: Colors.white70))),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'اسم اللاعب'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('حفظ وتوليد الكود'),
          ),
        ],
      ),
    );
  }
}
