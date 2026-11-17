import 'dart:convert';
import 'dart:io';

// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'src/models.dart';
import 'src/media_scanner.dart';
import 'src/live_photo_exporter.dart';
import 'src/motion_photo_exporter.dart';
import 'src/thumbnail_image.dart';
import 'src/tool_path.dart';
import 'src/baidu_live_exporter.dart';
import 'src/baidu_apple_guide_dialog.dart';
import 'src/camera_discovery.dart';
import 'src/export_support.dart';
import 'src/watermark.dart';
import 'src/watermark_controls.dart';
import 'src/media_preview.dart';

void main() => runApp(const DjiLiveApp());

enum GalleryViewMode { list, grid }

enum AssetSortOrder {
  shotTimeDesc('最新拍摄优先'),
  shotTimeAsc('最早拍摄优先'),
  sizeDesc('文件从大到小'),
  nameAsc('文件名 A → Z');

  final String label;
  const AssetSortOrder(this.label);
}

class DjiLiveApp extends StatelessWidget {
  const DjiLiveApp({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0D9488),
      brightness: Brightness.light,
      surface: Colors.white,
    );
    return MaterialApp(
      title: 'Pocket Motion',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        dividerColor: const Color(0xFFE2E8F0),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _scanner = MediaScanner();
  final _searchController = TextEditingController();
  late String _cameraDir = _defaultCameraDir();
  late String _outDir = _defaultOutDir();

  List<MediaAsset> _assets = [];
  MediaKind _filter = MediaKind.livePhoto; // 默认只显示实况
  GalleryViewMode _viewMode = GalleryViewMode.list;
  AssetSortOrder _sortOrder = AssetSortOrder.shotTimeDesc;
  String _searchQuery = '';

  bool _scanning = false;
  final Set<String> _selected = {};
  String? _anchorPath; // Shift 连选起点
  final List<String> _logs = [];
  bool _exporting = false;
  bool _hasExportSummary = false;
  int _doneCount = 0;
  int _totalCount = 0;
  int _success = 0;
  int _fail = 0;
  int _skipped = 0;
  bool _findingCamera = false;
  WatermarkSettings _watermark = const WatermarkSettings();

  @override
  void initState() {
    super.initState();
    _loadSavedDirs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static String _defaultCameraDir() => '';

  static String _defaultOutDir() {
    if (Platform.isWindows) {
      final userProfile =
          Platform.environment['USERPROFILE'] ?? r'C:\Users\Public';
      return p.join(userProfile, 'Downloads', 'PocketMotion_Out');
    }
    final home = Platform.environment['HOME'] ?? '/Users/Shared';
    return p.join(home, 'Downloads', 'live_out');
  }

  static File _configFile() {
    if (Platform.isWindows) {
      final appData =
          Platform.environment['APPDATA'] ??
          Platform.environment['USERPROFILE'] ??
          Directory.systemTemp.path;
      return File(p.join(appData, 'PocketMotion', 'config.json'));
    }
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return File(
      p.join(
        home,
        'Library',
        'Application Support',
        'PocketMotion',
        'config.json',
      ),
    );
  }

  Future<void> _loadSavedDirs() async {
    try {
      final file = _configFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        if (!mounted) return;
        if (data is Map) {
          final savedCamera = data['cameraDir'];
          final savedOut = data['outDir'];
          final savedView = data['viewMode'];
          setState(() {
            _watermark = WatermarkSettings.fromJson(data['watermark']);
            if (savedCamera is String && savedCamera.trim().isNotEmpty) {
              _cameraDir = savedCamera.trim();
            }
            if (savedOut is String && savedOut.trim().isNotEmpty) {
              _outDir = savedOut.trim();
            }
            if (savedView == 'grid') {
              _viewMode = GalleryViewMode.grid;
            } else if (savedView == 'list') {
              _viewMode = GalleryViewMode.list;
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveDirs() async {
    try {
      final file = _configFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'cameraDir': _cameraDir,
          'outDir': _outDir,
          'viewMode': _viewMode.name,
          'watermark': _watermark.toJson(),
        }),
      );
    } catch (_) {}
  }

  int _countByKind(MediaKind kind) =>
      _assets.where((a) => a.kind == kind).length;

  List<MediaAsset> get _liveAssets =>
      _assets.where((a) => a.kind == MediaKind.livePhoto).toList();

  List<MediaAsset> get _visible {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _assets.where((a) {
      if (a.kind != _filter) return false;
      if (query.isEmpty) return true;
      return a.filename.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      switch (_sortOrder) {
        case AssetSortOrder.shotTimeDesc:
          final ta = a.shotAt;
          final tb = b.shotAt;
          if (ta == null && tb == null) {
            return b.filename.compareTo(a.filename);
          }
          if (ta == null) return 1;
          if (tb == null) return -1;
          final cmp = tb.compareTo(ta);
          return cmp != 0 ? cmp : b.filename.compareTo(a.filename);
        case AssetSortOrder.shotTimeAsc:
          final ta = a.shotAt;
          final tb = b.shotAt;
          if (ta == null && tb == null) {
            return a.filename.compareTo(b.filename);
          }
          if (ta == null) return 1;
          if (tb == null) return -1;
          final cmp = ta.compareTo(tb);
          return cmp != 0 ? cmp : a.filename.compareTo(b.filename);
        case AssetSortOrder.sizeDesc:
          final cmp = b.sizeBytes.compareTo(a.sizeBytes);
          return cmp != 0 ? cmp : a.filename.compareTo(b.filename);
        case AssetSortOrder.nameAsc:
          return a.filename.compareTo(b.filename);
      }
    });
    return filtered;
  }

  Future<void> _scan() async {
    if (_scanning || _exporting) return;
    setState(() {
      _scanning = true;
      _selected.clear();
      _anchorPath = null;
      _hasExportSummary = false;
      _logs.clear();
    });
    try {
      final list = await _scanner.scan(_cameraDir, onWarning: _log);
      if (!mounted) return;
      setState(() {
        _assets = list;
        if (list.isNotEmpty && !list.any((a) => a.kind == _filter)) {
          _filter = MediaKind.values.firstWhere(
            (kind) => list.any((a) => a.kind == kind),
          );
        }
      });
      _log('扫描完成：${list.length} 项，实况 ${_liveAssets.length} 项');
    } catch (e) {
      if (mounted) setState(() => _assets = []);
      _log('扫描失败：$e');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _log(String s) {
    if (!mounted) return;
    setState(() {
      _logs.add(s);
      if (_logs.length > 300) _logs.removeAt(0);
    });
  }

  Future<void> _findCamera() async {
    setState(() => _findingCamera = true);
    try {
      final sources = await CameraDiscovery().find();
      if (!mounted) return;
      if (sources.isEmpty) {
        _log('没有找到相机存储。请用数据线连接，选择文件传输／U盘模式；也可手动选择素材文件夹。');
        return;
      }
      final chosen = sources.length == 1
          ? sources.first
          : await showDialog<String>(
              context: context,
              builder: (context) => SimpleDialog(
                title: const Text('选择相机或存储卡'),
                children: [
                  for (final path in sources)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(context, path),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.usb,
                            size: 18,
                            color: Color(0xFF0D9488),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(path)),
                        ],
                      ),
                    ),
                ],
              ),
            );
      if (chosen == null || !mounted) return;
      setState(() => _cameraDir = chosen);
      await _saveDirs();
      await _scan();
    } catch (e) {
      _log('查找失败：$e');
    } finally {
      if (mounted) setState(() => _findingCamera = false);
    }
  }

  Future<void> _openOutput() async {
    try {
      await Directory(_outDir).create(recursive: true);
      await Process.run(Platform.isWindows ? 'explorer.exe' : 'open', [
        _outDir,
      ]);
    } catch (e) {
      _log('无法打开导出文件夹：$e');
    }
  }

  Future<void> _pickCameraDir() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择本地或相机素材文件夹',
    );
    if (dir != null && mounted) {
      setState(() {
        _cameraDir = dir;
        _selected.clear();
        _anchorPath = null;
      });
      await _saveDirs();
      await _scan();
    }
  }

  Future<void> _pickOutDir() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目录',
    );
    if (dir != null && mounted) {
      setState(() => _outDir = dir);
      await _saveDirs();
    }
  }

  Future<void> _showBaiduAppleGuide() => showDialog<void>(
    context: context,
    builder: (_) => const BaiduAppleGuideDialog(),
  );

  List<MediaAsset> get _picked =>
      _visible.where((a) => _selected.contains(a.path)).toList();

  int get _pickedTotalBytes =>
      _picked.fold<int>(0, (sum, item) => sum + item.sizeBytes);

  void _toggleSingleSelection(MediaAsset asset) {
    setState(() {
      if (_selected.contains(asset.path)) {
        _selected.remove(asset.path);
      } else {
        _selected.add(asset.path);
      }
      _anchorPath = asset.path;
    });
  }

  Future<void> _previewAsset(MediaAsset asset, List<MediaAsset> list, int idx) =>
      showDialog<void>(
        context: context,
        builder: (_) => MediaPreviewDialog(
          asset: asset,
          playlist: list,
          initialIndex: idx,
          isSelected: (item) => _selected.contains(item.path),
          onToggleSelect: _toggleSingleSelection,
        ),
      );

  void _onItemTap(int index, MediaAsset asset, List<MediaAsset> visibleList) {
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final anchorIdx = _anchorPath == null
        ? -1
        : visibleList.indexWhere((a) => a.path == _anchorPath);

    setState(() {
      if (isShift && anchorIdx != -1) {
        final start = anchorIdx < index ? anchorIdx : index;
        final end = anchorIdx < index ? index : anchorIdx;
        for (var i = start; i <= end; i++) {
          _selected.add(visibleList[i].path);
        }
        _anchorPath = asset.path;
      } else {
        if (_selected.contains(asset.path)) {
          _selected.remove(asset.path);
        } else {
          _selected.add(asset.path);
        }
        _anchorPath = asset.path;
      }
    });
  }

  Future<void> _runExport(Future<dynamic> Function(MediaAsset a) task) async {
    final picks = _picked;
    if (picks.isEmpty || _exporting || _scanning) return;
    setState(() {
      _exporting = true;
      _hasExportSummary = false;
      _doneCount = 0;
      _totalCount = picks.length;
      _success = 0;
      _fail = 0;
      _skipped = 0;
    });
    try {
      await validateExportLocation(_cameraDir, _outDir);
      await Directory(_outDir).create(recursive: true);
    } catch (e) {
      _log('无法准备导出：$e');
      if (mounted) setState(() => _exporting = false);
      return;
    }
    if (!mounted) return;
    for (final a in picks) {
      try {
        await task(a);
        _success++;
      } on ExportSkipped catch (e) {
        _skipped++;
        _log(e.toString());
      } catch (e) {
        _fail++;
        _log('失败: ${a.filename} ($e)');
      }
      if (mounted) setState(() => _doneCount++);
    }
    _log('完成：成功 $_success，跳过 $_skipped，失败 $_fail');
    if (mounted) {
      setState(() {
        _exporting = false;
        _hasExportSummary = true;
      });
    }
  }

  void _exportBaidu() {
    final target = p.join(_outDir, 'baidu_live');
    final watermark = _watermark;
    _runExport(
      (a) => BaiduLiveExporter(
        onLog: _log,
      ).export(asset: a, outDir: target, watermark: watermark),
    );
  }

  void _exportApple() {
    final liveOutDir = p.join(_outDir, 'live');
    final watermark = _watermark;
    _runExport(
      (a) => LivePhotoExporter(
        onLog: _log,
      ).export(asset: a, outDir: liveOutDir, watermark: watermark),
    );
  }

  void _exportMotion() {
    final liveOutDir = p.join(_outDir, 'live');
    final watermark = _watermark;
    _runExport(
      (a) => MotionPhotoExporter(
        onLog: _log,
      ).export(asset: a, outDir: liveOutDir, watermark: watermark),
    );
  }

  void _exportVideos() {
    final movieOutDir = p.join(_outDir, 'movie');
    _runExport((a) => _copyMediaFile(a, movieOutDir, 'movie'));
  }

  void _exportPhotos() {
    final photoOutDir = p.join(_outDir, 'photo');
    _runExport((a) => _copyMediaFile(a, photoOutDir, 'photo'));
  }

  Future<void> _copyMediaFile(
    MediaAsset asset,
    String targetDir,
    String folderLabel,
  ) async {
    await Directory(targetDir).create(recursive: true);
    final destPath = p.join(targetDir, asset.filename);
    await ensureOutputsAvailable([destPath]);
    _log('导出: ${asset.filename} -> $folderLabel/');
    final staging = await Directory(targetDir).createTemp('.pocket-copy-');
    final pending = p.join(staging.path, asset.filename);
    try {
      await File(asset.path).copy(pending);

      DateTime? shotAt = asset.shotAt;
      if (shotAt == null) {
        try {
          shotAt = await File(asset.path).lastModified();
        } catch (_) {}
      }

      if (shotAt != null) {
        if (Platform.isMacOS) {
          try {
            await Process.run(ToolPath.find('SetFile'), [
              '-d',
              _macTime(shotAt),
              pending,
            ]);
          } catch (_) {}
        }
        try {
          await File(pending).setLastModified(shotAt);
        } catch (_) {}
      }
      await ensureOutputsAvailable([destPath]);
      await File(pending).rename(destPath);
      _log('完成: $folderLabel/${asset.filename}');
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  static String _macTime(DateTime dt) =>
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: Row(
        children: [
          Container(
            width: 326,
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: _buildSidebar(),
          ),
          Expanded(child: _buildMain()),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final busy = _exporting || _scanning || _findingCamera;
    final visibleLogs = _logs.length > 80
        ? _logs.sublist(_logs.length - 80)
        : _logs;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部品牌栏
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 2, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.motion_photos_on,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pocket Motion',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Pocket 4P 实况导出工作台',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '百度网盘与 Apple 实况交付指南',
                  visualDensity: VisualDensity.compact,
                  onPressed: _showBaiduAppleGuide,
                  icon: const Icon(
                    Icons.help_outline_rounded,
                    size: 19,
                    color: Color(0xFF0D9488),
                  ),
                ),
              ],
            ),
          ),

          // Step 1: 素材来源
          _SidebarCard(
            step: '1',
            title: '素材来源',
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              icon: _scanning
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              onPressed: busy ? null : _scan,
              tooltip: '重新扫描',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PathCard(
                  path: _cameraDir,
                  onChange: busy ? null : _pickCameraDir,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onPressed: busy ? null : _findCamera,
                  icon: const Icon(Icons.usb_rounded, size: 17),
                  label: Text(_findingCamera ? '正在查找…' : '查找 USB 相机 / 存储卡'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onPressed: busy ? null : _pickCameraDir,
                  icon: const Icon(Icons.folder_open_rounded, size: 17),
                  label: const Text('选择本地素材文件夹'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Step 2: 导出位置
          _SidebarCard(
            step: '2',
            title: '导出位置',
            trailing: TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: _exporting ? null : _openOutput,
              icon: const Icon(Icons.open_in_new_rounded, size: 14),
              label: const Text('打开导出文件夹', style: TextStyle(fontSize: 12)),
            ),
            child: _PathCard(
              path: _outDir,
              onChange: _exporting ? null : _pickOutDir,
              isOut: true,
            ),
          ),
          const SizedBox(height: 10),

          // Step 3: 导出格式 / 操作
          _SidebarCard(
            step: '3',
            title: _filter == MediaKind.livePhoto ? '导出格式' : '导出操作',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_filter == MediaKind.livePhoto) ...[
                  WatermarkControls(
                    settings: _watermark,
                    locked: _exporting,
                    onChanged: (settings) {
                      setState(() => _watermark = settings);
                      _saveDirs();
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                _buildExportButtons(),
                if (_exporting) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDFA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF99F6E4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '正在导出 $_doneCount / $_totalCount',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                            Text(
                              '成功 $_success · 失败 $_fail',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 6,
                            value: _totalCount == 0
                                ? 0
                                : _doneCount / _totalCount,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_hasExportSummary) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _fail > 0
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFF0FDFA),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _fail > 0
                            ? const Color(0xFFFECACA)
                            : const Color(0xFF99F6E4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _fail > 0
                              ? Icons.info_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 16,
                          color: _fail > 0
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF0D9488),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '完成：成功 $_success · 跳过 $_skipped · 失败 $_fail',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  switch (_filter) {
                    MediaKind.livePhoto =>
                      '网盘交付 iPhone / 安卓请选 .livp（保存到 baidu_live）；Mac 照片或隔空投送请选 Apple 实况（HEIC + MOV）。',
                    MediaKind.video =>
                      '未识别到实况标记的视频仅供预览和原文件导出，不转成实况。视频将复制至 movie 文件夹，源文件不会被修改。',
                    MediaKind.photo =>
                      '照片将导出至 photo 文件夹，保留原始拍摄时间，源文件不会被修改。',
                  },
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: Color(0xFF64748B),
                  ),
                ),
                if (_filter == MediaKind.livePhoto) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: const Color(0xFFF0FDFA),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Color(0xFFCCFBF1)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _showBaiduAppleGuide,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.phone_iphone_rounded,
                              size: 14,
                              color: Color(0xFF0D9488),
                            ),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Apple 用户如何经网盘查看并存实况？',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: Color(0xFF0D9488),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 运行日志面板
          if (_logs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.terminal_rounded,
                        size: 14,
                        color: Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '运行日志 (${_logs.length})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '复制日志',
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: _logs.join('\n')),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('日志已复制到剪贴板'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: '清空日志',
                        onPressed: () => setState(() => _logs.clear()),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 14,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  for (final line in visibleLogs)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.5, right: 4),
                      child: Text(
                        line,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          color: _logColor(line),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Color _logColor(String line) {
    if (line.contains('失败')) return const Color(0xFFFCA5A5);
    if (line.contains('跳过') || line.contains('已存在')) {
      return const Color(0xFFFCD34D);
    }
    if (line.contains('完成') || line.contains('已生成')) {
      return const Color(0xFF5EEAD4);
    }
    return const Color(0xFFCBD5E1);
  }

  Widget _buildExportButtons() {
    final disabled = _picked.isEmpty || _exporting || _scanning;
    switch (_filter) {
      case MediaKind.livePhoto:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              onPressed: disabled ? null : _exportBaidu,
              child: const Text('导出百度网盘实况 (.livp)'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 3, bottom: 8),
              child: Text(
                '单文件含 1000LIVP 索引 · 网盘 App 直接存 iPhone / 安卓相册',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
              ),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: disabled ? null : _exportApple,
              child: const Text('导出为 Apple 实况照片'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 3, bottom: 8),
              child: Text(
                'HEIC + MOV 双文件 · 适合 Mac 照片导入或隔空投送',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
              ),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: disabled ? null : _exportMotion,
              child: const Text('导出 Android 动态照片（试验）'),
            ),
          ],
        );
      case MediaKind.video:
        return FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 11),
          ),
          onPressed: disabled ? null : _exportVideos,
          child: const Text('导出视频'),
        );
      case MediaKind.photo:
        return FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 11),
          ),
          onPressed: disabled ? null : _exportPhotos,
          child: const Text('导出照片'),
        );
    }
  }

  void _switchFilter(MediaKind kind) {
    if (_filter == kind) return;
    setState(() {
      _filter = kind;
      _selected.clear();
      _anchorPath = null;
    });
  }

  void _setViewMode(GalleryViewMode mode) {
    if (_viewMode == mode) return;
    setState(() => _viewMode = mode);
    _saveDirs();
  }

  Widget _buildMain() {
    final visible = _visible;
    final picked = _picked;
    final allSelected =
        visible.isNotEmpty && visible.every((a) => _selected.contains(a.path));

    return Column(
      children: [
        // 顶部工作区标题栏 + 视图切换
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 14, 18, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            '实况照片转换',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 19,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        if (_assets.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDFA),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF99F6E4),
                              ),
                            ),
                            child: Text(
                              '共 ${_assets.length} 项素材',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Pocket 4P · USB / 本地素材 · 百度网盘实况导出',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                onPressed: _showBaiduAppleGuide,
                icon: const Icon(Icons.cloud_done_outlined, size: 16),
                label: const Text('网盘交付指南', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ViewModeButton(
                      icon: Icons.view_list_rounded,
                      tooltip: '列表视图',
                      active: _viewMode == GalleryViewMode.list,
                      onTap: () => _setViewMode(GalleryViewMode.list),
                    ),
                    _ViewModeButton(
                      icon: Icons.grid_view_rounded,
                      tooltip: '网格视图',
                      active: _viewMode == GalleryViewMode.grid,
                      onTap: () => _setViewMode(GalleryViewMode.grid),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 分类筛选 + 搜索与排序栏
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildFilterChip(
                    kind: MediaKind.livePhoto,
                    label: '实况',
                    count: _countByKind(MediaKind.livePhoto),
                    dotColor: const Color(0xFF0D9488),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    kind: MediaKind.video,
                    label: '视频',
                    count: _countByKind(MediaKind.video),
                    dotColor: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    kind: MediaKind.photo,
                    label: '照片',
                    count: _countByKind(MediaKind.photo),
                    dotColor: const Color(0xFF3B82F6),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 175,
                    height: 32,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: const TextStyle(fontSize: 12.5),
                      decoration: InputDecoration(
                        hintText: '搜索文件名…',
                        hintStyle: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF94A3B8),
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 32,
                        ),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                padding: EdgeInsets.zero,
                                tooltip: '清除搜索',
                                icon: const Icon(Icons.close, size: 14),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              ),
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 28,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF0D9488),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<AssetSortOrder>(
                        isDense: true,
                        value: _sortOrder,
                        icon: const Icon(Icons.sort_rounded, size: 15),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF334155),
                        ),
                        items: [
                          for (final order in AssetSortOrder.values)
                            DropdownMenuItem(
                              value: order,
                              child: Text(order.label),
                            ),
                        ],
                        onChanged: (order) {
                          if (order != null) setState(() => _sortOrder = order);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 批量选择工具栏
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: visible.isEmpty
                    ? null
                    : () => setState(() {
                        if (allSelected) {
                          _selected.removeAll(visible.map((a) => a.path));
                        } else {
                          _selected.addAll(visible.map((a) => a.path));
                        }
                      }),
                icon: Icon(
                  allSelected
                      ? Icons.check_box_rounded
                      : Icons.select_all_rounded,
                  size: 16,
                ),
                label: Text(allSelected ? '取消全选' : '全选'),
              ),
              if (visible.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => setState(() {
                    for (final a in visible) {
                      if (_selected.contains(a.path)) {
                        _selected.remove(a.path);
                      } else {
                        _selected.add(a.path);
                      }
                    }
                  }),
                  child: const Text('反选'),
                ),
              if (picked.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: const Color(0xFF64748B),
                  ),
                  onPressed: () => setState(() {
                    _selected.removeAll(visible.map((a) => a.path));
                  }),
                  child: const Text('清空'),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  picked.isEmpty
                      ? '未勾选素材 · 单击预览原片，勾选框选择导出（支持 Shift 连选）'
                      : '已选 ${picked.length} 项（共 ${_fmtSize(_pickedTotalBytes)}）· 支持 Shift 连选',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: picked.isEmpty
                        ? FontWeight.normal
                        : FontWeight.w600,
                    color: picked.isEmpty
                        ? const Color(0xFF64748B)
                        : const Color(0xFF0F766E),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 素材展示区
        Expanded(
          child: visible.isEmpty
              ? _buildEmptyState()
              : _viewMode == GalleryViewMode.list
              ? _buildListView(visible)
              : _buildGridView(visible),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required MediaKind kind,
    required String label,
    required int count,
    required Color dotColor,
  }) {
    final selected = _filter == kind;
    return ChoiceChip(
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      selected: selected,
      onSelected: (_) => _switchFilter(kind),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.7)
                  : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFF0F766E)
                    : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final busy = _scanning || _exporting || _findingCamera;
    if (_scanning) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text(
              '正在读取并识别素材标记…',
              style: TextStyle(color: Color(0xFF475569), fontSize: 13.5),
            ),
          ],
        ),
      );
    }

    if (_assets.isNotEmpty && _searchQuery.trim().isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 42,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 10),
            Text(
              '当前分类下没有匹配「${_searchQuery.trim()}」的文件',
              style: const TextStyle(color: Color(0xFF475569), fontSize: 13.5),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              child: const Text('清除搜索条件'),
            ),
          ],
        ),
      );
    }

    if (_assets.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.perm_media_outlined,
                size: 40,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(height: 12),
              const Text(
                '此分类没有素材',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '只有带 TPLG 实况标记的原始相机视频可导出实况；其余视频可在「视频」分类预览和复制。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDFA),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.motion_photos_on_rounded,
                    size: 30,
                    color: Color(0xFF0D9488),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '导入 Pocket 4P 素材开始转换',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '自动识别带实况标记的原始 MP4，一键封装为百度网盘 .livp 或 Apple 实况，不改动相机源文件。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: busy ? null : _findCamera,
                      icon: const Icon(Icons.usb_rounded, size: 17),
                      label: const Text('自动检测相机存储'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _pickCameraDir,
                      icon: const Icon(Icons.folder_open_rounded, size: 17),
                      label: const Text('浏览本地文件夹'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListView(List<MediaAsset> visible) {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final a = visible[i];
        final selected = _selected.contains(a.path);
        return Material(
          key: ValueKey(a.path),
          color: selected ? const Color(0xFFF0FDFA) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: selected
                  ? const Color(0xFF14B8A6)
                  : const Color(0xFFE2E8F0),
              width: selected ? 1.3 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (HardwareKeyboard.instance.isShiftPressed) {
                _onItemTap(i, a, visible);
              } else {
                _previewAsset(a, visible, i);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _buildListLeading(a),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              _fmtTime(a.shotAt),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            Text(
                              _fmtSize(a.sizeBytes),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            if (a.friendlySpec.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  a.friendlySpec,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '预览素材',
                    icon: const Icon(
                      Icons.open_in_full_rounded,
                      size: 17,
                      color: Color(0xFF475569),
                    ),
                    onPressed: () => _previewAsset(a, visible, i),
                  ),
                  Checkbox(
                    value: selected,
                    onChanged: (_) => _onItemTap(i, a, visible),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildListLeading(MediaAsset a) {
    if (a.kind == MediaKind.photo) {
      final isRaw = p.extension(a.path).toLowerCase() == '.dng';
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 76,
          height: 50,
          color: const Color(0xFFEFF2F6),
          child: isRaw
              ? const Center(
                  child: Text(
                    'DNG',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                )
              : Image.file(
                  File(a.path),
                  width: 76,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.image_outlined,
                    color: Color(0xFF94A3B8),
                  ),
                ),
        ),
      );
    }
    return ThumbnailImage(
      videoPath: a.path,
      isLive: a.kind == MediaKind.livePhoto,
      size: 76,
      height: 50,
      borderRadius: 7,
    );
  }

  Widget _buildGridView(List<MediaAsset> visible) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 235,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemCount: visible.length,
      itemBuilder: (_, i) {
        final a = visible[i];
        final selected = _selected.contains(a.path);
        return Material(
          key: ValueKey(a.path),
          color: selected ? const Color(0xFFF0FDFA) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected
                  ? const Color(0xFF0D9488)
                  : const Color(0xFFE2E8F0),
              width: selected ? 1.8 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (HardwareKeyboard.instance.isShiftPressed) {
                _onItemTap(i, a, visible);
              } else {
                _previewAsset(a, visible, i);
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildGridCover(a),
                      if (a.friendlySpec.isNotEmpty)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.60),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              a.friendlySpec,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () => _onItemTap(i, a, visible),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF0D9488)
                                  : Colors.black.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              selected ? Icons.check_rounded : Icons.add,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_fmtTime(a.shotAt)} · ${_fmtSize(a.sizeBytes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridCover(MediaAsset a) {
    if (a.kind == MediaKind.photo) {
      final isRaw = p.extension(a.path).toLowerCase() == '.dng';
      if (isRaw) {
        return const ColoredBox(
          color: Color(0xFFEFF2F6),
          child: Center(
            child: Text(
              'RAW / DNG',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
          ),
        );
      }
      return Image.file(
        File(a.path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(
          color: Color(0xFFEFF2F6),
          child: Icon(Icons.image_outlined, color: Color(0xFF94A3B8)),
        ),
      );
    }
    return ThumbnailImage(
      videoPath: a.path,
      isLive: a.kind == MediaKind.livePhoto,
      expand: true,
      borderRadius: 0,
    );
  }

  static String _fmtSize(int bytes) {
    final mb = bytes / 1024 / 1024;
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  String _fmtTime(DateTime? t) => t == null
      ? '无时间'
      : '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _SidebarCard extends StatelessWidget {
  final String step;
  final String title;
  final Widget? trailing;
  final Widget child;

  const _SidebarCard({
    required this.step,
    required this.title,
    this.trailing,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 19,
                height: 19,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6FFFA),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  step,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F766E),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _ViewModeButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        elevation: active ? 0.5 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Icon(
              icon,
              size: 17,
              color: active ? const Color(0xFF0D9488) : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}

/// 路径卡片：主行显示目录名，次行显示完整路径摘要，右侧"更改"按钮
class _PathCard extends StatelessWidget {
  final String path;
  final VoidCallback? onChange;
  final bool isOut;
  const _PathCard({
    required this.path,
    required this.onChange,
    this.isOut = false,
  });

  @override
  Widget build(BuildContext context) {
    final empty = path.isEmpty;
    final name = empty
        ? '尚未选择素材目录'
        : path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).lastOrNull ??
              path;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            isOut
                ? Icons.drive_folder_upload_outlined
                : (empty ? Icons.folder_off_outlined : Icons.sd_storage_outlined),
            size: 18,
            color: empty ? const Color(0xFF94A3B8) : const Color(0xFF0D9488),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: empty ? '尚未选择目录' : path,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: empty
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  if (!empty)
                    Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                ],
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: onChange,
            child: const Text('更改', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
