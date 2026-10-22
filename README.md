# 搜狗输入法去广告 (sogou-ime-ad-removal)

一键移除搜狗输入法（Sogou IME）的广告、游戏推广弹窗、新闻推送与 AI 助手弹窗。
支持 Windows，全部操作可逆。

## 特性

- **注册表开关**：关闭 AI 汪仔/IChat（`ichatenable`）、新闻弹窗（`NewsSwitch`/`NewsNewUser`）、游戏中心等推广开关。
- **进程清理**：结束 SogouCloud、SOGOUSmartAssistant 等广告相关进程。
- **域名屏蔽**：hosts 屏蔽腾讯优量汇广告平台（`rdelivery.qq.com` 系）与搜狗云推送域名，自动备份原 hosts。
- **空壳替换**：用"启动即退出"的空壳程序原位替换两个广告主程序（原程序自动备份为 `.bak`），既阻止广告进程运行，也不会出现"Windows 找不到文件"的错误弹窗。
- **幂等可重复**：脚本可反复运行，搜狗升级导致广告复发时重跑一次即可。

## 快速使用

以管理员身份打开 PowerShell，执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\apply_removal.ps1
```

脚本会自动探查搜狗安装路径并完成全部步骤，最后验证广告进程不再复活、屏蔽域名无法解析。

## 原理

| 广告来源 | 处理方式 |
| --- | --- |
| SogouCloud.exe（云广告配置下载） | 结束进程 + 空壳替换 + hosts 屏蔽其配置域名 |
| SOGOUSmartAssistant.exe（AI 助手/弹窗） | 结束进程 + 空壳替换 |
| 游戏推广（腾讯优量汇下发） | hosts 屏蔽 `rdelivery.qq.com` / `t.rdelivery.qq.com` / `qqdata.ab.qq.com` |
| 新闻/资讯弹窗 | 注册表关闭 `NewsSwitch` / `NewsNewUser` |
| AI 汪仔/IChat | 注册表关闭 `ichatenable` |

## 注意事项

- **副作用**：云联想/云候选、AI 汪仔等联网功能会失效；本地打字、词库不受影响。
- **防火墙规则不可靠**：若安装了火绒等安全软件接管网络防护，或防火墙配置文件被关闭，出站拦截规则不生效，因此本方案以 hosts + 空壳替换为主。
- **hosts 可能被安全软件注释**：火绒等安全软件的 hosts 防护可能把陌生条目注释掉（行首加 `#`），复发时先检查 hosts。
- **搜狗升级会复发**：输入法升级后可能重新生成被替换的 exe，重跑脚本即可。

## 恢复方法

1. 删除空壳 exe（约 3.5 KB）。
2. 把同名 `.bak` 文件改回 `.exe`。
3. 删除 hosts 中 `# === Sogou IME ad block` 到 `# === END ===` 段落。
4. 执行 `ipconfig /flushdns`。

## License

[MIT](LICENSE)
