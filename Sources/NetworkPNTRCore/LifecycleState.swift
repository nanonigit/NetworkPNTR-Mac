import Foundation

public enum LifecycleState: String, Sendable {
    case idle, starting, running, stopping, stopped, failed
    public var canStart: Bool { [.idle, .stopped, .failed].contains(self) }
    public var canStop: Bool { self == .running }
    public mutating func transition(to next: LifecycleState) throws {
        let valid: Bool
        switch (self, next) {
        case (.idle, .starting), (.stopped, .starting), (.failed, .starting),
             (.starting, .running), (.running, .stopping), (.stopping, .stopped),
             (.starting, .failed), (.running, .failed), (.stopping, .failed),
             (.running, .stopped), (.starting, .stopped), (.failed, .stopped): valid = true
        default: valid = false
        }
        guard valid else { throw RuntimeError.invalidTransition(rawValue, next.rawValue) }
        self = next
    }
}
public enum RuntimeError: LocalizedError {
    case invalidTransition(String, String), integrity(String), timeout(String), unsupported, guestKernelFault
    public var errorDescription: String? {
        switch self {
        case let .invalidTransition(a,b): return "Invalid lifecycle transition: \(a) → \(b)"
        case let .integrity(name): return "Guest artifact failed validation: \(name)"
        case let .timeout(stage): return "Timed out during \(stage). Inspect the guest log before retrying."
        case .unsupported: return "Hardware virtualization is unavailable on this Mac."
        case .guestKernelFault: return "The guest encountered a kernel fault."
        }
    }
}
