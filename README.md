# E01 Codex Ring

一个面向 macOS 的实验性 Swift 项目：读取本机 Codex 会话中最近一次额度快照，生成圆形仪表盘，并研究如何通过 BLE 把自定义内容写入 E01/ZRun 圆形电子胸牌。

> 当前结论：预览、BLE 扫描、绑定、设备信息解析和协议单元测试已经可复现；真实设备上的媒体写入仍会被一台 E01 以 `C5 reason 5` 拒绝。因此，本仓库没有把“连接成功”写成“写屏成功”，也不提供或刷写固件。

![Status](https://img.shields.io/badge/status-experimental-orange)
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

## 尚未验证的部分

- `display` 在当前实机上尚未得到 `C5 reason 0`；最后观察到的是 `C5 reason 5`。
- 不知道 `reason 5` 是媒体槽位、固件能力、文件封装还是设备状态导致。
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

# 实验性写屏；失败会以非零状态退出
swift run codex-ring display --timeout 30
```

`display_transfer_complete` 只有在设备明确返回成功结果后才会输出。看到扫描或绑定成功，不代表屏幕内容已经更新。

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
