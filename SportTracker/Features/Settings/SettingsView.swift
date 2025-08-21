import SwiftUI
import SwiftData
import HealthKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [Settings]
    
    @State private var isImporting = false
    @State private var importResult: String?
    @State private var showImportAlert = false

    // crea si no existe
    private func ensureSettings() -> Settings {
        if let s = settingsList.first { return s }
        let s = Settings()
        context.insert(s)
        try? context.save()
        return s
    }

    var body: some View {
        let s = ensureSettings()              // siempre tendremos uno
        @Bindable var sb = s                  // para editarlo con bindings

        Form {
            // HealthKit manual import
            Section(header: Text("Integrations")) {
                Button {
                    Task { await importFromAppleHealth() }
                } label: {
                    if isImporting {
                        ProgressView()
                    } else {
                        Text("Import from Apple Health")
                    }
                }
                .disabled(isImporting)

                Text("Last import: \(HealthKitManager.shared.lastImportDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // Nueva opción de Exercises
            Section {
                NavigationLink("Manage trainings") { ExercisesListScreen() }
            }

            Section("Units") {
                Toggle("Show miles (min/mi)", isOn: $sb.prefersMiles)
                Toggle("Show pounds (lb)",    isOn: $sb.prefersPounds)
            }
        }
        .navigationTitle("Settings")
        .alert("Import", isPresented: $showImportAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(importResult ?? "Operation completed")
                }
        .brandHeaderSpacer()
    }
    
    private func importFromAppleHealth() async {
        isImporting = true
        defer { isImporting = false }
        
        guard HKHealthStore.isHealthDataAvailable() else {
            importResult = "Health no disponible (este dispositivo no permite HealthKit)."
            showImportAlert = true
            return
        }

        let hs = HKHealthStore()
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        ]

        do {
            try await hs.requestAuthorization(toShare: [], read: readTypes)
            // OJO: si no tienes la capability "HealthKit" en el target, esta llamada falla.
            print("[HK][AUTH] OK (read: workouts + distanceWalkingRunning)")
        } catch {
            print("[HK][AUTH][ERR] \(error)")
        }
        
        do {
            try await HealthKitManager.shared.requestAuthorization()
            
            await debugDumpRecentWorkouts(daysBack: 365*3)
            await debugFetchAnyWorkouts(limit: 10)
            await debugCountDistanceSamples(daysBack: 30)
            await debugListWorkoutSources()
            
            let newWk = try await HealthKitManager.shared.fetchNewWorkouts()
            print("[HK] fetchNewWorkouts -> recibidos: \(newWk.count)")    // <-- AÑADIR
            
            // En lugar de fetchNewWorkouts():
            let all = try await debugFetchAllRunningWorkouts(since: Calendar.current.date(byAdding: .year, value: -3, to: Date())!)
            print("[HK][DEBUG] allRunning last 3y: \(all.count)")
            
            let supported = HealthKitManager.shared.filterSupported(newWk)
            print("[HK] filterSupported -> soportados: \(supported.count)") // <-- AÑADIR
            
            // Opcional: inspecciona los primeros 5 para ver qué traen
            for (i, wk) in supported.prefix(5).enumerated() {
                let dist = wk.distanceMeters ?? -1
                print("[HK] supported[\(i)] activity=\(wk.activity) dist=\(dist) start=\(wk.start) dur=\(wk.durationSec)")
            }
            
            // map to sessions and save
            let inserted = try await HealthKitImportService.saveToLocal(supported, context: context)
            HealthKitManager.shared.markImported()
            importResult = "Importados \(inserted) entrenamientos."
        } catch {
            importResult = "Error: \(error.localizedDescription)"
        }
        showImportAlert = true
    }
    
    func debugFetchAllRunningWorkouts(since start: Date) async throws -> [HKWorkout] {
        let healthStore = HKHealthStore()
        let workoutType = HKObjectType.workoutType()
        let predType = HKQuery.predicateForWorkouts(with: .running)
        let predDate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predType, predDate])

        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: workoutType,
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            healthStore.execute(q)
        }
    }
    
    func debugDumpRecentWorkouts(daysBack: Int = 30) async {
        let hs = HKHealthStore()
        let workoutType = HKObjectType.workoutType()
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])

        await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: workoutType, predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    print("[HK][DUMP][ERR] \(error)")
                    cont.resume()
                    return
                }
                let wks = (samples as? [HKWorkout]) ?? []
                print("[HK][DUMP] total workouts ultimos \(daysBack)d: \(wks.count)")
                var byType: [HKWorkoutActivityType:Int] = [:]
                for w in wks {
                    byType[w.workoutActivityType, default: 0] += 1
                }
                for (t,cnt) in byType.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                    print("[HK][DUMP] type=\(t) count=\(cnt)")
                }
                // Muestra algunos ejemplos
                for (i,w) in wks.prefix(5).enumerated() {
                    print("[HK][DUMP][\(i)] type=\(w.workoutActivityType) start=\(w.startDate) dur=\(w.duration/60)min totalDist=\(w.totalDistance?.doubleValue(for: .meter()) ?? -1)")
                }
                cont.resume()
            }
            hs.execute(q)
        }
    }
    
    func debugFetchAnyWorkouts(limit: Int = 10) async {
        let hs = HKHealthStore()
        let workoutType = HKObjectType.workoutType()
        await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: workoutType,
                                  predicate: nil, // <-- sin fechas, sin filtros
                                  limit: limit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error = error { print("[HK][ANY][ERR] \(error)"); cont.resume(); return }
                let wks = (samples as? [HKWorkout]) ?? []
                print("[HK][ANY] últimos \(limit) workouts: \(wks.count)")
                for (i,w) in wks.enumerated() {
                    print("[HK][ANY][\(i)] type=\(w.workoutActivityType) start=\(w.startDate) dur=\(Int(w.duration/60))min dist=\(w.totalDistance?.doubleValue(for: .meter()) ?? -1)")
                }
                cont.resume()
            }
            hs.execute(q)
        }
    }
    
    func debugCountDistanceSamples(daysBack: Int = 30) async {
        let hs = HKHealthStore()
        guard let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else { return }
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        let pred = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: distType, predicate: pred,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error { print("[HK][DIST][ERR] \(error)"); cont.resume(); return }
                print("[HK][DIST] muestras distancia (últimos \(daysBack)d): \((samples ?? []).count)")
                cont.resume()
            }
            hs.execute(q)
        }
    }
    
    func debugListWorkoutSources() async {
        let hs = HKHealthStore()
        let workoutType = HKObjectType.workoutType()
        await withCheckedContinuation { cont in
            let q = HKSourceQuery(sampleType: workoutType, samplePredicate: nil) { _, sources, error in
                if let error = error { print("[HK][SRC][ERR] \(error)"); cont.resume(); return }
                let srcs = sources ?? []
                print("[HK][SRC] fuentes de workouts: \(srcs.count)")
                for s in srcs { print("[HK][SRC] \(s.name) bundle=\(s.bundleIdentifier)") }
                cont.resume()
            }
            hs.execute(q)
        }
    }
}
