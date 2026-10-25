import AppKit
import XCTest
import ArtexCore
@testable import ArtexMac

final class MenuLocalizationTests:XCTestCase {
    @MainActor func testKnownActionsRoundTripWithoutReplacingCommandsOrMetadata() {
        let menu = NSMenu(title:"fixture");let target = NSObject()
        let cut = NSMenuItem(title:"剪切",action:NSSelectorFromString("cut:"),keyEquivalent:"x")
        cut.target = target;cut.keyEquivalentModifierMask = [.command,.shift];cut.isEnabled = false;cut.state = .on
        cut.identifier = .init("fixture-cut");cut.toolTip = "literal 中文 한국어";let payload = NSObject();cut.representedObject = payload
        menu.addItem(cut)
        for (language,title) in [(AppLanguage.english,"Cut"),(.japanese,"カット"),(.english,"Cut")] {
            AppMenuLocalizer.apply(.init(mainMenu:menu),language:language)
            XCTAssertTrue(menu.items[0] === cut);XCTAssertEqual(cut.title,title)
            XCTAssertTrue(cut.target === target);XCTAssertTrue(cut.representedObject as AnyObject? === payload)
            XCTAssertEqual(cut.action,NSSelectorFromString("cut:"));XCTAssertEqual(cut.keyEquivalent,"x")
            XCTAssertEqual(cut.keyEquivalentModifierMask,[.command,.shift]);XCTAssertFalse(cut.isEnabled);XCTAssertEqual(cut.state,.on)
            XCTAssertEqual(cut.identifier?.rawValue,"fixture-cut");XCTAssertEqual(cut.toolTip,"literal 中文 한국어")
        }
    }
    @MainActor func testStandardGroupsAndRegisteredMenusPreserveCustomWindowAndServiceNames() {
        let root = NSMenu(title:"fixture"),edit = NSMenu(title:"编辑"),windows = NSMenu(title:"unknown"),services = NSMenu(title:"unknown")
        let editItem = NSMenuItem(title:"编辑",action:nil,keyEquivalent:"");editItem.submenu=edit;root.addItem(editItem)
        edit.addItem(.init(title:"复制",action:NSSelectorFromString("copy:"),keyEquivalent:"c"))
        let windowItem=NSMenuItem(title:"unknown",action:nil,keyEquivalent:"");windowItem.submenu=windows;root.addItem(windowItem)
        let window=NSMenuItem(title:"literal 中文 한국어",action:NSSelectorFromString("makeKeyAndOrderFront:"),keyEquivalent:"");windows.addItem(window)
        let serviceItem=NSMenuItem(title:"unknown",action:nil,keyEquivalent:"");serviceItem.submenu=services;root.addItem(serviceItem)
        let service=NSMenuItem(title:"custom 中文 한국어",action:NSSelectorFromString("fixtureService:"),keyEquivalent:"");services.addItem(service)
        AppMenuLocalizer.apply(.init(mainMenu:root,windowsMenu:windows,servicesMenu:services),language:.japanese)
        XCTAssertEqual(editItem.title,"編集");XCTAssertEqual(edit.title,"編集");XCTAssertEqual(edit.items[0].title,"コピー")
        XCTAssertEqual(windowItem.title,"ウインドウ");XCTAssertEqual(serviceItem.title,"サービス")
        XCTAssertEqual(window.title,"literal 中文 한국어");XCTAssertEqual(service.title,"custom 中文 한국어")
    }
    @MainActor func testUnknownCustomAndAttributedItemsArePreserved() {
        let root=NSMenu(title:"fixture")
        let custom=NSMenuItem(title:"custom cut 中文 한국어",action:NSSelectorFromString("cut:"),keyEquivalent:"")
        let unknown=NSMenuItem(title:"unknown",action:NSSelectorFromString("fixture:"),keyEquivalent:"")
        let styled=NSMenuItem(title:"Copy",action:NSSelectorFromString("copy:"),keyEquivalent:"");styled.attributedTitle=NSAttributedString(string:"custom styled")
        let viewItem=NSMenuItem(title:"Paste",action:NSSelectorFromString("paste:"),keyEquivalent:"");viewItem.view=NSView()
        let originalStyledTitle=styled.title
        [custom,unknown,styled,viewItem].forEach(root.addItem)
        AppMenuLocalizer.apply(.init(mainMenu:root),language:.japanese)
        XCTAssertEqual(custom.title,"custom cut 中文 한국어");XCTAssertEqual(unknown.title,"unknown")
        XCTAssertEqual(styled.title,originalStyledTitle);XCTAssertEqual(styled.attributedTitle?.string,"custom styled");XCTAssertEqual(viewItem.title,"Paste")
    }
    @MainActor func testBridgeUsesLatestMenuAndLanguageWithOneObserverAndStops() {
        let center=NotificationCenter();var menu=NSMenu(title:"fixture");var calls=0
        let first=NSMenuItem(title:"Copy",action:NSSelectorFromString("copy:"),keyEquivalent:"");menu.addItem(first)
        let bridge=AppMenuLanguageBridge(center:center) {calls+=1;return .init(mainMenu:menu)}
        bridge.start(language:.japanese);XCTAssertEqual(first.title,"コピー")
        bridge.start(language:.japanese);let previous=calls
        center.post(name:NSMenu.didBeginTrackingNotification,object:menu);XCTAssertEqual(calls,previous+1)
        menu=NSMenu(title:"replacement");let second=NSMenuItem(title:"Paste",action:NSSelectorFromString("paste:"),keyEquivalent:"");menu.addItem(second)
        center.post(name:NSMenu.didBeginTrackingNotification,object:menu);XCTAssertEqual(second.title,"ペースト")
        bridge.select(.english);XCTAssertEqual(second.title,"Paste")
        bridge.stop();let stopped=calls;center.post(name:NSMenu.didBeginTrackingNotification,object:menu);XCTAssertEqual(calls,stopped)
        bridge.stop()
    }
}
