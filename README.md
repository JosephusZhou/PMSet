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

### 自动构建

当推送版本标签（如 `v1.0.0`）到 GitHub 时，GitHub Actions 会自动：
1. 在 macOS Intel 和 Apple Silicon 环境分别构建
2. 生成对应的 `PMSet-x86_64.zip` 和 `PMSet-arm64.zip`
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

**注意**：修改电源设置需要管理员权限，系统会弹出密码输入框。

## 安全注意事项

由于本应用未经过 Apple 公证（Notarization），首次在其他 Mac 上运行时可能会出现系统安全警告。以下是解决方法：

### 方法一：右键打开（推荐）

1. 在 Finder 中右键点击 `PMSet.app`
2. 选择「打开」
3. 在弹出的对话框中点击「打开」

### 方法二：系统偏好设置

1. 尝试打开应用（会收到安全警告）
2. 打开「系统偏好设置」>「安全性与隐私」>「通用」
3. 在「允许从以下位置打开的应用」部分，点击「仍要打开」

### 方法三：移除隔离属性（终端命令）

```bash
xattr -d com.apple.quarantine /Applications/PMSet.app
```

### 为什么会出现警告？

macOS 的 Gatekeeper 会检查应用是否经过 Apple 签名和公证。本应用使用本地签名（ad-hoc signing），未经过 Apple 公证，因此会触发安全机制。

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
