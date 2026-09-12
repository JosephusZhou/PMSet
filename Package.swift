// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PMSet",
    platforms: [.macOS(.v13)],
    targets: [
        // 主 App（菜单栏应用）
        .executableTarget(
            name: "PMSet",
            dependencies: ["PMSetShared"],
            path: "Sources/PMSet"
        ),
        // 特权 Helper Tool（以 root 身份运行，通过 XPC 接收 App 的命令）
        .executableTarget(
            name: "PMSetHelper",
            dependencies: ["PMSetShared"],
            path: "Sources/PMSetHelper",
            exclude: ["Info.plist"],
            linkerSettings: [
                // 将 Info.plist 嵌入到二进制的 __TEXT,__info_plist section。
                // SMJobBless 要求 Helper 二进制内置 Info.plist（含 CFBundleIdentifier 和 SMAuthorizedClients）。
                //
                // 【路径说明】此处使用相对路径 "Sources/PMSetHelper/Info.plist"，
                // 依赖于 swift build 在包根目录执行。build-app.sh 中已通过
                // `cd "$(dirname "$0")"` 确保工作目录正确。
                //
                // 【限制】SPM 的 unsafeFlags 不支持变量插值或可移植的绝对路径写法，
                // 因此只能用相对路径。若需在其他目录直接执行 `swift build`，
                // 请先 cd 到包根目录。
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PMSetHelper/Info.plist"
                ])
            ]
        ),
        // App 与 Helper 共享的 XPC 协议定义
        .target(
            name: "PMSetShared",
            path: "Sources/PMSetShared"
        )
    ]
)
