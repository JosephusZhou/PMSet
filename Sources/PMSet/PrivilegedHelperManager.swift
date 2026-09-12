// ============================================================================
// ⚠️ 预留代码：SMJobBless 特权 Helper Tool 方案
// ============================================================================
//
// 当前版本未启用此方案。PMSetManager 采用更简洁的 AppleScript 方式
// （`do shell script ... with administrator privileges`），每次执行特权操作
// 时弹出密码输入框（不支持 Touch ID），无需任何代码签名证书。
//
// 本文件及以下相关文件保留为未来升级预留：
//   - Sources/PMSet/PrivilegedHelperManager.swift（本文件）
//   - Sources/PMSetShared/HelperProtocol.swift
//   - Sources/PMSetHelper/main.swift + Info.plist
//   - Info.plist 中的 SMPrivilegedExecutables
//
// 【为什么需要证书】
// SMJobBless 安装的 Helper 由 launchd 以 root 身份拉起。launchd 拒绝加载
// ad-hoc 签名的二进制（会报 CFErrorDomainLaunchd error 8），必须使用正式的
// 代码签名证书（Apple Development / Developer ID / 自签名证书均可）。
//
// 【未来启用步骤】
// 1. 获得固定的代码签名证书（如 Developer ID Application）。
// 2. 用该证书签名 App 和 Helper：
//      bash build-app.sh --sign "Developer ID Application: XXX"
// 3. 在 PMSetManager 中，将 runAsAdmin() 的实现替换为：
//      PrivilegedHelperManager.shared.runCommands(commands) { success, output in ... }
// 4. 启用后用户只需授权一次，后续所有特权操作静默执行，不再弹框。
//
// 【当前状态】未调用，仅编译保留。
// ============================================================================

import Foundation
import ServiceManagement
import PMSetShared

/// 负责特权 Helper Tool 的安装、版本校验与 XPC 通信。
///
/// - Note: 当前版本未启用，详见文件顶部的预留说明。
final class PrivilegedHelperManager {

    static let shared = PrivilegedHelperManager()

    // MARK: - 常量

    let helperBundleID = "local.pmset.helper"
    let helperVersion = "1.0.0"

    private var helperInstallPath: String {
        "/Library/PrivilegedHelperTools/\(helperBundleID)"
    }

    /// App bundle 内 Helper 的路径（SMJobBless 从这里读取）。
    private var bundledHelperPath: String? {
        Bundle.main.path(forAuxiliaryExecutable: helperBundleID)
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents/Library/LaunchServices")
                .appendingPathComponent(helperBundleID).path
    }

    // MARK: - 状态

    private var connection: NSXPCConnection?
    /// 最近一次安装失败的错误信息，供 UI 展示。
    private(set) var lastErrorMessage: String = ""

    private init() {}

    // MARK: - 诊断

    /// 安装前检查，返回发现的问题列表（空数组表示无问题）。
    func diagnose() -> [String] {
        var issues: [String] = []

        // 1. Helper 是否存在于 App bundle 中
        guard let helperPath = bundledHelperPath else {
            issues.append("无法定位 App bundle 内的 Helper 路径")
            return issues
        }
        if !FileManager.default.fileExists(atPath: helperPath) {
            issues.append("Helper 不存在于 App bundle 中: \(helperPath)")
        } else {
            NSLog("PMSet: bundled helper path: \(helperPath)")
        }

        // 2. Helper 是否有可执行权限
        if !FileManager.default.isExecutableFile(atPath: helperPath) {
            issues.append("Helper 没有可执行权限")
        }

        // 3. App 签名信息
        let appStatus = codesignInfo(for: Bundle.main.bundlePath)
        NSLog("PMSet: app signature: \(appStatus)")
        if appStatus.contains("adhoc") {
            NSLog("PMSet: note: app is ad-hoc signed")
        }

        // 4. Helper 签名信息
        let helperStatus = codesignInfo(for: helperPath)
        NSLog("PMSet: helper signature: \(helperStatus)")
        if helperStatus.contains("adhoc") {
            NSLog("PMSet: note: helper is ad-hoc signed")
        }

        // 5. App Info.plist 中的 SMPrivilegedExecutables
        if let privileged = Bundle.main.object(forInfoDictionaryKey: "SMPrivilegedExecutables") as? [String: String] {
            NSLog("PMSet: SMPrivilegedExecutables: \(privileged)")
            if privileged[helperBundleID] == nil {
                issues.append("App Info.plist 中 SMPrivilegedExecutables 缺少 key: \(helperBundleID)")
            }
        } else {
            issues.append("App Info.plist 中缺少 SMPrivilegedExecutables")
        }

        return issues
    }

    private func codesignInfo(for path: String) -> String {
        let process = Process()
        process.launchPath = "/usr/bin/codesign"
        process.arguments = ["-dvv", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? "(无法读取签名信息)"
        } catch {
            return "签名检查失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 安装状态

    var isHelperInstalled: Bool {
        FileManager.default.fileExists(atPath: helperInstallPath)
    }

    func isHelperVersionCompatible() -> Bool {
        guard isHelperInstalled else { return false }

        var installedVersion = ""
        let semaphore = DispatchSemaphore(value: 0)

        let conn = NSXPCConnection(machServiceName: helperBundleID)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.resume()

        let proxy = conn.remoteObjectProxyWithErrorHandler { _ in
            semaphore.signal()
        } as? HelperProtocol

        proxy?.getVersion { version in
            installedVersion = version
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5)
        conn.invalidate()

        return installedVersion == helperVersion
    }

    // MARK: - 安装

    /// 调用 SMJobBless 安装 Helper，返回 (是否成功, 错误信息)。
    @discardableResult
    func installHelper() -> (success: Bool, errorMessage: String) {
        // 安装前诊断
        let issues = diagnose()
        if !issues.isEmpty {
            NSLog("PMSet: pre-install diagnostics found issues:")
            for issue in issues {
                NSLog("PMSet:   - \(issue)")
            }
        }

        // 创建 AuthorizationRef
        var authRef: AuthorizationRef?
        let authStatus = AuthorizationCreate(nil, nil, [], &authRef)

        if authStatus == errAuthorizationCanceled {
            let msg = "用户取消了授权。"
            NSLog("PMSet: \(msg)")
            lastErrorMessage = msg
            return (false, msg)
        }

        guard authStatus == errAuthorizationSuccess, let auth = authRef else {
            let msg = "无法创建授权会话（状态码 \(authStatus)）。"
            NSLog("PMSet: \(msg)")
            lastErrorMessage = msg
            return (false, msg)
        }
        defer { AuthorizationFree(auth, []) }

        // 调用 SMJobBless
        var error: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            helperBundleID as CFString,
            auth,
            &error
        )

        if success {
            NSLog("PMSet: SMJobBless succeeded")
            lastErrorMessage = ""
            connection?.invalidate()
            connection = nil
            return (true, "")
        }

        // 失败：提取详细错误信息
        var message = "SMJobBless 安装失败"
        if let cfError = error?.takeRetainedValue() {
            let nsError = cfError as Error
            message = "\(nsError.localizedDescription)"

            // 尝试提取更详细的信息
            let cfErrorRef = cfError as CFError
            if let userInfo = CFErrorCopyUserInfo(cfErrorRef) as? [String: Any] {
                NSLog("PMSet: SMJobBless error userInfo: \(userInfo)")
                if let description = userInfo[NSLocalizedDescriptionKey] as? String {
                    message = description
                }
                if let reason = userInfo[NSLocalizedFailureReasonErrorKey] as? String {
                    message += "（\(reason)）"
                }
            }

            let domain = CFErrorGetDomain(cfErrorRef) as String
            let code = CFErrorGetCode(cfErrorRef)
            NSLog("PMSet: SMJobBless failed: domain=\(domain), code=\(code), message=\(message)")

            // 常见错误码的中文解释
            if domain == "com.apple.ServiceManagement" {
                switch code {
                case 3:
                    message += "（错误码 3：签名无效或 requirement 不匹配）"
                case 4:
                    message += "（错误码 4：授权失败）"
                case 5:
                    message += "（错误码 5：Helper 工具无效或 Info.plist 缺失）"
                case 7:
                    message += "（错误码 7：Helper 未正确打包到 App bundle 中）"
                case 8:
                    message += "（错误码 8：Helper Info.plist 缺少 SMAuthorizedClients）"
                default:
                    message += "（错误码 \(code)）"
                }
            }
        } else {
            NSLog("PMSet: SMJobBless failed with no CFError")
        }

        lastErrorMessage = message
        return (false, message)
    }

    /// 确保 Helper 已安装且版本正确；如需要则触发安装。
    @discardableResult
    func ensureHelperReady() -> (success: Bool, errorMessage: String) {
        if isHelperInstalled && isHelperVersionCompatible() {
            return (true, "")
        }
        return installHelper()
    }

    // MARK: - XPC 通信

    func getHelper() -> HelperProtocol? {
        if connection == nil {
            let conn = NSXPCConnection(machServiceName: helperBundleID)
            conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
            conn.resume()
            connection = conn
        }
        return connection?.remoteObjectProxyWithErrorHandler { error in
            NSLog("PMSet: XPC error: \(error)")
        } as? HelperProtocol
    }

    /// 便捷方法：确保 Helper 就绪后，以 root 身份执行一组命令。
    func runCommands(
        _ commands: [String],
        completion: @escaping (_ success: Bool, _ output: String) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ready = self.ensureHelperReady()
            guard ready.success else {
                DispatchQueue.main.async {
                    completion(false, ready.errorMessage)
                }
                return
            }

            guard let helper = self.getHelper() else {
                DispatchQueue.main.async {
                    completion(false, "无法连接到特权辅助工具。")
                }
                return
            }

            helper.runCommands(commands) { success, output in
                DispatchQueue.main.async {
                    completion(success, output)
                }
            }
        }
    }
}
