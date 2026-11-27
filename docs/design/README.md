# design — 设计源文件（真源）

本目录存放 PMSet 的**设计原稿 / 设计源文件**，是视觉稿的唯一真源（single source of truth）。

## 使用约定

- **不要直接引用**：这里的文件不会被项目代码、构建脚本或任何配置直接引用。App 实际使用的资源请放在 `Resources/`，打包与资源声明也只在那边维护。
- **不要随意修改**：源文件只在设计层面变更时才更新，改了要同步重新导出到 `Resources/`（并重新打包 `PMSet.icns`）。不要为了「让某处编译通过」而在这里改图或改脚本。
- **只读参考**：日常开发按需查看、取色、比对，不要就地编辑，也不要让它成为构建产物。

## 目录内容

```
docs/design/
└── icons/
    ├── AppIcon.svg            # App 图标矢量源稿
    ├── AppIcon-1024.png       # 由源稿导出的 1024 主图
    ├── MenuBarIcon-Awake.svg  # 菜单栏「清醒」状态矢量源稿
    ├── MenuBarIcon-Sleep.svg  # 菜单栏「休眠」状态矢量源稿
    ├── gen_owl.py             # 图标生成脚本（设计侧工具，不参与构建）
    ├── Preview.png            # 设计预览
    ├── icons.zip              # 图标原始打包
    └── Assets.xcassets        # 设计侧资源集合
```

## 与构建产物的关系

| 设计源文件 | 项目实际使用 |
|---|---|
| `icons/AppIcon-1024.png` | `Resources/AppIcon-1024.png` → 打包生成 `PMSet.icns` |
| `icons/MenuBarIcon-*.svg` | 导出为 `Resources/MenuBarAwake*.png` / `MenuBarSleep*.png` |

改动流程：改本目录源稿 → 重新导出 → 更新 `Resources/` → 重新打包。不要反向把代码或构建脚本指向本目录。
