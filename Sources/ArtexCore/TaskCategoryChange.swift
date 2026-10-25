import Foundation

/// Confirmed category receipts project only grouping fields, preserving task runtime data.
public enum TaskCategoryChange: Sendable {
    case saved(TaskCategoryRecord), deleted(Int64), assigned(TaskRecord), batchAssigned(TaskCategoryBatchResult)
    public func applying(to tasks: [TaskRecord]) -> [TaskRecord] {
        tasks.map { original in
            var task = original
            switch self {
            case .saved(let category):
                if task.categoryId == category.id { task.categoryName = category.name }
            case .deleted(let id):
                if task.categoryId == id { task.categoryId = nil; task.categoryName = nil }
            case .assigned(let value):
                if task.id == value.id { task.categoryId = value.categoryId; task.categoryName = value.categoryName }
            case .batchAssigned(let value):
                if value.items.contains(where: { $0.id == task.id && $0.ok }) {
                    task.categoryId = value.category?.id; task.categoryName = value.category?.name
                }
            }
            return task
        }
    }
}
