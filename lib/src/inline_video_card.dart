import 'dart:async';
import 'dart:io';

// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'live_media_resolver.dart';
import 'models.dart';
import 'ui_tokens.dart';

/// Manages at most one active inline video/Live Photo player across the gallery
/// so scrolling or switching cards never leaks native decoders or locks files during export.
class InlinePlaybackManager extends ChangeNotifier {
  Player? _player;
  VideoController? _controller;
  final List<StreamSubscription<dynamic>> _subs = [];
  String? _activePath;
  bool _loading = false;
  bool _playing = false;
  bool _muted = false;
  int _generation = 0;

  String? get activePath => _activePath;
  VideoController? get controller => _controller;
  bool get isLoading => _loading;
  bool get isPlaying => _playing;
  bool get isMuted => _muted;

  bool isActive(String path) => _activePath == path;

  Future<void> toggle(MediaAsset asset) async {
    if (_activePath == asset.path) {
      await stop();
      return;
    }
    await playAsset(asset);
  }

  Future<void> playAsset(MediaAsset asset) async {
    final gen = ++_generation;
    await _disposeInternal(notify: false);
    _activePath = asset.path;
    _loading = true;
    _playing = false;
    notifyListeners();

    try {
      final resolved = await LiveMediaResolver.resolve(asset);
      if (gen != _generation || resolved.videoPath == null) {
        if (gen == _generation) await stop();
        return;
      }
      MediaKit.ensureInitialized();
      final player = Player();
      final video = VideoController(player);
      _player = player;
      _controller = video;

      _subs.addAll([
        player.stream.playing.listen((val) {
          if (gen == _generation) {
            _playing = val;
            notifyListeners();
          }
        }),
        player.stream.error.listen((_) {
          if (gen == _generation) {
            unawaited(stop());
          }
        }),
      ]);

      await video.platform.future;
      if (gen != _generation) return;

      await player.setPlaylistMode(PlaylistMode.single);
      await player.setVolume(_muted ? 0 : 100);
      if (gen != _generation) return;

      await player.open(
        Media(File(resolved.videoPath!).absolute.uri.toString()),
        play: true,
      );
      if (gen == _generation) {
        _loading = false;
        notifyListeners();
      }
    } catch (_) {
      if (gen == _generation) {
        await stop();
      }
    }
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    final p = _player;
    if (p != null) {
      try {
        await p.setVolume(_muted ? 0 : 100);
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _generation++;
    await _disposeInternal(notify: true);
  }

  Future<void> _disposeInternal({required bool notify}) async {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    final oldPlayer = _player;
    _player = null;
    _controller = null;
    _activePath = null;
    _loading = false;
    _playing = false;
    if (oldPlayer != null) {
      unawaited(oldPlayer.dispose().catchError((Object _) {}));
    }
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    final oldPlayer = _player;
    _player = null;
    _controller = null;
    if (oldPlayer != null) {
      unawaited(oldPlayer.dispose().catchError((Object _) {}));
    }
    super.dispose();
  }
}

/// Overlay rendered inside a Grid card when inline playback is active on that card.
class InlineVideoSurface extends StatelessWidget {
  final InlinePlaybackManager manager;
  final VoidCallback onExpand;

  const InlineVideoSurface({
    super.key,
    required this.manager,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = manager.controller;
    return ColoredBox(
      color: UiTokens.darkStage,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ctrl != null && !manager.isLoading)
            Video(
              controller: ctrl,
              fit: BoxFit.cover,
              controls: NoVideoControls,
            )
          else
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            ),
          Positioned(
            left: 6,
            bottom: 6,
            right: 6,
            child: Row(
              children: [
                _MiniActionPill(
                  icon: Icons.stop_rounded,
                  label: '停止',
                  onTap: manager.stop,
                ),
                const SizedBox(width: 4),
                _MiniActionPill(
                  icon: manager.isMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  onTap: manager.toggleMute,
                ),
                const Spacer(),
                _MiniActionPill(
                  icon: Icons.open_in_full_rounded,
                  onTap: onExpand,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniActionPill extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  const _MiniActionPill({
    required this.icon,
    this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: label != null ? 6 : 5,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            if (label != null) ...[
              const SizedBox(width: 3),
              Text(
                label!,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
