import 'dart:async';
import 'dart:io';

// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'live_media_resolver.dart';
import 'models.dart';
import 'ui_tokens.dart';

/// Built-in Live Photo & Video player inspired by Apple LivePhotosKit JS & JarkViewer.
/// Supports camera raw MP4s, `.livp` archives, Apple `.HEIC+.MOV` pairs, Android Motion Photos,
/// standard videos, and high-zoom static photos.
class MediaPreviewDialog extends StatefulWidget {
  final MediaAsset asset;
  final List<MediaAsset>? playlist;
  final int? initialIndex;
  final bool Function(MediaAsset)? isSelected;
  final ValueChanged<MediaAsset>? onToggleSelect;
  final bool? autoPlay;

  const MediaPreviewDialog({
    super.key,
    required this.asset,
    this.playlist,
    this.initialIndex,
    this.isSelected,
    this.onToggleSelect,
    this.autoPlay,
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

  ResolvedPlayableMedia? _resolved;
  bool _loading = true;
  bool _playing = false;
  bool _muted = false;
  double _volume = 100;
  double _speed = 1.0;
  bool _showingStaticCoverOnly = false;
  bool _vitalityZoom = false;
  late bool _loop = _currentAsset.kind == MediaKind.livePhoto;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragPosition;
  String? _error;

  bool get _effectiveAutoPlay =>
      widget.autoPlay ?? !Platform.environment.containsKey('FLUTTER_TEST');

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

  bool get _isPurePhoto =>
      _resolved != null
          ? _resolved!.isPurePhoto
          : _currentAsset.kind == MediaKind.photo;

  bool get _isLivePhoto =>
      _resolved != null
          ? _resolved!.isLivePhoto
          : _currentAsset.kind == MediaKind.livePhoto;

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
      _resolved = null;
      _loading = true;
      _playing = false;
      _showingStaticCoverOnly = false;
      _vitalityZoom = false;
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
      final resolved = await LiveMediaResolver.resolve(asset);
      if (!mounted || generation != _loadGeneration) return;
      _resolved = resolved;

      if (resolved.isPurePhoto) {
        setState(() => _loading = false);
        return;
      }

      MediaKit.ensureInitialized();
      final player = Player();
      _player = player;
      _video = VideoController(player);
      _subscriptions.addAll([
        player.stream.playing.listen((value) {
          if (mounted && generation == _loadGeneration) {
            setState(() {
              _playing = value;
              if (!value) _vitalityZoom = false;
            });
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

      await _video!.platform.future;
      if (!mounted || generation != _loadGeneration) return;

      await player.setVolume(_muted ? 0 : _volume);
      if (_speed != 1.0) {
        await player.setRate(_speed);
      }
      if (!mounted || generation != _loadGeneration) return;

      final shouldLoop = resolved.isLivePhoto ? _loop : _loop;
      await player.setPlaylistMode(
        shouldLoop ? PlaylistMode.single : PlaylistMode.none,
      );
      if (!mounted || generation != _loadGeneration) return;

      await player.open(
        Media(File(resolved.videoPath!).absolute.uri.toString()),
        play: _effectiveAutoPlay,
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
    if (_showingStaticCoverOnly) {
      setState(() => _showingStaticCoverOnly = false);
    }
    if (player.state.completed) await player.seek(Duration.zero);
    await player.playOrPause();
  });

  /// LivePhotosKit / JarkViewer style replay: hovering or clicking the LIVE badge
  /// or long-pressing the viewport plays the Live Photo from start with subtle vitality zoom.
  Future<void> _triggerLiveReplay() => _control((player) async {
    if (_showingStaticCoverOnly) {
      setState(() => _showingStaticCoverOnly = false);
    }
    setState(() => _vitalityZoom = true);
    await player.seek(Duration.zero);
    await player.play();
  });

  Future<void> _toggleMute() async {
    if (_loading || _isPurePhoto || _error != null) return;
    final muted = !_muted;
    await _control((player) => player.setVolume(muted ? 0 : _volume));
    if (mounted) setState(() => _muted = muted);
  }

  Future<void> _setSpeed(double rate) async {
    await _control((player) => player.setRate(rate));
    if (mounted) setState(() => _speed = rate);
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
    final formatBadge = _resolved?.formatBadge ?? asset.kindLabel;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (!_isPurePhoto && !_loading && _error == null) {
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
            width: (screen.width - 40).clamp(0, 1140),
            height: (screen.height - 40).clamp(0, 840),
            child: Column(
              children: [
                // 顶部标题栏
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: UiTokens.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _isLivePhoto
                              ? UiTokens.primarySoft
                              : UiTokens.mutedBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _isLivePhoto
                              ? Icons.motion_photos_on
                              : _isPurePhoto
                              ? Icons.image_outlined
                              : Icons.play_circle_outline,
                          size: 19,
                          color: _isLivePhoto
                              ? UiTokens.primary
                              : UiTokens.textSecondary,
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
                                      color: UiTokens.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isLivePhoto
                                        ? UiTokens.primaryTint
                                        : UiTokens.mutedBg,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: _isLivePhoto
                                          ? UiTokens.primaryBorder
                                          : UiTokens.border,
                                    ),
                                  ),
                                  child: Text(
                                    formatBadge,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: _isLivePhoto
                                          ? UiTokens.primaryDark
                                          : UiTokens.textSecondary,
                                    ),
                                  ),
                                ),
                                if (listLen > 1) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: UiTokens.mutedBg,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${_currentIndex + 1} / $listLen',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: UiTokens.textSecondary,
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
                                if (asset.sizeBytes > 0)
                                  '${(asset.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                                if (asset.friendlySpec.isNotEmpty)
                                  asset.friendlySpec,
                                if (asset.shotAt != null)
                                  _fmtShot(asset.shotAt!),
                              ].isEmpty
                                  ? '${asset.kindLabel}播放器'
                                  : [
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
                                color: UiTokens.textMuted,
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
                                ? UiTokens.primaryTint
                                : null,
                            side: BorderSide(
                              color: selected
                                  ? UiTokens.primary
                                  : UiTokens.borderStrong,
                            ),
                            foregroundColor: selected
                                ? UiTokens.primaryDark
                                : UiTokens.textSecondary,
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

                // 中央播放舞台
                Expanded(
                  child: ColoredBox(
                    color: UiTokens.darkStage,
                    child: _buildContent(),
                  ),
                ),

                // 视频与实况控制栏
                if (!_isPurePhoto && _error == null) _buildControls(),

                // 底部统一交互提示条
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: UiTokens.subtleBg,
                  child: Text(
                    _isPurePhoto
                        ? '滚轮或双指缩放、拖动查看细节${listLen > 1 ? ' · ← / → 切换上一张/下一张' : ''}'
                        : _isLivePhoto
                        ? '实况播放：悬停或点击左上角「LIVE」角标、长按画面或按空格可随时重播实况动效${listLen > 1 ? ' · ← / → 切换素材' : ''}'
                        : '视频播放：点击画面或按空格键播放 / 暂停 · 支持倍速与音量调节${listLen > 1 ? ' · ← / → 切换素材' : ''}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: UiTokens.textMuted,
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
    if (_isPurePhoto) {
      final imgPath = _resolved?.coverImagePath ?? _currentAsset.path;
      return InteractiveViewer(
        maxScale: 8,
        child: Center(
          child: Image.file(
            File(imgPath),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Text(
              '无法解码这张照片，请检查文件是否完整',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    final coverPath = _resolved?.coverImagePath;
    final showStaticOverlay =
        _isLivePhoto && coverPath != null && _showingStaticCoverOnly;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      onLongPressStart: _isLivePhoto ? (_) => _triggerLiveReplay() : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedScale(
            scale: _vitalityZoom && _playing ? 1.018 : 1.0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: Video(
              controller: _video!,
              fit: BoxFit.contain,
              controls: NoVideoControls,
            ),
          ),
          if (showStaticOverlay)
            ColoredBox(
              color: UiTokens.darkStage,
              child: Center(
                child: Image.file(File(coverPath), fit: BoxFit.contain),
              ),
            ),
          if (!_playing && !showStaticOverlay)
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

          // LivePhotosKit / iOS Photos interactive LIVE badge in top-left corner
          if (_isLivePhoto)
            Positioned(
              left: 16,
              top: 14,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => _triggerLiveReplay(),
                    child: GestureDetector(
                      onTap: _triggerLiveReplay,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _playing && !showStaticOverlay
                              ? UiTokens.primary.withValues(alpha: 0.88)
                              : Colors.black.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.motion_photos_on_rounded,
                              size: 15,
                              color: _playing && !showStaticOverlay
                                  ? Colors.white
                                  : const Color(0xFF5EEAD4),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _playing && !showStaticOverlay
                                  ? 'LIVE 播放中'
                                  : 'LIVE 实况',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (coverPath != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final next = !_showingStaticCoverOnly;
                        if (next && _playing) {
                          await _control((p) => p.pause());
                        }
                        if (mounted) {
                          setState(() => _showingStaticCoverOnly = next);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: showStaticOverlay
                              ? Colors.white.withValues(alpha: 0.90)
                              : Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          showStaticOverlay ? '正在看静态封面' : '对比静态封面',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: showStaticOverlay
                                ? UiTokens.textPrimary
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
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
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: _playing ? '暂停' : '播放',
            onPressed: _loading ? null : _togglePlay,
            icon: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
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
                if (_showingStaticCoverOnly) {
                  setState(() => _showingStaticCoverOnly = false);
                }
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
          const SizedBox(width: 6),
          // 倍速选择
          PopupMenuButton<double>(
            tooltip: '播放速度',
            enabled: !_loading,
            initialValue: _speed,
            onSelected: _setSpeed,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0.5, child: Text('0.5x 慢放')),
              PopupMenuItem(value: 1.0, child: Text('1.0x 正常')),
              PopupMenuItem(value: 1.5, child: Text('1.5x 倍速')),
              PopupMenuItem(value: 2.0, child: Text('2.0x 倍速')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: _speed != 1.0 ? UiTokens.primaryTint : UiTokens.mutedBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_speed}x',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _speed != 1.0
                      ? UiTokens.primaryDark
                      : UiTokens.textSecondary,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _muted ? '打开声音' : '静音',
            onPressed: _loading ? null : _toggleMute,
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
          ),
          SizedBox(
            width: 76,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: _muted ? 0 : _volume,
                max: 100,
                onChanged: _loading
                    ? null
                    : (val) async {
                        setState(() {
                          _volume = val;
                          _muted = val == 0;
                        });
                        await _control((p) => p.setVolume(val));
                      },
              ),
            ),
          ),
          IconButton(
            tooltip: _loop ? '关闭循环播放' : '开启循环播放',
            color: _loop ? UiTokens.primary : null,
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
