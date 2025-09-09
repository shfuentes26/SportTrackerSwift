import SwiftUI

struct ExerciseHeroImage: View {
    let name: String
    let group: MuscleGroup

    var body: some View {
        // 1) intentamos mapear por nombre del ejercicio
        if let asset = muscleAsset(for: name) {
            muscleImage(asset)
        } else {
            // 2) fallback por grupo (Core/Chest-Back/Arms/Legs)
            muscleImage(defaultAsset(for: group))
        }
    }

    // Imagen con estilo unificado
    private func muscleImage(_ asset: String) -> some View {
        Image(asset)
            .resizable()
            .scaledToFit()
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Mapping

private func muscleAsset(for rawName: String) -> String? {
    // normalize
    let n = rawName
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .replacingOccurrences(of: "-", with: " ")
        .lowercased()

    // Helper: regex contains with word boundaries
    func has(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern, options: []))?
            .firstMatch(in: n, options: [], range: NSRange(location: 0, length: n.utf16.count)) != nil
    }

    // ---- Specific patterns FIRST (order matters) ----
    // QUADRICEPS
    if has(#"\bleg\s+extension(s)?\b"#) ||
       has(#"\bextension(es)?\s+de\s+cuadr(í|i)ceps\b"#) ||
       has(#"\bleg\s+press\b"#) || has(#"\bprensa\s+de\s+piernas\b"#) ||
       has(#"\b(front\s+)?squat(s)?\b"#) || has(#"\b(zancad(as)?|lunge(s)?)\b"#) ||
       has(#"\bquadricep(s)?\b"#) {
        return "muscle_quadriceps"
    }

    // LATS / BACK
    if has(#"\b(lat\s*pull( |-)?down|dominad(as)?|pull-?up(s)?)\b"#) ||
       has(#"\b(row|remad(a|as))\b"#) ||
       has(#"\b(back|espalda)\b"#) {
        return "muscle_back_lats"
    }

    // TRAPEZIUS
    if has(#"\b(shrug(s)?|trap(ezius)?|trapezio)\b"#) { return "muscle_trapezius" }

    // SHOULDERS / DELTOIDS
    if has(#"\b(shoulder|deltoid(s)?)\b"#) ||
       has(#"\b(overhead|military)\s+press\b"#) ||
       has(#"\b(lateral|front)\s+raise(s)?\b"#) {
        return "muscle_shoulders_deltoids"
    }

    // TRICEPS (NOTE: no generic 'extension' here)
    if has(#"\btricep(s)?\b"#) ||
       has(#"\btriceps?\s+extension\b"#) ||
       has(#"\boverhead\s+extension\b"#) ||
       has(#"\b(skull\s*crusher|pressdown|pushdown|dip(s)?)\b"#) {
        return "muscle_triceps"
    }

    // BICEPS (kept conservative so it doesn't catch hamstring curl)
    if has(#"\bbicep(s)?\b"#) ||
       has(#"\bbiceps?\s+curl(s)?\b"#) ||
       has(#"\bdumbbell\s+curl(s)?\b"#) {
        return "muscle_triceps" // usamos la misma imagen que acordamos
    }

    // CALVES
    if has(#"\b(calf|calves|gemelo(s)?)\b"#) ||
       has(#"\b(calf|heel)\s+raise(s)?\b"#) {
        return "muscle_calves"
    }

    // GLUTES
    if has(#"\b(glute(s)?|gl(ú|u)teo(s)?)\b"#) ||
       has(#"\b(hip\s+thrust|glute\s+bridge|hip\s+bridge)\b"#) {
        return "muscle_glutes"
    }

    // ABS / CORE
    if has(#"\b(ab(s)?|core|crunch(es)?|sit[-\s]?up(s)?|plank)\b"#) {
        return "muscle_abs"
    }

    // CHEST (no generic 'press'; require bench/chest variants)
    if has(#"\b(bench|chest)\s+press\b"#) ||
       has(#"\bincline\s+press\b"#) ||
       has(#"\b(push[-\s]?up(s)?)\b"#) ||
       has(#"\b(chest\s+fly|pec\s+fly)\b"#) ||
       has(#"\bpecho|banca\b"#) {
        return "muscle_chest"
    }

    return nil // fall back to group-based defaultAsset(...)
}

private func defaultAsset(for g: MuscleGroup) -> String {
    switch g {
    case .core:       return "muscle_abs"
    case .chestBack:  return "muscle_chest"        // por defecto, pecho (si quieres, cámbialo a lats)
    case .arms:       return "muscle_triceps"
    case .legs:       return "muscle_quadriceps"
    @unknown default: return "muscle_chest"
    }
}
