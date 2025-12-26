import Foundation

/// Provider-specific options passed through to the provider implementation.
///
/// Mirrors the JS AI SDK `providerOptions` shape: provider namespace → option bag.
public typealias ProviderOptions = [String: [String: JSONValue]]

