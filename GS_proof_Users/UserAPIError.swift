//
//  UserAPIError.swift
//  GS_proof_Users
//
//  Created by Omar Jiménez Sotelo on 30/09/26.
//

import Foundation

/// Errores específicos de la API de usuarios.
enum UserAPIError: LocalizedError {

    /// El servidor respondió 404: el usuario solicitado no existe.
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Usuario no encontrado"
        }
    }
}