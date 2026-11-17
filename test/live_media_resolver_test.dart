import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:dji_live_gallery/src/live_media_resolver.dart';
import 'package:dji_live_gallery/src/livp_archive.dart';
import 'package:dji_live_gallery/src/models.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pocket-player-resolver-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('resolves .livp archive into extracted cover and motion video', () async {
    final srcJpg = File(p.join(root.path, 'src.jpg'));
    await srcJpg.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
    final srcMov = File(p.join(root.path, 'src.mov'));
    await srcMov.writeAsBytes([0, 0, 0, 12, ...ascii.encode('ftypqt  ')]);

    // Write a standard stored LIVP archive containing jpg + mov
    final livpPath = p.join(root.path, 'sample.livp');
    await LivpArchive.write(
      photo: srcJpg,
      video: srcMov,
      output: File(livpPath),
      shotAt: DateTime(2026, 11, 18, 3),
    );

    final asset = await LiveMediaResolver.assetFromFile(livpPath);
    expect(asset.kind, MediaKind.livePhoto);

    final resolved = await LiveMediaResolver.resolve(asset);
    expect(resolved.isLivePhoto, isTrue);
    expect(resolved.formatBadge, 'LIVP 实况包');
    expect(resolved.videoPath, isNotNull);
    expect(await File(resolved.videoPath!).readAsBytes(), await srcMov.readAsBytes());
  });

  test('splits Android Motion Photo JPEG into primary still and embedded MP4', () async {
    final fakeMp4 = Uint8List.fromList([
      0x00, 0x00, 0x00, 0x14,
      ...ascii.encode('ftypmp42'),
      0x00, 0x00, 0x00, 0x00,
      ...ascii.encode('mp42'),
      0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A,
      0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14,
    ]);
    final xmp = ascii.encode(
      '<x:xmpmeta GCamera:MotionPhoto="1">'
      '<Container:Item Item:Mime="video/mp4" Item:Semantic="MotionPhoto" '
      'Item:Length="${fakeMp4.length}"/></x:xmpmeta>',
    );
    final jpegPrefix = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE1,
      ((xmp.length + 2) >> 8) & 0xFF,
      (xmp.length + 2) & 0xFF,
      ...xmp,
      ...List<int>.filled(64, 0xAA),
      0xFF, 0xD9,
    ]);

    final motionFile = File(p.join(root.path, 'DJI_0001_MP.jpg'));
    await motionFile.writeAsBytes([...jpegPrefix, ...fakeMp4]);

    expect(await LiveMediaResolver.isMotionPhotoFile(motionFile.path), isTrue);
    final asset = await LiveMediaResolver.assetFromFile(motionFile.path);
    expect(asset.kind, MediaKind.livePhoto);

    final resolved = await LiveMediaResolver.resolve(asset);
    expect(resolved.isLivePhoto, isTrue);
    expect(resolved.formatBadge, 'Motion Photo 动态照片');
    expect(resolved.coverImagePath, isNotNull);
    expect(resolved.videoPath, isNotNull);
    expect(await File(resolved.coverImagePath!).readAsBytes(), jpegPrefix);
    expect(await File(resolved.videoPath!).readAsBytes(), fakeMp4);
  });

  test('deduplicates Apple Still + MOV pairs when scanning export directory', () async {
    final liveDir = await Directory(p.join(root.path, 'live')).create();
    await File(p.join(liveDir.path, 'CLIP_01I.JPG')).writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
    await File(p.join(liveDir.path, 'CLIP_01I.MOV')).writeAsBytes([0, 0, 0, 8, ...ascii.encode('ftyp')]);
    await File(p.join(liveDir.path, 'STANDALONE.MOV')).writeAsBytes([0, 0, 0, 8, ...ascii.encode('ftyp')]);

    final items = await LiveMediaResolver.scanExportedDirectory(root.path);
    expect(items, hasLength(2));
    final paired = items.singleWhere((a) => a.filename == 'CLIP_01I.JPG');
    final solo = items.singleWhere((a) => a.filename == 'STANDALONE.MOV');
    expect(paired.kind, MediaKind.livePhoto);
    expect(solo.kind, MediaKind.video);
  });
}
