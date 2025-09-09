import Foundation
import SwiftUI
import Combine
import CoreLocation
import HealthKit

final class RunningLiveManager: NSObject, ObservableObject {
    // Public to UI
    @Published var isRunning = false
    @Published var distanceMeters: Double = 0
    @Published var elapsed: TimeInterval = 0
    @Published var lastLocation: CLLocation?
    @Published var currentHeartRate: Double?   // (sin Watch no habrá HR; lo dejamos por compatibilidad)

    // Preferences
    var useMiles = false

    // Infra
    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var locations: [CLLocation] = []
    private var timer: Timer?
    private var startDate: Date?

    // MARK: - Authorization
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let toShare: Set = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        let toRead: Set = [
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)! // HR en iOS sin Watch no está en vivo
        ]
        try await healthStore.requestAuthorization(toShare: toShare, read: toRead)
    }

    // MARK: - Session control
    func start() {
        // Location
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.distanceFilter = 5
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true

        // Ask permissions (WhenInUse -> Always)
        locationManager.requestWhenInUseAuthorization()
        if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
        locationManager.startUpdatingLocation()

        // Route builder for Health
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())

        // Time
        startDate = Date()
        startTimer()
        isRunning = true
    }

    func pause() {
        stopTimer()
        isRunning = false
    }

    func resume() {
        startTimer()
        isRunning = true
    }

    func end(completion: @escaping (HKWorkout?) -> Void) {
        stopTimer()
        locationManager.stopUpdatingLocation()
        isRunning = false

        guard let start = startDate else {
            completion(nil); return
        }
        let end = Date()

        // Crea y guarda el workout en Health
        let workout = HKWorkout(activityType: .running, start: start, end: end)

        healthStore.save(workout) { [weak self] ok, _ in
            guard let self = self, ok else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Añade sample de distancia total (opcional pero útil)
            if let distType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
                let qty = HKQuantity(unit: .meter(), doubleValue: self.distanceMeters)
                let sample = HKQuantitySample(type: distType, quantity: qty, start: start, end: end)
                self.healthStore.add([sample], to: workout) { _, _ in }
            }

            // Finaliza la ruta y la asocia al workout
            // Después (OK):
            self.routeBuilder?.finishRoute(with: workout, metadata: nil) { _, _ in
                DispatchQueue.main.async { completion(workout) }
            }
            self.routeBuilder = nil
        }
    }

    // MARK: - Helpers
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let s = self, let start = s.startDate else { return }
            s.elapsed = Date().timeIntervalSince(start)
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    var distanceFormatted: String {
        if useMiles {
            let mi = (distanceMeters / 1000.0) / 1.60934
            return String(format: "%.2f mi", mi)
        } else {
            let km = distanceMeters / 1000.0
            return String(format: "%.2f km", km)
        }
    }

    var paceFormatted: String {
        let km = max(distanceMeters / 1000.0, 0.001)
        let secPerKm = elapsed / km
        let m = Int(secPerKm) / 60
        let s = Int(secPerKm) % 60
        return String(format: "%d:%02d min/%@", m, s, useMiles ? "mi" : "km")
    }
}

// MARK: - CLLocationManagerDelegate
extension RunningLiveManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations new: [CLLocation]) {
        guard isRunning else { return }
        let valid = new.filter { $0.horizontalAccuracy > 0 && $0.horizontalAccuracy < 25 }
        guard !valid.isEmpty else { return }

        for loc in valid {
            if let last = lastLocation {
                distanceMeters += loc.distance(from: last)
            }
            lastLocation = loc
        }
        locations.append(contentsOf: valid)

        // ✅ Firma correcta: (Bool, Error?) -> Void
        routeBuilder?.insertRouteData(valid) { _, _ in }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }
}

import CoreLocation

extension RunningLiveManager {
    /// Devuelve la ruta codificada como Google Encoded Polyline (o nil si no hay datos)
    func exportedPolyline() -> String? {
        guard !locations.isEmpty else { return nil }
        let coords = locations.map { $0.coordinate }
        return Polyline.encode(coords)
    }
}

/// Helper para codificar/decodificar polylines (Google Encoded Polyline)
enum Polyline {
    static func encode(_ coords: [CLLocationCoordinate2D]) -> String {
        guard !coords.isEmpty else { return "" }
        var lastLat = 0, lastLon = 0
        var out = ""
        for c in coords {
            let lat = Int(round(c.latitude * 1e5))
            let lon = Int(round(c.longitude * 1e5))
            out += encodeDelta(lat - lastLat)
            out += encodeDelta(lon - lastLon)
            lastLat = lat
            lastLon = lon
        }
        return out
    }

    private static func encodeDelta(_ delta: Int) -> String {
        var v = delta << 1
        if delta < 0 { v = ~v }
        var chunk = ""
        while v >= 0x20 {
            let c = (0x20 | (v & 0x1f)) + 63
            chunk.append(Character(UnicodeScalar(c)!))
            v >>= 5
        }
        chunk.append(Character(UnicodeScalar(v + 63)!))
        return chunk
    }

    // (Opcional) para reconstruir y dibujar la ruta después
    static func decode(_ str: String) -> [CLLocationCoordinate2D] {
        let bytes = Array(str.utf8)
        var idx = 0
        var lat = 0, lon = 0
        var coords: [CLLocationCoordinate2D] = []

        func nextValue() -> Int {
            var result = 0, shift = 0, b = 0
            repeat {
                b = Int(bytes[idx]) - 63; idx += 1
                result |= (b & 0x1f) << shift
                shift += 5
            } while b >= 0x20 && idx < bytes.count
            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }

        while idx < bytes.count {
            lat += nextValue()
            guard idx < bytes.count else { break }
            lon += nextValue()
            coords.append(.init(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5))
        }
        return coords
    }
}

