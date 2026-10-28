package system

import (
	"errors"
	"fmt"
	"server/config"
	"server/plugin/db"
	"time"

	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"
)

const (
	SyncStatusApplied = "applied"
	SyncStatusStale   = "stale"
)

// UserWatchHistory 用户观看进度, 服务端保存用于多端同步
type UserWatchHistory struct {
	ID              uint64 `gorm:"primaryKey"`
	UserID          uint   `gorm:"not null;uniqueIndex:uk_history_user_mid;index:idx_history_sync,priority:1"`
	Mid             int64  `gorm:"not null;uniqueIndex:uk_history_user_mid"`
	SourceID        string `gorm:"size:64"`
	Episode         int
	EpisodeName     string `gorm:"size:128"`
	Position        int64
	Duration        int64
	Deleted         bool  `gorm:"not null;default:false"`
	ClientUpdatedAt int64 `gorm:"not null"`
	ServerVersion   int64 `gorm:"not null;index:idx_history_sync,priority:2"`
	CreatedAt       int64 `gorm:"not null"`
}

func (h *UserWatchHistory) TableName() string {
	return "user_watch_histories"
}

// UserFavorite 用户收藏
type UserFavorite struct {
	ID              uint64 `gorm:"primaryKey"`
	UserID          uint   `gorm:"not null;uniqueIndex:uk_favorite_user_mid;index:idx_favorite_sync,priority:1"`
	Mid             int64  `gorm:"not null;uniqueIndex:uk_favorite_user_mid"`
	Deleted         bool   `gorm:"not null;default:false"`
	ClientUpdatedAt int64  `gorm:"not null"`
	ServerVersion   int64  `gorm:"not null;index:idx_favorite_sync,priority:2"`
	CreatedAt       int64  `gorm:"not null"`
}

func (f *UserFavorite) TableName() string {
	return "user_favorites"
}

// WatchHistorySyncItem 客户端提交的观看进度
type WatchHistorySyncItem struct {
	Mid         int64  `json:"mid"`
	SourceID    string `json:"sourceId"`
	Episode     int    `json:"episode"`
	EpisodeName string `json:"episodeName"`
	Position    int64  `json:"position"`
	Duration    int64  `json:"duration"`
	UpdatedAt   int64  `json:"updatedAt"`
	Deleted     bool   `json:"deleted"`
}

// FavoriteSyncItem 客户端提交的收藏变更
type FavoriteSyncItem struct {
	Mid       int64 `json:"mid"`
	UpdatedAt int64 `json:"updatedAt"`
	Deleted   bool  `json:"deleted"`
}

// SyncApplyResult 单条同步结果
type SyncApplyResult struct {
	Mid           int64  `json:"mid"`
	Status        string `json:"status"`
	ServerVersion int64  `json:"serverVersion"`
	UpdatedAt     int64  `json:"updatedAt"`
	Deleted       bool   `json:"deleted"`
}

var syncVersionScript = redis.NewScript(`
if redis.call('EXISTS', KEYS[1]) == 0 then
  redis.call('SET', KEYS[1], ARGV[1])
end
return redis.call('INCRBY', KEYS[1], ARGV[2])
`)

// nextSyncVersions 为用户分配一段单调递增的同步版本号
func nextSyncVersions(userID uint, n int) (int64, error) {
	if n <= 0 {
		return 0, nil
	}
	var historyMax, favoriteMax int64
	if err := db.Mdb.Model(&UserWatchHistory{}).Where("user_id = ?", userID).
		Select("COALESCE(MAX(server_version), 0)").Scan(&historyMax).Error; err != nil {
		return 0, err
	}
	if err := db.Mdb.Model(&UserFavorite{}).Where("user_id = ?", userID).
		Select("COALESCE(MAX(server_version), 0)").Scan(&favoriteMax).Error; err != nil {
		return 0, err
	}
	maxVersion := historyMax
	if favoriteMax > maxVersion {
		maxVersion = favoriteMax
	}
	next, err := syncVersionScript.Run(db.Cxt, db.Rdb,
		[]string{fmt.Sprintf(config.V1SyncVersionKey, userID)}, maxVersion, n).Int64()
	if err != nil {
		return 0, err
	}
	return next - int64(n) + 1, nil
}

// ListWatchHistory 增量拉取观看进度, 包含删除墓碑
func ListWatchHistory(userID uint, since int64, limit int) ([]UserWatchHistory, bool, error) {
	list := make([]UserWatchHistory, 0, limit)
	err := db.Mdb.Where("user_id = ? AND server_version > ?", userID, since).
		Order("server_version ASC").Limit(limit + 1).Find(&list).Error
	if err != nil {
		return nil, false, err
	}
	hasMore := len(list) > limit
	if hasMore {
		list = list[:limit]
	}
	return list, hasMore, nil
}

// ListFavorites 增量拉取收藏, 包含删除墓碑
func ListFavorites(userID uint, since int64, limit int) ([]UserFavorite, bool, error) {
	list := make([]UserFavorite, 0, limit)
	err := db.Mdb.Where("user_id = ? AND server_version > ?", userID, since).
		Order("server_version ASC").Limit(limit + 1).Find(&list).Error
	if err != nil {
		return nil, false, err
	}
	hasMore := len(list) > limit
	if hasMore {
		list = list[:limit]
	}
	return list, hasMore, nil
}

// BatchUpsertWatchHistory 批量同步观看进度, 以客户端时间戳做 LWW
func BatchUpsertWatchHistory(userID uint, items []WatchHistorySyncItem) ([]SyncApplyResult, error) {
	results := make([]SyncApplyResult, 0, len(items))
	if len(items) == 0 {
		return results, nil
	}
	base, err := nextSyncVersions(userID, len(items))
	if err != nil {
		return nil, err
	}
	applied := 0
	now := time.Now().UnixMilli()
	for _, item := range items {
		var old UserWatchHistory
		err := db.Mdb.Where("user_id = ? AND mid = ?", userID, item.Mid).First(&old).Error
		if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, err
		}
		if err == nil && old.ClientUpdatedAt > item.UpdatedAt {
			results = append(results, SyncApplyResult{
				Mid: item.Mid, Status: SyncStatusStale, ServerVersion: old.ServerVersion,
				UpdatedAt: old.ClientUpdatedAt, Deleted: old.Deleted,
			})
			continue
		}
		version := base + int64(applied)
		applied++
		if err == nil {
			updates := map[string]interface{}{
				"source_id":         item.SourceID,
				"episode":           item.Episode,
				"episode_name":      item.EpisodeName,
				"position":          item.Position,
				"duration":          item.Duration,
				"deleted":           item.Deleted,
				"client_updated_at": item.UpdatedAt,
				"server_version":    version,
			}
			if err := db.Mdb.Model(&UserWatchHistory{}).Where("id = ?", old.ID).Updates(updates).Error; err != nil {
				return nil, err
			}
		} else {
			rec := UserWatchHistory{
				UserID: userID, Mid: item.Mid, SourceID: item.SourceID, Episode: item.Episode,
				EpisodeName: item.EpisodeName, Position: item.Position, Duration: item.Duration,
				Deleted: item.Deleted, ClientUpdatedAt: item.UpdatedAt, ServerVersion: version, CreatedAt: now,
			}
			if err := db.Mdb.Create(&rec).Error; err != nil {
				return nil, err
			}
		}
		results = append(results, SyncApplyResult{
			Mid: item.Mid, Status: SyncStatusApplied, ServerVersion: version,
			UpdatedAt: item.UpdatedAt, Deleted: item.Deleted,
		})
	}
	return results, nil
}

// BatchUpsertFavorites 批量同步收藏状态
func BatchUpsertFavorites(userID uint, items []FavoriteSyncItem) ([]SyncApplyResult, error) {
	results := make([]SyncApplyResult, 0, len(items))
	if len(items) == 0 {
		return results, nil
	}
	base, err := nextSyncVersions(userID, len(items))
	if err != nil {
		return nil, err
	}
	applied := 0
	now := time.Now().UnixMilli()
	for _, item := range items {
		var old UserFavorite
		err := db.Mdb.Where("user_id = ? AND mid = ?", userID, item.Mid).First(&old).Error
		if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, err
		}
		if err == nil && old.ClientUpdatedAt > item.UpdatedAt {
			results = append(results, SyncApplyResult{
				Mid: item.Mid, Status: SyncStatusStale, ServerVersion: old.ServerVersion,
				UpdatedAt: old.ClientUpdatedAt, Deleted: old.Deleted,
			})
			continue
		}
		version := base + int64(applied)
		applied++
		if err == nil {
			updates := map[string]interface{}{
				"deleted":           item.Deleted,
				"client_updated_at": item.UpdatedAt,
				"server_version":    version,
			}
			if err := db.Mdb.Model(&UserFavorite{}).Where("id = ?", old.ID).Updates(updates).Error; err != nil {
				return nil, err
			}
		} else {
			rec := UserFavorite{
				UserID: userID, Mid: item.Mid, Deleted: item.Deleted,
				ClientUpdatedAt: item.UpdatedAt, ServerVersion: version, CreatedAt: now,
			}
			if err := db.Mdb.Create(&rec).Error; err != nil {
				return nil, err
			}
		}
		results = append(results, SyncApplyResult{
			Mid: item.Mid, Status: SyncStatusApplied, ServerVersion: version,
			UpdatedAt: item.UpdatedAt, Deleted: item.Deleted,
		})
	}
	return results, nil
}
