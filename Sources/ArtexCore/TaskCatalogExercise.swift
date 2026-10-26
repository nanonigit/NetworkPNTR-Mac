import Foundation

public struct TaskCatalogExerciseReport: Codable, Equatable, Sendable {
    public let checks: [String]
    public let categoryName: String
    public let templateDescription: String
    public let templateGoal: String
    public let rulePattern: String
    public let ruleNote: String
}

/// Fixed synthetic catalog operations; never creates a task, profile, conversation or agent.
@MainActor public enum TaskCatalogExercise {
    public static let expectedChecks = ["initial_empty","category_created","duplicate_rejected","category_renamed","template_created","template_cleared","template_relinked","category_deleted_link_cleared","single_missing_rejected","batch_missing_rejected","template_deleted","final_empty"]
    public static let description = "Description e\u{301} \u{FEFF} interior 中文 한국어"
    public static let goal = "Local contract fixture only"
    public static let note = "fixture {name} e\u{301}"
    public static func run(client: any BackendJSONTransport) async throws -> TaskCatalogExerciseReport {
        try Task.checkCancellation()
        let categories = TaskCategoryService(client:client), templates = TaskTemplateService(client:client)
        guard try await categories.tasks().isEmpty, try await categories.list().isEmpty, try await templates.list().isEmpty else { throw failure() }
        var checks = [expectedChecks[0]]
        let created = try await categories.create(name:"  T11  e\u{301} 日本語  ")
        guard same(created.name,"T11 e\u{301} 日本語"), created.taskCount == 0 else { throw failure() }
        checks.append(expectedChecks[1])
        do { _ = try await categories.create(name:"t11 e\u{301} 日本語"); throw failure() } catch BackendAPIError.status(409) {}
        checks.append(expectedChecks[2])
        let renamed = try await categories.rename(id:created.id,name:"T11 renamed e\u{301} 日本語")
        guard same(renamed.name,"T11 renamed e\u{301} 日本語"), renamed.taskCount == 0 else { throw failure() }
        checks.append(expectedChecks[3])
        var draft = TaskTemplateDraft(); draft.name = "T11 template e\u{301}"; draft.description = description; draft.goal = goal; draft.categoryId = created.id
        draft.interceptRules = [.init(enabled:true,action:.block,kind:.exactDomain,pattern:"example.invalid",note:note)]
        let template = try await templates.create(draft)
        guard TaskTemplateDraft(template).sameBytes(as:draft) else { throw failure() }; checks.append(expectedChecks[4])
        draft.name = "T11 updated e\u{301}"; draft.categoryId = nil; draft.interceptRules = []
        _ = try await templates.update(id:template.id,draft:draft)
        let cleared = try await templates.list()
        guard cleared.count == 1, cleared[0].id == template.id, TaskTemplateDraft(cleared[0]).sameBytes(as:draft) else { throw failure() }
        checks.append(expectedChecks[5])
        draft.categoryId = created.id
        let linked = try await templates.update(id:template.id,draft:draft)
        guard TaskTemplateDraft(linked).sameBytes(as:draft) else { throw failure() }; checks.append(expectedChecks[6])
        _ = try await categories.delete(id:created.id)
        let detached = try await templates.list(); draft.categoryId = nil
        guard detached.count == 1, detached[0].id == template.id, TaskTemplateDraft(detached[0]).sameBytes(as:draft) else { throw failure() }
        checks.append(expectedChecks[7])
        do { _ = try await categories.assign(taskID:"9223372036854775806",categoryID:nil); throw failure() } catch BackendAPIError.status(404) {}
        checks.append(expectedChecks[8])
        let missing = try await categories.assignBatch(taskIDs:["9223372036854775806","9223372036854775805"],categoryID:nil)
        guard missing.items.count == 2, missing.items.allSatisfy({!$0.ok}), missing.category == nil else { throw failure() }
        checks.append(expectedChecks[9])
        _ = try await templates.delete(id:template.id); checks.append(expectedChecks[10])
        guard try await categories.list().isEmpty, try await templates.list().isEmpty, try await categories.tasks().isEmpty else { throw failure() }
        try Task.checkCancellation(); checks.append(expectedChecks[11])
        return .init(checks:checks,categoryName:renamed.name,templateDescription:detached[0].description,templateGoal:detached[0].goal,rulePattern:template.interceptRules[0].pattern,ruleNote:template.interceptRules[0].note)
    }
    private static func same(_ a: String,_ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }
    private static func failure() -> RuntimeError { .integrity("task catalog exercise contract") }
}

public enum TaskCatalogRunStage: String, Encodable, Sendable { case preparing, boot, authentication, operations, shutdown, complete }
public struct TaskCatalogRunReport: Encodable, Sendable {
    public let stage: TaskCatalogRunStage
    public let boot: BackendPreflightReport
    public let exercise: TaskCatalogExerciseReport?
    public let terminalSuccess: Bool
    public let passed: Bool
    @MainActor public init(stage: TaskCatalogRunStage, boot: BackendPreflightReport, exercise: TaskCatalogExerciseReport?, terminalSuccess: Bool) {
        self.stage = stage; self.boot = boot; self.exercise = exercise; self.terminalSuccess = terminalSuccess
        passed = terminalSuccess && stage == .complete && boot.passed && exercise?.checks == TaskCatalogExercise.expectedChecks
    }
}
