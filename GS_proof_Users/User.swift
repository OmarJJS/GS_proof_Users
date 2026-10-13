//
//  User.swift
//  GS_proof_Users
//
//  Created by Omar Jiménez Sotelo on 30/09/26.
//

import Foundation

/// Model that matches the JSON returned by https://jsonplaceholder.typicode.com/users
struct User: Codable {
    let id: Int
    let name: String
    let username: String
    let email: String
    let phone: String
    let website: String
    let address: Address
    let company: Company
}

struct Address: Codable {
    let street: String
    let suite: String
    let city: String
    let zipcode: String
    let geo: Geo
}

struct Geo: Codable {
    let lat: String
    let lng: String
}

struct Company: Codable {
    let name: String
    let catchPhrase: String
    let bs: String
}