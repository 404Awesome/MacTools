<div align="center">

# MacTools

### macOS 原生工具集

让每一次点击，都恰到好处

![Version](https://img.shields.io/badge/version-1.2.0-blue?style=flat-square)
![Platform](https://img.shields.io/badge/platform-macOS%2014+-black?style=flat-square&logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
![PRs](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)

---

</div>

## 简介

MacTools 是一款使用 **SwiftUI** 原生开发的 macOS 工具集应用，专为开发者日常工作流打造。采用 **Vibe Coding** 开发理念，零第三方依赖，完全基于 Apple 系统框架构建。

## 功能特性

<table>
<tr>
<td width="50%">

### 插件构建与部署

一键构建 WPS Office JS 插件离线包并自动部署到指定目录。

- 验证项目合法性（检测 `package.json`）
- 支持拖拽导入或文件选择器
- 实时构建日志输出（支持导出）
- 自动备份与失败回滚
- 支持 `.7z` / `.zip` 格式解压
- 自动注册到 WPS 插件列表

</td>
<td width="50%">

### 修复应用

去除从网络下载的应用程序的 macOS 隔离属性。

- 显示 SIP（系统完整性保护）状态
- 显示 Gatekeeper 安全状态
- 支持拖拽 `.app` 文件操作
- 实时显示应用图标与隔离状态
- 使用 `xattr` 命令安全移除属性
- 解决 "已损坏，无法打开" 问题

</td>
</tr>
<tr>
<td width="50%">

### 环境信息

一键检测并展示开发环境信息，快速排查配置问题。

- 检测 Node.js、NPM、Homebrew 版本
- 列出 NPM 全局包安装情况
- 列出 Homebrew 公式/依赖/Cask
- 支持跨列表全局搜索
- 实时刷新环境状态

</td>
<td width="50%">

### 禁用键盘

临时禁用键盘功能，方便清洁键盘。

- 使用 CGEvent 拦截键盘事件
- 拦截普通按键、修饰键、媒体键
- 需要辅助功能权限授权
- 退出应用自动恢复键盘
- 安全可靠的事件拦截机制

</td>
</tr>
</table>

## 快速开始

### 环境要求

| 依赖 | 必需 | 说明 |
|:-----|:----:|:-----|
| macOS 14+ | ✅ | Sonoma 或更高版本 |
| Xcode | ✅ | 用于构建项目 |
| [create-dmg](https://github.com/create-dmg/create-dmg) | ❌ | 打包 DMG 安装包 |
| [wpsjs CLI](https://www.npmjs.com/package/@aspect-build/wpsjs) | ❌ | 插件构建功能需要 |
| [p7zip](https://p7zip.sourceforge.net/) | ❌ | 解压 `.7z` 文件 |

### 构建运行

**打开项目：**

```bash
open MacTools.xcodeproj
```

**命令行构建 (Release)：**

```bash
xcodebuild -scheme MacTools -configuration Release \
  -derivedDataPath ./build -quiet
```

**打包 DMG 安装包：**

```bash
# 安装 create-dmg (如未安装)
brew install create-dmg

# 执行打包脚本
./build-dmg.sh
```

生成的 DMG 文件位于 `./dist/MacTools-1.3.0.dmg`

## 技术栈

<table>
<tr>
<td><b>语言</b></td>
<td>Swift 5.9</td>
</tr>
<tr>
<td><b>UI 框架</b></td>
<td>SwiftUI + AppKit</td>
</tr>
<tr>
<td><b>并发模型</b></td>
<td>Swift Concurrency (async/await)</td>
</tr>
<tr>
<td><b>构建系统</b></td>
<td>Xcode / xcodebuild</td>
</tr>
<tr>
<td><b>打包工具</b></td>
<td>create-dmg</td>
</tr>
<tr>
<td><b>热重载</b></td>
<td>InjectionIII / InjectionNext (可选)</td>
</tr>
</table>

> 💡 本项目零第三方依赖，完全基于 Apple 系统框架构建。

## 项目结构

```
MacTools/
├── MacToolsApp.swift              # 应用入口
├── ContentView.swift              # 主界面导航
├── Views/
│   ├── Welcome.swift              # 欢迎页（动画效果）
│   ├── PluginLoad.swift           # 插件构建部署
│   ├── FixMacApp.swift            # 应用修复
│   ├── EnvInfo.swift              # 环境信息
│   └── DisableKeyboard.swift      # 禁用键盘
└── Assets.xcassets/               # 图标资源
```

## 快捷键

| 快捷键 | 功能 |
|:-------|:-----|
| `⌘ + S` | 切换侧边栏显示/隐藏 |

## 字体

项目优先使用以下等宽字体：

1. **JetBrains Mono**（推荐）
2. **Consolas**
3. 系统默认等宽字体

## 许可证

本项目基于 [MIT License](LICENSE) 开源。

---

<div align="center">

**Made with ❤️ using Vibe Coding**

</div>
