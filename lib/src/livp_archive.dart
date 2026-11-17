import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Two stored ZIP entries plus the Baidu LIVP index in the ZIP comment.
/// Format reference: https://github.com/LetMeFly666/2livp (README).
/// This is a community-documented transport format, not an Apple standard.
/// Media metadata must already be valid before packing.
class LivpArchive {
  static const _max32 = 0xffffffff;
  static final _crcTable = List<int>.generate(256, (n) {
    var value = n;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) != 0 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
    }
    return value;
  });

  static Future<void> write({
    required File photo,
    required File video,
    required File output,
    DateTime? shotAt,
  }) async {
    final entries = [
      _Entry(photo, 'IMG_POCKET.HEIC.heic'),
      _Entry(video, 'IMG_POCKET.HEIC.mov'),
    ];
    var totalSize = 0;
    for (final entry in entries) {
      entry.size = await entry.file.length();
      if (entry.size == 0) throw const FormatException('实况资源为空');
      totalSize += entry.size + 30 + entry.name.length + 46 + entry.name.length;
    }
    if (totalSize + 22 + 56 > _max32) {
      throw const FormatException('LIVP 文件超过此版本支持的 4 GiB 上限');
    }
    // Exclusive creation also prevents an output from overwriting an input.
    await output.create(exclusive: true);
    RandomAccessFile? out;
    try {
      out = await output.open(mode: FileMode.write);
      final date = shotAt ?? await photo.lastModified();
      final dosTime =
          (date.hour << 11) | (date.minute << 5) | (date.second ~/ 2);
      final dosDate =
          ((date.year.clamp(1980, 2107) - 1980) << 9) |
          (date.month << 5) |
          date.day;
      for (final entry in entries) {
        entry.offset = await out.position();
        final header = ByteData(30)
          ..setUint32(0, 0x04034b50, Endian.little)
          ..setUint16(4, 20, Endian.little)
          ..setUint16(10, dosTime, Endian.little)
          ..setUint16(12, dosDate, Endian.little)
          ..setUint32(18, entry.size, Endian.little)
          ..setUint32(22, entry.size, Endian.little)
          ..setUint16(26, entry.name.length, Endian.little);
        await out.writeFrom(header.buffer.asUint8List());
        await out.writeFrom(ascii.encode(entry.name));
        entry.dataOffset = await out.position();
        var crc = _max32;
        var written = 0;
        await for (final chunk in entry.file.openRead()) {
          written += chunk.length;
          for (final byte in chunk) {
            crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
          }
          await out.writeFrom(chunk);
        }
        if (written != entry.size) {
          throw const FileSystemException('打包期间素材发生变化');
        }
        entry.crc = (crc ^ _max32) & _max32;
        final end = await out.position();
        await out.setPosition(entry.offset + 14);
        await out.writeFrom(
          (ByteData(
            4,
          )..setUint32(0, entry.crc, Endian.little)).buffer.asUint8List(),
        );
        await out.setPosition(end);
      }
      final centralOffset = await out.position();
      for (final entry in entries) {
        final header = ByteData(46)
          ..setUint32(0, 0x02014b50, Endian.little)
          ..setUint16(6, 20, Endian.little)
          ..setUint16(12, dosTime, Endian.little)
          ..setUint16(14, dosDate, Endian.little)
          ..setUint32(16, entry.crc, Endian.little)
          ..setUint32(20, entry.size, Endian.little)
          ..setUint32(24, entry.size, Endian.little)
          ..setUint16(28, entry.name.length, Endian.little)
          ..setUint32(42, entry.offset, Endian.little);
        await out.writeFrom(header.buffer.asUint8List());
        await out.writeFrom(ascii.encode(entry.name));
      }
      final centralSize = await out.position() - centralOffset;
      String hex(int n) => n.toRadixString(16).padLeft(8, '0').toUpperCase();
      final comment = ascii.encode(
        '0002${hex(entries[0].dataOffset)}'
        '${hex(entries[0].size)}0003${hex(entries[1].dataOffset)}'
        '${hex(entries[1].size)}313030304C495650',
      );
      final footer = ByteData(22)
        ..setUint32(0, 0x06054b50, Endian.little)
        ..setUint16(8, 2, Endian.little)
        ..setUint16(10, 2, Endian.little)
        ..setUint32(12, centralSize, Endian.little)
        ..setUint32(16, centralOffset, Endian.little)
        ..setUint16(20, comment.length, Endian.little);
      await out.writeFrom(footer.buffer.asUint8List());
      await out.writeFrom(comment);
      await out.flush();
      await out.close();
      out = null;
      if (shotAt != null) await output.setLastModified(shotAt);
    } catch (_) {
      await out?.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }
}

class _Entry {
  final File file;
  final String name;
  int size = 0;
  int offset = 0;
  int dataOffset = 0;
  int crc = 0;
  _Entry(this.file, this.name);
}
