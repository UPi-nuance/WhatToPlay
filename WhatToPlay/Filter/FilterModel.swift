//
//  FilterModel.swift
//  WhatToPlay
//
//  Created by Ryan LaSante on 2/18/19.
//  Copyright © 2019 rlasante. All rights reserved.
//

import Foundation

protocol FilterModel {
    /// Returns true if we should keep the game, false if it should be filtered out
    func filter(_ game: Game) -> Bool
}

/// Simple Base Filter that requires no configuration
struct SimpleFilter: FilterModel {
    private let _filter: (Game) -> Bool
    init(filter: @escaping (Game) -> Bool) {
        self._filter = filter
    }

    func filter(_ game: Game) -> Bool {
        return _filter(game)
    }
}
