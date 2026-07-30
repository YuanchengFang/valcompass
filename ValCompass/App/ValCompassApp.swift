import SwiftUI

@main
struct ValCompassApp: App {
    @State private var repository = MarketRepository()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // 调试入口：xcrun simctl launch booted app.valcompass.ios -debugDetail sh510300
            if let id = debugDetailID, let target = TargetCatalog.target(id: id) {
                NavigationStack {
                    TargetDetailView(target: target)
                }
                .environment(repository)
                .task { repository.start() }
            } else {
                root
            }
            #else
            root
            #endif
        }
    }

    private var root: some View {
        ContentView()
            .environment(repository)
            .task { repository.start() }
    }

    #if DEBUG
    private var debugDetailID: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-debugDetail"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
    #endif
}
