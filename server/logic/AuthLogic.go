package logic

import (
	"crypto/subtle"
	"errors"
	"log"
	"regexp"
	"server/config"
	"server/model/system"
	"server/plugin/common/util"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/golang-jwt/jwt/v5"
)

type AuthLogic struct {
}

var AL = &AuthLogic{}

var deviceIDPattern = regexp.MustCompile(`^[A-Za-z0-9._:-]{8,64}$`)

// DeviceInfo 客户端设备信息
type DeviceInfo struct {
	DeviceID   string `json:"deviceId"`
	DeviceName string `json:"deviceName"`
	Platform   string `json:"platform"`
	AppVersion string `json:"appVersion"`
}

// UserVO 返回给客户端的用户信息
type UserVO struct {
	ID       uint   `json:"id"`
	UserName string `json:"userName"`
	NickName string `json:"nickName"`
	Avatar   string `json:"avatar"`
	Email    string `json:"email"`
	Gender   int    `json:"gender"`
	Role     string `json:"role"`
	Status   int    `json:"status"`
}

// AuthResult 登录 / 注册 / 刷新成功后返回的 token 信息
type AuthResult struct {
	AccessToken      string `json:"accessToken"`
	RefreshToken     string `json:"refreshToken"`
	TokenType        string `json:"tokenType"`
	ExpiresIn        int64  `json:"expiresIn"`
	RefreshExpiresIn int64  `json:"refreshExpiresIn"`
	DeviceID         string `json:"deviceId"`
	User             UserVO `json:"user"`
}

// DeviceVO 已登录设备信息
type DeviceVO struct {
	DeviceID     string `json:"deviceId"`
	DeviceName   string `json:"deviceName"`
	Platform     string `json:"platform"`
	AppVersion   string `json:"appVersion"`
	Current      bool   `json:"current"`
	CreatedAt    int64  `json:"createdAt"`
	LastActiveAt int64  `json:"lastActiveAt"`
	LastIP       string `json:"lastIp"`
}

// Register 开放注册, 注册成功后直接登录并创建会话
func (a *AuthLogic) Register(userName, password, nickName string, d DeviceInfo, ip string) (*AuthResult, error) {
	userName = strings.TrimSpace(userName)
	if err := util.ValidUserName(userName); err != nil {
		return nil, NewBadRequest(err.Error())
	}
	if err := util.ValidAccountPassword(password); err != nil {
		return nil, NewBadRequest(err.Error())
	}
	d, err := normalizeDevice(d)
	if err != nil {
		return nil, err
	}
	_, err = system.FindUserByNameOrEmail(userName)
	if err == nil {
		return nil, NewConflict("用户名已存在")
	}
	if !errors.Is(err, system.ErrUserNotFound) {
		return nil, NewInternal(err)
	}
	hash, err := util.HashPassword(password)
	if err != nil {
		return nil, NewBadRequest(err.Error())
	}
	nick := strings.TrimSpace(nickName)
	if nick == "" {
		nick = userName
	}
	if utf8.RuneCountInString(nick) > 32 {
		nick = string([]rune(nick)[:32])
	}
	u := &system.User{
		UserName: userName,
		Password: hash,
		NickName: nick,
		Avatar:   "empty",
		Role:     config.RoleUser,
	}
	if err := system.CreateUser(u); err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "duplicate") {
			return nil, NewConflict("用户名已存在")
		}
		return nil, NewInternal(err)
	}
	return a.issueTokens(u, d, ip)
}

// Login 账号密码登录, 每台设备独立会话
func (a *AuthLogic) Login(account, password string, d DeviceInfo, ip string) (*AuthResult, error) {
	account, err := util.NormalizeAccount(account)
	if err != nil {
		return nil, NewBadRequest(err.Error())
	}
	d, err = normalizeDevice(d)
	if err != nil {
		return nil, err
	}
	u, err := system.FindUserByNameOrEmail(account)
	if err != nil {
		if errors.Is(err, system.ErrUserNotFound) {
			return nil, NewUnauthorized(config.V1CodeUnauthorized, "账号或密码错误")
		}
		return nil, NewInternal(err)
	}
	if !util.VerifyPassword(password, u.Password, u.Salt) {
		return nil, NewUnauthorized(config.V1CodeUnauthorized, "账号或密码错误")
	}
	// 历史 md5 密码在登录成功后自动升级为 bcrypt
	if !util.IsBcryptHash(u.Password) {
		if hash, hashErr := util.HashPassword(password); hashErr == nil {
			if updateErr := system.UpdateUserPasswordHash(u.ID, hash); updateErr != nil {
				log.Println("Upgrade Password Hash Failed: ", updateErr)
			} else {
				u.Password = hash
				u.Salt = ""
			}
		}
	}
	if u.Role == "" {
		u.Role = config.RoleUser
	}
	return a.issueTokens(u, d, ip)
}

// Refresh 使用 refresh token 换取新的 token 对, refresh token 每次轮换
func (a *AuthLogic) Refresh(rawToken, ip string) (*AuthResult, error) {
	rawToken = strings.TrimSpace(rawToken)
	if rawToken == "" {
		return nil, NewBadRequest("refreshToken 不能为空")
	}
	claims, err := system.ParseV1Token(rawToken)
	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			return nil, NewUnauthorized(config.V1CodeTokenExpired, "登录已过期, 请重新登录")
		}
		return nil, NewUnauthorized(config.V1CodeUnauthorized, "refreshToken 无效")
	}
	if claims.TokenType != config.V1TokenTypeRefresh {
		return nil, NewUnauthorized(config.V1CodeUnauthorized, "token 类型错误")
	}
	if claims.UserID == 0 || claims.DeviceID == "" || claims.SessionID == "" {
		return nil, NewUnauthorized(config.V1CodeUnauthorized, "token 信息不完整")
	}
	session, err := system.GetDeviceSession(claims.UserID, claims.DeviceID)
	if err != nil {
		return nil, NewInternal(err)
	}
	if session == nil || session.SessionID != claims.SessionID {
		return nil, NewUnauthorized(config.V1CodeSessionInvalid, "登录状态已失效, 请重新登录")
	}
	if subtle.ConstantTimeCompare([]byte(session.RefreshHash), []byte(system.HashRefreshToken(rawToken))) != 1 {
		return nil, NewUnauthorized(config.V1CodeSessionInvalid, "登录状态已失效, 请重新登录")
	}
	u, err := system.FindUserByID(claims.UserID)
	if err != nil {
		if errors.Is(err, system.ErrUserNotFound) {
			return nil, NewUnauthorized(config.V1CodeSessionInvalid, "用户不存在, 请重新登录")
		}
		return nil, NewInternal(err)
	}
	if u.Role == "" {
		u.Role = config.RoleUser
	}
	access, err := system.GenV1Token(*u, session.DeviceID, session.SessionID, config.V1TokenTypeAccess, config.V1AccessTokenTTL)
	if err != nil {
		return nil, NewInternal(err)
	}
	refresh, err := system.GenV1Token(*u, session.DeviceID, session.SessionID, config.V1TokenTypeRefresh, config.V1RefreshTokenTTL)
	if err != nil {
		return nil, NewInternal(err)
	}
	session.RefreshHash = system.HashRefreshToken(refresh)
	session.LastActiveAt = time.Now().UnixMilli()
	session.LastIP = ip
	if err := system.SaveDeviceSession(session); err != nil {
		return nil, NewInternal(err)
	}
	return &AuthResult{
		AccessToken:      access,
		RefreshToken:     refresh,
		TokenType:        "Bearer",
		ExpiresIn:        int64(config.V1AccessTokenTTL / time.Second),
		RefreshExpiresIn: int64(config.V1RefreshTokenTTL / time.Second),
		DeviceID:         session.DeviceID,
		User:             toUserVO(u),
	}, nil
}

// Logout 注销当前设备会话
func (a *AuthLogic) Logout(userID uint, deviceID string) error {
	if err := system.DeleteDeviceSession(userID, deviceID); err != nil {
		return NewInternal(err)
	}
	return nil
}

// LogoutAll 注销用户全部设备会话
func (a *AuthLogic) LogoutAll(userID uint) (int, error) {
	count, err := system.DeleteAllDeviceSessions(userID)
	if err != nil {
		return 0, NewInternal(err)
	}
	return count, nil
}

// Me 获取当前用户信息
func (a *AuthLogic) Me(userID uint) (*UserVO, error) {
	u, err := system.FindUserByID(userID)
	if err != nil {
		if errors.Is(err, system.ErrUserNotFound) {
			return nil, NewNotFound("用户不存在")
		}
		return nil, NewInternal(err)
	}
	vo := toUserVO(u)
	return &vo, nil
}

// Devices 获取当前账号的全部登录设备
func (a *AuthLogic) Devices(userID uint, currentDeviceID string) ([]DeviceVO, error) {
	list, err := system.ListDeviceSessions(userID)
	if err != nil {
		return nil, NewInternal(err)
	}
	res := make([]DeviceVO, 0, len(list))
	for _, s := range list {
		res = append(res, DeviceVO{
			DeviceID:     s.DeviceID,
			DeviceName:   s.DeviceName,
			Platform:     s.Platform,
			AppVersion:   s.AppVersion,
			Current:      s.DeviceID == currentDeviceID,
			CreatedAt:    s.CreatedAt,
			LastActiveAt: s.LastActiveAt,
			LastIP:       s.LastIP,
		})
	}
	return res, nil
}

// RevokeDevice 下线指定设备
func (a *AuthLogic) RevokeDevice(userID uint, deviceID string) error {
	deviceID = strings.TrimSpace(deviceID)
	if deviceID == "" {
		return NewBadRequest("deviceId 不能为空")
	}
	session, err := system.GetDeviceSession(userID, deviceID)
	if err != nil {
		return NewInternal(err)
	}
	if session == nil {
		return NewNotFound("设备会话不存在")
	}
	if err := system.DeleteDeviceSession(userID, deviceID); err != nil {
		return NewInternal(err)
	}
	return nil
}

func (a *AuthLogic) issueTokens(u *system.User, d DeviceInfo, ip string) (*AuthResult, error) {
	sessionID := util.RandomString(16)
	access, err := system.GenV1Token(*u, d.DeviceID, sessionID, config.V1TokenTypeAccess, config.V1AccessTokenTTL)
	if err != nil {
		return nil, NewInternal(err)
	}
	refresh, err := system.GenV1Token(*u, d.DeviceID, sessionID, config.V1TokenTypeRefresh, config.V1RefreshTokenTTL)
	if err != nil {
		return nil, NewInternal(err)
	}
	now := time.Now().UnixMilli()
	session := &system.DeviceSession{
		UserID:       u.ID,
		DeviceID:     d.DeviceID,
		SessionID:    sessionID,
		DeviceName:   d.DeviceName,
		Platform:     d.Platform,
		AppVersion:   d.AppVersion,
		RefreshHash:  system.HashRefreshToken(refresh),
		CreatedAt:    now,
		LastActiveAt: now,
		LastIP:       ip,
	}
	if err := system.SaveDeviceSession(session); err != nil {
		return nil, NewInternal(err)
	}
	return &AuthResult{
		AccessToken:      access,
		RefreshToken:     refresh,
		TokenType:        "Bearer",
		ExpiresIn:        int64(config.V1AccessTokenTTL / time.Second),
		RefreshExpiresIn: int64(config.V1RefreshTokenTTL / time.Second),
		DeviceID:         d.DeviceID,
		User:             toUserVO(u),
	}, nil
}

func normalizeDevice(d DeviceInfo) (DeviceInfo, error) {
	d.DeviceID = strings.TrimSpace(d.DeviceID)
	if d.DeviceID == "" {
		d.DeviceID = util.GenerateUUID()
	}
	if !deviceIDPattern.MatchString(d.DeviceID) {
		return d, NewBadRequest("deviceId 必须为8-64位字母、数字或 . _ : -")
	}
	d.Platform = strings.ToLower(strings.TrimSpace(d.Platform))
	if d.Platform == "" {
		d.Platform = "unknown"
	}
	if len(d.Platform) > 32 {
		d.Platform = d.Platform[:32]
	}
	d.DeviceName = strings.TrimSpace(d.DeviceName)
	if d.DeviceName == "" {
		d.DeviceName = defaultDeviceName(d.Platform)
	}
	if utf8.RuneCountInString(d.DeviceName) > 64 {
		d.DeviceName = string([]rune(d.DeviceName)[:64])
	}
	d.AppVersion = strings.TrimSpace(d.AppVersion)
	if len(d.AppVersion) > 32 {
		d.AppVersion = d.AppVersion[:32]
	}
	return d, nil
}

func defaultDeviceName(platform string) string {
	switch platform {
	case "android-phone":
		return "Android 手机"
	case "android-tv":
		return "Android TV"
	default:
		return "未知设备"
	}
}

func toUserVO(u *system.User) UserVO {
	role := u.Role
	if role == "" {
		role = config.RoleUser
	}
	return UserVO{
		ID:       u.ID,
		UserName: u.UserName,
		NickName: u.NickName,
		Avatar:   u.Avatar,
		Email:    u.Email,
		Gender:   u.Gender,
		Role:     role,
		Status:   u.Status,
	}
}
