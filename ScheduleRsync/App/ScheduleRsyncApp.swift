import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_: Notification) {
        GlobalTimer.shared.shutdown()
    }
}

@main
struct ScheduleRsyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var schedules = ObservableSchedules()
    @State private var status = StorageStatus.shared

    var body: some Scene {
        Window("ScheduleRsync", id: "main") {
            VStack(alignment: .leading) {
                
                CalendarMonthView(schedules: schedules)
            }
            .frame(minWidth: 1000, minHeight: 700)
            .onDisappear {
                GlobalTimer.shared.shutdown()
                NSApplication.shared.terminate(nil)
            }
            .task {
                if let definitions = await ReadSchedule().readjsonfilecalendar(Homepath().profiles() + ["Default"]) {
                    guard !Task.isCancelled, !GlobalTimer.shared.isStopped else { return }
                    schedules.appendschdeuldatafromfile(definitions)
                }
            }
            .task {
                // Roll the bounded current-and-next-month plan forward while the app stays open.
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(3600)) } catch { return }
                    schedules.maintainSchedulingHorizon()
                }
            }
            .alert("ScheduleRsync", isPresented: Binding(
                get: { status.message != nil },
                set: { if !$0 { status.message = nil } }
            ), presenting: status.message) { _ in
                Button("OK") { status.message = nil }
            } message: { message in Text(message) }
        }
        .defaultSize(width: 1000, height: 700)
        MenuBarExtra("ScheduleRsync", systemImage: "calendar.badge.clock") {
            ScheduleMenu()
        }
    }
}

private struct ScheduleMenu: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(GlobalTimer.shared.nextScheduleDate() ?? "No upcoming schedules")
        Button("Show schedules") { openWindow(id: "main"); NSApplication.shared.activate() }
        Divider()
        Button("Quit ScheduleRsync") { NSApplication.shared.terminate(nil) }
    }
}
