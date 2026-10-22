---
name: sogou-ad-removal
description: "移除搜狗输入法（Sogou IME）的广告、推广弹窗与推荐内容。适用于用户要求关闭/去除/屏蔽搜狗输入法广告、游戏推广弹窗（如'点击查看'类游戏广告）、新闻推送、皮肤推荐、AI汪仔/智能助手弹窗，或用户抱怨搜狗输入法弹广告影响使用时的场景。方法包括：注册表开关、hosts 域名屏蔽、空壳程序替换广告主程序，全程可逆。仅限 Windows 平台。"
---

# 搜狗输入法去广告

## Overview

搜狗输入法（SogouInput）会通过以下途径推送广告：
- **SogouCloud.exe**：云服务进程，负责下载广告配置与推广资源（弹窗内容来源）。
- **SOGOUSmartAssistant.exe**（Components\IChat\ 下，即"AI汪仔/智能助手"）：独立弹窗与推荐进程。
- **biz_center / game_center / AppBox 组件**：商务弹窗、游戏推广（如"王者天下""传奇5"类游戏广告）、应用推荐。
- **新闻/资讯弹窗**：由注册表 `SogouInput.ppup` 控制。
- 游戏类广告实际由**腾讯优量汇广告平台**下发（`rdelivery.qq.com` 系域名）。

本 Skill 提供一键脚本 + 手工流程，从"开关、进程、域名、程序本体"四个层面切断广告链路，且**可逆**。

## 一键执行（推荐）

直接运行附带脚本，脚本会自动探查安装路径并完成全部步骤：

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>/scripts/apply_removal.ps1"
```

脚本做的事：
1. 从注册表探查搜狗安装目录，定位 `SogouCloud.exe` 与 `SOGOUSmartAssistant.exe`。
2. 关闭注册表广告开关：`ichatenable=0`、`NewsSwitch=0`、`NewsNewUser=0`、`gamecenterenable=0`。
3. 结束广告进程。
4. 备份并追加 hosts 屏蔽（腾讯优量汇 + 搜狗云推送域名）。
5. 用 .NET `csc.exe` 编译一个"启动即退出"的空壳 exe，替换两个广告主程序；原程序改名为 `.bak` 备份（防止 Windows"找不到文件"弹窗）。
6. 等待 20 秒验证广告进程不再复活、屏蔽域名无法解析。

脚本幂等，可重复运行。

## 手工流程（脚本不可用时）

### Step 1 探查

- 安装路径：注册表 `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*` 中 DisplayName 含"搜狗"，取其 `InstallLocation`（常见 `D:\SogouInput` / `E:\SogouInput`）。
- 广告主程序：
  - `SogouCloud.exe`：`<安装目录>\<版本>\SogouCloud.exe`
  - `SOGOUSmartAssistant.exe`：`<安装目录>\Components\IChat\<版本>\SOGOUSmartAssistant.exe`
- 运行中的广告进程：`SogouCloud`、`SOGOUSmartAssistant`、`SGSmartAssistant`、`SGBizLauncher`、`biz_notify`、`biz_render`、`SogouPlayLauncher`、`SGWebRender`。

### Step 2 关闭注册表开关

```powershell
Set-ItemProperty -Path "HKCU:\Software\SogouInput.store.user" -Name "ichatenable" -Value 0 -Type DWord
Set-ItemProperty -Path "HKCU:\Software\SogouInput.ppup" -Name "NewsSwitch" -Value 0 -Type DWord
Set-ItemProperty -Path "HKCU:\Software\SogouInput.ppup" -Name "NewsNewUser" -Value 0 -Type DWord
```

`ichatenable=0` 关闭 AI汪仔/IChat 智能助手；`NewsSwitch/NewsNewUser=0` 关闭新闻弹窗。
（可选 GUI 入口：托盘右键搜狗图标 → 全局设置 → 属性设置 → 高级 → 关闭"输入助手总开关"。）

### Step 3 hosts 屏蔽广告域名

先备份 `C:\Windows\System32\drivers\etc\hosts`，再追加：

```
# === Sogou IME ad block ===
0.0.0.0 rdelivery.qq.com
0.0.0.0 t.rdelivery.qq.com
0.0.0.0 qqdata.ab.qq.com
0.0.0.0 get.sogou.com
0.0.0.0 master-proxy.shouji.sogou.com
# === END ===
```

`rdelivery.qq.com` / `t.rdelivery.qq.com` / `qqdata.ab.qq.com` 是腾讯优量汇广告平台；`get.sogou.com`、`master-proxy.shouji.sogou.com` 是 SogouCloud 的配置/推送通道。写入后执行 `ipconfig /flushdns`。

**不要**屏蔽 `pinyin.sogou.com`、`cloud.pinyin.sogou.com` 等核心输入服务，否则云候选等基本功能会失效。

### Step 4 空壳替换广告主程序（关键步骤）

直接删除/改名 exe 会导致输入法拉起进程时弹"Windows 找不到文件"错误框。正确做法是**原位放一个启动即退出的空壳**，输入法以为启动成功，实际无任何行为。

用系统自带 C# 编译器（`C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`）编译：

```csharp
using System;
namespace SogouAdStub { static class Program { [STAThread] static void Main(string[] args) { Environment.Exit(0); } } }
```

```powershell
& csc.exe /nologo /target:winexe /out:sogou_stub.exe sogou_stub.cs
```

然后对每个目标程序：
1. `Rename-Item <目标.exe> <目标.exe.bak>`（备份原程序）
2. `Copy-Item sogou_stub.exe <目标.exe>`（部署空壳）

替换对象：`SogouCloud.exe`、`SOGOUSmartAssistant.exe`。

### Step 5 验证

- 等待 20 秒后确认广告进程没有复活（`Get-Process SogouCloud, SOGOUSmartAssistant` 为空）。
- 确认空壳就位（文件存在且约 3~4 KB）。
- 确认屏蔽域名无法解析（`Resolve-DnsName rdelivery.qq.com` 失败）。
- 确认没有 "Windows 找不到文件" 错误弹窗。

## 注意事项

- **Windows 防火墙可能无效**：若系统安装了火绒等安全软件接管网络防护，或防火墙配置文件被关闭，`New-NetFirewallRule` 出站拦截规则不会生效。不要依赖防火墙规则，以 hosts + 空壳替换为准。
- **hosts 可能被还原/注释**：火绒等安全软件的 hosts 防护可能把陌生条目注释掉（行首加 `#`）。复发时先检查 hosts 是否被注释。
- **搜狗升级会复发**：输入法升级后可能重新生成被替换的 exe。广告复发时重跑本脚本即可。
- **副作用**：云联想/云候选、AI汪仔（智能助手）等联网功能失效；本地打字、词库不受影响。
- **恢复方法**：删除空壳 exe → 把 `.bak` 改回 `.exe` → 删除 hosts 中 `# === Sogou IME ad block` 到 `# === END ===` 段落 → `ipconfig /flushdns`。
