import 'dart:io';

import 'package:path/path.dart' as p;

/// Read-only discovery of mounted storage. Does not use private DJI protocols.
class CameraDiscovery {
  Future<List<String>> find({Iterable<String>? roots}) async {
    final candidates = roots ?? await _mountedRoots();
    final found = <String>{};
    for (final root in candidates) {
      final dcim = Directory(p.join(root, 'DCIM'));
      try {
        if (!await dcim.exists()) continue;
        await for (final child in dcim.list(followLinks: false)) {
          if (child is Directory &&
              RegExp(
                r'^DJI[_ ]?\d+$',
                caseSensitive: false,
              ).hasMatch(p.basename(child.path))) {
            found.add(dcim.path);
            break;
          }
        }
      } on FileSystemException {
        // Unmounted/locked drives must not stop discovery on other drives.
      }
    }
    return found.toList()..sort();
  }

  Future<List<String>> _mountedRoots() async {
    if (Platform.isWindows) {
      return [for (var c = 67; c <= 90; c++) '${String.fromCharCode(c)}:\\'];
    }
    if (Platform.isMacOS) {
      return [
        await for (final entry in Directory(
          '/Volumes',
        ).list(followLinks: false))
          if (entry is Directory) entry.path,
      ];
    }
    return [];
  }
}
