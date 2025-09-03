import Foundation

// Marca temporal relativa (s desde el inicio).
public struct TimedSample<T: Codable & Sendable>: Codable, Sendable {
    public let t: TimeInterval
    public let v: T
    public init(t: TimeInterval, v: T) {
        self.t = t
        self.v = v
    }
}

// Punto de ruta opcional (si decides enviar la ruta en JSON).
public struct LocationPoint: Codable, Sendable {
    public let lat: Double
    public let lon: Double
    public let alt: Double?
    public let t: TimeInterval? // offset en s desde start
    public init(lat: Double, lon: Double, alt: Double? = nil, t: TimeInterval? = nil) {
        self.lat = lat
        self.lon = lon
        self.alt = alt
        self.t = t
    }
}

// NUEVO: split por kilómetro
public struct KilometerSplit: Codable, Sendable {
    public let index: Int                 // 1-based
    public let startOffset: TimeInterval  // s desde start
    public let endOffset: TimeInterval    // s desde start
    public let duration: TimeInterval     // end - start
    public let distanceMeters: Double     // ~1000m (puede variar)
    public let avgHR: Double?             // ppm
    public let avgSpeed: Double?          // m/s
    public init(index: Int,
                startOffset: TimeInterval,
                endOffset: TimeInterval,
                duration: TimeInterval,
                distanceMeters: Double,
                avgHR: Double?,
                avgSpeed: Double?) {
        self.index = index
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.avgHR = avgHR
        self.avgSpeed = avgSpeed
    }
}

// Payload principal que enviaremos del Watch al iPhone al finalizar el workout.
public struct WorkoutPayload: Codable, Sendable {
    // Propiedades
    public let schemaVersion: Int
    public let id: UUID
    public let sport: String?
    public let start: Date
    public let end: Date
    public let duration: TimeInterval
    public let distanceMeters: Double?
    public let totalEnergyKcal: Double?
    public let avgHR: Double?
    public let hrSeries: [TimedSample<Double>]?
    public let paceSeries: [TimedSample<Double>]?
    public let elevationSeries: [TimedSample<Double>]?
    public let totalAscent: Double?
    public let route: [LocationPoint]?
    public let kmSplits: [KilometerSplit]?   // NUEVO

    // Init
    public init(
        schemaVersion: Int = 2,              // subimos versión de esquema por los splits
        id: UUID = UUID(),
        sport: String? = "running",
        start: Date,
        end: Date,
        duration: TimeInterval,
        distanceMeters: Double? = nil,
        totalEnergyKcal: Double? = nil,
        avgHR: Double? = nil,
        hrSeries: [TimedSample<Double>]? = nil,
        paceSeries: [TimedSample<Double>]? = nil,
        elevationSeries: [TimedSample<Double>]? = nil,
        totalAscent: Double? = nil,
        route: [LocationPoint]? = nil,
        kmSplits: [KilometerSplit]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.sport = sport
        self.start = start
        self.end = end
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.totalEnergyKcal = totalEnergyKcal
        self.avgHR = avgHR
        self.hrSeries = hrSeries
        self.paceSeries = paceSeries
        self.elevationSeries = elevationSeries
        self.totalAscent = totalAscent
        self.route = route
        self.kmSplits = kmSplits
    }
}

public extension WorkoutPayload {
    // Claves de metadata para transferFile
    static let metadataTypeKey = "type"
    static let metadataTypeValue = "workout"
    static let metadataIDKey = "id"

    /// Metadata estándar para WCSession.transferFile(_:metadata:)
    func makeTransferMetadata() -> [String: Any] {
        [
            Self.metadataTypeKey: Self.metadataTypeValue,
            Self.metadataIDKey: id.uuidString
        ]
    }
}

/// Utilidades de codificación/decodificación y escritura a fichero temporal.
public enum WorkoutPayloadIO {
    /// URL temporal donde guardamos el JSON antes de transferirlo.
    public static func temporaryURL(for id: UUID) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Codifica y escribe el payload en JSON con fechas en milisegundos (compacto).
    @discardableResult
    public static func write(_ payload: WorkoutPayload) throws -> URL {
        let url = temporaryURL(for: payload.id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(payload)
        try data.write(to: url, options: [.atomic])
        return url
    }

    /// Lee y decodifica un payload desde un archivo JSON.
    public static func read(from url: URL) throws -> WorkoutPayload {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(WorkoutPayload.self, from: data)
    }
}
