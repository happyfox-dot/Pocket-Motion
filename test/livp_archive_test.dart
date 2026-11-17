import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:dji_live_gallery/src/livp_archive.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('pocket-livp-test-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test(
    'stored ZIP records, CRC32 and LIVP index locate original bytes',
    () async {
      final photo = await File(p.join(root.path, '中文 图片.heic'))
          .writeAsString('123456789');
      final video = await File(p.join(root.path, 'video.mov'))
          .writeAsBytes([0, 1, 2, 255]);
      final output = File(p.join(root.path, 'result.livp'));
      await LivpArchive.write(
        photo: photo,
        video: video,
        output: output,
        shotAt: DateTime(2026, 11, 17),
      );
      final bytes = await output.readAsBytes();
      final data = ByteData.sublistView(bytes);
      expect(data.getUint32(0, Endian.little), 0x04034b50);
      expect(data.getUint16(8, Endian.little), 0); // stored, never deflated
      expect(
        data.getUint32(14, Endian.little),
        0xcbf43926,
      ); // known CRC32 vector
      expect(data.getUint16(28, Endian.little), 0); // no extra fields
      final comment = ascii.decode(bytes.sublist(bytes.length - 56));
      expect(comment.substring(0, 4), '0002');
      expect(comment.substring(20, 24), '0003');
      expect(comment.substring(40), '313030304C495650');
      final photoOffset = int.parse(comment.substring(4, 12), radix: 16);
      final photoLength = int.parse(comment.substring(12, 20), radix: 16);
      final videoOffset = int.parse(comment.substring(24, 32), radix: 16);
      final videoLength = int.parse(comment.substring(32, 40), radix: 16);
      expect(
        bytes.sublist(photoOffset, photoOffset + photoLength),
        await photo.readAsBytes(),
      );
      expect(
        bytes.sublist(videoOffset, videoOffset + videoLength),
        await video.readAsBytes(),
      );
      final end = bytes.length - 56 - 22;
      expect(data.getUint32(end, Endian.little), 0x06054b50);
      expect(data.getUint16(end + 10, Endian.little), 2);
      final central = data.getUint32(end + 16, Endian.little);
      expect(data.getUint32(central, Endian.little), 0x02014b50);
      expect(data.getUint32(central + 42, Endian.little), 0);
    },
  );

  test('never overwrites an existing archive', () async {
    final photo = await File(p.join(root.path, 'photo.heic'))
        .writeAsString('photo');
    final video = await File(p.join(root.path, 'video.mov'))
        .writeAsString('video');
    final output = await File(p.join(root.path, 'existing.livp'))
        .writeAsString('keep');
    await expectLater(
      LivpArchive.write(photo: photo, video: video, output: output),
      throwsA(isA<FileSystemException>()),
    );
    expect(await output.readAsString(), 'keep');
  });

  test('empty resources fail without leaving an archive', () async {
    final photo = await File(p.join(root.path, 'photo.heic')).create();
    final video = await File(p.join(root.path, 'video.mov'))
        .writeAsString('video');
    final output = File(p.join(root.path, 'result.livp'));
    await expectLater(
      LivpArchive.write(photo: photo, video: video, output: output),
      throwsFormatException,
    );
    expect(await output.exists(), isFalse);
  });
}
