local m, s, o

m = Map("pcdn-detector", translate("下载 / 更新"))
m.description = translate("从 GitHub 或 CNB 下载 Go / C 版本的 pcdn-detect 二进制并安装。页面顶部可切换更新源与版本；下载后会用 -v 自检，失败自动回滚到旧版本。")

m:section(SimpleSection).template = "pcdn-detector/update"

s = m:section(TypedSection, "pcdn-detector", translate("下载源"))
s.anonymous = true
s.addremove = false

o = s:option(Value, "repo", translate("代码仓库"))
o.rmempty = true
o.datatype = "string"
o.description = translate("留空使用当前更新源的内置默认仓库；填写后作为自定义仓库原样使用。")

o = s:option(Value, "download_base", translate("下载地址前缀"))
o.rmempty = true
o.placeholder = "https://github.com/Womsxd/pcdn-detector/releases/latest/download"
o.datatype = "string"
o.description = translate("留空时按「更新源 + 版本」自动推导（GitHub 或 CNB 的 latest/download）；填写后覆盖推导结果，资源名仍会自动追加。")

o = s:option(Flag, "allow_overwrite", translate("空间不足时覆盖安装"))
o.default = 0
o.rmempty = false
o.description = translate("默认关闭。仅当目标分区（16 MiB）与 /tmp（24 MiB）空间都不足时生效：先删除旧程序再下载新版本，因此更新失败将无法自动回滚。")

return m
