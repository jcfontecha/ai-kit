# Macro Feasibility (AIKit)

This repo can support **Swift macros** for schema authoring in a way that stays consistent with AIKit’s single-schema strategy (`ObjectSchema<T>` + `JSONSchema`).

## What we learned from `../ai-kit`

`../ai-kit` already has a working pattern that maps well to AIKit v2:

- A **compiler plugin target** (`AIKitMacros`) that implements macros using SwiftSyntax.
- A separate **library target** (`AIKitMacro`) that exposes the user-facing `@AIModel` / `@Field` macros.
- The core SDK (`AIKitCore`) remains **macro-free** and can be used without any trust prompts or SwiftSyntax dependency.

We ported that pattern here.

## Current state in this repo

### Package

Macros live in a **separate Swift package** at `AIKitMacros/`:

- `AIKitMacros` (compiler plugin module; depends on `swift-syntax`)
- `AIKitMacro` (library you import; depends on `AIKit` + `AIKitMacros`)

The main AIKit package at the repo root remains **macro-free** (no SwiftSyntax dependency).

`AIKitMacro` re-exports `AIKit`, so in most cases you can just:

```swift
import AIKitMacro
```

### Toolchain + dependency

- This environment is running **Swift 6.2**.
- `AIKitMacros/Package.swift` pins `swift-syntax` at `602.0.0`, which matches Swift 6.2’s macro support distribution.

### Macro API

User-facing macros are in `AIKitMacros/Sources/AIKitMacro/AIModelMacro.swift`:

- `@AIModel`: synthesizes:
  - `extension Type: SchemaProviding {}`
  - `static var schema: ObjectSchema<Type>`
  - nested `struct Partial: Codable, Sendable` (all fields optional; initializer generated)
- `@Field(...)`: metadata-only annotation used by `@AIModel`

Supported `@Field` arguments right now:

- `description` (positional string)
- `minLength`, `maxLength`, `pattern`, `format`, `enum`
- `range` (parsed from `a...b` syntax; applied to `Int`/`Double`/`Float`)
- `minItems`, `maxItems` (for arrays)

### Schema correctness: nested `$schema`

AI SDK’s JSON Schema shape generally includes `"$schema"` only at the **root**, not in nested subschemas.

To match that, we updated schema builders to strip nested `"$schema"` when embedding properties/items:

- `Sources/AIKitProviders/JSON/JSONSchema+Builders.swift`

This matters both for macro-generated schemas and for manually-authored schemas.

## Feasibility & risk assessment

### Feasible / good fit

- **Yes**, macros are a good fit for generating `SchemaProviding` conformance and `ObjectSchema<T>` boilerplate.
- Keeping macros in an **optional package** avoids forcing SwiftSyntax + trust prompts on everyone.
- SwiftPM CLI builds work fine; macro compilation is validated by `AIKitMacros/Tests/AIKitMacroTests/AIKitMacroTests.swift`.

### Main risks / tradeoffs

- **Version coupling:** SwiftSyntax versions must track Swift toolchains (we pinned `602.0.0` for Swift 6.2).
- **Xcode trust prompts:** Xcode requires trusting compiler plugins/macros. If you’ve found a reliable trust/approval workflow, this becomes manageable; without it, macros remain painful for some teams.
- **Type-system limits:** macros can’t truly “reflect” runtime `Codable` behavior; they only see syntax. We currently:
  - handle common primitives and arrays
  - assume non-primitive types are `SchemaProviding` (best-effort)

## Recommendation

Make macros the **recommended ergonomics layer**, but keep the **escape hatch** (`ObjectSchema.manual(jsonSchema: ...)`) for external types as the stable baseline:

- App teams that can trust macros get the best DX (`@AIModel`).
- Everyone else can still use AIKit without compiler plugins.
