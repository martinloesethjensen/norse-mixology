import CryptoKit
import Foundation

/// The Ed25519 public keys trusted to sign `/v1/manifest.json`. The catalog's
/// publish job signs the exact manifest bytes into `manifest.json.sig` (base64
/// of the 64-byte signature); an update is applied only when one of these keys
/// verifies it. More than one key lets a new key ship before the old one retires.
public struct CatalogSigningKeys: Sendable {
    public static let signatureByteLimit = 1_024

    /// Raw 32-byte keys, each already known to be a valid Ed25519 public key.
    private let rawKeys: [Data]

    /// `base64Keys` are raw 32-byte Ed25519 public keys, base64-encoded — the
    /// "App key" line printed by norse-catalog's `scripts/new-signing-key.sh`.
    public init(base64Keys: [String]) throws {
        guard !base64Keys.isEmpty else {
            throw CatalogError.invalidSigningKey("no keys")
        }
        rawKeys = try base64Keys.map { (encoded: String) throws -> Data in
            guard let raw = Data(base64Encoded: encoded), (try? Curve25519.Signing.PublicKey(rawRepresentation: raw)) != nil else {
                throw CatalogError.invalidSigningKey(encoded)
            }
            return raw
        }
    }

    public init(keys: [Curve25519.Signing.PublicKey]) {
        rawKeys = keys.map(\.rawRepresentation)
    }

    /// Throws `.invalidSignature` unless `signatureFile` is a signature over
    /// `manifest` by one of the trusted keys.
    func verify(_ manifest: Data, signatureFile: Data) throws {
        let text = String(decoding: signatureFile, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: text), signature.count == 64 else {
            throw CatalogError.invalidSignature
        }
        let trusted = rawKeys.contains { raw in
            guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
            return key.isValidSignature(signature, for: manifest)
        }
        guard trusted else {
            throw CatalogError.invalidSignature
        }
    }
}
