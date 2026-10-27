import ArtexCore
import Foundation

struct FindingAssetRow: Identifiable {
    let node: FindingAssetNode
    let depth: Int
    let hasChildren: Bool
    var id: Data { node.identity }
}
enum FindingPresentation {
    static func pages(total: Int64,size: Int) -> Int64 { total > 0 && size > 0 ? (total-1)/Int64(size)+1 : 1 }
    static func status(_ value: String,language: AppLanguage) -> String {
        guard FindingStatus(rawValue:value) != nil, let key = AppStringKey(rawValue:"finding.ui.status."+value) else { return value }
        return AppStrings.text(key,language:language)
    }
    static func viewKey(_ value: FindingView) -> AppStringKey {
        switch value { case .flat: .findingUIFlat; case .grouped: .findingUIGrouped; case .asset: .findingUIAsset }
    }
    static func assetRows(_ tree: FindingAssetTree,expanded: Set<Data>) -> [FindingAssetRow] {
        var children: [Data:[FindingAssetNode]] = [:], roots: [FindingAssetNode] = []
        for node in tree.nodes {
            if let parent = node.parent, !parent.isEmpty { children[Data(parent.utf8),default:[]].append(node) }
            else { roots.append(node) }
        }
        var stack = roots.reversed().map{($0,0)}, result: [FindingAssetRow] = []
        while let (node,depth) = stack.popLast() {
            let descendants = children[node.identity] ?? []
            result.append(.init(node:node,depth:depth,hasChildren:!descendants.isEmpty))
            if expanded.contains(node.identity) { for child in descendants.reversed() { stack.append((child,depth+1)) } }
        }
        return result
    }
}
