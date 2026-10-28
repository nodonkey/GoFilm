package system

import (
	"errors"
	"server/config"
	"server/plugin/common/util"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// V1Claims 多端客户端 token 声明
type V1Claims struct {
	UserID    uint   `json:"uid"`
	UserName  string `json:"uname"`
	Role      string `json:"role"`
	DeviceID  string `json:"did"`
	SessionID string `json:"sid"`
	TokenType string `json:"typ"`
	jwt.RegisteredClaims
}

// GenV1Token 生成 access / refresh token
func GenV1Token(u User, deviceID, sessionID, tokenType string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := V1Claims{
		UserID:    u.ID,
		UserName:  u.UserName,
		Role:      u.Role,
		DeviceID:  deviceID,
		SessionID: sessionID,
		TokenType: tokenType,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    config.Issuer,
			Subject:   u.UserName,
			Audience:  jwt.ClaimStrings{config.V1TokenAudience},
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
			NotBefore: jwt.NewNumericDate(now.Add(-10 * time.Second)),
			IssuedAt:  jwt.NewNumericDate(now),
			ID:        util.RandomString(16),
		},
	}
	priKey, err := util.ParsePriKeyBytes([]byte(config.PrivateKey))
	if err != nil {
		return "", err
	}
	return jwt.NewWithClaims(jwt.SigningMethodRS256, claims).SignedString(priKey)
}

// ParseV1Token 解析并校验 v1 token
func ParseV1Token(tokenStr string) (*V1Claims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &V1Claims{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, errors.New("unexpected signing method")
		}
		return util.ParsePubKeyBytes([]byte(config.PublicKey))
	}, jwt.WithValidMethods([]string{"RS256"}),
		jwt.WithIssuer(config.Issuer),
		jwt.WithAudience(config.V1TokenAudience))
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*V1Claims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid v1 token")
	}
	return claims, nil
}
