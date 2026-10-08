## Rakazo 环境

computer 镜像已为系统 Python 预装 Tushare，直接使用 `python3`，无需安装包或创建 venv。
官方接口参考位于 `/opt/rakazo/skills/tushare-data/references/数据接口.md`。

`TUSHARE_TOKEN` 由 Rakazo Agent Secrets 在 shell 执行时注入。仅通过环境变量读取，不输出、不写入脚本、文件或聊天，不使用 `ts.set_token()` 保存到磁盘。
SDK 默认使用 HTTP；每次初始化都显式切换到 HTTPS：

```python
import os
import tushare as ts

pro = ts.pro_api(os.environ["TUSHARE_TOKEN"])
pro._DataApi__http_url = "https://api.waditu.com/dataapi"
```

待交付文件保存到当前 Bot 工作目录的 `exports/`，使用 `attach_file` 的相对路径（如 `exports/daily.csv`）附加到聊天。
跨 Bot 共享的文件放到 `/home/rakazo/shared/tushare/`；附加前先复制到当前 Bot 的 `exports/`。
