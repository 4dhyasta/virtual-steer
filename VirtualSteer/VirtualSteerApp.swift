import SwiftUI

@main
struct VirtualSteerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @ObservedObject private var hub = Hub.shared

    var body: some View {
        ZStack(alignment: .top) {
            Surface().ignoresSafeArea()
            if !hub.connected {
                Text("Nunggu PC lewat kabel...")
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

// Muncul kalau gear up + gear down ditahan barengan 1,2 detik.
struct SettingsView: View {
    @AppStorage("range") private var range = 90.0
    @AppStorage("invert") private var invert = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Putaran HP buat full lock: \(Int(range))°") {
                Slider(value: $range, in: 30...360, step: 5)
            }
            Toggle("Balik arah belok", isOn: $invert)
            Button("Center ulang setir") { Hub.shared.recenter(); dismiss() }
            Button("Selesai") { dismiss() }
        }
    }
}
