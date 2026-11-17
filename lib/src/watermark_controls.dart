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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('添加机型水印', style: TextStyle(fontSize: 13)),
          subtitle: const Text(
            WatermarkSettings.text,
            style: TextStyle(fontSize: 11),
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
          Row(
            children: [
              const Text('水印位置', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButton<WatermarkPosition>(
                  isExpanded: true,
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
            ],
          ),
          const Text(
            '封面和动态画面同步添加。视频将重新编码，导出较慢；带水印版本另存为新文件。',
            style: TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
      ],
    );
  }
}
