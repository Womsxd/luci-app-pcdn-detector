local m = Map("pcdn-detect", translate("配置编辑"))

m.description = translate("完整 TOML 文本编辑，等同于直接编辑一个 txt 文件；保存时把全文发回后端，由 pcdn-detect -T 校验，校验失败不会写入；运行中通过 SIGHUP 热重载。")
m.reset = false
m.submit = false

m:section(SimpleSection).template = "pcdn-detect/config"

return m
