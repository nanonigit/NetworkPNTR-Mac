/// Compatibility availability for the current verified boot, not an authorization boundary.
struct GuestRuntimeFeatures: Sendable {
    let trafficBlobExportDeclared: Bool
    init(trafficBlobExportDeclared: Bool = false) { self.trafficBlobExportDeclared = trafficBlobExportDeclared }
    func allowsTrafficBlobExport(state: LifecycleState, ready: Bool, hasMachine: Bool) -> Bool {
        trafficBlobExportDeclared && state == .running && ready && hasMachine
    }
}
