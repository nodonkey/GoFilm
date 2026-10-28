package v1

import (
	"net/http"
	"server/config"
	"server/logic"

	"github.com/gin-gonic/gin"
)

type registerRequest struct {
	UserName   string `json:"userName"`
	Password   string `json:"password"`
	NickName   string `json:"nickName"`
	DeviceID   string `json:"deviceId"`
	DeviceName string `json:"deviceName"`
	Platform   string `json:"platform"`
	AppVersion string `json:"appVersion"`
}

type loginRequest struct {
	Account    string `json:"account"`
	UserName   string `json:"userName"`
	Password   string `json:"password"`
	DeviceID   string `json:"deviceId"`
	DeviceName string `json:"deviceName"`
	Platform   string `json:"platform"`
	AppVersion string `json:"appVersion"`
}

type refreshRequest struct {
	RefreshToken string `json:"refreshToken"`
}

// Register 注册并登录
func Register(c *gin.Context) {
	var req registerRequest
	if !bindJSON(c, &req) {
		return
	}
	if req.UserName == "" || req.Password == "" {
		fail(c, http.StatusBadRequest, config.V1CodeBadRequest, "用户名和密码不能为空")
		return
	}
	result, err := logic.AL.Register(req.UserName, req.Password, req.NickName, logic.DeviceInfo{
		DeviceID: req.DeviceID, DeviceName: req.DeviceName, Platform: req.Platform, AppVersion: req.AppVersion,
	}, c.ClientIP())
	if err != nil {
		handleError(c, err)
		return
	}
	created(c, result)
}

// Login 账号密码登录
func Login(c *gin.Context) {
	var req loginRequest
	if !bindJSON(c, &req) {
		return
	}
	account := req.Account
	if account == "" {
		account = req.UserName
	}
	if account == "" || req.Password == "" {
		fail(c, http.StatusBadRequest, config.V1CodeBadRequest, "账号和密码不能为空")
		return
	}
	result, err := logic.AL.Login(account, req.Password, logic.DeviceInfo{
		DeviceID: req.DeviceID, DeviceName: req.DeviceName, Platform: req.Platform, AppVersion: req.AppVersion,
	}, c.ClientIP())
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, result)
}

// Refresh 刷新 token
func Refresh(c *gin.Context) {
	var req refreshRequest
	if !bindJSON(c, &req) {
		return
	}
	result, err := logic.AL.Refresh(req.RefreshToken, c.ClientIP())
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, result)
}

// Logout 注销当前设备
func Logout(c *gin.Context) {
	claims := currentClaims(c)
	if claims == nil {
		fail(c, http.StatusUnauthorized, config.V1CodeUnauthorized, "请先登录")
		return
	}
	if err := logic.AL.Logout(claims.UserID, claims.DeviceID); err != nil {
		handleError(c, err)
		return
	}
	okMsg(c, "已退出登录")
}

// LogoutAll 注销全部设备
func LogoutAll(c *gin.Context) {
	userID, valid := currentUserID(c)
	if !valid {
		return
	}
	count, err := logic.AL.LogoutAll(userID)
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, gin.H{"revoked": count})
}

// Me 当前用户信息
func Me(c *gin.Context) {
	userID, valid := currentUserID(c)
	if !valid {
		return
	}
	user, err := logic.AL.Me(userID)
	if err != nil {
		handleError(c, err)
		return
	}
	claims := currentClaims(c)
	ok(c, gin.H{"user": user, "deviceId": claims.DeviceID})
}

// Devices 已登录设备列表
func Devices(c *gin.Context) {
	userID, valid := currentUserID(c)
	if !valid {
		return
	}
	claims := currentClaims(c)
	list, err := logic.AL.Devices(userID, claims.DeviceID)
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, gin.H{"items": list, "total": len(list)})
}

// RevokeDevice 下线指定设备
func RevokeDevice(c *gin.Context) {
	userID, valid := currentUserID(c)
	if !valid {
		return
	}
	if err := logic.AL.RevokeDevice(userID, c.Param("deviceId")); err != nil {
		handleError(c, err)
		return
	}
	okMsg(c, "设备已下线")
}
