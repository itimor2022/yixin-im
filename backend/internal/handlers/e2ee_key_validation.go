package handlers

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"strings"
)

func validateE2EEPublicJWK(jwkText string) error {
	jwkText = strings.TrimSpace(jwkText)
	if jwkText == "" {
		return errors.New("public key is empty")
	}

	var data map[string]interface{}
	if err := json.Unmarshal([]byte(jwkText), &data); err != nil {
		return err
	}

	if strings.ToUpper(strings.TrimSpace(toString(data["kty"]))) != "RSA" {
		return errors.New("unsupported jwk kty")
	}

	modulus, err := decodeJWKBigInt(toString(data["n"]))
	if err != nil {
		return err
	}
	exponent, err := decodeJWKBigInt(toString(data["e"]))
	if err != nil {
		return err
	}

	if modulus.Sign() <= 0 || exponent.Sign() <= 0 {
		return errors.New("invalid rsa key")
	}
	if modulus.BitLen() < 2048 {
		return errors.New("rsa key too short")
	}
	if exponent.Cmp(big.NewInt(1)) <= 0 {
		return errors.New("invalid rsa exponent")
	}

	return nil
}

func isValidE2EEPublicJWK(jwkText string) bool {
	return validateE2EEPublicJWK(jwkText) == nil
}

func decodeJWKBigInt(value string) (*big.Int, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil, errors.New("missing jwk field")
	}

	padding := len(value) % 4
	if padding > 0 {
		value += strings.Repeat("=", 4-padding)
	}

	bytes, err := base64.URLEncoding.DecodeString(value)
	if err != nil {
		return nil, err
	}

	result := new(big.Int).SetBytes(bytes)
	if result.Sign() <= 0 {
		return nil, errors.New("invalid jwk integer")
	}
	return result, nil
}

func toString(value interface{}) string {
	if value == nil {
		return ""
	}
	if s, ok := value.(string); ok {
		return s
	}
	return strings.TrimSpace(fmt.Sprint(value))
}
