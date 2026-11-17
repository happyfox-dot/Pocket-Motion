# Pocket 4P watermark provenance

Checked on 2026-11-18 against DJI's own download:

- Landing page: https://www.dji.com/cn/downloads/djiapp/dji-mimo
- Official download: https://service-adhoc.dji.com/download/app/android/9bce0a64-3069-40c7-9bbf-1263da0bb900
- Package: `dji.mimo`, version `2.12.8`, version code `10004466`.
- Downloaded APK filename: `1794192325105-DJI-Mimo-store-official-release-10004466_sec.apk`.
- APK SHA-256: `33aee14572993b62146e9daea225ae4a0ab7d36fbfb7878dcb08d14cf8dd111c`.
- Android resource: `0x7f0821b8 drawable/pic_watermark_op4p_1` → `res/U_J.png`, identified with Android SDK `aapt2 dump resources`.
- Bundled copy: `watermarks/pocket4p_device.png`, 540 × 144 pixels, 1860 bytes.
- PNG SHA-256: `aafab562bb3611a926c65facb0b74f27c68049a34e2dcedf26029f4ab6dacc21`.

The PNG is a byte-for-byte copy. Its DJI graphic, OSMO POCKET 4P wordmark,
transparency, proportions and internal padding are unchanged. No replacement
font, outline, shadow or AI-generated logo is used. DJI's marks and artwork
remain DJI's; the repository's software license does not grant ownership of them.
Pocket Motion is an independent tool.

## Verified scope

This establishes the origin and identity of the artwork, not pixel-for-pixel
equivalence to a complete Mimo export. This app scales the PNG canvas to half
the video's short edge and anchors its canvas to the selected corner, retaining
the PNG's built-in padding. These placement values are this app's preset.
Exact Mimo placement across orientations, modes and versions still requires
paired source/Mimo-export samples. The APK's protected implementation did not
provide that evidence. Do not describe the entire output as an exact Mimo replica.

Other observed resources include `pic_watermark_op4p_2` (`res/Xw6.png`, pure
device wordmark), `pic_watermark_op4p_borderless`, and filter/holiday variants.
They are not substituted for the chosen basic DJI + device artwork.
