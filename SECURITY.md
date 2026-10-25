# Security

Report vulnerabilities through GitHub's private vulnerability reporting on this repository (Security, then Report a vulnerability). Do not open a public issue.

Include the affected endpoint or file, steps to reproduce, and the impact.

Areas that matter most:

- `server/`: authentication, owner checks in Convex, signed automation grants, connector data handling and the metered routes.
- `ios/`: Keychain credential storage and the per-account conversation cache.

If you find a secret in the repository or its history, report it the same way.
