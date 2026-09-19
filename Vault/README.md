# Vault Package

Vault package that contains the library for the Vault app.
It's a Swift package that defines several targets, ultimately vended via `VaultiOS` to the application wrapper.

## Platform Support

Due to general capacity constraints and to make Vault work the best for all users, we only aim to support the latest major iOS release.
It's just not feasible to support multiple iOS versions without sufficient testing capacity.

## Architecture

There's essentially 3 storage representations, which we encode and decode from.

To avoid exponential growth of encoders and decoders between all the formats, we always only encode and decode to the Application Layer `VaultItem`.
This gives us a common format and source of truth for fields that should be present in all the other formats.

```
                               ┌────────────────┐
                               │                │
                               │  Application   │
                            ┌─▶│  Layer         │◀─┐
                            │  │                │  │
                            │  │  [VaultItem]   │  │
                            │  └────────────────┘  │
                            │                      │
                            │                      │
                            │                      │
                            │                      │
┌─────────────────────────┐ │                      │    ┌────────────────────┐
│                         │ │                      │    │                    │
│  Persistence            │ │                      │    │ Backup             │
│  Layer (SwiftData)      │◀┘                      └──▶ │ Layer              │
│                         │                             │                    │
│  [PersistedVaultItem]   │                             │ [VaultBackupItem]  │
└─────────────────────────┘                             └────────────────────┘
```

Encrypted items use a custom encoding format, codified by `VaultItemEncryptedContainer`.
This allow their contents to be fully encrypted within every layer, using a consistent format for each.
The model type has an identifier associated with it, so if we need to upgrade the format, we can do so without breaking old clients.

## Key Derivation

Once defined, a key deriver's composition can never be changed for backwards compatibility.
Vault defines some standard key derivers that are used by default to create encryption keys for a variety of purposes.

In the case of a composition key deriver: the output at each step is directed as an input to the next step.

These derivers are benchmarked via `make benchmark-keygen`, so you can see their performance on your machine.

| Key Deriver Namespace        | Purpose                                                                                                                                                                                                                                                                                                                 |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `vault.keygen.backup.fast`   | Derivation for vault export backups in non-optimized binary builds. Scaled-down parameters for all key derivation algorithms so they are a lot faster to compute. Still technically secure, but not for sustained offline attacks.                                                                                      |
| `vault.keygen.backup.secure` | Derivation for backups in optimized binary builds. Relatively slow to compute, even on an optimized build. Uses a variety of compute-hard and memory-hard key derivation algorithms. Designed to be resilient to sustained, long-term offline attacks to protect data in the event of the theft of an encrypted backup. |
| `vault.keygen.item.fast`     | Derivation for individual vault items in non-optimized binary builds. Scaled-down parameters for all derivations.                                                                                                                                                                                                       |
| `vault.keygen.item.secure`   | Derivation for individual vault items in optimized binary builds. Designed to be relatively resilient to attacks, but much faster to keygen that the secure backup key, as this operation is preformed much more often.                                                                                                 |

### `vault.keygen.backup.fast.v1`

A composition key deriver, using the same salt at each step, in this order:

1. PBKDF2, 256 bit key length, SHA2 (SHA384), 2000 iterations
2. HKDF, 256 bit key length, SHA3 (SHA512)
3. scrypt, 256 bit key length, N = 1 << 6, r = 4, p = 1

### `vault.keygen.backup.secure.v1`

A composition key deriver, using the same salt at each step, in this order:

1. PBKDF2, 256 bit key length, SHA2 (SHA384), 5452351 iterations
2. HKDF, 256 bit key length, SHA3 (SHA512)
3. scrypt, 256 bit key length, N = 1 << 18, r = 8, p = 1

### `vault.keygen.item.fast.v1`

A composition key deriver, using the same salt at each step, in this order:

1. scrypt, 256 bit key length, N = 1 << 6, r = 4, p = 1
2. PBKDF2, 256 bit key length, SHA2 (SHA384), 1001 iterations

### `vault.keygen.item.secure.v1`

A composition key deriver, using the same salt at each step, in this order:

1. scrypt, 256 bit key length, N = 1 << 8, r = 4, p = 1
2. PBKDF2, 256 bit key length, SHA2 (SHA384), 372002 iterations

### `vault.keygen.testing`

Only for use during testing.
Algorithm is liable to change.

### `vault.keygen.failing`

Only for use during testing.
Designed to cause an internal error during key generation.

## Storage Resilience

- Throughout the development of the application, version `1.0` was used as the marketing version of the app.
- During development, many breaking changes were made to the storage format that makes this version unsafe and unresilient.
- To respect SemVer, we bumped the marketing version to `2.0` to indicate that the app is now storage resilient.

## Testing Configuration

<table>
  <tr>
	<td>Simulator for snapshot tests</td>
	<td><b>iPhone 18 Pro Max on iOS 27.0</b></td>
  </tr>
</table>

Simulator configuration, such as setting locale is covered by the use of test plans.
You shouldn't need to manually change the locale or any other simulator setting for the tests to pass.

## Development Workflow

<table>
  <tr>
	<td>Format Sources</td>
	<td><b>make format</b></td>
  </tr>
  <tr>
	<td>Lint Sources</td>
	<td><b>make lint</b></td>
  </tr>
  <tr>
	<td>Force clean existing build artifacts</td>
	<td><b>make clean</b></td>
  </tr>
  <tr>
	<td>Generate App Store screenshots (see <a href="./Screenshots/README.md">Screenshots/</a>)</td>
	<td><b>make screenshots</b></td>
  </tr>
</table>
