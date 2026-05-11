# Windows 平台层

> IM 客户端在 Windows 端的原生宿主工程，承载 Flutter 引擎与「壹信」应用在桌面上的运行，提供窗口、消息循环与 Flutter 嵌入层。

---

## 1. 模块简介 (Overview)

`windows` 在整个 IM 系统中的定位是 **Windows 平台宿主**，与项目根目录下的 Flutter 代码（`lib/`、`pubspec.yaml`）共同构成完整的 Windows 桌面客户端。主要作用包括：

- **Flutter 引擎承载**：通过 CMake 与 Win32 API 将 Flutter 应用构建为 Windows 可执行程序（`gao_ran_im.exe`），提供 Flutter 运行环境。
- **窗口与入口**：`main.cpp` 中创建标题为「壹信」的 Flutter 窗口（默认 1280×720），初始化 COM、Dart 工程与消息循环。
- **构建与安装**：CMake 管理 C++ 编译、Flutter 库与插件链接，并将运行时与资源安装到可执行文件目录，便于直接运行或集成到安装包。

业务与 UI 逻辑在 Flutter 侧（项目根目录）；本目录仅做原生层窗口与构建配置，一般无需在此编写业务代码。桌面端特有能力（如窗口管理、托盘、快捷键）由 Flutter 插件（如 window_manager、tray_manager、hotkey_manager）在 `pubspec.yaml` 中声明。

---

## 2. 技术栈 (Tech Stack)

| 类别           | 技术 |
|----------------|------|
| 开发语言       | C++（Win32） |
| 构建系统       | CMake 3.14+ |
| 编译器         | MSVC（Visual Studio 或 Build Tools），C++17 |
| Flutter 集成   | Flutter 托管目录 `flutter/`（含 generated_plugin_registrant、generated_plugins.cmake） |
| 可执行文件名   | gao_ran_im（在根 CMakeLists.txt 中 BINARY_NAME） |

与 IM 相关的原生侧要点：

- **窗口**：`runner/main.cpp` 中 `FlutterWindow` 创建窗口标题「壹信」、默认尺寸；`runner/flutter_window.cpp`、`win32_window.cpp` 实现 Flutter 视图与 Win32 窗口逻辑。
- **依赖**：链接 `flutter`、`flutter_wrapper_app`、`dwmapi.lib`；插件通过 `flutter/generated_plugins.cmake` 自动纳入构建。
- **资源与 AOT**：CMake 将 `flutter_assets`、ICU 数据、AOT 库（Profile/Release）、插件原生库安装到可执行文件同目录，保证单目录运行。

Flutter 侧 IM 能力（WebSocket、Dio、Isar、窗口/托盘等）由根目录 `pubspec.yaml` 管理；本目录不直接依赖这些库的源码。

---

## 3. 环境准备 (Prerequisites)

- **Flutter SDK**：满足项目根目录 `pubspec.yaml` 要求（如 `sdk: '>=3.2.0 <4.0.0'`），且已配置 `flutter doctor` 通过；Windows 桌面支持已启用。
- **Windows 10/11**：开发与运行均在 Windows 上进行。
- **Visual Studio 或 Build Tools**：带「使用 C++ 的桌面开发」工作负载，提供 MSVC 与 Windows SDK；CMake 需能找到该环境（通常通过「开发者命令提示」或 VS 自带终端）。
- **CMake**：3.14 及以上，通常随 Flutter 或 VS 已具备。

无需单独数据库或后端服务；Windows 端仅作为客户端运行。

---

## 4. 快速上手 (Getting Started)

### 4.1 建议在项目根目录操作

Windows 工程依赖 Flutter 源码与生成脚本，因此**推荐在项目根目录**执行 Flutter 命令：

```bash
# 在项目根目录（PowerShell 或 CMD）
flutter pub get
flutter run -d windows
```

或先列出设备再运行：

```bash
flutter devices
flutter run -d windows
```

### 4.2 构建 Release（项目根目录）

```bash
flutter build windows
```

产出在 `build/windows/x64/runner/`（或对应架构目录），可直接运行 `gao_ran_im.exe` 或整包发布。

### 4.3 使用 Visual Studio 打开（可选）

在项目根目录执行 `flutter pub get` 后，可用 VS 打开 Windows 工程（需先执行一次 `flutter build windows` 生成 VS 解决方案，或通过「打开本地文件夹」选择 `windows` 目录由 CMake 配置）。构建与运行需依赖 Flutter 生成的 `flutter/` 与 `build/` 内容，因此仍建议以 `flutter run -d windows` 与 `flutter build windows` 为主。

### 4.4 环境变量与配置文件

| 文件/配置           | 说明 |
|---------------------|------|
| **windows/CMakeLists.txt** | 顶层 CMake：项目名 gao_ran_im、BINARY_NAME、Flutter 目录、runner 子目录、插件包含、安装规则（可执行文件、flutter_assets、AOT、插件库）。 |
| **windows/runner/CMakeLists.txt** | 定义可执行文件源（main.cpp、flutter_window、win32_window、utils、generated_plugin_registrant）、链接 Flutter 与 dwmapi。 |
| **windows/runner/main.cpp** | 窗口标题「壹信」、默认尺寸 1280×720；可在此修改窗口名或初始大小。 |

无 `.env` 类环境变量；与后端或功能开关相关的配置在 Flutter 侧。

---

## 5. 核心目录结构 (Directory Structure)

```
windows/
├── runner/
│   ├── main.cpp              # 入口：COM 初始化、Flutter 工程、创建「壹信」窗口、消息循环
│   ├── flutter_window.cpp    # Flutter 窗口实现
│   ├── flutter_window.h
│   ├── win32_window.cpp      # Win32 窗口封装
│   ├── win32_window.h
│   ├── utils.cpp             # 命令行等工具
│   ├── utils.h
│   ├── resource.h
│   ├── Runner.rc
│   ├── runner.exe.manifest
│   └── CMakeLists.txt        # 可执行文件与链接配置
├── flutter/
│   ├── generated_plugin_registrant.cc
│   ├── generated_plugin_registrant.h
│   └── generated_plugins.cmake   # Flutter 生成，勿手改
├── CMakeLists.txt            # 顶层：BINARY_NAME、Flutter、runner、插件、安装
└── README.md
```

---

## 6. IM 核心业务引导 (Key Concepts)

| 关注点             | 位置说明 |
|--------------------|----------|
| **应用入口与窗口** | `runner/main.cpp`：创建标题「壹信」、默认 1280×720 的 Flutter 窗口；`runner/flutter_window.cpp`、`win32_window.cpp` 实现视图与 Win32 逻辑。 |
| **Flutter 集成**   | 根目录 `CMakeLists.txt` 中 `add_subdirectory(flutter)`、`include(flutter/generated_plugins.cmake)`；runner 链接 `flutter`、`flutter_wrapper_app`。 |
| **可执行文件与安装** | BINARY_NAME 为 gao_ran_im；CMake 将 exe、flutter_assets、AOT、插件库安装到同一目录，便于打包分发。 |
| **实际 IM 逻辑**   | 消息、连接、存储、UI、窗口管理/托盘等均在项目根目录的 Flutter 代码（`lib/`）及 `pubspec.yaml` 依赖中；本目录仅提供 Windows 运行环境。 |

---

## 7. 打包与发布 (Build & Deploy)

### 7.1 推荐方式（项目根目录）

```bash
# Debug
flutter run -d windows

# Release
flutter build windows
```

Release 产出在 `build/windows/x64/runner/`（或当前架构），可将整个 `runner` 目录打包为 zip 或放入安装包（如 Inno Setup、MSIX）进行分发。

### 7.2 生成一键安装包（推荐）

本项目已提供 Inno Setup 打包脚本，可直接生成 `Setup.exe`：

```powershell
.\scripts\build_windows_installer.ps1
```

前提：

- 已安装 `Inno Setup 6`
- 若 `iscc` 不在 PATH，可手动指定：

```powershell
.\scripts\build_windows_installer.ps1 -InnoSetupCompiler "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
```

默认输出目录：

- `dist/windows-installer/`

说明：

- 脚本会先执行 `flutter pub get`
- 默认自动构建 `Windows Release`
- 然后将 `build/windows/x64/runner/Release` 封装成可一键安装的 `Setup.exe`
- 已内置 Firebase Windows SDK 下载/解压兜底，避免 `firebase_core` 在 Windows 构建时被官方下载限流卡住

### 7.3 注意事项

- **架构**：默认 x64；若需 ARM64，使用 `flutter build windows` 时指定目标架构（取决于 Flutter 对 Windows ARM 的支持情况）。
- **依赖**：运行目标机器需安装 Visual C++ Redistributable（若 Flutter 运行时依赖）；通常与安装包一并提供或提示用户安装。

---

## 附录：常用命令速查

| 场景           | 建议执行 |
|----------------|----------|
| 安装 Flutter 依赖 | 项目根目录：`flutter pub get` |
| 运行           | 项目根目录：`flutter run -d windows` |
| 构建 Release   | `flutter build windows` |
| 清理           | `flutter clean` |

---

如有问题，可优先查阅本 README、项目根目录的 Flutter 文档与 `pubspec.yaml`，以及 `windows/CMakeLists.txt`、`runner/main.cpp` 中的注释。
