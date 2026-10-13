//
//  UserDetailViewController.swift
//  GS_proof_Users
//
//  Created by Omar Jiménez Sotelo on 30/09/26.
//

import UIKit

/// Muestra el detalle de un usuario. La información se solicita al
/// endpoint https://jsonplaceholder.typicode.com/users/{id}, usando el id
/// del registro seleccionado en la tabla.
final class UserDetailViewController: UITableViewController {

    // MARK: - Private properties

    private let userID: Int
    private var sections: [(title: String, rows: [(label: String, value: String)])] = []

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let avatarImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    /// Vista de pantalla completa mostrada cuando el usuario no existe (404).
    private lazy var notFoundView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGroupedBackground

        let imageView = UIImageView(image: UIImage(systemName: "person.crop.circle.badge.questionmark"))
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Usuario no encontrado"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = "No existe un usuario con el id \(userID)."
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.font = .preferredFont(forTextStyle: .callout)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(imageView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            imageView.widthAnchor.constraint(equalToConstant: 96),
            imageView.heightAnchor.constraint(equalToConstant: 96),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])

        return view
    }()

    // MARK: - Init

    init(userID: Int) {
        self.userID = userID
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Usuario #\(userID)"
        view.backgroundColor = .systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DetailCell")

        // Pull-to-refresh
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshUser), for: .valueChanged)
        tableView.refreshControl = refreshControl

        setupTableHeader()
        setupActivityIndicator()
        Task { await loadUser() }
        Task { await loadAvatar() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        avatarImageView.layer.cornerRadius = avatarImageView.bounds.width / 2
    }

    // MARK: - Actions

    @objc private func refreshUser() {
        Task { await loadUser(isRefreshing: true) }
    }

    // MARK: - UI

    /// Encabezado circular con el avatar del usuario.
    private func setupTableHeader() {
        let headerView = UIView()
        headerView.backgroundColor = .clear

        headerView.addSubview(avatarImageView)

        NSLayoutConstraint.activate([
            avatarImageView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            avatarImageView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 24),
            avatarImageView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -24),
            avatarImageView.widthAnchor.constraint(equalToConstant: 120),
            avatarImageView.heightAnchor.constraint(equalToConstant: 120),
        ])

        headerView.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 0)
        tableView.tableHeaderView = headerView

        // Ajusta la altura del header según su contenido.
        headerView.layoutIfNeeded()
        let size = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        if headerView.frame.height != size.height {
            headerView.frame.size.height = size.height
            tableView.tableHeaderView = headerView
        }
    }

    private func setupActivityIndicator() {
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        activityIndicator.startAnimating()
    }

    /// Carga el avatar desde https://i.pravatar.cc/300?img={id}.
    /// El endpoint /users/{id} no incluye imagen, así que se usa un servicio
    /// externo que devuelve un avatar determinístico según el id.
    private func loadAvatar() async {
        let urlString = "https://i.pravatar.cc/300?img=\(userID)"
        guard let url = URL(string: urlString) else { return }

        if let image = await AvatarLoader.shared.image(for: url) {
            avatarImageView.image = image
        }
    }

    // MARK: - Networking

    private func loadUser(isRefreshing: Bool = false) async {
        // El spinner central solo se muestra en la carga inicial, no al refrescar.
        if !isRefreshing {
            activityIndicator.startAnimating()
        }

        do {
            let user = try await fetchUser()
            buildSections(with: user)
            tableView.reloadData()
            notFoundView.removeFromSuperview()
        } catch {
            showLoadError(error)
        }

        activityIndicator.stopAnimating()
        tableView.refreshControl?.endRefreshing()
    }

    /// Realiza el GET a https://jsonplaceholder.typicode.com/users/{id}
    private func fetchUser() async throws -> User {
        let urlString = "https://jsonplaceholder.typicode.com/users/\(userID)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Si el id no existe, la API responde 404.
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw UserAPIError.notFound
            }
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(User.self, from: data)
    }

    // MARK: - Data

    private func buildSections(with user: User) {
        navigationItem.title = user.name

        sections = [
            (
                title: "General",
                rows: [
                    (label: "Usuario", value: "@\(user.username)"),
                    (label: "Email", value: user.email),
                    (label: "Teléfono", value: user.phone),
                    (label: "Sitio web", value: user.website),
                ]
            ),
            (
                title: "Dirección",
                rows: [
                    (label: "Calle", value: user.address.street),
                    (label: "Suite", value: user.address.suite),
                    (label: "Ciudad", value: user.address.city),
                    (label: "Código postal", value: user.address.zipcode),
                    (label: "Ubicación", value: "\(user.address.geo.lat), \(user.address.geo.lng)"),
                ]
            ),
            (
                title: "Compañía",
                rows: [
                    (label: "Nombre", value: user.company.name),
                    (label: "Lema", value: user.company.catchPhrase),
                    (label: "bs", value: user.company.bs),
                ]
            ),
        ]
    }

    private func showLoadError(_ error: Error) {
        // Un 404 muestra la vista de "usuario no encontrado" en pantalla completa.
        if case UserAPIError.notFound = error {
            showNotFound()
        } else {
            showError(error)
        }
    }

    /// Muestra la vista de pantalla completa "Usuario no encontrado".
    private func showNotFound() {
        guard notFoundView.superview == nil else { return }

        notFoundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(notFoundView)
        NSLayoutConstraint.activate([
            notFoundView.topAnchor.constraint(equalTo: view.topAnchor),
            notFoundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            notFoundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            notFoundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "Error",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Reintentar", style: .default) { [weak self] _ in
            guard let self else { return }
            self.activityIndicator.startAnimating()
            Task { await self.loadUser() }
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension UserDetailViewController {

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DetailCell", for: indexPath)
        let row = sections[indexPath.section].rows[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = row.label
        content.secondaryText = row.value
        cell.contentConfiguration = content

        return cell
    }
}