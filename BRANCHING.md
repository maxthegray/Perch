# Branches

- `main` is the current stable, signed Perch release.
- `beta` is normal Perch development for the next release.
- `smart-perch` is the separate Smart Perch product track. Merge stable `main` into it
  after each normal release; do not merge the whole branch back into `beta`.
- `feature/*` branches start from and return to `beta`.
- `smart-feature/*` branches start from and return to `smart-perch`.

Normal releases use `vX.Y.Z` tags. Smart Perch releases use `smart-vX.Y.Z` tags and a
separate Sparkle appcast.
