//
//  ExerciseThumbnail.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 8/19/25.
//
import SwiftUI

struct ExerciseThumbnail: View {
    let base64: String?

    var body: some View {
        Group {
            if let base64,
               let data = Data(base64Encoded: base64),
               let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                Image(systemName: "photo")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
            }
        }
        .frame(width: 40, height: 40)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

