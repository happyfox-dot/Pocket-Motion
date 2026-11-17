import 'dart:async';
import 'dart:io';

// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

/// Read-only source preview. Export effects are intentionally not rendered here.
class MediaPreviewDialog extends StatefulWidget {
  final MediaAsset asset;
  final List<MediaAsset>? playlist;
  final int? initialIndex;
  final bool Function(MediaAsset)? isSelected;
  final ValueChanged<MediaAsset>? onToggleSelect;

  const MediaPreviewDialog({
    super.key,
    required this.asset,
    this.playlist,
    this.initialIndex,
    this.isSelected,
    this.onToggleSelect,
  });

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  Player? _player;
  VideoController? _video;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late int _currentIndex = _resolveInitialIndex();
  int _loadGeneration = 0;
  bool _loading = true;
  bool _playing = false;
  bool _muted = false;
  late bool _loop = _currentAsset.kind == MediaKind.livePhoto;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragPosition;
  String? _error;

  int _resolveInitialIndex() {
    final list = widget.playlist;
    if (list == null || list.isEmpty) return 0;
    if (widget.initialIndex != null &&
        widget.initialIndex! >= 0 &&
        widget.initialIndex! < list.length) {
      return widget.initialIndex!;
    }
    final found = list.indexWhere((a) => a.path == widget.asset.path);
    return found >= 0 ? found : 0;
  }

  MediaAsset get _currentAsset {
    final list = widget.playlist;
    if (list != null && _currentIndex >= 0 && _currentIndex < list.length) {
      return list[_currentIndex];
    }
    return widget.asset;
  }

  bool get _isPhoto => _currentAsset.kind == MediaKind.photo;

  bool get _hasPrev => widget.playlist != null && _currentIndex > 0;
  bool get _hasNext =>
      widget.playlist != null && _currentIndex < widget.playlist!.length - 1;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _releasePlayer() async {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    _video = null;
    if (player != null) {
      unawaited(player.dispose().catchError((Object _) {}));
    }
  }

  Future<void> _switchTo(int newIndex) async {
    final list = widget.playlist;
    if (list == null || newIndex < 0 || newIndex >= list.length) return;
    await _releasePlayer();
    if (!mounted) return;
    setState(() {
      _currentIndex = newIndex;
      _loading = true;
      _playing = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _dragPosition = null;
      _error = null;
      _loop = _currentAsset.kind == MediaKind.livePhoto;
    });
    await _prepare();
  }

  Future<void> _prepare() async {
    final generation = ++_loadGeneration;
    final asset = _currentAsset;
    try {
      if (!await File(asset.path).exists()) {
        throw const FileSystemException('文件不可用，请检查相机连接或重新扫描');
      }
      if (!mounted || generation != _loadGeneration) return;
      if (_isPhoto) {
        if (p.extension(asset.path).toLowerCase() == '.dng') {
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
          if (mounted && generation == _loadGeneration) {
            setState(() => _playing = value);
          }
        }),
        player.stream.position.listen((value) {
          if (mounted && generation == _loadGeneration) {
            setState(() => _position = value);
          }
        }),
        player.stream.duration.listen((value) {
          if (mounted && generation == _loadGeneration) {
            setState(() => _duration = value);
          }
        }),
        player.stream.error.listen((msg) {
          if (generation == _loadGeneration) _showError(msg);
        }),
      ]);
      // Surface native video-output initialization failures in the dialog too.
      await _video!.platform.future;
      if (!mounted || generation != _loadGeneration) return;
      if (_muted) {
        await player.setVolume(0);
      }
      if (!mounted || generation != _loadGeneration) return;
      await player.setPlaylistMode(
        _loop ? PlaylistMode.single : PlaylistMode.none,
      );
      if (!mounted || generation != _loadGeneration) return;
      await player.open(
        Media(File(asset.path).absolute.uri.toString()),
        play: false,
      );
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (generation == _loadGeneration) {
        _showError(e.toString());
      }
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

  Future<void> _toggleMute() async {
    if (_loading || _isPhoto || _error != null) return;
    final muted = !_muted;
    await _control((player) => player.setVolume(muted ? 0 : 100));
    if (mounted) setState(() => _muted = muted);
  }

  void _toggleSelectCurrent() {
    final toggle = widget.onToggleSelect;
    if (toggle == null) return;
    toggle(_currentAsset);
    setState(() {});
  }

  @override
  void dispose() {
    _loadGeneration++;
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
    final asset = _currentAsset;
    final selected = widget.isSelected?.call(asset) ?? false;
    final listLen = widget.playlist?.length ?? 0;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (!_isPhoto && !_loading && _error == null) {
            _togglePlay();
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (_hasPrev) _switchTo(_currentIndex - 1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (_hasNext) _switchTo(_currentIndex + 1);
        },
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
        const SingleActivator(LogicalKeyboardKey.keyS): _toggleSelectCurrent,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          insetPadding: const EdgeInsets.all(20),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: (screen.width - 40).clamp(0, 1120),
            height: (screen.height - 40).clamp(0, 820),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: asset.kind == MediaKind.livePhoto
                              ? const Color(0xFFE6FFFA)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          asset.kind == MediaKind.livePhoto
                              ? Icons.motion_photos_on
                              : _isPhoto
                              ? Icons.image_outlined
                              : Icons.play_circle_outline,
                          size: 19,
                          color: asset.kind == MediaKind.livePhoto
                              ? const Color(0xFF0D9488)
                              : const Color(0xFF475569),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    asset.filename,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                if (listLen > 1) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${_currentIndex + 1} / $listLen',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF475569),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                '${asset.kindLabel} · 原始素材预览',
                                if (asset.sizeBytes > 0)
                                  '${(asset.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                                if (asset.friendlySpec.isNotEmpty)
                                  asset.friendlySpec,
                                if (asset.shotAt != null)
                                  _fmtShot(asset.shotAt!),
                              ].join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (listLen > 1) ...[
                        IconButton(
                          tooltip: '上一项 (←)',
                          onPressed: _hasPrev
                              ? () => _switchTo(_currentIndex - 1)
                              : null,
                          icon: const Icon(Icons.chevron_left, size: 22),
                        ),
                        IconButton(
                          tooltip: '下一项 (→)',
                          onPressed: _hasNext
                              ? () => _switchTo(_currentIndex + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right, size: 22),
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (widget.onToggleSelect != null) ...[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: selected
                                ? const Color(0xFFF0FDFA)
                                : null,
                            side: BorderSide(
                              color: selected
                                  ? const Color(0xFF0D9488)
                                  : const Color(0xFFCBD5E1),
                            ),
                            foregroundColor: selected
                                ? const Color(0xFF0F766E)
                                : const Color(0xFF334155),
                          ),
                          onPressed: _toggleSelectCurrent,
                          icon: Icon(
                            selected
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 16,
                          ),
                          label: Text(
                            selected ? '已选导出' : '加入导出',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      IconButton(
                        tooltip: '关闭预览',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: const Color(0xFF0B0F17),
                    child: _buildContent(),
                  ),
                ),
                if (!_isPhoto && _error == null) _buildControls(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  color: const Color(0xFFF8FAFC),
                  child: Text(
                    _isPhoto
                        ? '滚轮或双指缩放、拖动查看细节${listLen > 1 ? ' · 键盘 ← / → 切换素材' : ''} · 预览不会修改源文件'
                        : '点击画面或按空格键播放 / 暂停${listLen > 1 ? ' · ← / → 切换素材' : ''} · 此处显示相机原片，机型水印在导出时合成',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                  size: 38,
                ),
                const SizedBox(height: 12),
                const Text(
                  '无法预览',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    if (_isPhoto) {
      return InteractiveViewer(
        maxScale: 8,
        child: Center(
          child: Image.file(
            File(_currentAsset.path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text(
              '无法解码这张照片，请检查文件是否完整',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: _video!,
            fit: BoxFit.contain,
            controls: NoVideoControls,
          ),
          if (!_playing)
            Center(
              child: IgnorePointer(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.52),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final maxMs = _duration.inMilliseconds.toDouble();
    final position = (_dragPosition ?? _position.inMilliseconds.toDouble())
        .clamp(0.0, maxMs > 0 ? maxMs : 1.0);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: _playing ? '暂停' : '播放',
            onPressed: _loading ? null : _togglePlay,
            icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          Text(
            _clock(Duration(milliseconds: position.round())),
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
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
          Text(
            _clock(_duration),
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            tooltip: _muted ? '打开声音' : '静音',
            onPressed: _loading ? null : _toggleMute,
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
          ),
          IconButton(
            tooltip: _loop ? '关闭循环播放' : '开启循环播放',
            color: _loop ? const Color(0xFF0D9488) : null,
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
    );
  }

  static String _fmtShot(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _clock(Duration value) {
    final seconds = value.inSeconds.clamp(0, 36000000);
    final tail =
        '${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    return seconds >= 3600 ? '${seconds ~/ 3600}:$tail' : tail;
  }
}
