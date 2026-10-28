package logic

import (
	"fmt"
	"server/config"
	"server/model/system"
	"strings"
	"time"
	"unicode/utf8"
)

type SyncLogic struct {
}

var SYL = &SyncLogic{}

// WatchHistoryVO 观看进度同步数据
type WatchHistoryVO struct {
	Mid           int64                  `json:"mid"`
	SourceID      string                 `json:"sourceId"`
	Episode       int                    `json:"episode"`
	EpisodeName   string                 `json:"episodeName"`
	Position      int64                  `json:"position"`
	Duration      int64                  `json:"duration"`
	Progress      float64                `json:"progress"`
	UpdatedAt     int64                  `json:"updatedAt"`
	ServerVersion int64                  `json:"serverVersion"`
	Deleted       bool                   `json:"deleted"`
	Movie         *system.MovieBasicInfo `json:"movie,omitempty"`
}

// FavoriteVO 收藏同步数据
type FavoriteVO struct {
	Mid           int64                  `json:"mid"`
	UpdatedAt     int64                  `json:"updatedAt"`
	ServerVersion int64                  `json:"serverVersion"`
	Deleted       bool                   `json:"deleted"`
	Movie         *system.MovieBasicInfo `json:"movie,omitempty"`
}

// WatchHistoryPage 观看进度增量页
type WatchHistoryPage struct {
	Items      []WatchHistoryVO `json:"items"`
	Since      int64            `json:"since"`
	NextSince  int64            `json:"nextSince"`
	HasMore    bool             `json:"hasMore"`
	ServerTime int64            `json:"serverTime"`
}

// FavoritePage 收藏增量页
type FavoritePage struct {
	Items      []FavoriteVO `json:"items"`
	Since      int64        `json:"since"`
	NextSince  int64        `json:"nextSince"`
	HasMore    bool         `json:"hasMore"`
	ServerTime int64        `json:"serverTime"`
}

// WatchHistory 增量拉取观看进度
func (s *SyncLogic) WatchHistory(userID uint, since int64, limit int) (*WatchHistoryPage, error) {
	if since < 0 {
		return nil, NewBadRequest("since 不能为负数")
	}
	list, hasMore, err := system.ListWatchHistory(userID, since, limit)
	if err != nil {
		return nil, NewInternal(err)
	}
	items := make([]WatchHistoryVO, 0, len(list))
	mids := make([]int64, 0, len(list))
	nextSince := since
	for _, h := range list {
		if !h.Deleted {
			mids = append(mids, h.Mid)
		}
		if h.ServerVersion > nextSince {
			nextSince = h.ServerVersion
		}
	}
	movies := loadMovies(mids)
	for _, h := range list {
		vo := WatchHistoryVO{
			Mid:           h.Mid,
			SourceID:      h.SourceID,
			Episode:       h.Episode,
			EpisodeName:   h.EpisodeName,
			Position:      h.Position,
			Duration:      h.Duration,
			Progress:      progress(h.Position, h.Duration),
			UpdatedAt:     h.ClientUpdatedAt,
			ServerVersion: h.ServerVersion,
			Deleted:       h.Deleted,
		}
		if movie, ok := movies[h.Mid]; ok {
			m := movie
			vo.Movie = &m
		}
		items = append(items, vo)
	}
	return &WatchHistoryPage{
		Items: items, Since: since, NextSince: nextSince,
		HasMore: hasMore, ServerTime: time.Now().UnixMilli(),
	}, nil
}

// Favorites 增量拉取收藏
func (s *SyncLogic) Favorites(userID uint, since int64, limit int) (*FavoritePage, error) {
	if since < 0 {
		return nil, NewBadRequest("since 不能为负数")
	}
	list, hasMore, err := system.ListFavorites(userID, since, limit)
	if err != nil {
		return nil, NewInternal(err)
	}
	items := make([]FavoriteVO, 0, len(list))
	mids := make([]int64, 0, len(list))
	nextSince := since
	for _, f := range list {
		if !f.Deleted {
			mids = append(mids, f.Mid)
		}
		if f.ServerVersion > nextSince {
			nextSince = f.ServerVersion
		}
	}
	movies := loadMovies(mids)
	for _, f := range list {
		vo := FavoriteVO{
			Mid:           f.Mid,
			UpdatedAt:     f.ClientUpdatedAt,
			ServerVersion: f.ServerVersion,
			Deleted:       f.Deleted,
		}
		if movie, ok := movies[f.Mid]; ok {
			m := movie
			vo.Movie = &m
		}
		items = append(items, vo)
	}
	return &FavoritePage{
		Items: items, Since: since, NextSince: nextSince,
		HasMore: hasMore, ServerTime: time.Now().UnixMilli(),
	}, nil
}

// ApplyWatchHistory 批量同步观看进度
func (s *SyncLogic) ApplyWatchHistory(userID uint, items []system.WatchHistorySyncItem) ([]system.SyncApplyResult, error) {
	if len(items) == 0 {
		return nil, NewBadRequest("同步数据不能为空")
	}
	if len(items) > config.V1SyncBatchLimit {
		return nil, NewBadRequest(fmt.Sprintf("单次最多同步%d条数据", config.V1SyncBatchLimit))
	}
	now := time.Now().UnixMilli()
	clean := make([]system.WatchHistorySyncItem, 0, len(items))
	for i, item := range items {
		if item.Mid <= 0 {
			return nil, NewBadRequest(fmt.Sprintf("第%d条记录影片ID不合法", i+1))
		}
		if item.Episode < 0 || item.Position < 0 || item.Duration < 0 {
			return nil, NewBadRequest(fmt.Sprintf("第%d条记录进度数据不合法", i+1))
		}
		item.SourceID = truncate(strings.TrimSpace(item.SourceID), 64)
		item.EpisodeName = truncate(strings.TrimSpace(item.EpisodeName), 128)
		if item.UpdatedAt <= 0 {
			item.UpdatedAt = now
		}
		clean = append(clean, item)
	}
	res, err := system.BatchUpsertWatchHistory(userID, clean)
	if err != nil {
		return nil, NewInternal(err)
	}
	return res, nil
}

// ApplyFavorites 批量同步收藏状态
func (s *SyncLogic) ApplyFavorites(userID uint, items []system.FavoriteSyncItem) ([]system.SyncApplyResult, error) {
	if len(items) == 0 {
		return nil, NewBadRequest("同步数据不能为空")
	}
	if len(items) > config.V1SyncBatchLimit {
		return nil, NewBadRequest(fmt.Sprintf("单次最多同步%d条数据", config.V1SyncBatchLimit))
	}
	now := time.Now().UnixMilli()
	clean := make([]system.FavoriteSyncItem, 0, len(items))
	for i, item := range items {
		if item.Mid <= 0 {
			return nil, NewBadRequest(fmt.Sprintf("第%d条记录影片ID不合法", i+1))
		}
		if item.UpdatedAt <= 0 {
			item.UpdatedAt = now
		}
		clean = append(clean, item)
	}
	res, err := system.BatchUpsertFavorites(userID, clean)
	if err != nil {
		return nil, NewInternal(err)
	}
	return res, nil
}

func loadMovies(mids []int64) map[int64]system.MovieBasicInfo {
	res := make(map[int64]system.MovieBasicInfo, len(mids))
	if len(mids) == 0 {
		return res
	}
	list := system.GetBasicInfoByIds(mids)
	for _, m := range list {
		res[m.Id] = m
	}
	return res
}

func progress(position, duration int64) float64 {
	if duration <= 0 {
		return 0
	}
	p := float64(position) / float64(duration)
	if p < 0 {
		return 0
	}
	if p > 1 {
		return 1
	}
	return p
}

func truncate(s string, limit int) string {
	if utf8.RuneCountInString(s) <= limit {
		return s
	}
	return string([]rune(s)[:limit])
}
