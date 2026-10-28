package util

import (
	"errors"
	"fmt"
	"regexp"
	"strings"

	"golang.org/x/crypto/bcrypt"
)

var (
	userNamePattern = regexp.MustCompile(`^[a-zA-Z0-9_]{3,20}$`)
	letterPattern   = regexp.MustCompile(`[a-zA-Z]`)
	digitPattern    = regexp.MustCompile(`[0-9]`)
)

// HashPassword 使用 bcrypt 加密密码, 用于新注册用户及历史密码升级
func HashPassword(password string) (string, error) {
	if len(password) > 72 {
		return "", errors.New("密码长度不能超过72字节")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

// IsBcryptHash 判断密码是否为 bcrypt 格式
func IsBcryptHash(hash string) bool {
	return strings.HasPrefix(hash, "$2a$") || strings.HasPrefix(hash, "$2b$") || strings.HasPrefix(hash, "$2y$")
}

// VerifyPassword 校验密码, 兼容历史 md5*3 密码
func VerifyPassword(password, hash, salt string) bool {
	if hash == "" {
		return false
	}
	if IsBcryptHash(hash) {
		return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
	}
	return PasswordEncrypt(password, salt) == hash
}

// ValidUserName 校验用户名
func ValidUserName(name string) error {
	if !userNamePattern.MatchString(name) {
		return errors.New("用户名必须为3-20位字母、数字或下划线")
	}
	return nil
}

// ValidAccountPassword 校验新注册账号的密码强度
func ValidAccountPassword(password string) error {
	if len(password) < 6 || len(password) > 32 {
		return errors.New("密码长度必须为6-32位")
	}
	if !letterPattern.MatchString(password) || !digitPattern.MatchString(password) {
		return errors.New("密码必须同时包含字母和数字")
	}
	return nil
}

// NormalizeAccount 去除账号首尾空白并限制长度
func NormalizeAccount(account string) (string, error) {
	account = strings.TrimSpace(account)
	if account == "" {
		return "", errors.New("账号不能为空")
	}
	if len(account) > 64 {
		return "", fmt.Errorf("账号长度不能超过64位")
	}
	return account, nil
}
