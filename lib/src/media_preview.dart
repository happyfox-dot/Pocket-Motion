import 'dart:async';
import 'dart:io';

// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

/// Read-only source preview. Export effects are intentionally not rendered here.
class MediaPreviewDialog extends StatefulWidget {
  final MediaAsset asset;
  const MediaPreviewDialog({super.key, required this.asset});

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  Player? _player;
  VideoController? _video;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _loading = true;
  bool _playing = false;
  bool _muted = false;
  late bool _loop = widget.asset.kind == MediaKind.livePhoto;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragPosition;
  String? _error;

  bool get _isPhoto => widget.asset.kind == MediaKind.photo;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      if (!await File(widget.asset.path).exists()) {
        throw const FileSystemException('文件不可用，请检查相机连接或重新扫描');
      }
      if (!mounted) return;
      if (_isPhoto) {
        if (p.extension(widget.asset.path).toLowerCase() == '.dng') {
          throw const FormatException('暂不支持 DNG 原始照片预览，请查看配套 JPEG 照片');
        }
        setState(() => _loading = false);
        return;
      }
      // Lazy initialization keeps photo browsing/export usable if player DLLs
      // are missing; the error is displayed inside this preview only.
      MediaKit.ensureInitialized();
      final player = Player();
      _player = player;
      _video = VideoController(player);
      _subscriptions.addAll([
        player.stream.playing.listen((value) {
          if (mounted) setState(() => _playing = value);
        }),
        player.stream.position.listen((value) {
          if (mounted) setState(() => _position = value);
        }),
        player.stream.duration.listen((value) {
          if (mounted) setState(() => _duration = value);
        }),
        player.stream.error.listen(_showError),
      ]);
      // Surface native video-output initialization failures in the dialog too.
      await _video!.platform.future;
      if (!mounted) return;
      await player.setPlaylistMode(
        _loop ? PlaylistMode.single : PlaylistMode.none,
      );
      if (!mounted) return;
      await player.open(
        Media(File(widget.asset.path).absolute.uri.toString()),
        play: false,
      );
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  Future<void> _control(Future<void> Function(Player) action) async {
    final player = _player;
    if (player == null || _error != null) return;
    try {
      await action(player);
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _togglePlay() => _control((player) async {
    if (player.state.completed) await player.seek(Duration.zero);
    await player.playOrPause();
  });

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    final player = _player;
    if (player != null) {
      // dispose stops audio and releases the camera file, including when the
      // dialog is closed with Escape/outside click during an in-flight open.
      unawaited(player.dispose().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: (screen.width - 40).clamp(0, 1100),
        height: (screen.height - 40).clamp(0, 800),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 6),
              child: Row(
                children: [
                  Icon(
                    _isPhoto ? Icons.image_outlined : Icons.play_circle_outline,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.asset.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${widget.asset.kindLabel} · 原始素材预览',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭预览',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(color: Colors.black, child: _buildContent()),
            ),
            if (!_isPhoto && _error == null) _buildControls(),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                _isPhoto
                    ? '滚轮或触控缩放，可拖动画面。预览不会修改源文件。'
                    : '点击播放后开始有声预览。这里显示相机原片，水印在导出时添加。',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.white70,
                  size: 36,
                ),
                const SizedBox(height: 12),
                const Text(
                  '无法预览',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_isPhoto) {
      return InteractiveViewer(
        maxScale: 8,
        child: Center(
          child: Image.file(
            File(widget.asset.path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text(
              '无法解码这张照片，请检查文件是否完整',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }
    return Video(
      controller: _video!,
      fit: BoxFit.contain,
      controls: NoVideoControls,
    );
  }

  Widget _buildControls() {
    final maxMs = _duration.inMilliseconds.toDouble();
    final position = (_dragPosition ?? _position.inMilliseconds.toDouble())
        .clamp(0.0, maxMs > 0 ? maxMs : 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: _playing ? '暂停' : '播放',
                onPressed: _loading ? null : _togglePlay,
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              ),
              Text(
                _clock(Duration(milliseconds: position.round())),
                style: const TextStyle(fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: position,
                  max: maxMs > 0 ? maxMs : 1,
                  onChanged: _loading || maxMs <= 0
                      ? null
                      : (value) => setState(() => _dragPosition = value),
                  onChangeEnd: (value) async {
                    await _control(
                      (player) =>
                          player.seek(Duration(milliseconds: value.round())),
                    );
                    if (mounted) setState(() => _dragPosition = null);
                  },
                ),
              ),
              Text(_clock(_duration), style: const TextStyle(fontSize: 12)),
              IconButton(
                tooltip: _muted ? '打开声音' : '静音',
                onPressed: _loading
                    ? null
                    : () async {
                        final muted = !_muted;
                        await _control(
                          (player) => player.setVolume(muted ? 0 : 100),
                        );
                        if (mounted) setState(() => _muted = muted);
                      },
                icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
              ),
              IconButton(
                tooltip: _loop ? '关闭循环播放' : '开启循环播放',
                color: _loop ? Colors.teal : null,
                onPressed: _loading
                    ? null
                    : () async {
                        final loop = !_loop;
                        await _control(
                          (player) => player.setPlaylistMode(
                            loop ? PlaylistMode.single : PlaylistMode.none,
                          ),
                        );
                        if (mounted) setState(() => _loop = loop);
                      },
                icon: const Icon(Icons.repeat),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _clock(Duration value) {
    final seconds = value.inSeconds.clamp(0, 36000000);
    final tail =
        '${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    return seconds >= 3600 ? '${seconds ~/ 3600}:$tail' : tail;
  }
}
