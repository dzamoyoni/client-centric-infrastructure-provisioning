# Helper Scripts Reference

[← Back to Documentation Hub](README.md) | [Main README](../README.md)

---

## Overview

Automation scripts in `scripts/` directory for common operations.

---

## 1. CIDR Validation Script

**Location**: `scripts/validate-cidr.sh`

**Purpose**: Prevents CIDR conflicts across clients

**Usage**:
```bash
./scripts/validate-cidr.sh
```

**What it checks**:
- Duplicate CIDR detection
- CIDR format validation
- Reserved range verification
- Cross-client overlap detection

**Integration**:
```bash
# Add to pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
./scripts/validate-cidr.sh || exit 1
EOF
chmod +x .git/hooks/pre-commit
```

---





## Related Documentation

- [Getting Started](GETTING-STARTED.md) - Initial setup
- [Troubleshooting](TROUBLESHOOTING.md) - Script issues
- [Security](SECURITY.md) - Secure script usage

---

**Last Updated**: January 31, 2026  
**Maintained By**: Platform Engineering Team
