import 'package:flutter/material.dart';

import '../services/api.dart';

class PlayerAvatar extends StatefulWidget {
  final String? path;
  final String name;
  final double radius;
  const PlayerAvatar({super.key, required this.path, required this.name, this.radius = 24});

  @override
  State<PlayerAvatar> createState() => _PlayerAvatarState();
}

class _PlayerAvatarState extends State<PlayerAvatar> {
  Future<String?>? _url;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PlayerAvatar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  void _load() {
    _url = widget.path == null ? null : signedAvatarUrl(widget.path!);
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.name.trim().isEmpty ? '?' : widget.name.trim()[0];
    final fallback = CircleAvatar(
      radius: widget.radius,
      child: Text(initial, style: TextStyle(fontSize: widget.radius * 0.8)),
    );
    if (_url == null) return fallback;
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) return fallback;
        return CircleAvatar(
          radius: widget.radius,
          backgroundImage: NetworkImage(url),
          onBackgroundImageError: (_, __) {},
        );
      },
    );
  }
}
