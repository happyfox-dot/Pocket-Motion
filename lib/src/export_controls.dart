import 'dart:io';

// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'export_support.dart';

class ExportControlSettings {
  /// 0 means automatic concurrency based on CPU cores and workload.
  final int concurrency;
  final ExportConflictPolicy conflictPolicy;
  final bool useHardwareAccel;
  final bool openFolderWhenDone;

  const ExportControlSettings({
    this.concurrency = 0,
    this.conflictPolicy = ExportConflictPolicy.skip,
    this.useHardwareAccel = true,
    this.openFolderWhenDone = false,
  });

  int resolveWorkers({required bool watermarkEnabled}) {
    if (concurrency > 0) return concurrency.clamp(1, 8);
    final cores = Platform.numberOfProcessors;
    if (watermarkEnabled) {
      return cores >= 8 ? 2 : 1;
    }
    if (cores >= 12) return 4;
    if (cores >= 6) return 3;
    return 2;
  }

  ExportControlSettings copyWith({
    int? concurrency,
    ExportConflictPolicy? conflictPolicy,
    bool? useHardwareAccel,
    bool? openFolderWhenDone,
  }) {
    return ExportControlSettings(
      concurrency: concurrency ?? this.concurrency,
      conflictPolicy: conflictPolicy ?? this.conflictPolicy,
      useHardwareAccel: useHardwareAccel ?? this.useHardwareAccel,
      openFolderWhenDone: openFolderWhenDone ?? this.openFolderWhenDone,
    );
  }

  Map<String, Object> toJson() => {
    'concurrency': concurrency,
    'conflictPolicy': conflictPolicy.name,
    'useHardwareAccel': useHardwareAccel,
    'openFolderWhenDone': openFolderWhenDone,
  };

  factory ExportControlSettings.fromJson(Object? data) {
    if (data is! Map) return const ExportControlSettings();
    final rawConcurrency = data['concurrency'];
    final parsedConcurrency = rawConcurrency is int ? rawConcurrency : 0;
    const allowed = {0, 1, 2, 4};
    return ExportControlSettings(
      concurrency: allowed.contains(parsedConcurrency) ? parsedConcurrency : 0,
      conflictPolicy: ExportConflictPolicy.values.firstWhere(
        (v) => v.name == data['conflictPolicy'],
        orElse: () => ExportConflictPolicy.skip,
      ),
      useHardwareAccel: data['useHardwareAccel'] != false,
      openFolderWhenDone: data['openFolderWhenDone'] == true,
    );
  }
}

/// Compact export control strip inside Step 3 of the sidebar.
class ExportSettingsPanel extends StatelessWidget {
  final ExportControlSettings settings;
  final bool locked;
  final bool showHardwareToggle;
  final String? hardwareLabel;
  final ValueChanged<ExportControlSettings> onChanged;

  const ExportSettingsPanel({
    super.key,
    required this.settings,
    required this.onChanged,
    this.locked = false,
    this.showHardwareToggle = true,
    this.hardwareLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 6,
                child: _CompactDropdownField<ExportConflictPolicy>(
                  label: '同名文件',
                  value: settings.conflictPolicy,
                  enabled: !locked,
                  items: [
                    for (final policy in ExportConflictPolicy.values)
                      DropdownMenuItem(
                        value: policy,
                        child: Text(policy.label),
                      ),
                  ],
                  onChanged: (policy) {
                    if (policy != null) {
                      onChanged(settings.copyWith(conflictPolicy: policy));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: _CompactDropdownField<int>(
                  label: '任务并发',
                  value: settings.concurrency,
                  enabled: !locked,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('自动并发')),
                    DropdownMenuItem(value: 1, child: Text('单路 (1x)')),
                    DropdownMenuItem(value: 2, child: Text('双路 (2x)')),
                    DropdownMenuItem(value: 4, child: Text('四路 (4x)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      onChanged(settings.copyWith(concurrency: val));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (showHardwareToggle)
                _TogglePill(
                  icon: Icons.memory_rounded,
                  label: hardwareLabel != null && settings.useHardwareAccel
                      ? '硬件加速 ($hardwareLabel)'
                      : 'GPU 硬件加速',
                  selected: settings.useHardwareAccel,
                  enabled: !locked,
                  tooltip: '启用硬件 HEVC 编码加速水印合成，不兼容时自动回退 CPU',
                  onTap: () => onChanged(
                    settings.copyWith(
                      useHardwareAccel: !settings.useHardwareAccel,
                    ),
                  ),
                ),
              _TogglePill(
                icon: Icons.folder_open_outlined,
                label: '导完打开目录',
                selected: settings.openFolderWhenDone,
                enabled: !locked,
                tooltip: '批量导出完成后自动打开输出文件夹',
                onTap: () => onChanged(
                  settings.copyWith(
                    openFolderWhenDone: !settings.openFolderWhenDone,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactDropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final bool enabled;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _CompactDropdownField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 3),
        Container(
          height: 29,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: enabled ? Colors.white : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              isExpanded: true,
              isDense: true,
              value: value,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF1E293B)),
              items: items,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _TogglePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  const _TogglePill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? const Color(0xFFE6FFFA) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected
                ? const Color(0xFF14B8A6)
                : const Color(0xFFCBD5E1),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: selected
                      ? const Color(0xFF0F766E)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? const Color(0xFF0F766E)
                        : const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Interactive batch export progress & pause/cancel control card.
class ActiveExportControlCard extends StatelessWidget {
  final int doneCount;
  final int totalCount;
  final int successCount;
  final int skippedCount;
  final int failCount;
  final int workerCount;
  final bool paused;
  final bool cancelling;
  final List<String> activeNames;
  final Duration elapsed;
  final VoidCallback onTogglePause;
  final VoidCallback onCancel;

  const ActiveExportControlCard({
    super.key,
    required this.doneCount,
    required this.totalCount,
    required this.successCount,
    required this.skippedCount,
    required this.failCount,
    required this.workerCount,
    required this.paused,
    required this.cancelling,
    required this.activeNames,
    required this.elapsed,
    required this.onTogglePause,
    required this.onCancel,
  });

  String _etaText() {
    if (doneCount <= 0 || totalCount <= doneCount || elapsed.inSeconds < 1) {
      return '计算剩余时间…';
    }
    final avgMs = elapsed.inMilliseconds / doneCount;
    final remSec = ((totalCount - doneCount) * avgMs / 1000).round();
    if (remSec < 60) return '预计剩余 ~${remSec}s';
    return '预计剩余 ~${remSec ~/ 60}m ${remSec % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final ratio = totalCount == 0 ? 0.0 : (doneCount / totalCount).clamp(0.0, 1.0);
    final pct = (ratio * 100).round();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: paused ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: paused ? const Color(0xFFFDE68A) : const Color(0xFF99F6E4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  cancelling
                      ? '正在中止导出任务…'
                      : paused
                      ? '已暂停 ($doneCount/$totalCount · $pct%)'
                      : '正在导出 $doneCount/$totalCount ($pct% · ${workerCount}x 并发)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: paused
                        ? const Color(0xFFB45309)
                        : const Color(0xFF0F766E),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (!paused && !cancelling)
                Text(
                  _etaText(),
                  style: const TextStyle(
                    fontSize: 10.5,
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
              value: ratio,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '成功 $successCount · 跳过 $skippedCount · 失败 $failCount',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF475569),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (activeNames.isNotEmpty && !cancelling) ...[
            const SizedBox(height: 3),
            Text(
              '处理中：${activeNames.join('、')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: cancelling ? null : onTogglePause,
                  icon: Icon(
                    paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 15,
                  ),
                  label: Text(
                    paused ? '继续导出' : '暂停队列',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: cancelling ? null : onCancel,
                  icon: const Icon(Icons.stop_circle_outlined, size: 15),
                  label: const Text('取消导出', style: TextStyle(fontSize: 11.5)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
