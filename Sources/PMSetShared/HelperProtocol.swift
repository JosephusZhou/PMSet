import Foundation

/// App 与特权 Helper 之间的 XPC 协议。
/// 两端必须保持定义一致：方法名、参数顺序、回调签名都不能变。
@objc public protocol HelperProtocol {
    /// 以 root 身份依次执行一组 shell 命令。
    /// - Parameters:
    ///   - commands: 命令数组，按顺序执行；任一条失败即停止。
    ///   - reply: 回调。success 表示全部命令是否成功；output 为合并后的 stdout/stderr。
    func runCommands(_ commands: [String], reply: @escaping (_ success: Bool, _ output: String) -> Void)

    /// 返回 Helper 的版本号，App 端用于判断已安装版本是否需要升级。
    func getVersion(reply: @escaping (_ version: String) -> Void)
}
