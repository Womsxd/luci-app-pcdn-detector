# 使用与配置

安装步骤见[安装](install.md)。

## 首次使用

1. 进入 **服务 → PCDN 检测 → 概览**，确认「程序路径」下有可执行文件；没有则到「下载/更新」安装。
2. 打开 **配置编辑**，像编辑 txt 一样直接修改完整 TOML。首次打开时配置不存在，页面会调用 `pcdn-detect --init-config` 生成默认文本、填入默认 `br-lan`（不自动探测 `network.lan.device`，避免误填成 `eth2` 等物理口），并在校验通过后写入 `config_path`（默认 `/etc/pcdn-detect/pcdn-detect.toml`；需要二进制已安装）。常用项：
   - `[capture] interface = "br-lan"`：必须是能看到设备真实 MAC 的 LAN 侧网桥；
   - `[detect] threshold = 20`、`window = "60s"`：触发阈值与检测时长；
   - `[capture] protocol = "udp"`：PCDN 以 UDP 为主；
   - `[log] level = "warn"`：上游默认值；如需在日志页查看告警与解封记录，可临时改为 `info`。
3. 保存并应用，回到概览点击「启动」。
4. 「日志」页可查看告警；启用 HTTP API 后概览页会显示实时统计，见 [HTTP API 检测](http-api.md)。

## 配置说明

配置分两层：

| 层 | 文件 | 内容 |
| --- | --- | --- |
| UCI | `/etc/config/pcdn-detector` | 开机自启、配置文件路径、二进制路径、附加命令行参数、下载源、空间不足时覆盖安装 |
| TOML | `/etc/pcdn-detect/pcdn-detect.toml` | pcdn-detect 自身的全部配置（检测、抓包、内存、日志、HTTP、黑白名单、防火墙、UPnP）；首次使用时由程序生成 |

- 仓库与安装包 **不包含 TOML 文件**。缺少配置时，服务启动脚本或 LuCI 会在临时目录执行
  `pcdn-detect --init-config <临时目录>`，由程序把内置模板写入 `pcdn-detect.toml`，再补上检测到的
  LAN 网卡。该功能要求二进制支持 `--init-config`（当前上游已提供）。
- 后端 `getconfig` / `saveconfig` 只收发完整文件，不做 TOML 解析、字段提取或补丁。
- 大配置采用分片上传：前端每片最多 1000 个字符（UTF-8 约 4 KiB），`POST savechunk` 追加到 `/tmp/pcdn-detect.save.part`；全部发完后 `POST savecommit` 统一校验、落盘、热重载。
- 这样不再受 LuCI 单次请求 body 限制影响（部分固件约 8 KiB，会把 `[[filter.blacklist]]` 等尾部内容截断）；分片仍保留完整注释和名单。
- 「配置编辑」直接编辑完整 TOML 原文（等同 txt），前端不做解析；保存时把全文回传。
- 编辑链路不解析 TOML；`pcdn_toml.lua` 仅用于状态页 / HTTP 统计读取少量字段。
- 「恢复默认」也用程序生成一份新配置（保留当前监听网卡），不再依赖随包模板。
- 保存成功后：服务运行中 → `kill -HUP` 热重载；已启用但未运行 → 自动启动；未启用 → 仅保存。
- `附加启动参数` 会追加到 `pcdn-detect -c <配置>` 之后，**优先级高于 TOML**，例如 `-i br-lan -n 30`。

> 尚未安装 `pcdn-detect` 时无法生成默认配置：配置页会提示先到「下载/更新」安装二进制。

## 日志

pcdn-detect 输出到 stdout，由 procd（`stdout 1`）写入系统日志，tag 为二进制文件名：

```
Sat Oct 24 12:00:42 2026 daemon.info pcdn-detect[1234]: ... 疑似产生PCDN行为 ...
```

日志页按 syslog tag 精确筛选，不会把正文里提到 pcdn-detect 的其它进程日志混进来。可查看的历史长度取决于系统日志缓冲区；需要长期保存请配置 `logread` 落盘或远程 syslog。
