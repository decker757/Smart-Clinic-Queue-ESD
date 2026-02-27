package middleware

import (
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

type jwkKey struct {
	Kty string `json:"kty"`
	Crv string `json:"crv"`
	X   string `json:"x"` // base64url-encoded public key bytes
	Kid string `json:"kid"`
	Alg string `json:"alg"`
}

type jwksResponse struct {
	Keys []jwkKey `json:"keys"`
}

// FetchPublicKey retrieves the EdDSA public key from the auth-service JWKS endpoint.
// Called once at startup — the service cannot run without it.
func FetchPublicKey() (ed25519.PublicKey, error) {
	url := os.Getenv("AUTH_SERVICE_URL") + "/api/auth/jwks"
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch JWKS from %s: %w", url, err)
	}
	defer resp.Body.Close()

	var body jwksResponse
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("failed to decode JWKS: %w", err)
	}

	for _, k := range body.Keys {
		if k.Alg == "EdDSA" || k.Crv == "Ed25519" {
			pubKeyBytes, err := base64.RawURLEncoding.DecodeString(k.X)
			if err != nil {
				return nil, fmt.Errorf("failed to decode public key bytes: %w", err)
			}
			return ed25519.PublicKey(pubKeyBytes), nil
		}
	}

	return nil, fmt.Errorf("no EdDSA key found in JWKS response")
}

// RequireAuth returns a Gin middleware that validates EdDSA JWTs issued by the auth-service.
// pubKey is fetched once at startup via FetchPublicKey and passed in here.
func RequireAuth(pubKey ed25519.PublicKey) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing or malformed token"})
			return
		}
		tokenStr := strings.TrimPrefix(header, "Bearer ")

		token, err := jwt.Parse(tokenStr, func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodEd25519); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
			}
			return pubKey, nil
		},
			jwt.WithIssuer("smart-clinic"),
			jwt.WithAudience("smart-clinic-services"),
			jwt.WithExpirationRequired(),
		)
		if err != nil || !token.Valid {
			log.Printf("token validation failed: %v", err)
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			return
		}

		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token claims"})
			return
		}

		c.Set("user_id", claims["sub"])
		c.Next()
	}
}
