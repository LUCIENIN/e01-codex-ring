# 写入自己的内容

## 先理解设备模型

E01 是 BLE 媒体胸牌，不是普通外接显示器。你的程序不能持续推送桌面像素；它需要生成一份设备支持的内容，再通过协议上传到设备的媒体槽位。

## 最小链路

1. **准备数据**：从本地文件、HTTP API、监控系统或 Codex session 读取一个小快照。
2. **渲染**：输出 368×368 PNG。圆形屏幕四角不可见，重要信息放在中心安全区。
3. **编码**：当前实现按实机 App 路径把静态 PNG 编成 368×368、MJPEG、YUVJ420P AVI。
4. **扫描和绑定**：只选择广播 `FD00` 的候选设备，完成 `0x60 → 0x61`。
5. **读取身份**：先确认尺寸、存储、协议和固件字段，不用外壳照片猜型号。
6. **认证与传输**：在白名单特征上执行 RCSP 认证、存储协商和大文件分片传输。
7. **验收**：设备必须返回成功结果，并且屏幕上真的出现目标画面。

## 改成你自己的仪表盘

代码分成两层：

- `CodexSessionReader.swift`：当前数据源，只提取最近一次额度窗口。
- `RingCardRenderer.swift`：把数据画成圆形 PNG。

要显示别的内容，推荐新建一个数据结构和读取器，然后给渲染器增加对应入口。不要把 API Token、Cookie 或完整响应写进图片、日志、测试 fixture 或 GitHub Issue。

先只验证图片：

```bash
swift test
swift run codex-ring preview --output .runtime/my-ring.png
open .runtime/my-ring.png
```

再验证设备身份：

```bash
swift run codex-ring scan --timeout 10
swift run codex-ring bind --timeout 20
```

最后才尝试媒体更新：

```bash
swift run codex-ring display --timeout 30
```

当前版本已在一台 368×368 E01 上完成实机传输。仍然不要把命令正常启动、BLE 写入回调或绑定成功当成完成；只有出现 `display_transfer_complete`，并在圆屏上看到目标画面，才算本次写入完成。

## 如果要做成长期程序

建议把工程拆为四个接口：

```text
SnapshotProvider -> CardRenderer -> MediaEncoder -> BadgeTransport
```

这样可以先用假数据和文件传输测试前三层；只有最后一层需要真机。长期刷新至少保持 30 秒间隔，并在内容没有变化时跳过上传，减少闪存写入和 BLE 占用。

## 关于刷固件

当前仓库不提供刷机。只有同时满足以下条件才应增加 OTA：精确硬件/固件身份、官方来源镜像、校验值、设备支持声明、稳定连接、断电恢复和可验证回滚。缺少任一项时，继续研究普通媒体协议比盲刷更安全。

可先运行只读检查：

```bash
swift run codex-ring probe --timeout 20
```

当前测试设备返回协议 `2.9`、固件 `11.1.0.3`、型号字段 `1613`，RCSP 目标信息包含 AC697 SDK-family 标记。这只证明固件属于 AC697 开发谱系，不能据此选择某个通用 AC697 镜像直接刷写。原始目标信息可能含设备级字段，提交 Issue 或日志时必须脱敏。
