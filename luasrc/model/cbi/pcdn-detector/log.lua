local m = Map("pcdn-detector", translate("运行日志"))

m.description = translate("查看 pcdn-detect 的运行日志。日志来自系统日志（logread），按 tag 精确筛选。")
m.reset = false
m.submit = false

m:section(SimpleSection).template = "pcdn-detector/log"

return m
