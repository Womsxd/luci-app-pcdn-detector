local m, s, o

m = Map("pcdn-detect", translate("下载 / 更新"))
m.description = translate("从 GitHub Release 或自定义地址下载 pcdn-detect 二进制并安装。下载后会用 -v 自检，失败自动回滚到旧版本。")

m:section(SimpleSection).template = "pcdn-detect/update"

s = m:section(TypedSection, "pcdn-detect", translate("下载源"))
s.anonymous = true
s.addremove = false

o = s:option(Value, "repo", translate("GitHub 仓库"))
o.default = "Womsxd/pcdn-detector"
o.rmempty = false
o.datatype = "string"
o.description = translate("格式：用户名/仓库名。用于推导 Release 下载地址与版本检查接口。")

o = s:option(Value, "download_base", translate("下载地址前缀"))
o.rmempty = true
o.placeholder = "https://github.com/Womsxd/pcdn-detector/releases/latest/download"
o.datatype = "string"
o.description = translate("留空使用 GitHub Release 地址；使用镜像时可改为镜像的 releases/latest/download 前缀，或直接在上方填写完整地址。")

return m
