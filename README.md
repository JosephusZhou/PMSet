# PMSet

一个简洁的 macOS 菜单栏应用，用于管理电源设置（pmset）。支持备份/恢复电源配置，以及快速设置合盖不睡眠。

## 功能

- **备份当前配置**：将当前电源设置保存到备份文件
- **恢复备份配置**：从备份文件恢复电源设置
- **设置合盖不睡眠**：禁用睡眠、休眠等，保持系统运行（需插电使用）
- **设置合盖睡眠**：恢复默认睡眠行为
- 以菜单栏图标形式运行，不占用 Dock 栏空间

## 安装

### 下载

从 [Releases](https://github.com/JosephusZhou/PMSet/releases) 页面下载最新版本的 `PMSet.app`，解压后拖入应用程序文件夹即可。

### 从源码构建

1. 确保已安装 [Swift](https://www.swift.org/download/) 和 Xcode 命令行工具
2. 克隆仓库：
   ```bash
   git clone https://github.com/JosephusZhou/PMSet.git
   cd PMSet
   ```
3. 运行构建脚本：
   ```bash
   ./build-app.sh
   ```
4. 构建完成后，会在当前目录生成 `PMSet.app`

#### 构建参数

| 参数 | 说明 |
|---|---|
| `--version <版本号>` | 设置 App 的版本号（如 `--version 1.2.0`） |
| `--sign <签名 identity>` | 使用指定证书签名（默认 ad-hoc 签名）。详见下方「技术实现」章节 |

示例：
```bash
# 默认 ad-hoc 签名（日常开发使用）
./build-app.sh

# 指定版本号
./build-app.sh --version 1.2.0

# 使用开发者证书签名（启用 SMJobBless 方案时需要）
./build-app.sh --sign "Developer ID Application: Your Name (TEAMID)"
```

### 自动构建

当推送版本标签（如 `v1.0.0`）到 GitHub 时，GitHub Actions 会自动：
1. 构建 universal 二进制，并分别抽取为 arm64 / x86_64 版本
2. 生成对应的 `PMSet-arm64.dmg` 和 `PMSet-x86_64.dmg`
3. 创建 GitHub Release 并上传构建产物

使用方法：
```bash
git tag v1.0.0
git push origin v1.0.0
```

## 使用

1. 启动 `PMSet.app`
2. 菜单栏会出现一个图标（月亮图标）
3. 点击图标即可访问所有功能：
   - 备份当前配置
   - 恢复备份配置
   - 设置合盖不睡眠
   - 设置合盖睡眠（恢复默认）
   - 退出应用

**管理员权限**：修改电源设置需要管理员权限。执行相关操作时，系统会弹出密码输入框，输入当前用户密码后授权执行。多条 `pmset` 命令会合并为一次执行，因此每次操作只需输入一次密码。

> **关于 Touch ID**：AppleScript 方式弹出的授权框仅支持密码输入，不支持 Touch ID。若需要指纹授权，需切换到 SMJobBless 特权 Helper 方案（需代码签名证书，详见下方「技术实现」章节）。

## 技术实现

### 当前方案：AppleScript 授权

当前版本通过 AppleScript（`do shell script ... with administrator privileges`）执行特权命令。系统弹出密码输入框，用户输入密码后以 root 身份执行命令。

- 优点：实现简洁，**无需代码签名证书**，ad-hoc 签名即可
- 缺点：每次执行特权操作都需要输入一次密码；授权框不支持 Touch ID

### 预留方案：SMJobBless 特权 Helper Tool

项目中保留了完整的 SMJobBless 特权 Helper Tool 实现（当前未调用），未来获得固定代码签名证书后可启用，实现「授权一次、永久静默执行」。

相关代码：
- `Sources/PMSet/PrivilegedHelperManager.swift` — App 端安装与 XPC 通信（顶部有启用步骤说明）
- `Sources/PMSetShared/HelperProtocol.swift` — 共享 XPC 协议
- `Sources/PMSetHelper/main.swift` — 特权 Helper（以 root 身份常驻）
- `Info.plist` 中的 `SMPrivilegedExecutables` — 预留配置

**为什么需要证书**：SMJobBless 安装的 Helper 由 launchd 以 root 身份拉起，launchd 拒绝加载 ad-hoc 签名的二进制，必须使用正式的代码签名证书（Apple Development / Developer ID / 自签名证书均可）。

启用步骤详见 `PrivilegedHelperManager.swift` 文件顶部的注释块。

## 项目结构

```
PMSet/
├── Sources/
│   ├── PMSet/                  # 主 App
│   │   ├── main.swift
│   │   ├── AppDelegate.swift       # 菜单栏与菜单
│   │   ├── PMSetManager.swift      # 电源配置管理（AppleScript 授权）
│   │   └── PrivilegedHelperManager.swift  # SMJobBless 预留代码
│   ├── PMSetShared/            # 共享 XPC 协议（预留）
│   │   └── HelperProtocol.swift
│   └── PMSetHelper/            # 特权 Helper Tool（预留）
│       ├── main.swift
│       └── Info.plist
├── Info.plist                  # App 配置
├── Package.swift               # Swift Package 定义
├── build-app.sh                # 构建脚本
└── PMSet.app                   # 构建产物
```

## 安全注意事项

由于本应用未经过 Apple 公证（Notarization），首次在其他 Mac 上运行时可能会出现系统安全警告。以下是解决方法：

### 方法一：右键打开（推荐）

1. 在 Finder 中右键点击 `PMSet.app`
2. 选择「打开」
3. 在弹出的对话框中点击「打开」

### 方法二：系统设置

1. 尝试打开应用（会收到安全警告）
2. 打开「系统设置」>「隐私与安全性」
3. 在「安全性」部分，点击「仍要打开」

### 方法三：移除隔离属性（终端命令）

```bash
xattr -d com.apple.quarantine /Applications/PMSet.app
```

### 为什么会出现警告？

macOS 的 Gatekeeper 会检查应用是否经过 Apple 签名和公证。本应用默认使用本地签名（ad-hoc signing），未经过 Apple 公证，因此会触发安全机制。

**提示**：如果您需要分发给其他用户，建议使用 Apple 开发者证书进行签名和公证，或指导用户使用上述方法之一。

## 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建你的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交你的更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开一个 Pull Request

## 许可证

本项目基于 [MIT 许可证](LICENSE) 开源。
