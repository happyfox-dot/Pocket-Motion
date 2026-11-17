// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

import 'watermark.dart';

class WatermarkControls extends StatelessWidget {
  final WatermarkSettings settings;
  final bool locked;
  final ValueChanged<WatermarkSettings> onChanged;

  const WatermarkControls({
    super.key,
    required this.settings,
    required this.onChanged,
    this.locked = false,
  });

  Alignment _cornerAlignment(WatermarkPosition pos) => switch (pos) {
    WatermarkPosition.bottomRight => Alignment.bottomRight,
    WatermarkPosition.bottomLeft => Alignment.bottomLeft,
    WatermarkPosition.topRight => Alignment.topRight,
    WatermarkPosition.topLeft => Alignment.topLeft,
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: settings.enabled
          ? const Color(0xFFF0FDFA)
          : const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: settings.enabled
              ? const Color(0xFF99F6E4)
              : const Color(0xFFE2E8F0),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '添加机型水印',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
            subtitle: const Text(
              WatermarkSettings.text,
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
            value: settings.enabled,
            onChanged: locked
                ? null
                : (enabled) => onChanged(
                    WatermarkSettings(
                      enabled: enabled,
                      position: settings.position,
                    ),
                  ),
          ),
          if (settings.enabled) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              height: 76,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // 四角定位参考框
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Image.asset(
                      WatermarkSettings.assetPath,
                      height: 54,
                      fit: BoxFit.contain,
                      semanticLabel: 'DJI Mimo Pocket 4P 机型水印字标',
                    ),
                  ),
                  Align(
                    alignment: _cornerAlignment(settings.position),
                    child: Container(
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xCC0D9488),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        settings.position.label,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  '水印位置',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<WatermarkPosition>(
                        isExpanded: true,
                        isDense: true,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF1E293B),
                        ),
                        value: settings.position,
                        items: [
                          for (final position in WatermarkPosition.values)
                            DropdownMenuItem(
                              value: position,
                              child: Text(position.label),
                            ),
                        ],
                        onChanged: locked
                            ? null
                            : (position) {
                                if (position != null) {
                                  onChanged(
                                    WatermarkSettings(
                                      enabled: true,
                                      position: position,
                                    ),
                                  );
                                }
                              },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                '封面与动态画面同步叠印，视频将重编码（耗时增加），导出另存新文件名。',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.35,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
    );
  }
}
