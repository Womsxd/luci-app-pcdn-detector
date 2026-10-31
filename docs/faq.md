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

**升级时提示 `Existing conffile /etc/config/pcdn-detector is different ...`**

旧版本把 UCI 配置当作 conffile 随包安装，而页面会把更新源、版本、仓库、开机自启等写回该文件，因此每次升级都与包内默认值不同。opkg 会保留现有文件，把新默认值写成 `/etc/config/pcdn-detector-opkg`（apk 系统为 `.apk-new`），安装本身不受影响。

新版只随包提供 `/usr/share/pcdn-detector/pcdn-detector.config` 模板，由 `postinst` / `uci-defaults` 在文件缺失时创建：升级保留用户设置，不再出现该提示，残留的 `-opkg` 副本也会在下次安装或开机时清理。从仍带 conffile 的旧版本升级时，opkg 会先把用户改过的配置备份为 `-opkg`，`postinst` 会把它恢复成主配置，因此升级不会丢设置。

**升级时提示 `uci: Entry not found`**

这一行由 base-files 安装钩子里的 `uci commit` 打印，与本包脚本无关：它会把 `/etc/config` 下每个**文件名**当作包名逐个提交，文件名里带 `.` 时（如 `pcdn-detector-opkg.backup`）会被解析成 `<包>.<段>`，段不存在就报这个错。定位并清理：

```sh
for c in $(ls /etc/config); do uci -q commit "$c" || echo "FAIL: $c"; done
rm -f /etc/config/pcdn-detector-opkg.backup
```

`/etc/config` 下不要留带点号的备份文件（`*.bak`、`*.backup` 等）。

**LuCI 菜单不显示 / 页面空白**

- 21.02+ 未安装 `luci-compat` 时会出现该问题；通过 opkg/apk 正常安装本包会自动拉取，手动安装请先执行 `opkg install luci-compat` 或 `apk add luci-compat`；
- 安装后清理缓存：`rm -f /tmp/luci-indexcache && rm -rf /tmp/luci-modulecache`。
