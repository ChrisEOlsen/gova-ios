# Claude Code Context: GOVA iOS

You are the iOS Lead for a GOVA iOS app. Your job is to faithfully translate a web
application built with the gova-monolith stack into a native SwiftUI app. The Go
backend and JSON API are shared — you are only building the iOS client. The web app's
SEED.md (populated automatically by running `/export:mobile` here) is the source of truth for
screens, data models, and API endpoints.

---

## What This Repo Is

`gova-ios` is a template repository. When a developer runs `/build`, Claude reads the
Generated Context block in `SEED.md`, translates each screen from the web app into a
SwiftUI View + ViewModel pair, and wires them together into a working native iOS app.

The Go JSON API (running via Docker in the gova-monolith project) is the shared backend.
This repo only contains the iOS client. The Xcode project is managed by XcodeGen —
after adding any Swift file, always run `xcodegen generate` inside `ios/` to update the project.

---

## First-Time Setup (once per clone)

Before running `/prep`, `/export:mobile` or `/build`, the developer must run `./install-claude.sh`
from the repo root. It sets `Config.plist`'s `API_BASE_URL` and, if given the gova-monolith
project's `APP_NAME`, writes `.mcp.json` so the `gova-builder` MCP tools (`inspect_app`,
`scaffold_mobile_auth`) connect to that project's running MCP container. `.mcp.json` ships
empty — those tools are unavailable until this script has been run and `gova-monolith`'s
containers are up (`docker compose up -d`).

After that, `/prep` is the entry point: it asks the developer for app name, gova-monolith
path, API base URL and design notes, writes them into `SEED.md`, syncs `Config.plist`, then
runs `/export:mobile` to populate the Generated Context block. The developer runs `/build`
next.

---

## Translation Guide

### Step 1 — Read the SEED.md Generated Context

Before writing any Swift code, read the Generated Context block in `SEED.md` and confirm:
- The list of screens (one per JS module in the web app)
- Each screen's data model fields and their types
- Which API endpoints each screen uses
- Whether authentication is required

If the Generated Context block is empty, STOP. Tell the developer to set `Web App Path`
in SEED.md and run `/export:mobile` — it writes that section into SEED.md directly.

### Step 2 — Extend the Go API for mobile auth (if auth is required)

Web auth uses signed HMAC-SHA256 cookies — mobile cannot use these.
Use the gova-builder MCP tool `scaffold_mobile_auth` to add token-based auth endpoints
alongside the existing cookie auth. The web app's cookie auth is untouched.

This tool is idempotent — safe to call even if gova-android has already called it.

Endpoints added to the Go API (every gova-monolith response is wrapped in
`{"ok":bool,"data":...,"error":"..."}` — `APIClient` unwraps this automatically, so the
shapes below are the `data` payload your Swift types decode, not the raw response body):
- `POST /api/auth/login_token` → `{ "token": "...", "user": { "id": 1, "name": "...", "email": "..." } }`
- `DELETE /api/auth/logout_token` → invalidates the token
- `GET /api/auth/me_token` → returns the current user for a valid Bearer token

### Step 3 — Define Swift models

Write one Swift struct per data model in SEED.md to `ios/GovaApp/Models/ModelName.swift`.

Field type mapping:

| SEED.md type | Swift type |
|---|---|
| string | String |
| int | Int |
| boolean | Bool |
| float | Double |
| created_at | Date |

If a field can be `NULL` in the gova-monolith schema (check `inspect_app` or the model's
Go struct — a pointer type or `sql.Null*` field means nullable), make the Swift property
optional (e.g. `String?`) instead of using the table above directly. A non-optional
property decoding a `null` value fails the whole list, not just that item.

All models must conform to `Codable` and `Identifiable` with `var id: Int`.
Use `CodingKeys` to map `snake_case` JSON to `camelCase` Swift properties.

Example — a model with fields `name:string, status:string`:

```swift
struct Item: Codable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, status
        case createdAt = "created_at"
    }
}
```

After writing the file, run:
```bash
cd ios && xcodegen generate
```

### Step 4 — Build screens (one per JS module in the web app)

Each screen becomes two files:
- `ios/GovaApp/ViewModels/NameViewModel.swift` — owns all fetch logic and `@Published` state
- `ios/GovaApp/Views/NameView.swift` — pure rendering, zero network calls

Build the ViewModel first, then the View. After writing both files, run:
```bash
cd ios && xcodegen generate
```

Every ViewModel must declare:
```swift
@Published var isLoading = false
@Published var errorMessage: String? = nil
```

Every View must display the error when it is non-nil:
```swift
if let msg = viewModel.errorMessage {
    Text(msg).foregroundStyle(.red).font(.caption)
}
```

### Step 5 — Wire navigation

Update `ios/GovaApp/ContentView.swift` to include `NavigationStack` destinations for each
generated screen. If auth is required, show `LoginView` when `auth.isLoggedIn == false`.

Run `xcodegen generate` after editing ContentView.swift if you add new imports.

### Step 6 — Verify

```bash
cd ios && xcodebuild -scheme GovaApp -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

Check before reporting done:
- Every ViewModel has `isLoading` and `errorMessage` states
- Every View displays `errorMessage` when non-nil
- Auth gate wired: `LoginView` shown when `!auth.isLoggedIn` (if auth required)
- No force unwraps (`!`) in generated Swift code
- No raw `URLSession` calls — always `APIClient.shared`
- No tokens in `UserDefaults` — always `AuthManager`
- `xcodegen generate` was run after the last file was added

---

## Web-to-iOS Pattern Mapping

| Web (JS module pattern) | iOS (SwiftUI equivalent) |
|---|---|
| `loadList()` → fetch → `renderList()` | `vm.load()` → `@Published var items: [Model]` → `List { ForEach(items) }` |
| `add_js_form` creation form | `.sheet(isPresented: $showCreate) { Form { TextField... Button("Save") } }` |
| `del('/api/x/:id')` delete | `.onDelete { offsets in Task { await vm.delete(items[offsets.first!]) } }` |
| `requireAuth()` at module top | `.onAppear { if !auth.isLoggedIn { showLogin = true } }` |
| `api.js get(path)` | `try await APIClient.shared.get(path: path)` |
| `api.js post(path, body)` | `try await APIClient.shared.post(path: path, body: body)` |
| `api.js del(path)` | `try await APIClient.shared.delete(path: path)` |
| `element.textContent = item.name` | `Text(item.name)` |
| `res.error ?? 'Something went wrong.'` | `Text(errorMessage).foregroundStyle(.red)` |

---

## Architecture Rules (Non-Negotiable)

1. **MVVM always.** No network calls in Views. ViewModels only.
2. **APIClient always.** Never call `URLSession` directly. Use `APIClient.shared`.
3. **Keychain always.** Never store tokens in `UserDefaults`. `AuthManager` handles Keychain.
4. **No force unwrap.** Never use `!` on optionals in production code. Use `guard let`.
5. **@MainActor on ViewModels.** Mark all ViewModel classes `@MainActor` to avoid concurrency warnings on `@Published` mutations.
6. **async/await only.** No completion handler callbacks.
7. **NavigationStack.** Never use the deprecated `NavigationView`.
8. **Error states required.** Every API call must have a visible error state in the UI.
9. **Config.plist for base URL.** Never hardcode the API base URL. `APIClient` reads from `Config.plist`.
10. **xcodegen after adding files.** After creating any new `.swift` file, run `xcodegen generate` in `ios/`.

---

## Infrastructure Files (Pre-committed — Do Not Regenerate)

These live in `ios/GovaApp/Lib/`. They are the iOS equivalents of `api.js` and `auth.js`.
Never overwrite them. Import and use them.

**`APIClient.swift`**
- `static let shared = APIClient()`
- Reads `API_BASE_URL` from `Config.plist` at init
- Injects `Authorization: Bearer <token>` header if `AuthManager` has a token
- Automatically unwraps gova-monolith's `{"ok":bool,"data":...,"error":"..."}` envelope —
  `get`/`post` return the decoded `data` payload directly; models describe only that payload,
  never the envelope itself
- `func get<T: Decodable>(path: String) async throws -> T`
- `func post<T: Decodable>(path: String, body: some Encodable) async throws -> T`
- `func delete(path: String) async throws`
- Throws `APIError`: `.network(Error)`, `.decode(Error)`, `.server(statusCode: Int, message: String)`

**`AuthManager.swift`**
- `static let shared = AuthManager()` — `ObservableObject`
- `@Published private(set) var isLoggedIn: Bool`
- `@Published private(set) var currentUser: UserInfo?`
- `nonisolated var token: String?` — reads from Keychain, safe from any thread/actor
- `@MainActor func login(token: String, user: UserInfo)`
- `@MainActor func logout()`
- Keychain key: `"gova.auth.token"`

**`UserInfo`** (defined in `AuthManager.swift`): `id: Int`, `name: String`, `email: String`

---

## MCP Tools Available

The gova-builder MCP (from the connected gova-monolith instance) provides:

| Tool | When to use |
|---|---|
| `inspect_app` | Read web app models, handlers, routes before translating |
| `scaffold_mobile_auth` | Add token auth endpoints to the Go API (idempotent) |

All iOS file creation is done by Claude directly using its file tools.
No MCP tools are used for Swift file generation.
