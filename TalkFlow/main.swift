import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// 主菜单栏
let mainMenu = NSMenu()

// 应用菜单
let appMenu = NSMenu(title: "TalkFlow")
appMenu.addItem(NSMenuItem(title: "关于 TalkFlow", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(NSMenuItem(title: "退出 TalkFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
let appMenuItem = NSMenuItem()
appMenuItem.submenu = appMenu
mainMenu.addItem(appMenuItem)

// Edit 菜单 — 支持 NSTextView 复制/粘贴
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
let editMenuItem = NSMenuItem()
editMenuItem.submenu = editMenu
mainMenu.addItem(editMenuItem)

app.mainMenu = mainMenu

let delegate = AppDelegate()
app.delegate = delegate
app.run()
