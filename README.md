# MacTools

> macOS 原生工具集 | 采用 Vibe Coding 开发

![Version](https://img.shields.io/badge/version-1.2.0-blue)
![Platform](https://img.shields.io/badge/platform-macOS%2014+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple?logo=swift)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 简介

MacTools 是一款使用 SwiftUI 原生开发的 macOS 工具集应用，专为开发者日常工作流打造。当前包含 **WPS JS 插件构建部署**、**应用隔离属性修复** 和 **环境信息检测** 三大核心功能。

## 功能特性

### 插件构建与部署

一键构建 WPS Office JS 插件离线包并自动部署到指定目录。

- 自动检测 `package.json` 验证项目合法性
- 支持拖拽导入项目或文件选择器
- 实时构建日志输出，支持导出
- 自动备份已部署插件，失败时可回滚
- 支持 `.7z` 和 `.zip` 格式解压
- 自动注册到 WPS 插件列表

### 修复应用

去除从网络下载的应用程序的 macOS 隔离属性，解决 "已损坏，无法打开" 问题。

- 显示 SIP（系统完整性保护）状态
- 显示 Gatekeeper 状态
- 支持拖拽 `.app` 文件或文件选择器
- 显示应用图标、名称和隔离状态
- 使用 `xattr` 命令安全移除属性

### 环境信息

一键检测并展示开发环境信息，快速排查环境配置问题。

- 检测 Node.js、NPM、Homebrew 版本
- 列出 NPM 全局包、Homebrew 已装公式/依赖/Cask
- 支持跨列表全局搜索
- 实时刷新环境状态

## 快速开始

### 环境要求

| 依赖 | 必需 | 说明 |
|------|------|------|
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

生成的 DMG 文件位于 `./dist/MacTools-1.2.0.dmg`

## 技术栈

| 类别 | 技术 |
|------|------|
| 语言 | Swift 5.9 |
| UI 框架 | SwiftUI + AppKit |
| 并发模型 | Swift Concurrency (async/await) |
| 构建系统 | Xcode / xcodebuild |
| 打包工具 | create-dmg |

> 本项目零第三方依赖，完全基于 Apple 系统框架构建。

## 项目结构

```
MacTools/
├── MacToolsApp.swift          # 应用入口
├── ContentView.swift          # 主界面导航
├── Views/
│   ├── Welcome.swift          # 欢迎页
│   ├── PluginLoad.swift       # 插件构建部署
│   ├── FixMacApp.swift        # 应用修复
│   └── EnvInfo.swift          # 环境信息
└── Assets.xcassets/           # 图标资源
```

## 许可证

本项目基于 [MIT License](LICENSE) 开源。
