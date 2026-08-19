# E01 Codex Ring

一个面向 macOS 的实验性 Swift 项目：读取本机 Codex 会话中最近一次额度快照，生成圆形仪表盘，并研究如何通过 BLE 把自定义内容写入 E01/ZRun 圆形电子胸牌。

> 当前结论：预览、BLE 扫描、绑定、设备信息解析和 RCSP 媒体传输已经在一台 368×368 E01 上完成实机验证；屏幕肉眼显示仍未通过验收。`display` 传输 MPEG-4/YUV420P AVI，只有设备完成尾包与头部复核后才输出 `display_transfer_complete`，但该结果不能替代屏幕确认。仓库暂不刷写固件。

![Status](https://img.shields.io/badge/status-hardware--investigation-orange)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0%2B-F05138)
![License](https://img.shields.io/badge/license-MIT-green)

## 已验证的部分

- 只读取近期 Codex JSONL 中的 `token_count.rate_limits`，忽略提示词、消息、账号标识和 Cookie。
- 生成 64–2048 像素的圆形 PNG；默认 320×320，设备路径使用 368×368。
- 只读扫描 E01 的 `FD00` 数据服务。
- 在 `FD01/FD02/FD03` 白名单内执行绑定，并校验 `0x61` 响应。
- 解析屏幕尺寸、存储容量、协议版本、固件版本、平台和型号字段。
- 实现普通数据帧、视频表盘 `C0/C1/C2/C3/C5`、RCSP 帧和大文件传输的解析/编码测试。
- 在一台自有 E01 上通过 RCSP 完成 368×368 AVI 传输；设备完成尾包和 offset 0 头部复核，但屏幕显示尚未确认。

## 验证边界

- 实机结论只覆盖当前这一台 E01 及其已观察到的协议组合，不代表所有同外壳设备兼容。
- 普通数据服务的 `C0` 表盘更新在该固件上会在请求媒体分片前被拒绝，因此 `display` 使用已经实机成功的 RCSP 文件传输路径。
- 没有取得与该设备精确版本匹配、可回滚的官方固件，所以没有执行 OTA。
- 其他 E01 固件和相似外壳设备的兼容性未知。

## 快速开始

要求：macOS 14+、Swift 6+。`display` 还需要 Homebrew 路径下的 FFmpeg：`/opt/homebrew/bin/ffmpeg`。

```bash
git clone https://github.com/LUCIENIN/e01-codex-ring.git
cd e01-codex-ring
swift test

# 只生成预览，不连接设备
swift run codex-ring preview \
  --sessions "$HOME/.codex/sessions" \
  --output .runtime/codex-ring-preview.png
open .runtime/codex-ring-preview.png

# 只扫描，不连接、不写入
swift run codex-ring scan --timeout 10

# 执行普通数据服务绑定
swift run codex-ring bind --timeout 20

# 写屏；失败会以非零状态退出
swift run codex-ring display --timeout 30

# 持续同步；至少每 30 秒检查一次，只在剩余百分比变化后写屏
swift run codex-ring display-watch --interval 30 --timeout 30
```

`display_transfer_complete` 只有在设备明确返回成功结果后才会输出。看到扫描或绑定成功，不代表屏幕内容已经更新。

`display-watch` 会持续读取最新的本地额度快照。只有设备写入成功后，它才记住该百分比；扫描或传输失败会在下一轮重试，相同百分比不会重复写入。E01 必须处于 Mac 可发现的 BLE 状态，手机端 ZRun 占用连接时无法刷新。

## 新徽章首次同步

新用户需要一台 macOS 14+ 的 Mac、Swift 6+、Homebrew 版 FFmpeg，以及已经产生本地额度记录的 Codex Desktop/CLI。程序读取的是本机 JSONL 中主额度 `limit_id=codex`，不读取聊天正文、Cookie 或云端账号密码。

```bash
brew install ffmpeg
git clone https://github.com/LUCIENIN/e01-codex-ring.git
cd e01-codex-ring
chmod +x scripts/install-display-watch.zsh
./scripts/install-display-watch.zsh
```

安装完成后按这个顺序操作：

1. 关闭手机蓝牙，避免 ZRun 或手机系统先占用徽章连接。
2. 给 E01 断电再上电一次，让 Mac 捕获它的短时 BLE 广播。
3. 等待 `display_sync_complete`；只有这条日志和屏幕肉眼变化同时出现，才算同步成功。
4. 查看日志：`tail -f .runtime/display-watch.error.log .runtime/display-watch.log`。

首次完成 GATT 服务发现后，程序会在 `~/.codex/e01-known-device-id` 保存本机 CoreBluetooth UUID。更换另一块徽章时执行 `./scripts/install-display-watch.zsh --reset-device`，旧 UUID 会先备份，再重新扫描新设备。

这不是 HDMI 或 USB 外接屏。显示链路是“本地 Codex 额度 → 368×368 图片 → MPEG-4 AVI → BLE/RCSP 推送”，因此更新粒度是百分比变化后的同步，不是逐帧镜像。当前只在一台 368×368 E01 上验证过协议传输；实际显示和自动重连仍需按设备固件逐台验收。

## 写入自己的程序/内容

这个胸牌不是 HDMI 显示器，不能直接把 macOS 窗口投进去。可行模型是：

`数据源 → 368×368 渲染 → 设备接受的媒体封装 → BLE 绑定/认证 → 分片传输 → 设备确认 → 肉眼回读`

如果你要显示天气、订单数、服务器状态或自己的 API，只需替换数据读取器和 `RingCardRenderer` 的展示内容；BLE 层保持不变。完整入口见 [写入自己的内容](docs/BUILD-YOUR-OWN.md)，协议边界见 [协议观察](docs/PROTOCOL.md)。

## 项目状态

路线图、验收门和已知阻塞见 [PROJECT.md](PROJECT.md)。公开 Issue 只记录脱敏后的协议与复现信息，不记录真实 MAC、二维码绑定 URL、Codex 会话或固件文件。

## 安全与版权

- 只在你拥有或得到明确授权的设备上测试。
- 仓库不包含 ZRun APK、反编译源码或 E01 固件。
- `jl_auth_2.0.0.js` 来自 Jieli-Tech 的 Apache-2.0 项目；详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- 主项目以 MIT 许可证发布；第三方文件继续遵循其原许可证。

## 参考来源

- [Jieli-Tech/WeChat-Mini-Program-OTA](https://github.com/Jieli-Tech/WeChat-Mini-Program-OTA)（RCSP 认证资源和公开 SDK 语义）
- 本仓库的 E01 普通数据/表盘协议代码来自对自有设备和自有 App 流量的 clean-room 观察；未复制厂商 App 源码。

## 参与贡献

请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。最有价值的贡献不是“我这里也不行”，而是脱敏后的固件身份、完整阶段、返回命令与 reason code。
