//
//  ViewController.swift
//  GS_proof_Users
//
//  Created by Omar Jiménez Sotelo on 29/09/26.
//

import UIKit

class ViewController: UIViewController {

    // MARK: - UI

    private let tableView = UITableView(frame: .zero, style: .plain)

    private let refreshControl = UIRefreshControl()

    /// Vista de carga (spinner centrado) mostrada durante la primera consulta.
    private lazy var loadingView: UIView = {
        let view = UIView()
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }()

    /// Vista mostrada cuando la consulta devuelve cero usuarios.
    private lazy var emptyStateView: UIView = {
        let view = UIView()

        let imageView = UIImageView(image: UIImage(systemName: "tray"))
        imageView.tintColor = .systemGray3
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "No hay usuarios disponibles"
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .callout)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(imageView)
        view.addSubview(label)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
            imageView.widthAnchor.constraint(equalToConstant: 64),
            imageView.heightAnchor.constraint(equalToConstant: 64),

            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])

        return view
    }()

    // MARK: - Data

    private var users: [User] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Usuarios"
        view.backgroundColor = .systemBackground
        setupTableView()
        Task { await loadUsers() }
    }

    // MARK: - UI Setup

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UserTableViewCell.self, forCellReuseIdentifier: UserTableViewCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        // Pull-to-refresh
        refreshControl.addTarget(self, action: #selector(refreshUsers), for: .valueChanged)
        tableView.refreshControl = refreshControl

        // Estado inicial: cargando.
        tableView.backgroundView = loadingView

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func refreshUsers() {
        Task { await loadUsers(isRefreshing: true) }
    }

    // MARK: - Networking

    private func loadUsers(isRefreshing: Bool = false) async {
        // Solo muestra el spinner de fondo en la carga inicial, no al refrescar.
        if !isRefreshing {
            tableView.backgroundView = loadingView
        }

        do {
            users = try await fetchUsers()
        } catch {
            // En una actualización se conservan los datos previos.
            if !isRefreshing {
                users = []
            }
            showError(error)
        }

        tableView.reloadData()
        refreshControl.endRefreshing()

        // Estado final: vacío o con datos.
        if users.isEmpty {
            tableView.backgroundView = emptyStateView
        } else {
            tableView.backgroundView = nil
        }
    }

    /// Realiza el GET a https://jsonplaceholder.typicode.com/users
    private func fetchUsers() async throws -> [User] {
        guard let url = URL(string: "https://jsonplaceholder.typicode.com/users") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([User].self, from: data)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "Error",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Reintentar", style: .default) { [weak self] _ in
            Task { await self?.loadUsers() }
        })
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension ViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        users.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: UserTableViewCell.reuseIdentifier,
                                                 for: indexPath) as! UserTableViewCell
        cell.configure(with: users[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate

extension ViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        // Navega al detalle usando el id del usuario seleccionado.
        // La URL de consulta será https://jsonplaceholder.typicode.com/users/{id}
        let user = users[indexPath.row]
        let detailVC = UserDetailViewController(userID: user.id)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}