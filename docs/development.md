# 开发与校验

## 目录结构

```
luci-app-pcdn-detector/
├── Makefile                                      # OpenWrt 打包
├── scripts/build-openwrt.sh                      # 官方源码编译 ipk / apk
├── docs/                                         # 文档
├── luasrc/
│   ├── controller/pcdn-detector.lua              # 菜单、页面与后端接口
│   ├── model/pcdn_toml.lua                       # TOML 只读解析（状态 / 统计）
│   ├── model/pcdn_util.lua                       # JSON、进程、HTTP、格式化
│   ├── model/cbi/pcdn-detector/
│   │   ├── overview.lua                          # 概览 + 服务设置（UCI）
│   │   ├── config.lua                            # 完整 TOML 文本编辑
│   │   ├── log.lua                               # 日志
│   │   └── update.lua                            # 下载源设置
│   └── view/pcdn-detector/
│       ├── status.htm                            # 状态卡片 + 服务控制
│       ├── config.htm                            # TOML 文本编辑器
│       ├── log.htm                               # 日志查看器
│       └── update.htm                            # 下载面板
├── root/
│   ├── etc/config/pcdn-detector                  # UCI 配置
│   ├── etc/init.d/pcdn-detector                  # procd 服务脚本（缺配置时让程序自动生成）
│   ├── etc/uci-defaults/40_luci-pcdn-detector    # 首次安装初始化
│   └── usr/share/pcdn-detector/update.sh         # 下载 / 安装 / 回滚脚本
└── po/zh-cn/pcdn-detector.po
```

> 仓库不内嵌 TOML 配置：首次启动服务或首次打开「配置编辑」时，由
> `pcdn-detect` 生成默认配置并写入 UCI 指定的 `config_path`（默认
> `/etc/pcdn-detect/pcdn-detect.toml`），内容来自二进制内置模板，因此会随上游版本更新。

## 本地校验

```bash
# Lua 语法
find luasrc -name '*.lua' -exec luac -p {} \;

# shell 语法
sh -n root/etc/init.d/pcdn-detector
sh -n root/usr/share/pcdn-detector/update.sh

# 默认配置由程序自己生成，可在临时目录验证
tmp="$(mktemp -d)"
pcdn-detect --init-config "$tmp"
pcdn-detect -T -i br-lan -c "$tmp/pcdn-detect.toml"
rm -rf "$tmp"
```

`getconfig` / `saveconfig` 的完整文件收发已用上游真实二进制做端到端校验：保存的全文可直接通过 `pcdn-detect -T`。
