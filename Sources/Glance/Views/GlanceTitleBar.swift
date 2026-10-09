//
//  GlanceTitleBar.swift
//  Glance
//

import AppKit
import SwiftUI

/// Window title bar drawn by the app (Paper: flat bar with hairline border, icons on the right).
/// The system traffic lights are moved to the bar's vertical centre by `TrafficLightInset`.
struct GlanceTitleBar<Leading: View, Trailing: View>: View {
    static var height: CGFloat { 52 }

    @Environment(\.colorScheme) private var colorScheme
    private let leading: Leading
    private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, 96)      // clears the traffic lights
        .padding(.trailing, 16)
        .frame(height: Self.height)
        .background(WindowDragArea())
        .background(GlancePalette.surface(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(GlancePalette.divider(colorScheme)).frame(height: 1)
        }
    }
}

/// 32×32 icon button used in the title bar.
struct TitleBarButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let symbol: String
    let label: LocalizedStringKey
    var isOn = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(isOn ? GlancePalette.accent : GlancePalette.muted(colorScheme))
                .frame(width: 32, height: 32)
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }
}

/// Lets the bar move the window like a normal title bar.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Centres the traffic lights vertically in a taller custom title bar.
struct TrafficLightInset: NSViewRepresentable {
    let barHeight: CGFloat

    @MainActor
    final class Coordinator {
        weak var window: NSWindow?
        var barHeight: CGFloat = 52
        var observers: [NSObjectProtocol] = []

        func attach(to window: NSWindow?, barHeight: CGFloat) {
            self.barHeight = barHeight
            guard let window, window !== self.window else { apply(); return }
            self.window = window
            observers.forEach(NotificationCenter.default.removeObserver)
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification,
                NSWindow.didBecomeKeyNotification, NSWindow.didEndLiveResizeNotification,
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                }
            }
            apply()
        }

        func apply() {
            guard let window, !window.styleMask.contains(.fullScreen),
                  let close = window.standardWindowButton(.closeButton),
                  let titlebar = close.superview,
                  let container = titlebar.superview else { return }
            container.frame = NSRect(x: 0, y: window.frame.height - barHeight, width: window.frame.width, height: barHeight)
            titlebar.frame = container.bounds
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(type) else { continue }
                button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: (barHeight - button.frame.height) / 2))
            }
        }

    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            context.coordinator.attach(to: view?.window, barHeight: barHeight)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView.window, barHeight: barHeight)
    }
}
