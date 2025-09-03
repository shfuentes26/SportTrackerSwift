import SwiftUI

enum TrainingItem {
    case running(RunningSession)
    case gym(StrengthSession)
}

struct TrainingDetailView: View {
    let item: TrainingItem

    var body: some View {
        switch item {
        case .running(let s):
            RunningSessionDetail(session: s)
        case .gym(let s):
            GymSessionDetail(session: s)
        }
    }
}

// Compat: constructores de conveniencia
extension TrainingDetailView {
    init(session: RunningSession)  { self.init(item: .running(session)) }
    init(session: StrengthSession) { self.init(item: .gym(session)) }
}
