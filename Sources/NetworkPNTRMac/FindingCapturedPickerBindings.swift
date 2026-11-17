import Foundation
import NetworkPNTRCore
import SwiftUI

@MainActor enum FindingCapturedPickerBindings {
    static func presentation(_ model: FindingTrafficWorkspace,id: UUID?) -> Binding<FindingCapturedPicker?> {
        Binding(get:{model.picker?.id == id ? model.picker : nil},set:{value in if value == nil, let id { model.closePicker(id:id) }})
    }
    static func draft(_ picker: FindingCapturedPicker,key: ReferenceWritableKeyPath<FindingCapturedPicker,String>) -> Binding<String> {
        Binding(get:{picker.isActive ? picker[keyPath:key] : ""},set:{value in picker.updateDraft { picker[keyPath:key] = value }})
    }
    static func method(_ picker: FindingCapturedPicker) -> Binding<String> {
        Binding(get:{picker.isActive ? picker.methodDraft?.rawValue ?? "" : ""},set:{value in picker.updateDraft { picker.methodDraft = CapturedHTTPMethod(rawValue:value) }})
    }
    static func selected(_ picker: FindingCapturedPicker,source: String,owner: UUID) -> Binding<Bool> {
        Binding(get:{picker.isSelected(source,owner:owner)},set:{value in _ = picker.toggle(source,selected:value,owner:owner)})
    }
}
