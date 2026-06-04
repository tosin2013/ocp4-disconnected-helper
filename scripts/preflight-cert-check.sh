#!/bin/bash
# Preflight certificate configuration validation
# Added 2026-06-04 per incident hardening (registry TLS auth failure)
#
# Purpose: Verify ssl_cert_provider matches available infrastructure
# Usage: ./scripts/preflight-cert-check.sh
# Exit codes: 0 = match, 1 = mismatch warning

set -euo pipefail

# Configuration
AWS_CREDS="$HOME/.aws/credentials"
INVENTORY="inventory/ibm-cloud.yml"

echo "=========================================="
echo "Preflight Certificate Configuration Check"
echo "=========================================="
echo ""

# Check for AWS credentials
if [[ -f "$AWS_CREDS" ]]; then
  echo "✅ AWS credentials found at $AWS_CREDS"
  RECOMMENDED="letsencrypt"
else
  echo "❌ AWS credentials NOT found at $AWS_CREDS"
  RECOMMENDED="selfsigned"
fi

# Extract configured provider from inventory
if [[ ! -f "$INVENTORY" ]]; then
  echo "❌ ERROR: Inventory file not found at $INVENTORY"
  exit 2
fi

CONFIGURED=$(grep "ssl_cert_provider:" "$INVENTORY" | head -1 | awk '{print $2}' | tr -d '"' || echo "not_set")

echo ""
echo "Configuration Status:"
echo "  Recommended provider: $RECOMMENDED"
echo "  Configured provider:  $CONFIGURED"
echo ""

# Validate match
if [[ "$CONFIGURED" == "$RECOMMENDED" ]]; then
  echo "✅ Configuration matches infrastructure"
  echo ""
  echo "Ready for deployment:"
  echo "  ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --tags registry"
  echo ""
  exit 0
elif [[ "$CONFIGURED" == "not_set" ]]; then
  echo "⚠️  WARNING: ssl_cert_provider not set in inventory"
  echo "   Will use auto-detection (checks ~/.aws/credentials)"
  echo "   Auto-detected value: $RECOMMENDED"
  echo ""
  exit 0
else
  echo "⚠️  WARNING: Configuration mismatch detected!"
  echo ""
  echo "Recommended action:"
  echo "  Edit $INVENTORY"
  echo "  Change: ssl_cert_provider: \"$CONFIGURED\""
  echo "  To:     ssl_cert_provider: \"$RECOMMENDED\""
  echo ""
  echo "Rationale:"
  if [[ "$RECOMMENDED" == "letsencrypt" ]]; then
    echo "  - AWS credentials available for Route53 DNS-01 validation"
    echo "  - Let's Encrypt certificates are auto-trusted (no CA distribution)"
    echo "  - Recommended for cloud deployments (IBM Cloud, AWS, GCP)"
  else
    echo "  - No AWS credentials available for Let's Encrypt"
    echo "  - Self-signed CA requires manual trust store installation"
    echo "  - Required for true air-gapped/on-premise deployments"
  fi
  echo ""
  echo "You can proceed with current configuration, but this may cause TLS authentication issues."
  echo ""
  exit 1
fi
