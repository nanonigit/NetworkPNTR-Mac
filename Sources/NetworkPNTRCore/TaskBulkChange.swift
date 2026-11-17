/// Receipts already validated by the finite services; never inferred from refresh success.
public enum TaskBulkChange: Sendable {
    case deleted(TaskDeletionResult), controlled([TaskBatchControlItem]), moved(TaskCategoryBatchResult)
}
