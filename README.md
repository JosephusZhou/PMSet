# PMSet

一个简洁的 macOS 菜单栏应用，用于管理电源设置（pmset）。把 9 个电源键组合成具名「方案」，在菜单栏一键切换。

## 功能

- **默认睡眠方案**：调用 `pmset restoredefaults` 恢复系统出厂电源设置
- **用户自定义方案**：自由组合 9 个电源键并保存为具名方案，菜单一键切换（最多 10 个）
- **自定义配置窗口**：按四层分组展示 9 个键的单位、取值、影响与风险提示，草稿式编辑
- **差异化写入**：切换方案时只下发与当前实际值不同的键，执行后回读校验
- **权限自动回退**：优先使用特权 Helper 静默执行，不可用时自动回退管理员密码方式
- 以菜单栏图标形式运行，不占用 Dock 栏空间；图标反映当前是否禁止睡眠

## 菜单结构

点击菜单栏图标后，菜单固定按以下顺序展示：

| 菜单项 | 说明 |
|---|---|
| 自定义配置 | 打开配置窗口（单例，已打开时前置） |
| —— | 分割线 |
| 默认睡眠方案 | 内置方案，不可重命名、不可删除 |
| 自定义方案 1、2 | 按用户顺序展示前两个自定义方案 |
| 更多 ▸ | 自定义方案 ≥ 3 个时出现；二级菜单以固定高度、可滚动列表展示全部自定义方案 |
| —— | 分割线 |
| 关于 | 打开项目主页 |
| 当前版本：vX.Y.Z | 仅展示版本号，点击无响应 |
| —— | 分割线 |
| 退出 App | 退出应用 |

- 自定义方案为 0、1、2 个时不出现「更多」项，方案按顺序直接展示。
- 当前生效的方案显示勾选，其余不显示；勾选与图标均以回读的系统实际值为准，菜单每次展开前刷新。

## 方案

方案 = 9 个 pmset 键的一组取值，统一按 `-a` 全局下发，不区分电源适配器与电池。

- **切换方案**：先读取当前实际值，只下发有差异的键；执行后逐键回读校验，失败时提示具体键名，不改动其余键。当前值已与方案一致时不下发任何命令。
- **默认睡眠方案**：调用 `/usr/bin/pmset restoredefaults` 恢复系统出厂设置，成功后回读当前值作为该方案的快照。
- **本机不支持的键**：写入前做能力探测，本机不存在的键（例如部分机型的 `autopoweroff`）自动跳过并记录。
- **关闭「禁止睡眠」**：当方案把 `disablesleep` 从 1 改为 0 且当前处于合盖状态时，提示「合盖状态下改回允许睡眠不会立即入睡」，并提供「立即睡眠」选项（`pmset sleepnow`）。
- **持久化**：方案保存在 `~/Library/Application Support/PMSet/presets.json`，包含 `schemaVersion`、`activePresetID` 与方案列表，重启 App 后保持。
- **数量上限**：最多 10 个自定义方案，达到上限后「保存为方案…」置灰并说明原因。

### 9 个键

键按四层分组；完整释义、开启/关闭影响与 ⚠️ 提示见「自定义配置」窗口。

| 层 | 键 | 单位 / 取值 | 0 的含义 |
|---|---|---|---|
| 抑制层 | `disablesleep` | 0 / 1 开关，1 表示禁止 | 允许正常睡眠 |
| 抑制层 | `sleep` | 分钟 | 系统永不因空闲而睡眠（合盖仍会睡眠） |
| 显示层 | `displaysleep` | 分钟 | 屏幕永不休眠 |
| 显示层 | `disksleep` | 分钟 | 磁盘永不休眠 |
| 深度层 | `hibernatemode` | 仅 0 / 3 / 25 | 不写休眠镜像，纯内存睡眠（断电丢失内存内容） |
| 深度层 | `standby` | 0 / 1 开关 | 不进入深度待机 |
| 深度层 | `autopoweroff` | 0 / 1 开关（部分机型不存在） | 不进入自动断电 |
| 网络层 | `tcpkeepalive` | 0 / 1 开关 | 睡眠中不再周期性唤醒维持 TCP 连接 |
| 网络层 | `womp` | 0 / 1 开关 | 关闭网络唤醒 |

## 自定义配置

「自定义配置」打开单例窗口，采用「草稿 → 保存并应用」流程：

- 按 **抑制层 / 显示层 / 深度层 / 网络层** 四组展示 9 个键，每个键显示单位与取值域、0 的含义、中文释义、开启与关闭分别造成的影响；高风险键附 ⚠️ 提示。
- 本机不存在的键置灰，并标注「本机不支持该设置」。
- 编辑只改内存草稿，不写系统、不落盘；点「保存并应用」才一次性下发全部差异，成功后回读系统值作为新基线；点「取消」或关闭窗口直接丢弃草稿。
- 窗口内实时提示危险组合：`hibernatemode = 0` 但 `standby ≠ 0` 时提示「仍可能写入休眠镜像，需三项同时为 0」；`disablesleep = 1` 时提示深度层与网络层的设置当前不会生效，若已合盖还会提示注意散热。
- **保存为方案…**：用当前草稿创建具名方案；名称为空或与已有方案重名会被拒绝，并保留输入内容以便修改。
- **管理方案**：窗口底部列出已保存的自定义方案，支持重命名、复制、删除；复制自动生成「XXX 副本」名称。删除当前生效方案后回落到默认睡眠方案，删除操作不会修改系统当前配置。

## 安装

### 下载

从 [Releases](https://github.com/JosephusZhou/PMSet/releases) 页面下载最新版本的 `PMSet.app`，解压后拖入应用程序文件夹即可。

Release 产物是 **ad-hoc 签名**：功能完整，但每次修改电源配置都会要求输入管理员密码。想改成「授权一次、之后免密」，需要用自己的证书重签（见下方「让下载版免密」）。

### 让下载版免密（可选）

准备一个 Apple 签发的开发证书（免费 Apple ID 的「个人团队」证书即可，需先在 Xcode 登录一次并让 Xcode 生成证书）：

```bash
codesign --force --deep --sign "Apple Development: 你的名字 (TEAMID)" /Applications/PMSet.app
```

- `--deep` 会连同 App 内嵌的 Helper（`Contents/Library/LaunchServices/local.pmset.helper`）一起重签。**必须一并重签 Helper**，只签外层 App 时 Helper 仍然装不上。
- 首次改配置时系统会弹出一次「PMSet 想要添加辅助工具」的授权框，之后不再要求密码。
- 重签不会绕过 Gatekeeper：应用没有公证，下载来的包仍会带隔离属性，需右键「打开」或执行 `xattr -d com.apple.quarantine`（见「安全注意事项」）。
- 自签名证书（自己造的根证书）未做验证，SMJobBless 对自签名证书有已知的拒绝记录，不推荐作为免密方案。

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
| `--sign [签名 identity]` | 使用指定证书签名（默认 ad-hoc 签名）。**不传值时进入交互式选择**：列出本机所有代码签名证书，标明每个证书属于「个人」还是「团队」，用 ↑/↓ 或直接输序号选择，回车确认。详见下方「权限」与「技术实现」章节 |

示例：
```bash
# 默认 ad-hoc 签名（日常开发使用；Helper 不可用，会自动回退密码方式）
./build-app.sh

# 指定版本号
./build-app.sh --version 1.2.0

# 交互式选择签名证书（列表标注个人 / 团队，↑/↓ 或序号选择）
./build-app.sh --sign

# 使用开发者证书签名（Helper 免密静默执行必需）
./build-app.sh --sign "Developer ID Application: Your Name (TEAMID)"
```

> ad-hoc 签名时构建脚本会在签名前后输出警告：SMJobBless 的 Helper 无法被 launchd 加载，App 会自动回退到「每次输入管理员密码」的方式。该警告不影响构建产物。

### 自动构建

当推送版本标签（如 `v1.0.0`）到 GitHub 时，GitHub Actions 会自动：
1. 构建 universal 二进制（含 App 与内嵌 Helper），并分别抽取为 arm64 / x86_64 版本
2. 生成对应的 `PMSet-arm64.dmg` 和 `PMSet-x86_64.dmg`
3. 创建 GitHub Release 并上传构建产物

> 自动构建使用 ad-hoc 签名，因此下载版默认走密码方式；需要免密的用户按「让下载版免密」一节自行重签。

使用方法：
```bash
git tag v1.0.0
git push origin v1.0.0
```

## 使用

1. 启动 `PMSet.app`，菜单栏会出现图标（禁止睡眠时为闪电图标，否则为月亮图标）
2. 点击图标：
   - 选择「默认睡眠方案」恢复系统默认电源设置
   - 或选择已保存的自定义方案直接切换
   - 选择「自定义配置」调整 9 个键、保存新方案或管理已有方案
3. 菜单每次展开前都会重新读取系统实际值，勾选状态与图标始终与实际一致

> **备份 / 恢复**：相关实现代码仍保留，备份文件写入 `~/Library/Application Support/PMSet/pmset-backup.txt`；但当前版本菜单未暴露「备份当前配置」「恢复备份配置」入口。

## 权限

### 特权 Helper 优先

所有需要特权的电源写入都优先交给 SMJobBless 特权 Helper：

- **安装是懒触发的**：启动 App、打开菜单、打开自定义配置窗口都不会安装 Helper；只有第一次真正要写系统配置时才安装。
- 如果目标方案与系统当前值完全一致（没有差异需要下发），本次操作不会发起任何特权调用，因此也不会触发安装。
- 首次执行特权写入时弹出一次系统授权框安装 Helper（`local.pmset.helper`），安装成功后本次及后续操作静默执行，不再弹密码框。
- App 内置 Helper 版本（`1.1.0`）高于已安装版本时，下一次特权操作前会自动重装一次（一次授权）。
- Helper 安装于 `/Library/PrivilegedHelperTools/local.pmset.helper`，由 launchd 以 root 身份拉起。

### 自动回退

Helper 未安装、安装被拒绝、版本不匹配或 XPC 调用失败时，会自动回退到 AppleScript 密码方式（`do shell script ... with administrator privileges`）完成同一次写入，结果一致，且一次操作只提示一次错误。回退路径下多条 `pmset` 命令会合并为一次执行，因此每次操作只需输入一次密码。

### ad-hoc 签名下的 Helper

launchd 拒绝加载 ad-hoc 签名的 Helper 二进制，因此用默认的 `./build-app.sh` 构建出的 App 中 Helper 无法安装，这属于预期行为：功能不受影响，只是每次写入都会走管理员密码方式。需要免密静默执行时，请用自己的 Apple 签发证书构建（免费个人团队证书即可）：

```bash
./build-app.sh --sign            # 交互式列出本机证书，标注个人 / 团队
./build-app.sh --sign "Apple Development: Your Name (TEAMID)"
```

对已下载的包做同样的重签：

```bash
codesign --force --deep --sign "Apple Development: Your Name (TEAMID)" /Applications/PMSet.app
```

> 重签必须覆盖内嵌 Helper。只想签一层（`codesign --sign ... PMSet.app` 不加 `--deep`）时，Helper 仍是 ad-hoc 签名，照样装不上。

### 关于 Touch ID

两条授权路径都只支持密码输入，不支持 Touch ID：

- Helper 安装使用的是系统管理员授权框（`AuthorizationCreate`），仅支持密码。
- 回退的 AppleScript 授权框同样仅支持密码。

## 技术实现

### 特权执行：Helper 优先 + AppleScript 回退

`PMSetManager` 的所有特权写入统一走 `runPrivileged(_:completion:)`：先通过 `PrivilegedHelperManager` 让 Helper 以 root 执行；失败则回退 AppleScript 密码方式，并只向上层回调一次错误。

相关代码：
- `Sources/PMSet/PrivilegedHelperManager.swift` — App 端安装、版本校验与 XPC 通信
- `Sources/PMSetShared/HelperProtocol.swift` — 共享 XPC 协议
- `Sources/PMSetHelper/main.swift` — 特权 Helper（以 root 身份常驻）
- `Info.plist` 中的 `SMPrivilegedExecutables` — 声明允许安装的 Helper 与签名要求

### Helper 命令白名单

Helper 不接受任意 shell 命令，只执行严格匹配白名单的 pmset 调用：

| 允许的命令 | 说明 |
|---|---|
| `/usr/bin/pmset -a <键> <值>` | 键限定为上述 9 个；值限定为十进制非负整数 |
| `/usr/bin/pmset restoredefaults` | 「默认睡眠方案」使用 |
| `/usr/bin/pmset sleepnow` | 合盖状态下关闭「禁止睡眠」后立即睡眠 |

- 只允许 `/usr/bin/pmset`；其他可执行文件、管道、重定向、shell 元字符、多余空格一律拒绝。
- 命令以参数数组直接传给 `Process` 执行，不经过 shell。
- 一批命令中任一条不合法就整批拒绝，一条都不执行。
- XPC 连接要求调用方满足 `identifier "local.pmset.app"`，其他进程无法借 Helper 提权。

### 状态读取与勾选

- 用 `pmset -g`、`pmset -g custom`、`pmset -g cap` 解析当前值与本机可用键集合。
- 「禁止睡眠」状态取自 `pmset -g` 的 `SleepDisabled`（映射为写入用的 `disablesleep`），不再用 `hibernatemode == 0` 推断。
- 图标与菜单勾选均以回读的实际值为准，菜单每次展开前刷新。

### 签名要求

SMJobBless 对 Helper 有两类硬性要求，缺任意一条都装不上：

1. **二进制内嵌两段 plist**：`__TEXT,__info_plist`（`CFBundleIdentifier`、`SMAuthorizedClients`）与 `__TEXT,__launchd_plist`（`Label`、`MachServices`）。后者由 `Sources/PMSetHelper/launchd.plist` 经 `Package.swift` 的 `-sectcreate` 链接进去；缺失时 `SMJobBless` 会返回 `kSMErrorJobPlistNotFound`（error 8）。`build-app.sh` 会自检这两段，缺任意一段直接构建失败。
2. **签名被 launchd 信任**：已实测 Apple Development（免费个人团队）与 Developer ID 可用；ad-hoc 会被 launchd 拒绝。自签名根证书未验证，且 Apple 的 SMJobBless 示例假定使用 Apple 签发的证书，不建议依赖。

签名顺序是先签内部 Helper、再签整个 App bundle，让 App 的签名 seal 覆盖 Helper。

两端的签名要求都只校验 bundle id（`SMPrivilegedExecutables` = `identifier "local.pmset.helper"`，`SMAuthorizedClients` = `identifier "local.pmset.app"`），不绑定 Team ID，所以任何有效的 Apple 开发证书都能用，包括免费个人团队证书。

## 项目结构

```
PMSet/
├── Sources/
│   ├── PMSet/                  # 主 App
│   │   ├── main.swift
│   │   ├── AppDelegate.swift               # 菜单栏、菜单结构与勾选同步
│   │   ├── PMSetManager.swift              # 方案应用、差异下发与回读校验
│   │   ├── Preset.swift                    # 方案数据模型
│   │   ├── PresetStore.swift               # 方案持久化与增删改查
│   │   ├── PowerKey.swift                  # 9 个键的元数据与四层分组
│   │   ├── SystemPowerReader.swift         # pmset 状态读取与能力探测
│   │   ├── PresetEditorWindowController.swift  # 自定义配置窗口
│   │   └── PrivilegedHelperManager.swift   # Helper 安装、版本校验与 XPC 通信
│   ├── PMSetShared/            # 共享 XPC 协议
│   │   └── HelperProtocol.swift
│   └── PMSetHelper/            # 特权 Helper Tool
│       ├── main.swift
│       ├── Info.plist          # 内嵌为 __TEXT,__info_plist
│       └── launchd.plist       # 内嵌为 __TEXT,__launchd_plist（SMJobBless 必需）
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
