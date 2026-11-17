# Third-party components

Pocket Motion is based on https://github.com/MicageEritc/Pocket-Motion.
This independently maintained build is published at https://github.com/happyfox-dot/Pocket-Motion.
No endorsement by DJI or by the upstream developers is implied.

- **FFmpeg / ffprobe:** unmodified Gyan 7.1 full Windows builds. See
  `licenses/FFmpeg-GPL.txt` and `licenses/FFmpeg-build.txt` for the supplied
  license, exact source revision and configuration. Build provider:
  https://www.gyan.dev/ffmpeg/builds/ . Upstream source:
  https://github.com/FFmpeg/FFmpeg/tree/b08d7969c5 .
- **Flutter / Dart and Dart packages:** see `licenses/Flutter-LICENSE.txt` and
  the generated `data/flutter_assets/NOTICES.Z` notice bundle.
  Sources: https://github.com/flutter/flutter and the dependencies in `pubspec.lock`.
- **media_kit:** see `licenses/media-kit-LICENSE.txt`.
  https://github.com/media-kit/media-kit .
- **libmpv:** the media_kit Windows dependency supplies the unmodified
  `mpv-dev-x86_64-20230924-git-652a1dd` build.
  Binary and build sources: https://github.com/media-kit/libmpv-win32-video-build/releases/tag/2023-09-24 .
  Upstream: https://github.com/mpv-player/mpv .
- **ANGLE / graphics components:** supplied by media_kit from
  https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/tag/v1.0.1 .
  Upstream: https://chromium.googlesource.com/angle/angle .
- **Microsoft Visual C++ runtime:** unmodified x64 redistributable DLLs from
  Visual Studio 2022 Build Tools. These remain Microsoft components.
- **DJI watermark artwork:** see `assets/SOURCES.md`. The included artwork and
  trademarks remain DJI's property and are not licensed as original project code.

The application starts FFmpeg/ffprobe as separate command-line processes.
Individual components retain their respective licenses and notices.
