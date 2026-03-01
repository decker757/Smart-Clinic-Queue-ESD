#!/bin/sh
# Extracts the RSA public key PEM from the auth-service JWKS endpoint.
# The output is set as BETTER_AUTH_RSA_PUBLIC_KEY in Kong's Railway env vars.
#
# Usage:
#   sh infra/scripts/extract-jwks-pem.sh <auth-service-url>
#
# Example (local):
#   sh infra/scripts/extract-jwks-pem.sh http://localhost:3000
#
# Example (Railway):
#   sh infra/scripts/extract-jwks-pem.sh https://auth-service.up.railway.app

AUTH_URL=${1:-http://localhost:3000}

echo "Fetching JWKS from $AUTH_URL/api/auth/jwks ..."

JWKS=$(curl -sf "$AUTH_URL/api/auth/jwks")
if [ -z "$JWKS" ]; then
  echo "Error: could not fetch JWKS"
  exit 1
fi

echo "$JWKS" | jq .

# Requires: node (for jwk-to-pem conversion via inline script)
PEM=$(node -e "
const jwks = $(echo "$JWKS");
const key = jwks.keys.find(k => k.alg === 'RS256' || k.kty === 'RSA');
if (!key) { console.error('No RS256 key found in JWKS'); process.exit(1); }

// Convert JWK to PEM using Node.js built-in crypto (Node 16+)
const crypto = require('crypto');
const publicKey = crypto.createPublicKey({ key, format: 'jwk' });
console.log(publicKey.export({ type: 'spki', format: 'pem' }));
")

if [ -z "$PEM" ]; then
  echo "Error: failed to convert JWK to PEM"
  exit 1
fi

echo ""
echo "=== BETTER_AUTH_RSA_PUBLIC_KEY ==="
echo "$PEM"
echo ""
echo "Copy the PEM above (including the BEGIN/END lines) and set it"
echo "as BETTER_AUTH_RSA_PUBLIC_KEY in your Kong Railway environment variables."
