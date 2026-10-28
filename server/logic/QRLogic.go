package logic

import (
	"errors"
	"regexp"
	"server/config"
	"server/model/system"
	"server/plugin/common/util"
	"strconv"
	"strings"
	"time"
)

// QRLogic TV 扫码登录
type QRLogic struct {
}

var QL = &QRLogic{}

var qrIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{16,64}$`)

// QRCreateResult 创建二维码后返回给 TV 的信息
type QRCreateResult struct {
	QID          string `json:"qid"`
	PollToken    string `json:"pollToken"`
	QRUrl        string `json:"qrUrl"`
	ExpiresIn    int64  `json:"expiresIn"`
	PollInterval int    `json:"pollInterval"`
}

// QRInfoResult 二维码公开信息
type QRInfoResult struct {
	Status     string `json:"status"`
	DeviceName string `json:"deviceName"`
	Platform   string `json:"platform"`
	ExpiresIn  int64  `json:"expiresIn"`
}

// QRPollResult TV 轮询结果, 确认后携带 token
type QRPollResult struct {
	Status string      `json:"status"`
	Auth   *AuthResult `json:"auth,omitempty"`
}

// Create 创建扫码登录票据
func (q *QRLogic) Create(d DeviceInfo, baseURL, ip string) (*QRCreateResult, error) {
	if !system.QRCreateAllowed(ip) {
		return nil, NewTooManyRequests("请求过于频繁, 请稍后再试")
	}
	d, err := normalizeDevice(d)
	if err != nil {
		return nil, err
	}
	qid := util.RandomString(24)
	pollToken := util.RandomString(32)
	now := time.Now().UnixMilli()
	ticket := &system.QRTicket{
		QID:        qid,
		PollHash:   system.HashQRPollToken(pollToken),
		DeviceID:   d.DeviceID,
		DeviceName: d.DeviceName,
		Platform:   d.Platform,
		AppVersion: d.AppVersion,
		Status:     config.V1QRStatusPending,
		CreatedAt:  now,
		IP:         ip,
	}
	if err := system.CreateQRTicket(ticket); err != nil {
		return nil, NewInternal(err)
	}
	qrURL := strings.TrimRight(baseURL, "/") + "/qr?qid=" + qid
	return &QRCreateResult{
		QID:          qid,
		PollToken:    pollToken,
		QRUrl:        qrURL,
		ExpiresIn:    int64(config.V1QRTTL / time.Second),
		PollInterval: config.V1QRPollInterval,
	}, nil
}

// Info 获取二维码状态与设备信息, 供 H5 确认页展示
func (q *QRLogic) Info(qid string) (*QRInfoResult, error) {
	ticket, err := loadQRTicket(qid)
	if err != nil {
		return nil, err
	}
	if ticket == nil {
		return nil, NewNotFound("二维码已过期")
	}
	return &QRInfoResult{
		Status:     publicQRStatus(ticket.Status),
		DeviceName: ticket.DeviceName,
		Platform:   ticket.Platform,
		ExpiresIn:  remainingSeconds(ticket.CreatedAt),
	}, nil
}

// Scan 手机扫码后标记状态, 供 H5 页面展示
func (q *QRLogic) Scan(qid string, userID uint) (string, error) {
	if _, err := loadQRTicket(qid); err != nil {
		return "", err
	}
	status, err := system.ScanQRTicket(qid, userID)
	if err != nil {
		return "", NewInternal(err)
	}
	switch status {
	case config.V1QRStatusPending, config.V1QRStatusScanned:
		return publicQRStatus(status), nil
	case config.V1QRStatusConfirmed:
		return config.V1QRStatusConfirmed, nil
	case config.V1QRStatusExpired, "":
		return config.V1QRStatusExpired, nil
	}
	return publicQRStatus(status), nil
}

// Confirm 手机确认登录, 为 TV 设备签发 token
func (q *QRLogic) Confirm(qid string, userID uint) (string, error) {
	ticket, err := loadQRTicket(qid)
	if err != nil {
		return "", err
	}
	if ticket == nil {
		return "", NewNotFound("二维码已过期")
	}
	status, err := system.ClaimQRTicket(qid, userID)
	if err != nil {
		return "", NewInternal(err)
	}
	switch {
	case status == "claimed":
		// 继续签发 token
	case strings.HasPrefix(status, "confirmed:"):
		owner, _ := strconv.ParseUint(strings.TrimPrefix(status, "confirmed:"), 10, 64)
		if owner == uint64(userID) {
			return config.V1QRStatusConfirmed, nil
		}
		return "", NewConflict("二维码已被其他账号确认")
	case strings.HasPrefix(status, "confirming:"):
		owner, _ := strconv.ParseUint(strings.TrimPrefix(status, "confirming:"), 10, 64)
		if owner == uint64(userID) {
			return "", NewConflict("正在确认, 请稍候")
		}
		return "", NewConflict("二维码正在被其他账号确认")
	case status == config.V1QRStatusCanceled:
		return "", NewConflict("二维码已取消")
	default:
		return "", NewNotFound("二维码已过期")
	}

	u, err := system.FindUserByID(userID)
	if err != nil {
		if errors.Is(err, system.ErrUserNotFound) {
			return "", NewUnauthorized(config.V1CodeUnauthorized, "用户不存在, 请重新登录")
		}
		return "", NewInternal(err)
	}
	d := DeviceInfo{
		DeviceID:   ticket.DeviceID,
		DeviceName: ticket.DeviceName,
		Platform:   ticket.Platform,
		AppVersion: ticket.AppVersion,
	}
	auth, err := AL.issueTokens(u, d, ticket.IP)
	if err != nil {
		return "", err
	}
	now := time.Now().UnixMilli()
	ticket.UserID = u.ID
	ticket.AccessToken = auth.AccessToken
	ticket.RefreshToken = auth.RefreshToken
	ticket.AccessExpiresIn = auth.ExpiresIn
	ticket.RefreshExpiresIn = auth.RefreshExpiresIn
	ticket.ConfirmedAt = now
	finalized, err := system.FinalizeQRTicket(qid, ticket)
	if err != nil || finalized != config.V1QRStatusConfirmed {
		// 抢锁失败时回滚刚创建的空会话, 避免占用设备槽位
		_ = system.DeleteDeviceSession(u.ID, ticket.DeviceID)
		if err != nil {
			return "", NewInternal(err)
		}
		return "", NewConflict("二维码状态已变化, 请刷新后重试")
	}
	return config.V1QRStatusConfirmed, nil
}

// Poll TV 轮询扫码状态, 确认后一次性取走 token
func (q *QRLogic) Poll(qid, pollToken string) (*QRPollResult, error) {
	if _, err := validateQRID(qid); err != nil {
		return nil, err
	}
	pollToken = strings.TrimSpace(pollToken)
	if len(pollToken) < 16 {
		return nil, NewUnauthorized(config.V1CodeUnauthorized, "轮询令牌无效")
	}
	ticket, valid, err := system.PollQRTicket(qid, pollToken)
	if err != nil {
		return nil, NewInternal(err)
	}
	if !valid {
		return nil, NewUnauthorized(config.V1CodeUnauthorized, "轮询令牌无效")
	}
	if ticket == nil {
		return &QRPollResult{Status: config.V1QRStatusExpired}, nil
	}
	status := publicQRStatus(ticket.Status)
	if status != config.V1QRStatusConfirmed {
		return &QRPollResult{Status: status}, nil
	}
	u, err := system.FindUserByID(ticket.UserID)
	if err != nil {
		if errors.Is(err, system.ErrUserNotFound) {
			return &QRPollResult{Status: config.V1QRStatusExpired}, nil
		}
		return nil, NewInternal(err)
	}
	return &QRPollResult{
		Status: config.V1QRStatusConfirmed,
		Auth: &AuthResult{
			AccessToken:      ticket.AccessToken,
			RefreshToken:     ticket.RefreshToken,
			TokenType:        "Bearer",
			ExpiresIn:        ticket.AccessExpiresIn,
			RefreshExpiresIn: ticket.RefreshExpiresIn,
			DeviceID:         ticket.DeviceID,
			User:             toUserVO(u),
		},
	}, nil
}

func loadQRTicket(qid string) (*system.QRTicket, error) {
	if _, err := validateQRID(qid); err != nil {
		return nil, err
	}
	ticket, err := system.GetQRTicket(qid)
	if err != nil {
		return nil, NewInternal(err)
	}
	return ticket, nil
}

func validateQRID(qid string) (string, error) {
	qid = strings.TrimSpace(qid)
	if !qrIDPattern.MatchString(qid) {
		return "", NewBadRequest("二维码ID不合法")
	}
	return qid, nil
}

func publicQRStatus(status string) string {
	switch status {
	case config.V1QRStatusPending:
		return config.V1QRStatusPending
	case config.V1QRStatusScanned, "confirming":
		return config.V1QRStatusScanned
	case config.V1QRStatusConfirmed:
		return config.V1QRStatusConfirmed
	case config.V1QRStatusCanceled:
		return config.V1QRStatusCanceled
	default:
		return config.V1QRStatusExpired
	}
}

func remainingSeconds(createdAt int64) int64 {
	left := int64(config.V1QRTTL/time.Second) - (time.Now().UnixMilli()-createdAt)/1000
	if left < 0 {
		return 0
	}
	return left
}
