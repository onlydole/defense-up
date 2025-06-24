# Defense-Up

A demonstration project showcasing Software Bill of Materials (SBOM) generation and GitHub Attestations for supply chain security.

## Overview

This project demonstrates modern supply chain security practices including:

- **SBOM Generation**: Automated Software Bill of Materials creation
- **GitHub Attestations**: Cryptographic attestations for build integrity
- **Container Security**: Multi-stage Docker builds with security best practices
- **Supply Chain Verification**: End-to-end traceability from source to deployment

## Quick Start

### Docker Compose

```bash
# Run with docker-compose
docker compose up --build
```

The application will be available at `http://localhost:5001` with `docker compose up`.

## Security Features

### SBOM Generation

This project automatically generates SBOMs during the build process to provide complete dependency transparency.

### GitHub Attestations

Build artifacts are cryptographically attested using GitHub's attestation framework, ensuring:

- Build provenance verification
- Dependency integrity
- Reproducible builds

### Container Security

- Multi-stage builds to minimize attack surface
- Non-root user execution
- Minimal base images
- Dependency pinning

## Supply Chain Security

The project implements a complete supply chain security workflow:

1. **Source Control**: Git-based version control with signed commits
2. **Build Verification**: Automated SBOM generation and attestation
3. **Artifact Integrity**: Cryptographic verification of build outputs
4. **Deployment Security**: Secure container deployment practices

## Project Structure

```bash
defense-up/
├── app/                 # Application source code
├── Dockerfile          # Multi-stage container build
├── docker-compose.yml  # Local development setup
└── requirements.txt    # Python dependencies
```

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for details.
