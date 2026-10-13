//
//  UserTableViewCell.swift
//  GS_proof_Users
//
//  Created by Omar Jiménez Sotelo on 30/09/26.
//

import UIKit

/// Celda de la lista de usuarios. Muestra el nombre, el usuario/email
/// y el avatar circular del usuario (https://i.pravatar.cc/300?img={id}).
final class UserTableViewCell: UITableViewCell {

    static let reuseIdentifier = "UserCell"

    /// URL del avatar que esta celda debe mostrar, para evitar que una
    /// respuesta tardía pise el contenido de una celda reutilizada.
    private var avatarURL: URL?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with user: User) {
        var content = defaultContentConfiguration()
        content.text = user.name
        content.secondaryText = "@\(user.username) · \(user.email)"
        content.image = placeholderImage
        content.imageProperties.tintColor = .systemGray3
        content.imageProperties.cornerRadius = 24
        content.imageProperties.maximumSize = CGSize(width: 48, height: 48)
        contentConfiguration = content

        guard let url = URL(string: "https://i.pravatar.cc/300?img=\(user.id)") else {
            avatarURL = nil
            return
        }
        avatarURL = url
        loadAvatar(from: url)
    }

    // MARK: - Avatar

    private var placeholderImage: UIImage? {
        UIImage(systemName: "person.crop.circle.fill")
    }

    private func loadAvatar(from url: URL) {
        Task { [weak self] in
            let image = await AvatarLoader.shared.image(for: url)

            // Solo aplica la imagen si esta celda sigue pidiendo esa URL.
            guard let self, self.avatarURL == url else { return }

            var content = self.contentConfiguration as? UIListContentConfiguration
            content?.image = image ?? self.placeholderImage
            self.contentConfiguration = content
        }
    }
}