import SwiftUI
import UniformTypeIdentifiers

@main
struct PulseApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(.strainBlue)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView {
            TodayView()
                .tabItem { Label("Heute", systemImage: "heart.text.square") }
            SleepView()
                .tabItem { Label("Schlaf", systemImage: "bed.double") }
            StrainView()
                .tabItem { Label("Belastung", systemImage: "flame") }
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
        }
        .task {
            if model.state == .idle { await model.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, model.dataSource == .healthKit, !model.isBusy,
                  let last = model.lastUpdated, Date.now.timeIntervalSince(last) > 15 * 60 else { return }
            Task { await model.refresh() }
        }
        .fileImporter(isPresented: $model.showImporter, allowedContentTypes: [.zip, .xml]) { result in
            if case .success(let url) = result {
                Task { await model.importExport(from: url) }
            }
        }
        .onOpenURL { url in
            Task { await model.importExport(from: url) }
        }
    }
}
