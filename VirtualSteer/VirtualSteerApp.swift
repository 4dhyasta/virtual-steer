import SwiftUI

@main
struct VirtualSteerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @ObservedObject private var hub = Hub.shared
    @AppStorage("layout") private var layout = 1

    var body: some View {
        ZStack(alignment: .top) {
            Surface(layout: layout, paused: hub.showSettings).ignoresSafeArea()
            if !hub.connected {
                Text("Waiting for PC over USB...")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.top, 10)
                    .allowsHitTesting(false)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .all)
        .sheet(isPresented: $hub.showSettings) { SettingsView() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            Hub.shared.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Hub.shared.start(force: true)
        }
    }
}

// Opens when both gear buttons are held together for 1.2 seconds.
struct SettingsView: View {
    @AppStorage("layout") private var layout = 1
    @AppStorage("range") private var gyroRange = 90.0
    @AppStorage("invert") private var invert = false
    @AppStorage("wheelRange") private var wheelRange = 120.0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Layout") {
                    Picker("Layout", selection: $layout) {
                        Text("1 - Columns + gyro").tag(1)
                        Text("2 - On-screen wheel").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Gyro steering (layout 1): \(Int(gyroRange))° for full lock") {
                    Slider(value: $gyroRange, in: 30...360, step: 5)
                    Toggle("Reverse direction", isOn: $invert)
                    Button("Recenter gyro") { Hub.shared.recenter(); dismiss() }
                }
                Section("Wheel rotation (layout 2): \(Int(wheelRange))° for full lock") {
                    Slider(value: $wheelRange, in: 45...360, step: 5)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
