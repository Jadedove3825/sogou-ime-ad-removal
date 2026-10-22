<#
.SYNOPSIS
  搜狗输入法去广告一键脚本：注册表开关 + 杀进程 + hosts 屏蔽 + 空壳替换 + 验证

.DESCRIPTION
  自动探查搜狗输入法安装路径，依次执行：
  1) 关闭注册表广告开关（AI汪仔/IChat、新闻弹窗、游戏中心）
  2) 结束广告相关进程
  3) hosts 屏蔽广告下发域名（腾讯优量汇 rdelivery.qq.com 系 + 搜狗云推送），自动备份原 hosts
  4) 编译一个"启动即退出"的空壳程序，替换 SogouCloud.exe / SOGOUSmartAssistant.exe，
     原程序改名为 .bak 备份（防止"找不到文件"报错，同时进程无法再拉起）
  5) 验证：广告进程不再复活、空壳就位、屏蔽域名无法解析

  本脚本可重复运行（幂等）：hosts 不会重复追加，已替换过的 exe 不会重复改名。

.NOTES
  影响范围：云联想/云候选、AI汪仔（智能助手）等联网功能失效；本地打字不受影响。
  恢复方法：删除空壳 exe，把同名 .bak 改回 .exe，删除 hosts 中 "# === Sogou IME ad block" 段落。
  已知风险：搜狗输入法升级后可能重新生成 SogouCloud.exe / SOGOUSmartAssistant.exe，
  广告可能复发，重跑本脚本即可。
#>

$ErrorActionPreference = "Stop"

function Write-Step { param([string]$Msg) Write-Host "[sogou-ad-removal] $Msg" -ForegroundColor Cyan }

# ---------- 0. 探查安装路径 ----------
Write-Step "探查搜狗输入法安装路径"
$installDir = $null
$uninstallKeys = @(
  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($k in $uninstallKeys) {
  $items = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*搜狗*" -or $_.DisplayName -like "*Sogou*" }
  foreach ($it in $items) {
    if ($it.InstallLocation -and (Test-Path -LiteralPath $it.InstallLocation)) {
      $installDir = $it.InstallLocation; break
    }
  }
  if ($installDir) { break }
}
if (-not $installDir) {
  foreach ($p in @("D:\SogouInput","E:\SogouInput","C:\Program Files (x86)\SogouInput","C:\Program Files\SogouInput")) {
    if (Test-Path -LiteralPath $p) { $installDir = $p; break }
  }
}
if (-not $installDir) { Write-Error "未找到搜狗输入法安装目录，请手动确认后重试"; exit 1 }
Write-Step "安装目录: $installDir"

# 定位两个广告主程序（兼容版本子目录结构）
$cloudExe = $null
$ichatExe = $null
Get-ChildItem -LiteralPath $installDir -Recurse -Filter "SogouCloud.exe" -ErrorAction SilentlyContinue | ForEach-Object { $cloudExe = $_.FullName }
Get-ChildItem -LiteralPath $installDir -Recurse -Filter "SOGOUSmartAssistant.exe" -ErrorAction SilentlyContinue | ForEach-Object { $ichatExe = $_.FullName }
Write-Step "SogouCloud.exe -> $cloudExe"
Write-Step "SOGOUSmartAssistant.exe -> $ichatExe"

# ---------- 1. 注册表广告开关 ----------
Write-Step "关闭注册表广告开关"
$storeUser = "HKCU:\Software\SogouInput.store.user"
$ppup = "HKCU:\Software\SogouInput.ppup"
if (Test-Path $storeUser) {
  Set-ItemProperty -Path $storeUser -Name "ichatenable" -Value 0 -Type DWord -ErrorAction SilentlyContinue
  Set-ItemProperty -Path $storeUser -Name "gamecenterenable" -Value 0 -Type DWord -ErrorAction SilentlyContinue
  Set-ItemProperty -Path $storeUser -Name "wizardpromotion" -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
if (Test-Path $ppup) {
  Set-ItemProperty -Path $ppup -Name "NewsSwitch" -Value 0 -Type DWord -ErrorAction SilentlyContinue
  Set-ItemProperty -Path $ppup -Name "NewsNewUser" -Value 0 -Type DWord -ErrorAction SilentlyContinue
}
Write-Step "注册表开关已关闭（ichatenable=0, NewsSwitch=0, NewsNewUser=0, gamecenterenable=0）"

# ---------- 2. 结束广告进程 ----------
Write-Step "结束广告进程"
$adNames = "SogouCloud","SOGOUSmartAssistant","SGSmartAssistant","SGBizLauncher","biz_notify","biz_render","biz_helper","biz_aurfx","SogouPlayLauncher","SGWebRender"
foreach ($n in $adNames) {
  Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# ---------- 3. hosts 屏蔽（幂等，先备份） ----------
Write-Step "配置 hosts 屏蔽广告域名"
$hosts = "C:\Windows\System32\drivers\etc\hosts"
$markerStart = "# === Sogou IME ad block"
$markerEnd = "# === END ==="
$blockLines = @(
  "# === Sogou IME ad block ===",
  "0.0.0.0 rdelivery.qq.com",
  "0.0.0.0 t.rdelivery.qq.com",
  "0.0.0.0 qqdata.ab.qq.com",
  "0.0.0.0 get.sogou.com",
  "0.0.0.0 master-proxy.shouji.sogou.com",
  "# === END ==="
)
if (Test-Path -LiteralPath $hosts) {
  $fs = [System.IO.File]::Open($hosts, 'Open', 'Read', 'ReadWrite')
  $sr = New-Object System.IO.StreamReader($fs)
  $hostsText = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
  if ($hostsText -match [regex]::Escape($markerStart)) {
    Write-Step "hosts 已包含屏蔽条目，跳过追加（幂等）"
  } else {
    $bak = Join-Path (Split-Path -Parent $hosts) ("hosts.sogou_backup_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
    Copy-Item -LiteralPath $hosts -Destination $bak -Force
    Write-Step "hosts 备份: $bak"
    $newText = $hostsText.TrimEnd("`r","`n") + "`r`n`r`n" + ($blockLines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($hosts, $newText, [System.Text.Encoding]::ASCII)
    Write-Step "hosts 屏蔽条目已追加"
  }
} else {
  [System.IO.File]::WriteAllText($hosts, (($blockLines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)
  Write-Step "hosts 不存在，已新建并写入屏蔽条目"
}

# ---------- 4. 编译并部署空壳 ----------
Write-Step "编译空壳程序（启动即退出）"
$csc = Get-ChildItem "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $csc) { $csc = Get-ChildItem "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 }
if (-not $csc) { Write-Error "未找到 .NET Framework 编译器 csc.exe"; exit 1 }
$workDir = Join-Path $env:TEMP "sogou_stub_build"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$srcFile = Join-Path $workDir "sogou_stub.cs"
$stubExe = Join-Path $workDir "sogou_stub.exe"
$srcCode = @'
using System;
namespace SogouAdStub { static class Program { [STAThread] static void Main(string[] args) { Environment.Exit(0); } } }
'@
[System.IO.File]::WriteAllText($srcFile, $srcCode, [System.Text.Encoding]::UTF8)
& $csc.FullName /nologo /target:winexe /out:$stubExe $srcFile | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stubExe)) { Write-Error "空壳编译失败"; exit 1 }
Write-Step "空壳编译完成: $stubExe"

function Deploy-Stub {
  param([string]$Target)
  if (-not $Target) { Write-Step "目标路径为空，跳过"; return }
  $bak = "$Target.bak"
  if (Test-Path -LiteralPath $bak) {
    Write-Step "已存在备份 $bak，跳过替换（幂等）"
    return
  }
  if (Test-Path -LiteralPath $Target) {
    Rename-Item -LiteralPath $Target -NewName (Split-Path -Leaf $bak) -Force
    Write-Step "原程序改名备份: $bak"
  }
  Copy-Item -LiteralPath $stubExe -Destination $Target -Force
  Write-Step "空壳已部署: $Target"
}
Deploy-Stub $cloudExe
Deploy-Stub $ichatExe

# ---------- 5. 验证 ----------
Write-Step "验证中（等待 20 秒观察进程是否复活）"
Start-Sleep -Seconds 20
$left = Get-Process -Name $adNames -ErrorAction SilentlyContinue
if ($left) {
  Write-Warning "仍有广告进程在运行: $($left.Name -join ', ')"
} else {
  Write-Step "广告进程未复活，验证通过"
}
Write-Step "=== 屏蔽域名解析检查 ==="
foreach ($d in @("rdelivery.qq.com","t.rdelivery.qq.com","qqdata.ab.qq.com","get.sogou.com","master-proxy.shouji.sogou.com")) {
  try {
    $ips = [System.Net.Dns]::GetHostAddresses($d) | ForEach-Object { $_.IPAddressToString }
    Write-Warning "$d 仍可解析: $($ips -join ',')"
  } catch {
    Write-Step "$d 已被屏蔽"
  }
}
Write-Step "=== 完成 ==="
