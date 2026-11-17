// Keep the upstream Flutter 3.47 API while also building on newer SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BaiduAppleGuideDialog extends StatelessWidget {
  const BaiduAppleGuideDialog({super.key});

  static const String receiverShareTip = '''【iPhone / iPad 经百度网盘查看并保存实况照片步骤】
1. 请用「百度网盘 App」打开分享链接，先点「保存到网盘」转存（不要在微信或浏览器网页直接下载）。
2. 在自己的网盘目录点开 .livp 文件，先点「查看原图」（出现实况标识可在线预览），再点底部「下载 / 保存到相册」；若弹出格式选项请选「实况格式」。
3. 请确认 iOS「设置 → 百度网盘 → 照片」权限已设为「完全访问 / 所有照片」，并关闭手机低电量模式。
4. 【找图提示】因文件保留了相机原始拍摄时间，在相册主时间线可能排在拍摄当天而非最底部；请打开系统「照片」App，前往「最近保存（最近项目）」或下滑至「媒体类型 → 实况照片」查看，左上角带「实况 / LIVE」标且长按能有声播放即成功！''';

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: (screen.height - 48).clamp(360, 740),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF0FDFA),
                border: Border(bottom: BorderSide(color: Color(0xFFCCFBF1))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.cloud_done_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '通过百度网盘向 Apple 用户交付实况照片指南',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '真 UUID 配对封装 · 支持网盘在线预览与存入 iPhone / 安卓系统相册',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionBlock(
                      badge: '第 1 步 · 你的导出与上传方式',
                      title: '选择「导出百度网盘实况 (.livp)」，原样上传文件夹',
                      icon: Icons.upload_file_outlined,
                      items: const [
                        '本工具生成的 .livp 内部已写入真 iOS 配对元数据（HEIC MakerNote 0x0011 与 MOV content.identifier 同 UUID + still-image-time 快门轨），外层附带百度 1000LIVP 尾注索引。',
                        '直接将 baidu_live 内的 .livp 原文件上传百度网盘并分享；切勿在外层再套 .zip / .7z 压缩包。',
                        '新版百度网盘已同时支持 iOS 与主流安卓跨系统实况下载（下载时可选「实况格式」），同一份 .livp 可兼顾多端接收。',
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SectionBlock(
                      badge: '第 2 步 · iPhone / iPad 接收与验收要点',
                      title: '转存 → 查看原图 → 下载实况格式 → 去「最近保存 / 实况照片」验收',
                      icon: Icons.phone_iphone,
                      items: const [
                        '在 iPhone「百度网盘 App」转存后打开 .livp，建议先点「查看原图」再点「下载」（若弹出格式选项选「实况格式」）；确保系统设置中百度网盘拥有「所有照片/完全访问」权限，并关闭省电模式。',
                        '【为什么主相册最底部可能看不到？】因为导出的实况保留了相机原始拍摄时间，主图库按拍摄日期排列会归位到拍摄当天；请前往相册「最近保存（最近项目）」或「媒体类型 → 实况照片」中查找。',
                        '验收标准：在系统「照片」App 中左上角显示「实况 / LIVE」角标，且长按画面能流畅有声播放（若设锁屏壁纸，需在壁纸编辑页手动点亮左下角实况开关）。',
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SectionBlock(
                      badge: '补充 · Mac 电脑导入或兜底排查',
                      title: 'Mac「照片」App 成对导入 / AirDrop 隔空投送',
                      icon: Icons.laptop_mac,
                      items: const [
                        'Mac 接收可导出「Apple 实况照片（HEIC + MOV）」（或把 .livp 改名 .zip 解包），同时选中同名的 .HEIC 与 .MOV 拖入 Mac「照片」App，或同时 AirDrop 给 iPhone 即可自动合并为实况。',
                        '注意：不要在 iPhone 本机的「文件」App 里多选分离的 HEIC + MOV 点存储，iOS 文件管理器不会调用实况合流接口，若相册里已残留半边静态图需先删除再重新导入。',
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '建议先用 1～3 张素材跑通「网盘下载 → 最近保存 / 实况照片相簿长按播放」验收。',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await Clipboard.setData(
                        const ClipboardData(text: receiverShareTip),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制「iPhone 接收与找图提示」，可直接粘贴发给对方'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('复制接收方操作说明'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final String badge;
  final String title;
  final IconData icon;
  final List<String> items;

  const _SectionBlock({
    required this.badge,
    required this.title,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: const Color(0xFF0D9488)),
              const SizedBox(width: 6),
              Text(
                badge,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0D9488),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      items[i],
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
