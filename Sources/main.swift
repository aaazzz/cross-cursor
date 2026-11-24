import Cocoa
import ServiceManagement

// MARK: - Settings

enum Config {
    /// 2回目のタップまでの最大間隔（秒）
    static let doubleTapInterval: TimeInterval = 0.4
    /// 1回のタップとみなす最大押下時間（秒）
    static let maxTapDuration: TimeInterval = 0.3
    static let lineWidth: CGFloat = 1
}

// MARK: - Line color (persisted in UserDefaults)

enum LineColor {
    private static let key = "lineColor" // [r, g, b, a] in sRGB

    static let presets: [(name: String, color: NSColor)] = [
        ("Red", NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 0.85)),
        ("Orange", NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 0.85)),
        ("Yellow", NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 0.85)),
        ("Green", NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 0.85)),
        ("Cyan", NSColor(srgbRed: 0.20, green: 0.75, blue: 1.00, alpha: 0.85)),
        ("Blue", NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 0.85)),
        ("Magenta", NSColor(srgbRed: 1.00, green: 0.18, blue: 0.85, alpha: 0.85)),
        ("White", NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.85)),
        ("Black", NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 0.85)),
    ]

    static var current: NSColor {
        get {
            if let c = UserDefaults.standard.array(forKey: key) as? [Double], c.count == 4 {
                return NSColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: c[3])
            }
            return presets[0].color
        }
        set {
            guard let c = newValue.usingColorSpace(.sRGB) else { return }
            UserDefaults.standard.set(
                [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map(Double.init),
                forKey: key)
        }
    }

    static func isSame(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let a = a.usingColorSpace(.sRGB), let b = b.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.01
            && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
            && abs(a.alphaComponent - b.alphaComponent) < 0.01
    }

    /// メニュー用の色見本アイコン
    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            color.withAlphaComponent(1).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
    }
}

// MARK: - Elastic effect settings

enum Elastic {
    private static let key = "elasticEffect"
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    /// 折れ具合が目標に追いつく時定数（秒）。大きいほどゆっくり戻る
    static let followTime: CGFloat = 0.05
    /// 加速度 (pt/s²) → 引っぱり量 (pt) の係数。大きいほど加速時によく折れる
    static let accelerationGain: CGFloat = 0.003
    /// 速度をなめらかにする時定数（秒）。加速度のノイズ対策
    static let velocitySmoothing: CGFloat = 0.03
    /// 線が引っぱられる最大量（pt）
    static let maxStretch: CGFloat = 100
    /// 傾きの効き具合（大きいほど傾きが小さい）。最大傾き = atan(maxStretch / leverLength)
    static let leverLength: CGFloat = 1200
}

// MARK: - Overlay (1 window per screen)

final class OverlayWindow: NSWindow {
    private let hLine = CAShapeLayer()
    private let vLine = CAShapeLayer()
    let screenFrame: NSRect

    init(screen: NSScreen) {
        screenFrame = screen.frame
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        for line in [hLine, vLine] {
            line.actions = ["path": NSNull(), "strokeColor": NSNull(), "hidden": NSNull()]
            line.fillColor = nil
            line.lineWidth = Config.lineWidth
            line.lineJoin = .round
            line.contentsScale = screen.backingScaleFactor
            view.layer?.addSublayer(line)
        }
        contentView = view
        setLineColor(LineColor.current)
    }

    func setLineColor(_ color: NSColor) {
        hLine.strokeColor = color.cgColor
        vLine.strokeColor = color.cgColor
    }

    /// `p` はポインタ位置、`lag` はバネで遅れて追従する点（どちらもグローバルな Cocoa 座標）
    func update(pointer p: NSPoint, lag: NSPoint) {
        let o = screenFrame.origin
        let lp = NSPoint(x: p.x - o.x, y: p.y - o.y)
        let ll = NSPoint(x: lag.x - o.x, y: lag.y - o.y)
        let size = screenFrame.size

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hLine.path = Self.linePath(length: size.width, along: lp.x, at: lp.y, lagAt: ll.y, horizontal: true)
        vLine.path = Self.linePath(length: size.height, along: lp.y, at: lp.x, lagAt: ll.x, horizontal: false)
        CATransaction.commit()
    }

    /// ポインタ `at` で折れ曲がる「く」の字の線。両端が遅れ (`lagAt - at`) の方向に引っぱられる
    private static func linePath(length: CGFloat, along pos: CGFloat, at: CGFloat, lagAt: CGFloat,
                                 horizontal: Bool) -> CGPath {
        let slope = (lagAt - at) / Elastic.leverLength
        func point(_ s: CGFloat) -> CGPoint {
            let v = at + abs(s - pos) * slope
            return horizontal ? CGPoint(x: s, y: v) : CGPoint(x: v, y: s)
        }
        let path = CGMutablePath()
        path.move(to: point(0))
        path.addLine(to: point(min(max(pos, 0), length)))
        path.addLine(to: point(length))
        return path
    }
}

final class Overlay: NSObject {
    private var windows: [OverlayWindow] = []
    private(set) var isVisible = false

    private var displayLink: CADisplayLink?
    private var lag = NSPoint.zero
    private var lastPointer = NSPoint.zero
    private var velocity = CGVector.zero
    private var offset = CGVector.zero

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuild() }
        rebuild()
    }

    private func rebuild() {
        displayLink?.invalidate()
        displayLink = nil
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { OverlayWindow(screen: $0) }
        if let view = windows.first?.contentView {
            let link = view.displayLink(target: self, selector: #selector(tick(_:)))
            link.isPaused = true
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        if isVisible { show() }
    }

    func show() {
        isVisible = true
        let p = NSEvent.mouseLocation
        lag = p
        lastPointer = p
        velocity = .zero
        offset = .zero
        render(pointer: p)
        windows.forEach { $0.orderFrontRegardless() }
    }

    func hide() {
        isVisible = false
        displayLink?.isPaused = true
        windows.forEach { $0.orderOut(nil) }
    }

    func toggle() { isVisible ? hide() : show() }

    func setLineColor(_ color: NSColor) {
        windows.forEach { $0.setLineColor(color) }
    }

    /// マウスが動いたときに呼ばれる
    func updatePosition() {
        guard isVisible else { return }
        if Elastic.isEnabled, let link = displayLink {
            link.isPaused = false
        } else {
            let p = NSEvent.mouseLocation
            lag = p
            render(pointer: p)
        }
    }

    private func render(pointer p: NSPoint) {
        windows.forEach { $0.update(pointer: p, lag: lag) }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let p = NSEvent.mouseLocation
        let dt = min(max(link.targetTimestamp - link.timestamp, 1.0 / 240), 1.0 / 30)

        let t = CGFloat(dt)

        // 速度（なめらかにしてマウスイベントのばらつきを抑える）
        let rawV = CGVector(dx: (p.x - lastPointer.x) / t, dy: (p.y - lastPointer.y) / t)
        let av = 1 - exp(-t / Elastic.velocitySmoothing)
        let newV = CGVector(dx: velocity.dx + (rawV.dx - velocity.dx) * av,
                            dy: velocity.dy + (rawV.dy - velocity.dy) * av)

        // 加速度に比例して、線の両端を加速と逆向きに引っぱる（慣性のイメージ）
        let accel = CGVector(dx: (newV.dx - velocity.dx) / t, dy: (newV.dy - velocity.dy) / t)
        velocity = newV
        // 速くなる向きの加速だけを使う（減速は無視して、反対側には折らない）
        let speed = hypot(newV.dx, newV.dy)
        var target = CGVector.zero
        if speed > 1 {
            let dir = CGVector(dx: newV.dx / speed, dy: newV.dy / speed)
            let speedingUp = accel.dx * dir.dx + accel.dy * dir.dy
            if speedingUp > 0 {
                let m = Elastic.maxStretch
                target = CGVector(dx: min(max(-dir.dx * speedingUp * Elastic.accelerationGain, -m), m),
                                  dy: min(max(-dir.dy * speedingUp * Elastic.accelerationGain, -m), m))
            }
        }

        // 振動させず、指数的に目標の折れ具合へ寄せる
        let ao = 1 - exp(-t / Elastic.followTime)
        offset.dx += (target.dx - offset.dx) * ao
        offset.dy += (target.dy - offset.dy) * ao
        lag = NSPoint(x: p.x + offset.dx, y: p.y + offset.dy)

        // 落ち着いたら止めて CPU を休ませる
        if p == lastPointer && abs(offset.dx) < 0.05 && abs(offset.dy) < 0.05
            && abs(velocity.dx) < 1 && abs(velocity.dy) < 1 {
            offset = .zero
            velocity = .zero
            lag = p
            link.isPaused = true
        }
        lastPointer = p
        render(pointer: p)
    }
}

// MARK: - Double-Shift detection (CGEventTap, listen only)

final class ShiftDoubleTapDetector {
    var onDoubleTap: () -> Void = {}
    var onMouseMove: () -> Void = {}

    private var tap: CFMachPort?
    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    private var shiftDownAt: TimeInterval?
    private var tapIsClean = false
    private var lastTapAt: TimeInterval?

    private static let shiftKeyCodes: Set<Int64> = [56, 60] // left / right shift
    private static let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskSecondaryFn]

    /// 成功したら true。Input Monitoring 権限がないと失敗する。
    func start() -> Bool {
        let types: [CGEventType] = [
            .flagsChanged, .keyDown,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let me = Unmanaged<ShiftDoubleTapDetector>.fromOpaque(userInfo!).takeUnretainedValue()
            me.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let now = ProcessInfo.processInfo.systemUptime

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard Self.shiftKeyCodes.contains(keyCode) else {
                // Shift 以外の修飾キーが絡んだらリセット
                reset()
                return
            }
            let flags = event.flags
            if flags.contains(.maskShift) {
                // Shift 押下
                shiftDownAt = now
                tapIsClean = flags.intersection(Self.otherModifiers).isEmpty
            } else {
                // Shift 解放
                defer { shiftDownAt = nil }
                guard tapIsClean, let down = shiftDownAt, now - down <= Config.maxTapDuration else {
                    lastTapAt = nil
                    return
                }
                if let last = lastTapAt, now - last <= Config.doubleTapInterval {
                    lastTapAt = nil
                    onDoubleTap()
                } else {
                    lastTapAt = now
                }
            }

        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // Shift+文字 の大文字入力などは対象外にする
            reset()

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            onMouseMove()

        default:
            break
        }
    }

    private func reset() {
        tapIsClean = false
        lastTapAt = nil
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlay: Overlay!
    private let detector = ShiftDoubleTapDetector()
    private var retryTimer: Timer?
    private var statusLineItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var colorItems: [NSMenuItem] = []
    private var customColorItem: NSMenuItem!
    private var elasticItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = Overlay()
        setupStatusItem()

        detector.onDoubleTap = { [weak self] in self?.overlay.toggle() }
        detector.onMouseMove = { [weak self] in self?.overlay.updatePosition() }
        startDetector()
    }

    private func startDetector() {
        if detector.start() { return }

        // Input Monitoring 権限を要求し、許可されるまで再試行
        CGRequestListenEventAccess()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self else { return }
            if self.detector.start() { timer.invalidate() }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "plus.viewfinder", accessibilityDescription: "CrossCursor")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Crosshair (Shift ×2)", action: #selector(toggleOverlay), keyEquivalent: "")
        menu.addItem(.separator())

        let colorItem = menu.addItem(withTitle: "Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for (index, preset) in LineColor.presets.enumerated() {
            let item = colorMenu.addItem(withTitle: preset.name, action: #selector(selectPresetColor(_:)), keyEquivalent: "")
            item.tag = index
            item.image = LineColor.swatch(preset.color)
            item.target = self
            colorItems.append(item)
        }
        colorMenu.addItem(.separator())
        customColorItem = colorMenu.addItem(withTitle: "Custom…", action: #selector(openColorPanel), keyEquivalent: "")
        customColorItem.target = self
        colorItem.submenu = colorMenu
        elasticItem = menu.addItem(withTitle: "Elastic Effect", action: #selector(toggleElastic), keyEquivalent: "")
        elasticItem.target = self

        menu.addItem(.separator())
        loginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        statusLineItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(withTitle: "Open Input Monitoring Settings…", action: #selector(openPrivacySettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CrossCursor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func toggleOverlay() { overlay.toggle() }

    @objc private func toggleElastic() {
        Elastic.isEnabled.toggle()
        overlay.updatePosition()
    }

    private func applyColor(_ color: NSColor) {
        LineColor.current = color
        overlay.setLineColor(color)
    }

    @objc private func selectPresetColor(_ sender: NSMenuItem) {
        applyColor(LineColor.presets[sender.tag].color)
    }

    @objc private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.isContinuous = true
        panel.color = LineColor.current
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // 色を選びながら確認できるよう十字線を表示
        if !overlay.isVisible { overlay.show() }
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        applyColor(sender.color)
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        statusLineItem.title = detector.isRunning
            ? "Shift ×2: Active"
            : "⚠️ Shift ×2: Needs Input Monitoring permission"
        elasticItem.state = Elastic.isEnabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let current = LineColor.current
        var matched = false
        for item in colorItems {
            let isSelected = LineColor.isSame(LineColor.presets[item.tag].color, current)
            item.state = isSelected ? .on : .off
            matched = matched || isSelected
        }
        customColorItem.state = matched ? .off : .on
        customColorItem.image = matched ? nil : LineColor.swatch(current)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
