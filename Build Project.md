# Build Project — Guía paso a paso

> Documento de referencia sobre la construcción de **GS_proof_Users**: una app iOS (UIKit, sin storyboards de UI complejos) que consume `https://jsonplaceholder.typicode.com/users` con `URLSession`, muestra los usuarios en una `UITableView` y permite ver el detalle de cada uno consultando `https://jsonplaceholder.typicode.com/users/{id}`.
>
> Cada paso explica **qué se hizo** y **por qué** (la razón detrás de cada parte del código).

---

## Tabla de contenidos

0. [Conceptos clave (glosario)](#0-conceptos-clave-glosario)
1. [Estado inicial del proyecto](#1-estado-inicial-del-proyecto)
2. [Paso 1 — Modelo de datos `User.swift`](#paso-1--modelo-de-datos-userswift)
3. [Paso 2 — Lista con `URLSession` + `UITableView` (`ViewController.swift`)](#paso-2--lista-con-urlsession--uitableview-viewcontrollerswift)
4. [Paso 3 — Vista de detalle con URL dinámica (`UserDetailViewController.swift`)](#paso-3--vista-de-detalle-con-url-dinámica-userdetailviewcontrollerswift)
5. [Paso 4 — Navegación con `UINavigationController` (`SceneDelegate.swift`)](#paso-4--navegación-con-uinavigationcontroller-scenedelegateswift)
6. [Paso 5 — Avatar en el detalle](#paso-5--avatar-en-el-detalle)
7. [Paso 6 — Avatar en las celdas (`AvatarLoader.swift` y `UserTableViewCell.swift`)](#paso-6--avatar-en-las-celdas-avatarloaderswift-y-usertableviewcellswift)
8. [Paso 7 — Validaciones: pull-to-refresh, carga, vacío y error](#paso-7--validaciones-pull-to-refresh-carga-vacío-y-error)
9. [Paso 8 — Manejo de "Usuario no encontrado" (404)](#paso-8--manejo-de-usuario-no-encontrado-404)
10. [Paso 9 — Vista de pantalla completa "Usuario no encontrado"](#paso-9--vista-de-pantalla-completa-usuario-no-encontrado)
11. [Cómo verificar la API](#cómo-verificar-la-api)
12. [Errores comunes y buenas prácticas](#errores-comunes-y-buenas-prácticas)
13. [Posibles mejoras siguientes](#posibles-mejoras-siguientes)
14. [Cómo correr el proyecto](#cómo-correr-el-proyecto)
15. [Estructura final de archivos](#estructura-final-de-archivos)
16. [Apéndice — Código final completo](#apéndice--código-final-completo)

---

## 0. Conceptos clave (glosario)

Estas son las piezas técnicas que la app usa una y otra vez. Léelas una vez y el resto del documento se entenderá mucho más fácil. *(Explicación en lenguaje cercano, no definición formal.)*

### async / await (Swift Concurrency)

```swift
let (data, response) = try await URLSession.shared.data(from: url)
```

- `async` marca una función que **puede suspender** (esperar sin bloquear).
- `await` dice "**espera aquí** a que termine esto, pero no bloquees el hilo".
- Beneficio: la **UI no se congela** mientras llega la respuesta de la red; en el ínterin el hilo principal sigue atendiendo toques y animaciones.
- Antes de Swift Concurrency esto se hacía con *completion handlers* (clausuras) o delegates — más verboso y propenso a errores.

### `URL(string:)` devuelve un opcional

```swift
guard let url = URL(string: "https://...") else { throw URLError(.badURL) }
```

`URL(string:)` puede fallar (cadena inválida) y por eso devuelve `URL?` (opcional). El `guard ... else` **desenvolve** el valor o corta el flujo con un error temprano. Es el patrón idiomático en Swift: nunca asumas que un inicializador failable tiene valor.

### Codable / Decodable

```swift
struct User: Codable { ... }
```

- `Codable` = `Decodable` + `Encodable` (puede pasar de JSON → objeto y viceversa).
- Al declarar un `struct` con `Codable`, el compilador **genera solo** el código para convertir JSON a la estructura — siempre que los nombres de las propiedades coincidan con las llaves del JSON.

### JSONDecoder y la coincidencia de llaves (keys)

```swift
try JSONDecoder().decode([User].self, from: data)
```

`JSONDecoder` compara las *keys* del JSON con los nombres de las propiedades. La propiedad `id` → JSON `"id"`. Si el JSON usara `user_id`, habría que mapearlo con `CodingKeys`. En este proyecto las llaves coinciden 1 a 1, así que **no hace falta `CodingKeys`**.

### MainActor — el hilo principal

- Todo lo de la **UI debe ocurrir en el hilo principal**.
- Este proyecto tiene `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: todas las clases/tipos quedan "anclados" al actor principal por defecto.
- Efecto práctico: puedes escribir `Task { await loadUsers() }` en un `UIViewController` y al reanudar el `await`, el código sigue en el hilo principal → **actualizar la tabla/alertas es seguro** sin pensarlo dos veces.

### `Task { }` — lanzar trabajo asíncrono

```swift
Task { await loadUsers() }
```

Crea una **tarea asíncrona** desde un contexto síncrono (como `viewDidLoad`). Es la forma de "disparar y olvidar" una operación que no bloquea. La tarea hereda el actor del lugar donde se crea (MainActor aquí).

### Crear vistas en código (no con storyboard)

La app construye su UI con Swift (`.frame`, `addSubview`, constraints) en lugar de arrastrar objetos en Interface Builder. Ventajas: el código es explícito, versionable y sin archivos XML frágiles.

### `translatesAutoresizingMaskIntoConstraints = false`

Regla de oro de Auto Layout en código: **toda** vista a la que le agregues constraints necesita esto en `false`. Si lo olvidas, Auto Layout no controla el frame y las constraints se ignoran o dan conflictos.

### `safeAreaLayoutGuide`

Zona "segura" de la pantalla (excluye notch / barra de estado / barra inferior). Anclar la tabla a `safeAreaLayoutGuide` evita que el contenido quede oculto debajo de esos elementos:

```swift
tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
```

### Reutilización de celdas (`dequeueReusableCell`)

```swift
let cell = tableView.dequeueReusableCell(withIdentifier: ..., for: indexPath)
```

El sistema **recicla** celdas en lugar de crear una por fila. Al hacer scroll solo existen tantas celdas como caben en pantalla. Por eso hay que llenarlas **completas en cada `cellForRowAt`** y por eso las cargas asíncronas dentro de celdas necesitan protecciones (ver Paso 6, el guard de `avatarURL`).

### `UIListContentConfiguration` (`defaultContentConfiguration()`)

API moderna (iOS 14+) para configurar el contenido de una celda: texto, subtítulo, imagen, márgenes — todo en una sola configuración:

```swift
var content = cell.defaultContentConfiguration()
content.text = user.name
content.secondaryText = "@\(user.username) · \(user.email)"
content.image = ...
cell.contentConfiguration = content
```

Sustituye al antiguo `cell.textLabel?.text` / `cell.imageView?.image`.

### NSCache — caché en memoria

Almacén de datos en memoria que el sistema **puede vaciar** si hay presión de memoria (a diferencia de un `Dictionary`). Ideal para imágenes: evita descargar lo mismo varias veces.

### `backgroundView` de la tabla — estados visuales

`UITableView.backgroundView` es una vista que se dibuja **detrás de las celdas**. Asignarla (spinner o mensaje de vacío) es la forma limpia de mostrar estados de toda la tabla:

```swift
tableView.backgroundView = loadingView      // estado cargando
tableView.backgroundView = emptyStateView   // estado vacío
tableView.backgroundView = nil              // con datos → nada detrás
```

### UIRefreshControl — pull-to-refresh

Componente nativo que muestra un spinner cuando el usuario **jala la tabla hacia abajo**:

```swift
refreshControl.addTarget(self, action: #selector(refreshUsers), for: .valueChanged)
tableView.refreshControl = refreshControl
refreshControl.endRefreshing()   // al terminar, se retira el spinner
```

### ¿Alert o estado en pantalla?

- **Alert (`UIAlertController`):** para avisos que no son el contenido central (ej. un fallo de red con opción de reintentar).
- **Estado en pantalla completa:** cuando el estado ES la pantalla (ej. "usuario no encontrado": no hay nada más que mostrar).

### Flujo general de la app

```
┌─────────────────────────────┐
│  ViewController (lista)      │
│  viewDidLoad                 │
│   └─ Task { loadUsers() }    │
│        └─ GET /users         │
│             └─ [User]        │
│   └─ UITableView (10 filas)  │
└──────────────┬──────────────┘
               │ toca una fila (id = N)
               ▼
┌─────────────────────────────┐
│  UserDetailViewController    │
│  init(userID: N)             │
│   ├─ Task { loadUser() }     │
│   │    └─ GET /users/N       │
│   │         ├─ 200 → secciones │
│   │         └─ 404 → "No encontrado" │
│   └─ Task { loadAvatar() }   │
│        └─ GET i.pravatar.cc/300?img=N │
└─────────────────────────────┘
```

---

## 1. Estado inicial del proyecto

El proyecto fue creado con la plantilla *App* de Xcode (UIKit, **Storyboard** `Main.storyboard`, `AppDelegate` + `SceneDelegate`). Solo existía una `ViewController` con un `viewDidLoad` vacío y un borrador de código que **no compilaba**:

```swift
// ❌ Código original con errores
func getUsers() async throws -> Any {
    let url = URL(String: "https://jsonplaceholder.typicode.com/users") // ❌ no existe URL(String:)
    let (data, _) = try URLSession.shared.data(from: url)
    return try JSONDecoder().decode(Any.self, from: data)              // ❌ Any no es Decodable
}

struct printUsers : View { }  // ❌ SwiftUI dentro de una app UIKit
struct ResponseC codable      // ❌ error de sintaxis
```

Problemas detectados:

| Línea | Problema | Solución |
|---|---|---|
| `URL(String:)` | El inicializador correcto es `URL(string:)` | Usar `URL(string:)` y validar con `guard` |
| `decode(Any.self)` | `Any` no cumple `Decodable` | Definir un modelo `User: Codable` tipado |
| Structs SwiftUI / sintaxis suelta | No tienen lugar en una app UIKit | Eliminarlas |

> ⚙️ **Nota del proyecto:** los build settings incluyen `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, por lo que las clases de UI son `@MainActor` por defecto. Esto hace que escribir `Task { await ... }` desde la UI sea seguro (las actualizaciones de UI ocurren en el hilo principal).

---

## Paso 1 — Modelo de datos `User.swift`

**Objetivo:** representar la respuesta JSON de `/users` con tipos seguros.

**Archivo:** `GS_proof_Users/User.swift` (nuevo)

La API devuelve algo como:

```json
[
  {
    "id": 7,
    "name": "Kurtis Weissnat",
    "username": "Elwyn.Skiles",
    "email": "Telly.Hoeger@billy.biz",
    "address": { "street": "Rex Trail", "suite": "Suite 280", "city": "Howemouth",
                 "zipcode": "58804-1099", "geo": { "lat": "24.8918", "lng": "21.8984" } },
    "phone": "210.067.6132",
    "website": "elvis.io",
    "company": { "name": "Johns Group", "catchPhrase": "Configurable multimedia task-force",
                 "bs": "generate enterprise e-tailers" }
  }
]
```

El modelo:

```swift
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
```

**Por qué:**

- **`Codable` (Decodable + Encodable):** permite a `JSONDecoder` convertir el JSON en instancias tipadas. Al ser un `struct` con `let`, el compilador sintetiza automáticamente `init(from:)` si los nombres de las propiedades coinciden con las *keys* del JSON (aquí coinciden 1 a 1).
- **Modelos anidados** (`Address`, `Geo`, `Company`): el JSON tiene objetos anidados; cada uno necesita su propio tipo `Codable` para poder decodificarlos.
- **`let` (inmutables):** el modelo es de solo lectura, lo que evita mutaciones accidentales y es la práctica recomendada para modelos de respuesta de API.
- **Un modelo tipado** en lugar de diccionarios `[String: Any]` da **seguridad en tiempo de compilación**: si la API cambia, el error aparece al decodificar, no al usar los datos.

> 💡 Como el proyecto usa `PBXFileSystemSynchronizedRootGroup` (carpetas sincronizadas), **basta con crear el archivo dentro de `GS_proof_Users/`** para que Xcode lo incluya en el target automáticamente, sin tocar `project.pbxproj`.

---

## Paso 2 — Lista con `URLSession` + `UITableView` (`ViewController.swift`)

**Objetivo:** hacer el GET a `/users` y mostrar el resultado en una tabla.

**Archivo:** `GS_proof_Users/ViewController.swift` (reescrito)

Partes clave:

```swift
// 1. La tabla se crea en código (el storyboard solo tiene una vista vacía)
private let tableView = UITableView(frame: .zero, style: .plain)

override func viewDidLoad() {
    super.viewDidLoad()
    title = "Usuarios"
    view.backgroundColor = .systemBackground
    setupTableView()
    Task { await loadUsers() }          // lanza la consulta async
}

// 2. Layout con Auto Layout
private func setupTableView() {
    tableView.dataSource = self
    tableView.delegate = self
    tableView.register(UserTableViewCell.self,
                       forCellReuseIdentifier: UserTableViewCell.reuseIdentifier)
    tableView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(tableView)

    NSLayoutConstraint.activate([
        tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
}

// 3. La consulta con URLSession + async/await
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
```

**Por qué:**

- **Tabla programática en lugar de storyboard:** editar XML de storyboard a mano es frágil; crearla en código es explícito, versionable y fácil de revisar. `dataSource`/`delegate` se conectan a extensiones separadas (organización por responsabilidad).
- **`translatesAutoresizingMaskIntoConstraints = false` + Auto Layout:** obligatorio para que Auto Layout controle el frame; sin esto las constraints se ignoran o la vista queda con tamaño cero/arbitrario.
- **`safeAreaLayoutGuide`:** evita que la tabla quede debajo de la barra de estado / notch.
- **`URLSession.shared.data(from:)` con async/await:**
  - No bloquea el hilo principal (la UI sigue respondiendo).
  - El hilo se libera durante la espera de red; al volver, se reanuda en el actor correcto (MainActor por la configuración del proyecto).
  - Es la API moderna (Swift Concurrency) en lugar de *completion handlers* o *delegates*, mucho más legible.
- **Validación del `HTTPURLResponse`:** no basta con recibir datos; hay que verificar que el servidor respondió `2xx`. Recibir un `200` fallido (ej. HTML de error) se detectaría al decodificar, pero validar el status da un error más claro y temprano.
- **`guard let url`:** porque `URL(string:)` es un inicializador *failable* (puede devolver `nil` con cadenas inválidas); el guard corta el flujo con un error descriptivo.

Los datos se guardan en `private var users: [User]` y la tabla simplemente la renderiza:

```swift
func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    users.count
}

func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: UserTableViewCell.reuseIdentifier,
                                             for: indexPath) as! UserTableViewCell
    cell.configure(with: users[indexPath.row])
    return cell
}
```

- **`dequeueReusableCell`:** reutiliza celdas en lugar de crear una por fila (rendimiento al hacer scroll). Con celdas personalizadas se usa el *reuse identifier* registrado.
- **`configure(with:)`:** encapsula el llenado de la celda para que la celda sepa qué mostrar sin exponer UIKit en el controller.

---

## Paso 3 — Vista de detalle con URL dinámica (`UserDetailViewController.swift`)

**Objetivo:** al seleccionar un usuario, consultar `https://jsonplaceholder.typicode.com/users/{id}` (el endpoint con el id como último parámetro) y mostrar toda su información.

**Archivo:** `GS_proof_Users/UserDetailViewController.swift` (nuevo)

```swift
final class UserDetailViewController: UITableViewController {

    private let userID: Int                       // se recibe por el init

    init(userID: Int) {
        self.userID = userID
        super.init(style: .insetGrouped)
    }

    private func fetchUser() async throws -> User {
        // 🔑 LA URL SE ARMA CON EL ID RECIBIDO
        let urlString = "https://jsonplaceholder.typicode.com/users/\(userID)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(User.self, from: data)  // decodifica UN SOLO User
    }
}
```

**Por qué:**

- **El id se pasa por `init(userID:)`:** la vista de detalle no recibe el objeto completo ni "adivina" el dato; recibe exactamente el identificador que le interesa y construye su propia URL. Esto refleja una **separación de responsabilidades**: la lista decide *qué*, el detalle decide *cómo pedirlo al servidor* (además, la API es la fuente de verdad).
- **`UITableViewController` con `.insetGrouped`:** es la subclase que ya trae `tableView` y gestión de `dataSource`/`delegate`; el estilo agrupado resalta cada bloque de información.
- **Interpolación `"\(userID)"`:** si seleccionas el id 7, la URL consultada es exactamente `https://jsonplaceholder.typicode.com/users/7`.
- **`decode(User.self, ...)`:** aquí la respuesta es un **objeto único**, no un arreglo; por eso se decodifica `User` y no `[User]`.
- La organización de la información se hace en secciones (General, Dirección, Compañía) para mejorar la legibilidad de la pantalla.

El push desde la lista (en `ViewController`):

```swift
func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let user = users[indexPath.row]
    let detailVC = UserDetailViewController(userID: user.id)
    navigationController?.pushViewController(detailVC, animated: true)
}
```

- **`deselectRow`:** deja la fila sin sombreado al volver (UX estándar).
- **`pushViewController`:** navegación *stack* con botón "atrás" automático.

---

## Paso 4 — Navegación con `UINavigationController` (`SceneDelegate.swift`)

**Objetivo:** tener una barra de navegación y poder hacer `push` al detalle.

**Archivo:** `GS_proof_Users/SceneDelegate.swift` (modificado)

```swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = (scene as? UIWindowScene) else { return }

    let window = UIWindow(windowScene: windowScene)
    let storyboard = UIStoryboard(name: "Main", bundle: nil)
    let rootViewController = storyboard.instantiateInitialViewController() ?? ViewController()

    // 🔑 Envolver la vista inicial en un Navigation Controller
    window.rootViewController = UINavigationController(rootViewController: rootViewController)
    self.window = window
    window.makeKeyAndVisible()
}
```

**Por qué:**

- En el storyboard no hay un `UINavigationController`; si el root fuera directamente la `ViewController`, `navigationController` sería `nil` y `pushViewController` no haría nada.
- Creamos la ventana nosotros (en lugar de dejar que UIKit cargue el storyboard solo) para poder **intercalar el navigation controller** como root.
- `instantiateInitialViewController()` devuelve la `ViewController` del storyboard (la misma clase), así que no perdemos el resto de la configuración del storyboard (fondo, orientaciones, etc.).

---

## Paso 5 — Avatar en el detalle

**Objetivo:** mostrar una imagen de perfil en la vista de detalle.

**Contexto importante:** se verificó con una petición real que el endpoint `https://jsonplaceholder.typicode.com/users/{id}` **NO incluye ningún campo de imagen**. Su respuesta solo contiene `id`, `name`, `username`, `email`, `address`, `phone`, `website`, `company`. Por eso se usa un servicio externo de avatares determinístico: `https://i.pravatar.cc/300?img={id}`.

```swift
private func loadAvatar() async {
    let urlString = "https://i.pravatar.cc/300?img=\(userID)"
    guard let url = URL(string: urlString) else { return }

    if let image = await AvatarLoader.shared.image(for: url) {
        avatarImageView.image = image
    }
}
```

**Por qué:**

- El avatar se coloca como **encabezado de la tabla** (imageView circular de 120×120 con `cornerRadius = ancho/2` y `clipsToBounds = true`).
- `cornerRadius` se recalcula en `viewDidLayoutSubviews` para que el círculo sea correcto aunque cambie el tamaño.
- Se lanza en `Task` paralelo a la carga de datos: la imagen y el texto cargan de forma independiente.
- Si la imagen no carga, se conserva un fondo gris de *placeholder* (no se rompe la vista).

---

## Paso 6 — Avatar en las celdas (`AvatarLoader.swift` y `UserTableViewCell.swift`)

**Objetivo:** mostrar el avatar de cada usuario en la lista, con descarga eficiente.

### `AvatarLoader.swift` (nuevo) — caché centralizada

```swift
final class AvatarLoader {

    static let shared = AvatarLoader()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {}

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached                          // 1) caché
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }
            cache.setObject(image, forKey: url as NSURL)   // 2) guardar en caché
            return image
        } catch {
            return nil
        }
    }
}
```

**Por qué:**

- **`NSCache`** es una caché en memoria que la propia `UIImageView`/sistema puede evacuar bajo presión de memoria (a diferencia de un `Dictionary`). Se evita descargar la misma imagen en cada scroll.
- **Singleton (`shared`)** para compartir la caché entre la lista y el detalle: si ya viste un avatar en la tabla, el detalle lo muestra al instante sin re-descargar.
- Devuelve `UIImage?` y **falla suave** (`nil`/catch) para que la UI decida qué hacer, sin propagar errores de imagen.

### `UserTableViewCell.swift` (nuevo) — celda con imagen asíncrona

```swift
final class UserTableViewCell: UITableViewCell {

    static let reuseIdentifier = "UserCell"

    private var avatarURL: URL?               // 🔑 sello de "qué URL pidió esta celda"

    func configure(with user: User) {
        var content = defaultContentConfiguration()
        content.text = user.name
        content.secondaryText = "@\(user.username) · \(user.email)"
        content.image = placeholderImage                       // placeholder gris
        content.imageProperties.tintColor = .systemGray3
        content.imageProperties.cornerRadius = 24              // círculo de 48×48
        content.imageProperties.maximumSize = CGSize(width: 48, height: 48)
        contentConfiguration = content

        guard let url = URL(string: "https://i.pravatar.cc/300?img=\(user.id)") else {
            avatarURL = nil
            return
        }
        avatarURL = url
        loadAvatar(from: url)
    }

    private func loadAvatar(from url: URL) {
        Task { [weak self] in
            let image = await AvatarLoader.shared.image(for: url)

            // 🔑 Solo aplica la imagen si esta celda sigue pidiendo ESA url
            guard let self, self.avatarURL == url else { return }

            var content = self.contentConfiguration as? UIListContentConfiguration
            content?.image = image ?? self.placeholderImage
            self.contentConfiguration = content
        }
    }
}
```

**Por qué:**

- **`defaultContentConfiguration()` (UIListContentConfiguration):** API moderna para celdas (iOS 14+) que sustituye a `textLabel`/`detailTextLabel`/`imageView`; permite configurar estilo, márgenes, tamaño máximo e imagen con una sola configuración inmutable.
- **`[weak self]` dentro del `Task`:** evita que la tarea retenga la celda y que esta nunca se libere (ciclos de retención con celdas reutilizadas).
- **El guard `self.avatarURL == url` es la parte más importante:** al hacer scroll rápido, una celda se reutiliza para otra fila. Sin este guard, una respuesta tardía podría pintar el **avatar equivocado**. Al guardar la URL pedida y compararla al terminar, solo se aplica la imagen correcta.
- **`UIListContentConfiguration` re-casteada:** `contentConfiguration` almacena el valor como `UIContentConfiguration`; se castea de regreso para modificar solo la `image` y re-aplicarla.

---

## Paso 7 — Validaciones: pull-to-refresh, carga, vacío y error

**Objetivo:** que la lista comunique claramente su estado (cargando / vacío / error / con datos).

**Archivo:** `GS_proof_Users/ViewController.swift` (modificado)

```swift
// Pull-to-refresh
let refreshControl = UIRefreshControl()
refreshControl.addTarget(self, action: #selector(refreshUsers), for: .valueChanged)
tableView.refreshControl = refreshControl
```

```swift
@objc private func refreshUsers() {
    Task { await loadUsers(isRefreshing: true) }
}

private func loadUsers(isRefreshing: Bool = false) async {
    if !isRefreshing {
        tableView.backgroundView = loadingView      // spinner central (carga inicial)
    }

    do {
        users = try await fetchUsers()
    } catch {
        if !isRefreshing { users = [] }             // en refresh se conservan datos previos
        showError(error)
    }

    tableView.reloadData()
    refreshControl.endRefreshing()

    if users.isEmpty {
        tableView.backgroundView = emptyStateView   // estado vacío
    } else {
        tableView.backgroundView = nil
    }
}
```

**Por qué:**

- **`UIRefreshControl`:** componente nativo que muestra el spinner al jalarlo; `endRefreshing()` lo retira al terminar. El selector `@objc` es el *target/action* clásico.
- **`isRefreshing`:** distingue la primera carga (hace falta el spinner central y no hay datos aún) de una actualización (la tabla ya tiene contenido; solo se refresca). En un refresh fallido **se conserva la información previa** en lugar de borrarla: mejor UX que ver desaparecer los datos.
- **`tableView.backgroundView` como contenedor de estados:** evita overlay/views flotantes; el sistema muestra el `backgroundView` debajo de las celdas, que es exactamente el lugar de un estado vacío. Con datos, se quita (`nil`).
- **Avisos y estados de una sola fuente:** el flujo es `cargando → (datos | vacío)` y cualquier error va al alert con **Reintentar/Cancelar**.

La alerta de error con reintento:

```swift
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
```

- `[weak self]` evita retener el controller desde la acción del alert.
- "Reintentar" relanza la carga completa, cerrando el ciclo de validación.

---

## Paso 8 — Manejo de "Usuario no encontrado" (404)

**Objetivo:** distinguir el error 404 de la API de otros fallos de red.

### `UserAPIError.swift` (nuevo)

```swift
enum UserAPIError: LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Usuario no encontrado"
        }
    }
}
```

**Por qué:**

- `URLError.badServerResponse` da un mensaje genérico ("The operation couldn't be completed..."), poco amigable.
- Un `LocalizedError` con `errorDescription` permite mostrar un **mensaje claro** y comunicar *intención* del negocio. Es la forma idiomática de errores tipados en Swift.

### En `fetchUser()` (del detalle)

```swift
guard let httpResponse = response as? HTTPURLResponse else {
    throw URLError(.badServerResponse)
}

guard (200...299).contains(httpResponse.statusCode) else {
    if httpResponse.statusCode == 404 {
        throw UserAPIError.notFound
    }
    throw URLError(.badServerResponse)
}
```

**Por qué:**

- El servidor responde `404` cuando el id no existe (ej. `.../users/999`). Detectar ese código **antes** de intentar decodificar da una señal específica para la UI. `404` tiene un significado de negocio ("no existe") distinto de otros fallos (servidor caído, timeout, 500...).

---

## Paso 9 — Vista de pantalla completa "Usuario no encontrado"

**Objetivo:** reemplazar el alert por una vista dedicada de pantalla completa cuando no existe el usuario.

**Archivo:** `GS_proof_Users/UserDetailViewController.swift` (modificado)

```swift
private func showLoadError(_ error: Error) {
    if case UserAPIError.notFound = error {
        showNotFound()          // pantalla completa
    } else {
        showError(error)        // alert con Reintentar/Cancelar (fallos de red, etc.)
    }
}
```

La vista `notFoundView` es una `UIView` que cubre todo el controller (fondo `systemGroupedBackground`, para integrarse con el estilo del detalle) con:

- Ícono `person.crop.circle.badge.questionmark` (96×96, gris).
- Título **"Usuario no encontrado"** (bold 22 pt).
- Subtítulo con el **id dinámico**: "No existe un usuario con el id N."

```swift
private func showNotFound() {
    guard notFoundView.superview == nil else { return }   // evita duplicarla
    notFoundView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(notFoundView)
    NSLayoutConstraint.activate([ /* top/leading/trailing/bottom = view */ ])
}
```

Y al cargar con éxito se retira: `notFoundView.removeFromSuperview()`.

**Por qué:**

- **Pantalla completa en lugar de alert:** el mensaje es el estado principal de esa pantalla, no un aviso transitorio; además, el botón "atrás" de la barra de navegación sigue disponible (la vista cubre el área del contenido, no la barra).
- **`guard notFoundView.superview == nil`:** protege de duplicar la vista o sus constraints si el estado se dispara dos veces.
- **Subtitulo dinámico con `userID`:** contextualiza el error ("el id X no existe"), lo que ayuda a depurar.
- **Se retira al tener éxito:** si la consulta vuelve a responder (p. ej. reintento que sí encuentra), la tabla vuelve a aparecer sin reiniciar la vista.

---

## Cómo verificar la API

Antes de probar en el simulador, conviene confirmar que los endpoints responden como se espera. Todo se puede hacer con `curl` desde Terminal:

```bash
# 1. Lista de usuarios (10 registros)
curl https://jsonplaceholder.typicode.com/users

# 2. Un solo usuario por id (ej. 7)
curl https://jsonplaceholder.typicode.com/users/7

# 3. Id inexistente → HTTP 404
curl -i https://jsonplaceholder.typicode.com/users/999
#   → HTTP/1.1 404 Not Found
#   → body: {}
```

**Qué revisar:**

| Comando | Esperado | Qué valida |
|---|---|---|
| `users` | Arreglo JSON de 10 usuarios con las llaves del modelo | El `User: Codable` del Paso 1 |
| `users/7` | Objeto único (no arreglo) | Que el detalle use `decode(User.self)` y no `[User]` |
| `users/999` | `404` con `{}` | La rama `UserAPIError.notFound` del Paso 8 |

> La URL de la imagen de avatar (`https://i.pravatar.cc/300?img=7`) se puede probar pegándola en un navegador: devolverá una imagen JPG.

---

## Errores comunes y buenas prácticas

### Errores típicos al hacer este tipo de app

| Error | Síntoma | Cómo evitarlo |
|---|---|---|
| Olvidar `translatesAutoresizingMaskIntoConstraints = false` | Constraints ignoradas o vistas en (0,0) | Ponerlo en **toda** vista creada en código |
| `URL(String:)` (sin `string`) | Error de compilación | El inicializador correcto es `URL(string:)` |
| Decodificar en `Any` | Error de compilación | Siempre un modelo `Codable` tipado |
| No validar el `HTTPURLResponse` | Se "descodifican" errores HTTP | Validar `(200...299).contains(statusCode)` |
| Celda sin "sello" de URL | Avatar equivocado al hacer scroll | El guard `avatarURL == url` del Paso 6 |
| `UIRefreshControl` duplicado en `UITableViewController` | Error "cannot override" | `UITableViewController` ya trae `refreshControl`; usa `tableView.refreshControl =` |
| Actualizar UI fuera del hilo principal | Comportamiento impredecible/crash | Confiar en el aislamiento MainActor del proyecto |
| Crear el `UINavigationController` en el storyboard XML a mano | Archivo frágil | Hacerlo en `SceneDelegate` en código (Paso 4) |

### Buenas prácticas aplicadas en este proyecto

1. **Separar responsabilidades:** el modelo (`User`), la descarga (`URLSession`), la celda (`UserTableViewCell`) y el controlador están en archivos distintos con un propósito único.
2. **Tipos fuertes en la red:** nunca `[String: Any]`; siempre `Codable`.
3. **Validar todo lo que entra de la red:** status code antes de decodificar.
4. **Cachear lo repetible:** avatares con `NSCache`.
5. **Manejar la reutilización de celdas:** sello de URL para imágenes asíncronas.
6. **Estados explícitos en la UI:** cargando / vacío / error / datos.
7. **Errores con significado:** `LocalizedError` en lugar de mensajes crudos de `URLError`.
8. **No bloquear el hilo principal:** siempre `async/await` para red.
9. **`[weak self]` en clausuras y `Task`:** evita ciclos de retención.

---

## Posibles mejoras siguientes

Ideas de evolución ordenadas de **fáciles y de bajo riesgo** a **más grandes** (requieren más estructura). La app ya cubre lo esencial; estas mejoras la acercan a un producto real. Cualquiera de ellas mantiene la filosofía del proyecto: `URLSession`, UIKit y sin dependencias externas (excepto donde se indique).

### 🔹 Fáciles (alto valor, bajo riesgo)

1. **Búsqueda/filtro local** — Agregar un `UISearchController` y filtrar `users` por nombre/email en memoria. Implica solo actualizar el arreglo mostrado y `reloadData()`. Excelente para practicar `UISearchResultsUpdating`.

2. **Accesibilidad** — Etiquetas *VoiceOver* descriptivas en las celdas, *Dynamic Type* (ya se usa `preferredFont` en parte) y contraste adecuado. iOS audita accesibilidad con el **Accessibility Inspector** de Xcode.

3. **Localización** — Mover los textos ("Usuarios", "Error", "Usuario no encontrado") a un String Catalog (`.xcstrings`). El proyecto ya tiene `STRING_CATALOG_GENERATE_SYMBOLS = YES`, así que el soporte está listo: solo falta extraer los strings.

4. **Paginación** — JSONPlaceholder no pagina, pero el patrón aplica: al llegar cerca del final (`scrollViewDidScroll` + umbral) lanzar `GET /users?_page=N&_limit=10`, mostrar un spinner al pie (`tableFooterView`) y anexar datos.

### 🔸 Medias (ya requieren más estructura)

5. **Capa de red genérica (APIClient)** — Extraer la duplicación de `URLSession` + validación de status + `JSONDecoder` (hoy repetida en lista y detalle) a un cliente reutilizable:

   ```swift
   protocol APIClientProtocol {
       func get<T: Decodable>(_ path: String) async throws -> T
   }
   ```

   Con un `enum Endpoint` que centralice las URLs (`users`, `user(id:)`, `avatar(id:)`). Reduce duplicación y facilita los tests (punto siguiente).

6. **Tests unitarios (XCTest)** — El target `GS_proof_UsersTests` ya existe. Pruebas de alto valor sin tocar la UI:
   - Decodificar un **fixture JSON** (copia local de la respuesta) en `[User]` con `JSONDecoder`.
   - Verificar que un status `404` produce `UserAPIError.notFound`.
   - Probar `buildSections(with:)` (que las secciones/rows se arman correctamente).

7. **Caché en disco + cancelación de tareas** — Mejorar `AvatarLoader`:
   - **Caché en disco** (directorio `Caches/`) para no recargar avatares entre sesiones.
   - **Cancelación cooperativa**: guardar la `URLSessionTask` y cancelarla si la celda se reutiliza, o comprobar `Task.isCancelled`. Hoy el guard de `avatarURL` ya evita *imágenes equivocadas*; la cancelación añade eficiencia pura.

8. **Persistencia offline** — Guardar los últimos usuarios con **SwiftData** (o CoreData) y mostrar la caché cuando la red falle. Requiere una capa de almacenamiento y decidir la política de refresco.

9. **Detección de conectividad** — Usar **NWPathMonitor** para mostrar un banner "Sin conexión" y evitar consultas fallidas innecesarias. Combinado con timeouts explícitos (`URLSessionConfiguration.timeoutIntervalForRequest`).

### 🔺 Grandes (requieren rediseño parcial)

10. **Arquitectura MVVM** — Mover la lógica de red/estado fuera del `UIViewController` a *view models* observados (`@Observable` en iOS 17+ o Combine). Los controladores quedan delgados y la lógica se puede testear sin UI.

11. **Inyección de dependencias** — Pasar el `APIClient` (protocolo) por `init` al `ViewController` y al detalle en lugar de usar `URLSession.shared` global. Es el habilitador clave para tests realistas de los controladores.

12. **Imágenes con librería de terceros** — Integrar **Kingfisher o SDWebImage** (via Swift Package Manager) para `UIImageView.kf.setImage(with:)`: cache en memoria+disco, cancelación automática y placeholders, a costa de añadir una dependencia.

13. **App por módulos / SwiftUI progresivo** — Migrar gradualmente el detalle a SwiftUI con un *hosting controller* (`UIHostingController`) y `UIViewControllerRepresentable`, manteniendo la lista en UIKit mientras se valida implementación.

> 💡 **Sugerencia de orden:** empezar por la paginación o búsqueda (mejoras visibles e inmediatas), seguir con las pruebas unitarias de decodificación (blindan el modelo contra cambios de la API) y la capa `APIClient` (reduce duplicación), y dejar MVVM/inyección de dependencias para cuando la app crezca.

---

## Cómo correr el proyecto

1. Abre `GS_proof_Users.xcodeproj` en Xcode.
2. Selecciona un simulador de iPhone (o dispositivo).
3. Presiona **⌘R** (Run).

Flujo esperado:

1. La lista muestra un **spinner** mientras consulta `https://jsonplaceholder.typicode.com/users`.
2. Se cargan los **10 usuarios** con su nombre, `@username · email` y **avatar circular**.
3. **Jala** la tabla hacia abajo para refrescar (pull-to-refresh).
4. Toca un usuario → el detalle consulta `.../users/{id}` y muestra avatar + secciones General/Dirección/Compañía.
5. Si el id no existe (404) → vista completa **"Usuario no encontrado"**.

> Prueba del caso 404: cambia temporalmente en `ViewController.didSelectRowAt` el `userID` a un valor alto (ej. `999`) o navega directamente con `UserDetailViewController(userID: 999)`.

---

## Estructura final de archivos

```
GS_proof_Users/                       (carpeta sincronizada → TODOS estos archivos entran al target)
├── AppDelegate.swift                 (plantilla, sin cambios)
├── SceneDelegate.swift               (modificado: NavigationController)
├── ViewController.swift              (reescrito: lista + URLSession + estados)
├── User.swift                        (nuevo: modelo Codable)
├── UserTableViewCell.swift           (nuevo: celda con avatar asíncrono)
├── AvatarLoader.swift                (nuevo: caché de imágenes)
├── UserDetailViewController.swift    (nuevo: detalle con URL dinámica)
├── UserAPIError.swift                (nuevo: error 404 tipado)
├── Info.plist
├── Assets.xcassets
└── Base.lproj/ (LaunchScreen, Main)
Build Project.md                      (este documento — fuera de la carpeta del target, no altera la compilación)
```

> El archivo de esta guía vive en la **raíz del proyecto** y no dentro de `GS_proof_Users/`, por lo que el esquema sincronizado no lo incluye en el build: **no altera el proyecto**.

---

## Apéndice — Código final completo

Código íntegro y actualizado de los archivos creados/modificados (a la fecha de esta guía). Si algún fragmento en los pasos anteriores queda cortado, aquí está la versión completa.

### `GS_proof_Users/User.swift`

```swift
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
```

### `GS_proof_Users/UserAPIError.swift`

```swift
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
```

### `GS_proof_Users/AvatarLoader.swift`

```swift
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
```

### `GS_proof_Users/UserTableViewCell.swift`

```swift
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
```

### `GS_proof_Users/ViewController.swift`

```swift
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
```

### `GS_proof_Users/UserDetailViewController.swift`

```swift
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
```

### `GS_proof_Users/SceneDelegate.swift` (solo la parte modificada)

```swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    // Carga la escena con la vista inicial envuelta en un UINavigationController
    // para poder navegar al detalle de cada usuario.
    guard let windowScene = (scene as? UIWindowScene) else { return }

    let window = UIWindow(windowScene: windowScene)
    let storyboard = UIStoryboard(name: "Main", bundle: nil)
    let rootViewController = storyboard.instantiateInitialViewController() ?? ViewController()
    window.rootViewController = UINavigationController(rootViewController: rootViewController)
    self.window = window
    window.makeKeyAndVisible()
}
```

---

*Fin del documento. Esta guía es únicamente documentación: no se compila ni forma parte del target de la app.*