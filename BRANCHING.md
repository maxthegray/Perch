# Branches

- `main` is the current stable, signed Perch release.
- `beta` is development for the next Perch release, including Smart Perch work.
- `feature/*` branches start from and return to `beta`.
- `smart/*` branches also start from and return to `beta`.
- `smart-perch` is legacy compatibility only. Do not develop on it or merge it
  back after the unified release.

All releases use `vX.Y.Z` tags and the appcast on `main`.

After publishing the first unified release, run:

```sh
./Scripts/publish-smart-perch-bridge.sh X.Y.Z
```

That replaces only `appcast.xml` on the legacy branch. Existing Smart Perch
installs receive the unified app once, whose bundled feed then follows `main`.
Keep the branch afterward so installations that were offline can still migrate.
