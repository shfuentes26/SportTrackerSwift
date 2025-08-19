//
//  ExercisesListScreen.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/19/25.
//

import SwiftUI

struct ExercisesListScreen: View {
    @StateObject private var store = ExercisesStore()

    var body: some View {
        NavigationStack {
            ExercisesListView()      // usa tu vista existente
                .navigationTitle("Exercises")
        }
    }
}
