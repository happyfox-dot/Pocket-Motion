"""Verify synthetic watermark exports with an independent decoder (stdlib only)."""
import json
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def run(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def probe(path):
    return json.loads(run('ffprobe', '-v', 'error', '-show_streams',
                          '-show_format', '-of', 'json', str(path)))


def pixels(path, seconds=0):
    stream = next(s for s in probe(path)['streams'] if s['codec_type'] == 'video')
    width, height = stream['width'], stream['height']
    # Seeking even to zero can discard the only JPEG frame in some demuxers.
    seek = ['-ss', str(seconds)] if seconds > 0 else []
    rgb = run('ffmpeg', '-v', 'error', *seek, '-i', str(path),
              '-frames:v', '1', '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-')
    assert len(rgb) == width * height * 3, 'Unexpected decoded frame size'
    indices = [i // 3 for i in range(0, len(rgb), 3)
               if min(rgb[i:i + 3]) > 200]
    if not indices:
        return width, height, None
    return width, height, (min(i % width for i in indices),
                           min(i // width for i in indices),
                           max(i % width for i in indices),
                           max(i // width for i in indices))


def check_corner(path, corner, seconds=0):
    width, height, box = pixels(path, seconds)
    assert box is not None, f'Missing watermark: {path}'
    x0, y0, x1, y1 = box
    assert x1 - x0 > 100 and y1 - y0 > 10, f'Text too small: {box}'
    assert x0 > 0 and y0 > 0 and x1 < width - 1 and y1 < height - 1
    assert (x1 < width / 2) if corner.endswith('L') else (x0 > width / 2)
    assert (y1 < height / 2) if corner.startswith('T') else (y0 > height / 2)
    return box


def packet_hashes(path, selector):
    result = json.loads(run('ffprobe', '-v', 'error', '-select_streams', selector,
                            '-show_packets', '-show_data_hash', 'sha256',
                            '-show_entries', 'packet=data_hash', '-of', 'json',
                            str(path)))
    return [p['data_hash'] for p in result.get('packets', [])]


def verify_pair(still, video, source, corner):
    data = probe(video)
    video_stream = next(s for s in data['streams'] if s['codec_type'] == 'video')
    source_stream = next(s for s in probe(source)['streams'] if s['codec_type'] == 'video')
    duration = float(video_stream['duration'])
    cover_box = check_corner(still, corner)
    for instant in (0, duration / 2, max(0, duration - 0.1)):
        box = check_corner(video, corner, instant)
        assert all(abs(a - b) <= 3 for a, b in zip(cover_box, box)), (cover_box, box)
    assert packet_hashes(source, 'a') == packet_hashes(video, 'a'), 'Audio changed'
    assert video_stream['nb_frames'] == source_stream['nb_frames'], 'Video frames lost or duplicated'
    assert abs(duration - float(source_stream['duration'])) < 0.001, 'Video duration changed'


def main(root):
    output = root / 'output'
    assert len(list(output.glob('*.livp'))) == 5
    assert len(list(output.glob('*.jpg'))) == 2
    with tempfile.TemporaryDirectory(prefix='verify-', dir=root) as scratch:
        scratch = Path(scratch)
        for archive in sorted(output.glob('*.livp')):
            name = archive.stem
            corner = name.split('_')[1]
            source = next(root.glob(f"*/synthetic_{corner}.mp4"))
            with zipfile.ZipFile(archive) as z:
                assert z.testzip() is None
                assert len(z.comment) == 56
                assert all(i.compress_type == zipfile.ZIP_STORED for i in z.infolist())
                assert set(z.namelist()) == {'IMG_POCKET.HEIC.heic', 'IMG_POCKET.HEIC.mov'}
                still = scratch / 'photo.heic'
                video = scratch / 'video.mov'
                still.write_bytes(z.read('IMG_POCKET.HEIC.heic'))
                video.write_bytes(z.read('IMG_POCKET.HEIC.mov'))
            if '_WM_' in name:
                verify_pair(still, video, source, corner)
                tags = probe(video)['format']['tags']
                identifier = tags['com.apple.quicktime.content.identifier']
                assert identifier.encode() in still.read_bytes(), 'Pair ID mismatch'
                assert b'com.apple.quicktime.still-image-time' in video.read_bytes()
            else:
                assert pixels(still)[2] is None
                assert pixels(video)[2] is None
                assert packet_hashes(source, 'v') == packet_hashes(video, 'v')
                assert packet_hashes(source, 'a') == packet_hashes(video, 'a')
            if name == 'synthetic_BR_WM_DJI1_BR':
                # Keep a decoded preview, clearly sourced from synthetic media.
                run('ffmpeg', '-v', 'error', '-y', '-i', str(still), '-frames:v', '1',
                    str(root / 'watermark-preview.png'))
            print(f'PASS LIVP: {name}')
        for motion in sorted(output.glob('*.jpg')):
            data = motion.read_bytes()
            match = re.search(rb'Item:Mime="video/mp4"\s+Item:Semantic="MotionPhoto"'
                              rb'\s+Item:Length="(\d+)"', data)
            assert match is not None
            size = int(match.group(1))
            still, video = scratch / 'photo.jpg', scratch / 'video.mp4'
            still.write_bytes(data[:-size])
            video.write_bytes(data[-size:])
            corner = motion.stem.split('_')[1]
            source = next(root.glob(f"*/synthetic_{corner}.mp4"))
            verify_pair(still, video, source, corner)
            print(f'PASS Motion Photo: {motion.stem}')
    assert not list(output.glob('.pocket-*')), 'Temporary export files remain'
    print('Verified four corners, landscape/portrait, short clips, audio, pair IDs, '
          'still/video consistency, and the unwatermarked path.')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python tools/verify_watermark.py OUTPUT_DIRECTORY')
    main(Path(sys.argv[1]))
