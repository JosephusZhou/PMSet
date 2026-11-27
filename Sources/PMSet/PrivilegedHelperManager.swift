// ============================================================================
// SMJobBless 特权 Helper Tool（已启用）
// ============================================================================
//
// PMSetManager 的所有特权电源写入都优先走这里：
//   1. ensureHelperReady()：Helper 已安装且版本与 App 内置版本一致时直接复用，
//      版本不一致（或未安装）时自动重装，用户只需授权一次；
//   2. runCommands(_:completion:)：通过 XPC 让 Helper 以 root 身份执行白名单内的
//      pmset 命令，后续操作静默完成，不再弹密码框。
//
// 【自动回退】Helper 未安装、安装被拒绝、版本不匹配或 XPC 调用失败时，
// PMSetManager 会自动回退到 AppleScript 密码方式，功能结果一致。
//
// 【签名要求】SMJobBless 安装的 Helper 由 launchd 以 root 身份拉起，launchd 拒绝
// 加载 ad-hoc 签名的二进制（CFErrorDomainLaunchd error 8），因此分发构建必须使用
// 正式签名身份：bash build-app.sh --sign "Developer ID Application: XXX"。
// ad-hoc 构建下 Helper 装不上，但不会阻塞功能，只会回退到密码方式。
// ============================================================================

import Foundation
import ServiceManagement
import PMSetShared

/// 负责特权 Helper Tool 的安装、版本校验与 XPC 通信。
final class PrivilegedHelperManager {

    static let shared = PrivilegedHelperManager()

    // MARK: - 常量

    let helperBundleID = "local.pmset.helper"
    /// 必须与 Helper 端 kHelperVersion 保持一致；版本不一致会触发自动重装。
    let helperVersion = "1.1.0"

    private var helperInstallPath: String {
        "/Library/PrivilegedHelperTools/\(helperBundleID)"
    }

    private var helperLaunchdPlistPath: String {
        "/Library/LaunchDaemons/\(helperBundleID).plist"
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
    private let connectionLock = NSLock()
    /// 串行化 Helper 的安装、卸载与就绪检查，避免并发弹窗或边卸载边 XPC 调用
    private let lifecycleLock = NSLock()
    private let autoInstallDisabledKey = "helperAutoInstallDisabled"
    /// 最近一次安装失败的错误信息，供 UI 展示。
    private(set) var lastErrorMessage: String = ""

    private var isAutoInstallDisabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoInstallDisabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoInstallDisabledKey) }
    }

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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? "(无法读取签名信息)"
        } catch {
            return "签名检查失败: \(error.localizedDescription)"
        }
    }

    // MARK: - 安装状态

    var isHelperInstalled: Bool {
        FileManager.default.fileExists(atPath: helperInstallPath)
            && FileManager.default.fileExists(atPath: helperLaunchdPlistPath)
    }

    private var hasAnyHelperArtifact: Bool {
        FileManager.default.fileExists(atPath: helperInstallPath)
            || FileManager.default.fileExists(atPath: helperLaunchdPlistPath)
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

    /// 调用 SMJobBless 安装 Helper，返回 (是否成功, 是否用户取消, 错误信息)。
    @discardableResult
    func installHelper() -> (success: Bool, canceled: Bool, errorMessage: String) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        // 避免等待确认框期间后台已完成安装而再次弹出授权框
        if isHelperInstalled && isHelperVersionCompatible() {
            isAutoInstallDisabled = false
            return (true, false, "")
        }
        return installHelperLocked()
    }

    private func installHelperLocked() -> (success: Bool, canceled: Bool, errorMessage: String) {
        // 安装前诊断
        let issues = diagnose()
        if !issues.isEmpty {
            NSLog("PMSet: pre-install diagnostics found issues:")
            for issue in issues {
                NSLog("PMSet:   - \(issue)")
            }
        }

        // 创建 AuthorizationRef 并预申请 bless 权限，以明确区分用户取消与授权失败
        var authRef: AuthorizationRef?
        let authStatus = AuthorizationCreate(nil, nil, [], &authRef)

        if authStatus == errAuthorizationCanceled {
            let msg = "用户取消了授权。"
            NSLog("PMSet: \(msg)")
            lastErrorMessage = msg
            return (false, true, msg)
        }

        guard authStatus == errAuthorizationSuccess, let auth = authRef else {
            let msg = "无法创建授权会话（状态码 \(authStatus)）。"
            NSLog("PMSet: \(msg)")
            lastErrorMessage = msg
            return (false, false, msg)
        }
        defer { AuthorizationFree(auth, []) }

        let rightStatus = kSMRightBlessPrivilegedHelper.withCString { rightName in
            var item = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPtr in
                var rights = AuthorizationRights(count: 1, items: itemPtr)
                let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
                return AuthorizationCopyRights(auth, &rights, nil, flags, nil)
            }
        }
        if rightStatus == errAuthorizationCanceled {
            let msg = "用户取消了授权。"
            NSLog("PMSet: \(msg)")
            lastErrorMessage = msg
            return (false, true, msg)
        }
        if rightStatus != errAuthorizationSuccess {
            let msg = "获取安装授权失败（状态码 \(rightStatus)）。"
            NSLog("PMSet: \(msg)")
            lastErrorMessage = msg
            return (false, false, msg)
        }

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
            isAutoInstallDisabled = false
            lastErrorMessage = ""
            resetConnection()
            return (true, false, "")
        }

        // 失败：提取详细错误信息
        var message = "SMJobBless 安装失败"
        var canceled = false
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

            if code == Int(errAuthorizationCanceled) {
                canceled = true
                message = "用户取消了授权。"
            } else if domain == "com.apple.ServiceManagement" {
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
        return (false, canceled, message)
    }

    /// 通过管理员权限卸载 launchd 任务与磁盘上的 Helper 文件。
    @discardableResult
    func uninstallHelper() -> (success: Bool, canceled: Bool, errorMessage: String) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        if !hasAnyHelperArtifact {
            isAutoInstallDisabled = true
            lastErrorMessage = ""
            resetConnection()
            return (true, false, "")
        }
        return uninstallHelperLocked()
    }

    private func uninstallHelperLocked() -> (success: Bool, canceled: Bool, errorMessage: String) {
        let command = "/bin/launchctl bootout system/\(helperBundleID) 2>/dev/null || true; " +
            "/bin/rm -f '\(helperLaunchdPlistPath)' '\(helperInstallPath)'"
        let result = Self.executeAsAdminViaAppleScript(
            command,
            prompt: "PMSet 需要管理员权限来卸载辅助工具"
        )
        if result.success {
            NSLog("PMSet: helper uninstalled")
            isAutoInstallDisabled = true
            lastErrorMessage = ""
            resetConnection()
            return (true, false, "")
        }
        NSLog("PMSet: helper uninstall failed: \(result.message)")
        lastErrorMessage = result.message
        return (false, result.canceled, result.message)
    }

    /// 确保 Helper 已安装且版本正确；如需要则触发安装。
    @discardableResult
    func ensureHelperReady() -> (success: Bool, canceled: Bool, errorMessage: String) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        return ensureHelperReadyLocked()
    }

    private func ensureHelperReadyLocked() -> (success: Bool, canceled: Bool, errorMessage: String) {
        if isHelperInstalled && isHelperVersionCompatible() {
            return (true, false, "")
        }
        // 用户主动卸载后不再自动重装，直接交由上层走管理员密码路径
        if !isHelperInstalled && isAutoInstallDisabled {
            return (false, false, "辅助工具已卸载，跳过自动安装。")
        }
        return installHelperLocked()
    }

    // MARK: - 管理员 AppleScript（回退与卸载共用）

    /// AppleScript 提权执行 shell 命令；注意不支持 Touch ID。
    static func executeAsAdminViaAppleScript(
        _ shellCommand: String,
        prompt: String = "PMSet 需要管理员权限来修改电源设置"
    ) -> (success: Bool, canceled: Bool, message: String) {
        // 转义命令与提示语中的反斜杠和双引号，确保嵌入 AppleScript 字符串后语法正确
        let escape: (String) -> String = { text in
            text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "do shell script \"\(escape(shellCommand))\" with administrator privileges with prompt \"\(escape(prompt))\""

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            return (false, false, "无法创建 AppleScript 实例。")
        }

        appleScript.executeAndReturnError(&error)

        if let error = error {
            let errorNumber = error[NSAppleScript.errorNumber] as? Int
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "未知错误"
            return (false, errorNumber == -128, message)
        }
        return (true, false, "")
    }

    // MARK: - XPC 通信

    private func activeConnection() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let existing = connection {
            return existing
        }
        let conn = NSXPCConnection(machServiceName: helperBundleID)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        conn.invalidationHandler = { [weak self, weak conn] in
            guard let self, let conn else { return }
            self.resetConnection(ifMatching: conn)
        }
        conn.interruptionHandler = {
            NSLog("PMSet: XPC connection interrupted")
        }
        conn.resume()
        connection = conn
        return conn
    }

    private func resetConnection(ifMatching target: NSXPCConnection? = nil) {
        connectionLock.lock()
        let old: NSXPCConnection?
        if let target {
            if connection === target {
                old = connection
                connection = nil
            } else {
                old = nil
            }
        } else {
            old = connection
            connection = nil
        }
        connectionLock.unlock()
        // 避免在持有锁时触发 invalidationHandler 再次加锁
        if target == nil {
            old?.invalidate()
        }
    }

    /// 便捷方法：确保 Helper 就绪后，以 root 身份执行一组命令。
    func runCommands(
        _ commands: [String],
        completion: @escaping (_ success: Bool, _ canceled: Bool, _ output: String) -> Void
    ) {
        let finishLock = NSLock()
        var finished = false
        let finish: (Bool, Bool, String) -> Void = { success, canceled, output in
            finishLock.lock()
            let alreadyFinished = finished
            finished = true
            finishLock.unlock()
            guard !alreadyFinished else { return }
            DispatchQueue.main.async {
                completion(success, canceled, output)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let ready = self.ensureHelperReady()
            guard ready.success else {
                finish(false, ready.canceled, ready.errorMessage)
                return
            }

            let conn = self.activeConnection()
            let proxy = conn.remoteObjectProxyWithErrorHandler { [weak self, weak conn] error in
                NSLog("PMSet: XPC error: \(error)")
                if let conn {
                    self?.resetConnection(ifMatching: conn)
                    conn.invalidate()
                }
                finish(false, false, "XPC 通信失败：\(error.localizedDescription)")
            } as? HelperProtocol

            guard let helper = proxy else {
                finish(false, false, "无法连接到特权辅助工具。")
                return
            }

            helper.runCommands(commands) { success, output in
                finish(success, false, output)
            }
        }
    }
}
