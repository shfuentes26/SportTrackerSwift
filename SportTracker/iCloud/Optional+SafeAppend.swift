//
//  Optional+SafeAppend.swift
//  SportTracker
//
//  Created by Satur Hernandez Fuentes on 9/5/25.
//
extension Optional where Wrapped: RangeReplaceableCollection {
    mutating func safeAppend(_ newElement: Wrapped.Element) {
        if self == nil { self = Wrapped() }
        self!.append(newElement)
    }
}

