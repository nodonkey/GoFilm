package system

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"server/config"
	"server/plugin/db"
	"sort"
	"time"

	"github.com/redis/go-redis/v9"
)

// DeviceSession 单台设备的登录会话, 存储于 redis
type DeviceSession struct {
	UserID       uint   `json:"userId"`
	DeviceID     string `json:"deviceId"`
	SessionID    string `json:"sessionId"`
	DeviceName   string `json:"deviceName"`
	Platform     string `json:"platform"`
	AppVersion   string `json:"appVersion"`
	RefreshHash  string `json:"refreshHash"`
	CreatedAt    int64  `json:"createdAt"`
	LastActiveAt int64  `json:"lastActiveAt"`
	LastIP       string `json:"lastIp"`
}

// HashRefreshToken 对 refresh token 做摘要后存储
func HashRefreshToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func sessionKey(userID uint, deviceID string) string {
	return fmt.Sprintf(config.V1SessionKey, userID, deviceID)
}

func userSessionsKey(userID uint) string {
	return fmt.Sprintf(config.V1UserSessionsKey, userID)
}

// SaveDeviceSession 保存设备会话并延长有效期
func SaveDeviceSession(s *DeviceSession) error {
	data, err := json.Marshal(s)
	if err != nil {
		return err
	}
	pipe := db.Rdb.TxPipeline()
	pipe.Set(db.Cxt, sessionKey(s.UserID, s.DeviceID), data, config.V1RefreshTokenTTL)
	pipe.SAdd(db.Cxt, userSessionsKey(s.UserID), s.DeviceID)
	pipe.Expire(db.Cxt, userSessionsKey(s.UserID), config.V1RefreshTokenTTL)
	_, err = pipe.Exec(db.Cxt)
	return err
}

// GetDeviceSession 获取指定设备的会话, 不存在时返回 nil, nil
func GetDeviceSession(userID uint, deviceID string) (*DeviceSession, error) {
	val, err := db.Rdb.Get(db.Cxt, sessionKey(userID, deviceID)).Result()
	if errors.Is(err, redis.Nil) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var s DeviceSession
	if err := json.Unmarshal([]byte(val), &s); err != nil {
		return nil, err
	}
	return &s, nil
}

// ListDeviceSessions 获取用户全部有效会话, 按最近活跃时间倒序
func ListDeviceSessions(userID uint) ([]DeviceSession, error) {
	ids, err := db.Rdb.SMembers(db.Cxt, userSessionsKey(userID)).Result()
	if err != nil {
		return nil, err
	}
	list := make([]DeviceSession, 0, len(ids))
	if len(ids) == 0 {
		return list, nil
	}
	keys := make([]string, 0, len(ids))
	for _, id := range ids {
		keys = append(keys, sessionKey(userID, id))
	}
	vals, err := db.Rdb.MGet(db.Cxt, keys...).Result()
	if err != nil {
		return nil, err
	}
	var stale []string
	for i, v := range vals {
		raw, ok := v.(string)
		if !ok || raw == "" {
			stale = append(stale, ids[i])
			continue
		}
		var s DeviceSession
		if err := json.Unmarshal([]byte(raw), &s); err != nil {
			stale = append(stale, ids[i])
			continue
		}
		list = append(list, s)
	}
	if len(stale) > 0 {
		members := make([]interface{}, 0, len(stale))
		for _, id := range stale {
			members = append(members, id)
		}
		db.Rdb.SRem(db.Cxt, userSessionsKey(userID), members...)
	}
	sort.Slice(list, func(i, j int) bool {
		return list[i].LastActiveAt > list[j].LastActiveAt
	})
	return list, nil
}

// DeleteDeviceSession 删除指定设备的会话
func DeleteDeviceSession(userID uint, deviceID string) error {
	pipe := db.Rdb.TxPipeline()
	pipe.Del(db.Cxt, sessionKey(userID, deviceID))
	pipe.SRem(db.Cxt, userSessionsKey(userID), deviceID)
	_, err := pipe.Exec(db.Cxt)
	return err
}

// DeleteAllDeviceSessions 删除用户全部设备会话, 返回删除数量
func DeleteAllDeviceSessions(userID uint) (int, error) {
	ids, err := db.Rdb.SMembers(db.Cxt, userSessionsKey(userID)).Result()
	if err != nil {
		return 0, err
	}
	pipe := db.Rdb.TxPipeline()
	for _, id := range ids {
		pipe.Del(db.Cxt, sessionKey(userID, id))
	}
	pipe.Del(db.Cxt, userSessionsKey(userID))
	if _, err := pipe.Exec(db.Cxt); err != nil {
		return 0, err
	}
	return len(ids), nil
}

// TouchDeviceSession 更新会话活跃时间和有效期
func TouchDeviceSession(s *DeviceSession, ip string) error {
	s.LastActiveAt = time.Now().UnixMilli()
	if ip != "" {
		s.LastIP = ip
	}
	return SaveDeviceSession(s)
}
