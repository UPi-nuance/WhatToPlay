//
//  BoardGameGeekAPI.swift
//  WhatToPlay
//
//  Created by Ryan LaSante on 6/25/17.
//  Copyright © 2017 rlasante. All rights reserved.
//

import CoreData
import UIKit
import Alamofire
import SWXMLHash
import PMKAlamofire
import PromiseKit

enum APIError: Error {
    case noGames
    case noUser
    case tryAgain
}

class BoardGameGeekAPI {

    static let useMockData = false

    static let baseURL = "https://www.boardgamegeek.com/xmlapi2"

    static let gamesSessionManager: SessionManager = {
        let sessionConfiguration = URLSessionConfiguration.default

        let gamesSession = Alamofire.SessionManager(configuration: sessionConfiguration)
        gamesSession.adapter = GamesAdapter()
        gamesSession.retrier = BGGRetrier()
        return gamesSession
    }()

    static let bggSessionManager: SessionManager = {
        let sessionConfiguration = URLSessionConfiguration.default

        let session = Alamofire.SessionManager(configuration: sessionConfiguration)
        session.retrier = BGGRetrier()
        return session
    }()

    class func attempt<T>(maximumRetryCount: Int = 3, delayBeforeRetry: DispatchTimeInterval = .seconds(2), _ body: @escaping () -> Promise<T>) -> Promise<T> {
        var attempts = 0
        func attempt() -> Promise<T> {
            attempts += 1
            return body().recover { error -> Promise<T> in
                guard attempts < maximumRetryCount else { throw error }
                return after(delayBeforeRetry).then(on: nil, attempt)
            }
        }
        return attempt()
    }

//    class func getUser(userName: String, context: NSManagedObjectContext) -> Promise<User> {
//        return attempt { Void -> String
//            let url = "\(baseURL)/user?name=\(userName)&top=1"
//            print("[GetUser] Performing Request: \(url)")
//            return bggSessionManager.request(url)
//            .responseString()
//            .map { xmlString, dataResponse -> String in
//                guard !dataResponse.response.statusCode else {
//                    print("[API]: Retrying fetching user")
//                    throw APIError.tryAgain
//                }
//                return xmlString
//            }
//        }.map(on: .main) { xmlString -> User in
//            let xml = SWXMLHash.lazy(xmlString)
//            guard let userData: UserXMLData = xml["user"].value()
//                throw APIError.noUser
//            }
//            return User(data: userData, in: context)
//        }
//    }

    class func getCollection(userName: String, context: NSManagedObjectContext) -> Promise<[Game]> {
//        if useMockData, let mockCollectionData = mockCollectionData {
//            print("[Collection] Using Mock Collection")
//            handleResponse(xmlString: mockCollectionData)
//        }
        return attempt { () -> Promise<String> in
            let url = "\(baseURL)/collection?username=\(userName)&own=1"
            print("\(#function) Performing Request: \(url)")
            return bggSessionManager.request(url)
            .responseString()
            .tap { _ in print("[API]: Fetched Collection") }
            .map { xmlString, dataResponse in
                guard !dataResponse.response.shouldRetryRequest else {
                    print("[API]: Retrying fetching Collection")
                    throw APIError.tryAgain
                }
                return xmlString
            }
        }.map { xmlString -> [String] in
            let xml = SWXMLHash.parse(xmlString)
            let nodes = xml["items"].children
            let gameIds = nodes.compactMap { node -> String? in
                guard
                    let objectType: String = node.value(ofAttribute: "objecttype".lowercased()),
                    objectType == "thing".lowercased(),
                    let subType: String = node.value(ofAttribute: "subtype".lowercased()),
                    subType == "boardgame".lowercased()
                else { return nil }
                let gameId: String? = node.value(ofAttribute: "objectid".lowercased())
                return gameId
            }
            return gameIds
        }.tap {
            print("Game Ids to fetch: \($0)")
        }.then { gameIds -> Promise<[Game]> in
            getBoardGames(gameIds: gameIds, context: context)
        }
    }

    class func getBoardGame(gameId: String, context: NSManagedObjectContext) -> Promise<Game> {
        return getBoardGames(gameIds: [gameId], context: context).firstValue
    }

    class func getBoardGames(gameIds: [String], context: NSManagedObjectContext) -> Promise<[Game]> {
//        if useMockData, let mockData = mockGameData {
//            print("[Games] Using mock games")
//            handleResponse(xmlString: mockData)
//        }
        // first we want to see if we have the games locally
        let localGames: [Game] = (try? context.fetch(Game.fetchRequest(forIds: gameIds))) ?? []
        let gameIds = gameIds.filter { id in
            !localGames.contains { $0.gameId == id }
        }
        if gameIds.isEmpty {
            return Promise<[Game]>.value(localGames)
        }
        return attempt { () -> Promise<String> in
            let url = "\(baseURL)/thing?id=\(gameIds.joined(separator: ","))&type=boardgame&stats=1"
            print("\(#function) Performing Request: \(url)")
            return gamesSessionManager.request(url)
            .responseString()
            .tap { _ in print("[API]: Got Board Games") }
            .map { xmlString, dataResponse -> String in
                guard !dataResponse.response.shouldRetryRequest else {
                    print("[API]: Retrying Fetching Board Games")
                    throw APIError.tryAgain
                }
                return xmlString
            }
        }.map(on: .main) { xmlString -> [Game] in
            let xml = SWXMLHash.parse(xmlString)
            // TODO figure out a way to store the data so that way we will have it when I add new properties
            let gamesData: [GameXMLData] = try xml["items"]["item"].all.map { try $0.value() }

            let games = gamesData.map { Game(data: $0, in: context)}
            _ = try? context.save()
            let allSortedGames = [games, localGames].flatMap { $0 }.sorted { $0.name ?? "" < $1.name ?? "" }
            guard !allSortedGames.isEmpty else {
                throw APIError.noGames
            }
            if !gameIds.isEmpty {
                print("Missing the following ids: \(gameIds)")
            }
            return allSortedGames
        }
    }

    private class GamesAdapter: RequestAdapter {
        func adapt(_ urlRequest: URLRequest) throws -> URLRequest {
            var urlRequest = urlRequest
            urlRequest.cachePolicy = .returnCacheDataElseLoad
            return urlRequest
        }
    }

    private class BGGRetrier: RequestRetrier {
        func should(_ manager: SessionManager, retry request: Request, with error: Error, completion: @escaping RequestRetryCompletion) {
            guard let response = request.response else {
                completion(false, 0)
                return
            }
            if response.shouldRetryRequest {
                completion(true, 0.2)
            }
            completion(false, 0)
        }
    }
}

private extension Optional where Wrapped == HTTPURLResponse {
    var shouldRetryRequest: Bool {
        return self?.shouldRetryRequest ?? true
    }
}
private extension HTTPURLResponse {
    var shouldRetryRequest: Bool {
        return statusCode == 202
    }
}
