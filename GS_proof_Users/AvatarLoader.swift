//
//  AvatarLoader.swift
//  GS_proof_Users
//
//  Created by Omar Jiménez Sotelo on 30/09/26.
//

import UIKit

/// Carga imágenes de forma asíncrona con caché en memoria.
/// Se usa para los avatares generados con https://i.pravatar.cc/300?img={id}
final class AvatarLoader {

    static let shared = AvatarLoader()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {}

    /// Devuelve la imagen para la URL, tomándola de la caché si ya se cargó.
    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }
            cache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }
}