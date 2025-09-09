import Foundation
import SwiftData

#if os(iOS)
enum PersistenceDiagnostics {
    @MainActor
    static func dumpInitialStats(using container: ModelContainer, tag: String = "BOOT") {
        let cx = container.mainContext
        print("[DIAG][\(tag)] useICloudSync =", cx.hasChanges)
        let useCloud = UserDefaults.standard.bool(forKey: "useICloudSync")
        print("[DIAG][\(tag)] useICloudSync =", useCloud)
        do {
            let runs: [RunningSession] = try cx.fetch(FetchDescriptor<RunningSession>())
            let gyms: [StrengthSession] = try cx.fetch(FetchDescriptor<StrengthSession>())
            let exs:  [Exercise]        = try cx.fetch(FetchDescriptor<Exercise>())
            print("[DIAG][\(tag)] counts → Runs:", runs.count, "Gyms:", gyms.count, "Exercises:", exs.count)
        } catch {
            print("[DIAG][\(tag)][WARN] fetch failed:", error.localizedDescription)
        }
    }

    // 🔎 Nueva: sonda que imprime solo cuando cambian los conteos
    @MainActor
    static func startLiveProbe(using container: ModelContainer, seconds: Int = 30) {
        let cx = container.mainContext
        var last = (-1, -1, -1) // (runs, gyms, exs)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            do {
                let runs = try cx.fetch(FetchDescriptor<RunningSession>()).count
                let gyms = try cx.fetch(FetchDescriptor<StrengthSession>()).count
                let exs  = try cx.fetch(FetchDescriptor<Exercise>()).count
                let cur = (runs, gyms, exs)
                if cur != last {
                    print("[DIAG][LIVE] counts → Runs:", runs, "Gyms:", gyms, "Exercises:", exs)
                    last = cur
                }
            } catch {
                print("[DIAG][LIVE][WARN] fetch failed:", error.localizedDescription)
            }
        }
        // Auto-stop tras N segundos
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
            print("[DIAG][LIVE] stop")
        }
    }
}
#endif
