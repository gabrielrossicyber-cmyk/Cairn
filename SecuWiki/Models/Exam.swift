import Foundation

/// Résultat d'un examen blanc, gardé dans .secuwiki.json (historique par wiki, synchronisé par iCloud).
struct ExamResult: Codable, Equatable, Identifiable {
    var id = UUID()
    var date: Date
    /// Périmètre : « Tout le wiki », un dossier, un #tag.
    var scope: String
    var points: Double
    var total: Int
    var durationSeconds: Int

    var grade: Double { ExamGrading.swissGrade(points: points, total: total) }
}

/// Barème suisse : note = 1 + 5 × (points / maximum), arrondie au demi-point. Réussi dès 4.
enum ExamGrading {
    static let passingGrade = 4.0

    static func swissGrade(points: Double, total: Int) -> Double {
        guard total > 0 else { return 1 }
        let raw = 1 + 5 * max(0, min(points, Double(total))) / Double(total)
        return (raw * 2).rounded() / 2
    }

    static func format(_ grade: Double) -> String {
        grade.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", grade) : String(format: "%.1f", grade)
    }
}
