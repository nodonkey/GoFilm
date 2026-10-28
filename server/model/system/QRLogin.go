package system

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"server/config"
	"server/plugin/db"
	"strconv"
	"strings"
)

// QRTicket TV 扫码登录票据, 以 redis hash 存储, 确认后由 TV 一次性取走 token
type QRTicket struct {
	QID              string
	PollHash         string
	DeviceID         string
	DeviceName       string
	Platform         string
	AppVersion       string
	Status           string
	UserID           uint
	AccessToken      string
	RefreshToken     string
	AccessExpiresIn  int64
	RefreshExpiresIn int64
	CreatedAt        int64
	ConfirmedAt      int64
	IP               string
}

// HashQRPollToken 轮询令牌只保存摘要
func HashQRPollToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func qrKey(qid string) string {
	return fmt.Sprintf(config.V1QRKey, qid)
}

// CreateQRTicket 创建票据, 同一 qid 不会被覆盖
func CreateQRTicket(t *QRTicket) error {
	key := qrKey(t.QID)
	pipe := db.Rdb.TxPipeline()
	pipe.HSet(db.Cxt, key, map[string]interface{}{
		"poll_hash":          t.PollHash,
		"device_id":          t.DeviceID,
		"device_name":        t.DeviceName,
		"platform":           t.Platform,
		"app_version":        t.AppVersion,
		"status":             t.Status,
		"created_at":         t.CreatedAt,
		"ip":                 t.IP,
		"access_expires_in":  0,
		"refresh_expires_in": 0,
	})
	pipe.Expire(db.Cxt, key, config.V1QRTTL)
	_, err := pipe.Exec(db.Cxt)
	return err
}

// GetQRTicket 读取票据, 不存在时返回 nil, nil
func GetQRTicket(qid string) (*QRTicket, error) {
	vals, err := db.Rdb.HGetAll(db.Cxt, qrKey(qid)).Result()
	if err != nil {
		return nil, err
	}
	if len(vals) == 0 {
		return nil, nil
	}
	t := &QRTicket{
		QID:          qid,
		PollHash:     vals["poll_hash"],
		DeviceID:     vals["device_id"],
		DeviceName:   vals["device_name"],
		Platform:     vals["platform"],
		AppVersion:   vals["app_version"],
		Status:       vals["status"],
		AccessToken:  vals["access_token"],
		RefreshToken: vals["refresh_token"],
		IP:           vals["ip"],
	}
	t.UserID = parseUint(vals["user_id"])
	t.AccessExpiresIn = parseInt64(vals["access_expires_in"])
	t.RefreshExpiresIn = parseInt64(vals["refresh_expires_in"])
	t.CreatedAt = parseInt64(vals["created_at"])
	t.ConfirmedAt = parseInt64(vals["confirmed_at"])
	return t, nil
}

const qrScanScript = `
local s = redis.call('HGET', KEYS[1], 'status')
if not s then return 'expired' end
if s == 'pending' then
  redis.call('HSET', KEYS[1], 'status', 'scanned', 'scanned_by', ARGV[1])
  return 'scanned'
end
return s
`

// ScanQRTicket 标记二维码已被扫描, 幂等
func ScanQRTicket(qid string, userID uint) (string, error) {
	res, err := db.Rdb.Eval(db.Cxt, qrScanScript, []string{qrKey(qid)}, userID).Result()
	if err != nil {
		return "", err
	}
	status, _ := res.(string)
	return status, nil
}

const qrClaimScript = `
local s = redis.call('HGET', KEYS[1], 'status')
if not s then return 'expired' end
if s == 'confirmed' then
  return 'confirmed:' .. (redis.call('HGET', KEYS[1], 'user_id') or '')
end
if s == 'confirming' then
  return 'confirming:' .. (redis.call('HGET', KEYS[1], 'user_id') or '')
end
if s == 'canceled' then return 'canceled' end
redis.call('HSET', KEYS[1], 'status', 'confirming', 'user_id', ARGV[1])
return 'claimed'
`

// ClaimQRTicket 原子地抢占确认权, 避免同一二维码并发确认导致会话被覆盖
func ClaimQRTicket(qid string, userID uint) (string, error) {
	res, err := db.Rdb.Eval(db.Cxt, qrClaimScript, []string{qrKey(qid)}, userID).Result()
	if err != nil {
		return "", err
	}
	status, _ := res.(string)
	return status, nil
}

const qrFinalizeScript = `
if redis.call('HGET', KEYS[1], 'status') ~= 'confirming' then return 'expired' end
if redis.call('HGET', KEYS[1], 'user_id') ~= ARGV[1] then return 'conflict' end
redis.call('HSET', KEYS[1],
  'status', 'confirmed',
  'access_token', ARGV[2],
  'refresh_token', ARGV[3],
  'access_expires_in', ARGV[4],
  'refresh_expires_in', ARGV[5],
  'confirmed_at', ARGV[6])
return 'confirmed'
`

// FinalizeQRTicket 写入确认后的 token, 票据仍保留到 TV 轮询取走
func FinalizeQRTicket(qid string, t *QRTicket) (string, error) {
	res, err := db.Rdb.Eval(db.Cxt, qrFinalizeScript, []string{qrKey(qid)},
		t.UserID, t.AccessToken, t.RefreshToken, t.AccessExpiresIn, t.RefreshExpiresIn, t.ConfirmedAt).Result()
	if err != nil {
		return "", err
	}
	status, _ := res.(string)
	return status, nil
}

const qrPollScript = `
local s = redis.call('HGET', KEYS[1], 'status')
if not s then return {} end
if s ~= 'confirmed' then return {'status', s} end
local vals = redis.call('HGETALL', KEYS[1])
redis.call('DEL', KEYS[1])
return vals
`

// PollQRTicket 校验轮询令牌并读取状态, 确认成功后票据立即销毁
func PollQRTicket(qid, pollToken string) (*QRTicket, bool, error) {
	t, err := GetQRTicket(qid)
	if err != nil {
		return nil, false, err
	}
	if t == nil {
		// 票据不存在或已过期时统一返回 expired, 不向调用方区分 qid 是否真实存在
		return nil, true, nil
	}
	if subtle.ConstantTimeCompare([]byte(t.PollHash), []byte(HashQRPollToken(pollToken))) != 1 {
		return nil, false, nil
	}
	res, err := db.Rdb.Eval(db.Cxt, qrPollScript, []string{qrKey(qid)}).Result()
	if err != nil {
		return nil, true, err
	}
	vals, ok := res.([]interface{})
	if !ok || len(vals) == 0 {
		return nil, false, nil
	}
	// 未确认时只返回状态, 确认时返回完整 hash
	if len(vals) == 2 && fmt.Sprint(vals[0]) == "status" {
		t.Status = fmt.Sprint(vals[1])
		return t, true, nil
	}
	t.Status = config.V1QRStatusConfirmed
	for i := 0; i+1 < len(vals); i += 2 {
		key := fmt.Sprint(vals[i])
		val := fmt.Sprint(vals[i+1])
		switch key {
		case "user_id":
			t.UserID = parseUint(val)
		case "access_token":
			t.AccessToken = val
		case "refresh_token":
			t.RefreshToken = val
		case "access_expires_in":
			t.AccessExpiresIn = parseInt64(val)
		case "refresh_expires_in":
			t.RefreshExpiresIn = parseInt64(val)
		case "confirmed_at":
			t.ConfirmedAt = parseInt64(val)
		}
	}
	return t, true, nil
}

// DeleteQRTicket 删除票据
func DeleteQRTicket(qid string) error {
	return db.Rdb.Del(db.Cxt, qrKey(qid)).Err()
}

// QRCreateAllowed 限制单 IP 创建票据的频率
func QRCreateAllowed(ip string) bool {
	if ip == "" {
		ip = "unknown"
	}
	key := "v1:qr:rate:" + ip
	n, err := db.Rdb.Incr(db.Cxt, key).Result()
	if err != nil {
		return true
	}
	if n == 1 {
		db.Rdb.Expire(db.Cxt, key, config.V1QRCreateWindow)
	}
	return n <= config.V1QRCreateLimit
}

func parseUint(v string) uint {
	n, _ := strconv.ParseUint(strings.TrimSpace(v), 10, 64)
	return uint(n)
}

func parseInt64(v string) int64 {
	n, _ := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
	return n
}
