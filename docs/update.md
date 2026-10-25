# 下载 / 更新

「下载/更新」页用于安装 `pcdn-detect` 二进制；LuCI 应用本身见[安装](install.md)。

默认按 `https://github.com/<repo>/releases/latest/download/pcdn-detect-<arch>` 推导地址，资源命名与上游 Makefile 产物一致：

| 设备架构（opkg） | 资源名 |
| --- | --- |
| `mipsel_24kc` / `mipsel_*` | `pcdn-detect-mipsle` |
| `mips_24kc` / `mips_*` | `pcdn-detect-mips` |
| `aarch64_*` | `pcdn-detect-arm64` |
| `arm_*`（armv7） | `pcdn-detect-armv7` |
| `x86_64` | `pcdn-detect-amd64` |

若仓库没有公开 Release、使用私有仓库或需要走镜像：

- 在「下载/更新 → 下载源」中修改仓库名，或设置「下载地址前缀」；
- 也可以直接在页面顶部填写完整的 http(s) 地址（需为未压缩的 ELF 二进制）；

架构识别顺序：`opkg print-architecture`（opkg 系统）→ `apk --print-arch`（apk 系统，24.10+）→ `uname -m` 兜底。

安装流程按剩余空间选择下载位置（阈值由 `update.sh` 统一判定，页面会显示目标分区与 `/tmp` 的剩余空间）：

| 方式 | 条件 | 行为 |
| --- | --- | --- |
| `tmp` | `/tmp` ≥ 24 MiB | 下载到 `/tmp`（tmpfs，下载期间占用内存），复制到目标目录后立刻删除 |
| `direct` | `/tmp` < 24 MiB 且目标分区 ≥ 16 MiB | 下载到目标目录下的临时文件，同分区 `rename` 覆盖：不占内存，替换是原子的 |
| `overwrite` | 两者都不足 | 先删除旧程序再下载；需在「下载/更新 → 下载源」开启「空间不足时覆盖安装」，更新失败无法回滚 |

无论哪种方式，下载后都会校验文件大小与 ELF 头 → 备份原文件（`rename` 到 `pcdn-detect.bak`，不额外占用闪存）→ 覆盖安装 → 执行 `-v` 自检 → 失败自动回滚 → 成功则删除临时文件与 `.bak` → 重启服务。若上次更新被中断（只剩 `.bak`），下次运行会先自动恢复。进度输出位于 `/tmp/pcdn-detect-update.log`。

> `-v` 输出为 SemVer，git 短哈希作为 build metadata：`0.0.1-alpha+c6d101c`（早期格式为 `0.0.1-alpha-c6d101c`）。
> 概览页与下载页把主版本与构建号分开显示，完整字符串保留在鼠标悬停提示中。
