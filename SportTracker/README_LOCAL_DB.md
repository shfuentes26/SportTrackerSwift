# Local DB Add-on (SwiftData)

Copia estos archivos dentro de tu proyecto `SportTracker`:

- `Models.swift`: entidades SwiftData (UserProfile, Settings, Exercise, StrengthSet, StrengthSession, RunningSession) + enums.
- `PointsCalculator.swift`: lógica de puntuación para Running y Gym.
- `Persistence.swift`: crea el `ModelContainer` y hace *seeding* de datos básicos.
- `SportTrackerApp.swift`: reemplaza tu archivo `...App.swift` para inyectar el `modelContainer`.

> Requisitos: iOS 17+ / Xcode 15+ (SwiftData).
