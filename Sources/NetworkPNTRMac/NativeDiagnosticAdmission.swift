#if DEBUG
/// Admits diagnostic startup only after both launch and runtime attachment, in either order.
struct NativeDiagnosticAdmission {
    private(set) var launched = false
    private(set) var started = false

    mutating func didLaunch() { launched = true }

    mutating func admit(requested: Bool, hasEnvironment: Bool) -> Bool {
        guard launched, requested, hasEnvironment, !started else { return false }
        started = true
        return true
    }
}
#endif
