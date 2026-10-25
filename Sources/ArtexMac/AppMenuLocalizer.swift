import AppKit
import ArtexCore

@MainActor struct AppMenuContext {
    let mainMenu: NSMenu?
    var windowsMenu: NSMenu? = nil
    var helpMenu: NSMenu? = nil
    var servicesMenu: NSMenu? = nil
}

/// Retitles recognized native commands in place; never replaces responder-chain commands.
@MainActor enum AppMenuLocalizer {
    private struct Command {
        let key: AppStringKey
        var aliases: [String] = []
    }
    private static let commands: [String: Command] = [
        "orderFrontStandardAboutPanel:": .init(key: .menuAbout),
        "hide:": .init(key: .menuHide),
        "hideOtherApplications:": .init(key: .menuHideOthers, aliases: ["Hide Other Applications", "Hide Other Apps"]),
        "unhideAllApplications:": .init(key: .menuShowAll),
        "terminate:": .init(key: .menuQuit),
        "performClose:": .init(key: .menuClose),
        "undo:": .init(key: .menuUndo, aliases: ["元に戻す"]),
        "redo:": .init(key: .menuRedo, aliases: ["やり直し"]),
        "cut:": .init(key: .menuCut, aliases: ["切り取り", "剪切", "剪下", "오려두기"]),
        "copy:": .init(key: .menuCopy, aliases: ["复制", "拷貝", "복사하기"]),
        "paste:": .init(key: .menuPaste, aliases: ["貼り付け", "粘贴", "貼上", "붙여넣기"]),
        "pasteAsPlainText:": .init(key: .menuPastePlain, aliases: ["Paste and Match Formatting"]),
        "delete:": .init(key: .menuDelete),
        "selectAll:": .init(key: .menuSelectAll, aliases: ["すべて選択"]),
        "performMiniaturize:": .init(key: .menuMinimize, aliases: ["最小化"]),
        "performZoom:": .init(key: .menuZoom, aliases: ["拡大/縮小"]),
        "arrangeInFront:": .init(key: .menuBringAll),
        "toggleFullScreen:": .init(key: .menuFullScreen),
        "toggleSidebar:": .init(key: .menuSidebar),
        "toggleToolbarShown:": .init(key: .menuToolbar),
        "runToolbarCustomizationPalette:": .init(key: .menuCustomizeToolbar),
        "showHelp:": .init(key: .menuAppHelp)
    ]
    static func apply(_ context: AppMenuContext, language: AppLanguage, applicationName: String = "ARTEX Mac") {
        guard let main = context.mainMenu else { return }
        func title(_ key: AppStringKey, _ language: AppLanguage) -> String {
            AppStrings.formatted(key, language: language, values: ["app": applicationName])
        }
        func group(_ item: NSMenuItem, submenu: NSMenu, root: Bool) -> AppStringKey? {
            if submenu === context.windowsMenu { return .menuWindow }
            if submenu === context.helpMenu { return .menuHelp }
            if submenu === context.servicesMenu { return .menuServices }
            guard root else { return nil }
            let name = item.title.isEmpty ? submenu.title : item.title
            let actions = Set(submenu.items.compactMap { $0.action.map(NSStringFromSelector) })
            let groups: [(AppStringKey, [String], Set<String>)] = [
                (.menuFile, ["文件", "檔案", "파일"], ["performClose:"]),
                (.menuEdit, ["编辑", "編輯", "편집"], ["cut:", "copy:", "paste:", "undo:"]),
                (.menuView, ["显示", "檢視", "보기"], ["toggleFullScreen:", "toggleSidebar:", "toggleToolbarShown:"]),
                (.menuWindow, ["ウィンドウ", "窗口", "視窗", "윈도우"], ["performMiniaturize:", "performZoom:"]),
                (.menuHelp, ["帮助", "說明", "도움말"], ["showHelp:"])
            ]
            for (key, aliases, anchors) in groups {
                let known = aliases + AppLanguage.allCases.map { title(key, $0) }
                if known.contains(name), !actions.isDisjoint(with: anchors) { return key }
            }
            return nil
        }
        func visit(_ menu: NSMenu, root: Bool) {
            for item in menu.items {
                if let submenu = item.submenu {
                    visit(submenu, root: false)
                    if item.attributedTitle == nil, item.view == nil, let key = group(item, submenu: submenu, root: root) {
                        let value = title(key, language);item.title = value;submenu.title = value
                    }
                }
                guard !item.isSeparatorItem, item.view == nil, item.attributedTitle == nil,
                      let action = item.action, let command = commands[NSStringFromSelector(action)] else { continue }
                let known = command.aliases + AppLanguage.allCases.map { title(command.key, $0) }
                guard known.contains(item.title) else { continue }
                item.title = title(command.key, language)
            }
        }
        visit(main, root: true)
    }
}

/// Owns one menu-notification observer, but language persistence remains in SwiftUI.
@MainActor final class AppMenuLanguageBridge: NSObject {
    private let center: NotificationCenter
    private let context: @MainActor () -> AppMenuContext
    private var language: AppLanguage = .english
    private var observing = false
    init(center: NotificationCenter = .default, context: @escaping @MainActor () -> AppMenuContext) {
        self.center = center;self.context = context
    }
    func start(language: AppLanguage) {
        if !observing {
            center.addObserver(self, selector: #selector(menuDidBeginTracking(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
            observing = true
        }
        select(language)
    }
    func select(_ language: AppLanguage) { self.language = language;refresh() }
    func refresh() { AppMenuLocalizer.apply(context(), language: language) }
    func stop() {
        center.removeObserver(self, name: NSMenu.didBeginTrackingNotification, object: nil)
        observing = false
    }
    // AppKit delivers native menu tracking on the main thread.
    @objc private func menuDidBeginTracking(_ notification: Notification) { refresh() }
}
