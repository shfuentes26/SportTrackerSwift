//
//  ExercisesListViewModel.swift
//  SportTracker
//
//  Created by ChatGPT on 8/24/25.
//

import Foundation
import SwiftUI

/// A simple view model to drive ``ExercisesListView``.
///
/// This type encapsulates the state for the search text and the
/// currently selected muscle group. It also exposes a method to
/// filter a list of exercises based on those properties. Moving
/// this state and filtering logic out of the view makes the view
/// itself simpler and adheres to the MVVM pattern.
@MainActor
final class ExercisesListViewModel: ObservableObject {

    /// The current search string. Updating this value will automatically
    /// refresh any views bound to it thanks to the ``@Published`` property
    /// wrapper.
    @Published var search: String = ""

    /// The currently selected muscle group. A value of `nil` represents
    /// the "All" category.
    @Published var selected: MuscleGroup? = nil

    /// Returns a filtered array of ``Exercise`` values based on the current
    /// ``search`` and ``selected`` values.
    ///
    /// - Parameter allExercises: The complete list of exercises to filter.
    /// - Returns: A new array containing only those exercises that match
    ///   the current search string and selected muscle group.
    func filteredExercises(from allExercises: [Exercise]) -> [Exercise] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return allExercises.filter { ex in
            // When a specific category is selected, ensure the exercise
            // belongs to that category. Otherwise accept all.
            let categoryMatches: Bool
            if let sel = selected {
                categoryMatches = ex.muscleGroup == sel
            } else {
                categoryMatches = true
            }
            // When the search string is empty, accept all names; otherwise
            // perform a case‑insensitive substring search.
            let nameMatches: Bool
            if trimmed.isEmpty {
                nameMatches = true
            } else {
                nameMatches = ex.name.localizedCaseInsensitiveContains(trimmed)
            }
            return categoryMatches && nameMatches
        }
    }
}
