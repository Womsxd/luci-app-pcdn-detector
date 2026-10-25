# 常见问题

**服务启动失败 / 一直重启**

在「配置编辑」点「仅校验」查看具体错误。常见原因：

- 监听网卡为空或填错（必须填 LAN 侧网桥）；
- 选择了 `hook` 防火墙后端但没写 `[firewall.hook] cmd`；
- 选了 `blacklist` 名单模式但名单为空（pcdn-detect 会拒绝启动）；
- HTTP API 绑定了非回环地址但没设置 token。

**日志页为空**

- 服务可能没启动；
- `[log] level` 默认为 `warn`，不会输出普通告警与业务事件；需要查看时改为 `info`（见[日志说明](usage.md#日志)）；
- 系统日志缓冲区已滚动，或设备没有 `logread`。

**概览页没有实时统计**

「配置编辑」中的 `[http] enabled` 没有启用，或 `listen` / `token` 不匹配。默认 `127.0.0.1:8080` 仅本机可访问，LuCI 通过本机回环读取，详见 [HTTP API 检测](http-api.md)。

**下载 404**

默认仓库没有公开 Release 时会出现。请改用自定义完整地址，或把编译好的二进制上传到路由器：

```bash
scp bin/pcdn-detect-mipsle root@192.168.1.1:/usr/bin/pcdn-detect
```

**SSH 里 `pcdn-detect -v` 正常，但 LuCI 概览页版本显示 `sh: ... Permission denied`**

这是旧版本缓存：`version_of` 曾把失败输出也写入 `/tmp/pcdn-detect.version`，而 `chmod` 只改变 `ctime` / `mode`，不改变 `mtime`，导致缓存没有失效。清除缓存并刷新页面：

```bash
rm -f /tmp/pcdn-detect.version
```

新版已修复：缓存 key 包含 `mtime | ctime | mode`，且只缓存匹配版本号的输出，错误信息不再写入缓存。

**LuCI 菜单不显示 / 页面空白**

- 21.02+ 未安装 `luci-compat` 时会出现该问题；通过 opkg/apk 正常安装本包会自动拉取，手动安装请先执行 `opkg install luci-compat` 或 `apk add luci-compat`；
- 安装后清理缓存：`rm -f /tmp/luci-indexcache && rm -rf /tmp/luci-modulecache`。
