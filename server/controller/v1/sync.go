package v1

import (
	"net/http"
	"server/config"
	"server/logic"
	"server/model/system"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

type historySyncRequest struct {
	Items []system.WatchHistorySyncItem `json:"items"`
}

type favoriteSyncRequest struct {
	Items []system.FavoriteSyncItem `json:"items"`
}

func parseSince(c *gin.Context) (int64, bool) {
	raw := c.DefaultQuery("since", "0")
	since, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || since < 0 {
		fail(c, http.StatusBadRequest, config.V1CodeBadRequest, "since 参数不合法")
		return 0, false
	}
	return since, true
}

func parseSyncLimit(c *gin.Context) int {
	limit, err := strconv.Atoi(c.DefaultQuery("limit", strconv.Itoa(config.V1SyncBatchLimit)))
	if err != nil || limit < 1 {
		limit = config.V1SyncBatchLimit
	}
	if limit > config.V1SyncBatchLimit {
		limit = config.V1SyncBatchLimit
	}
	return limit
}

// SyncHistory 增量拉取观看进度
func SyncHistory(c *gin.Context) {
	userID, valid := currentUserID(c)
	if !valid {
		return
	}
	since, valid := parseSince(c)
	if !valid {
		return
	}
	page, err := logic.SYL.WatchHistory(userID, since, parseSyncLimit(c))
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, page)
}

// ApplyHistory 批量提交观看进度
func ApplyHistory(c *gin.Context) {
	userID, valid := currentUserID(c)
	if !valid {
		return
	}
	var req historySyncRequest
	if !bindJSON(c, &req) {
		return
	}
	results, err := logic.SYL.ApplyWatchHistory(userID, req.Items)
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, gin.H{"results": results, "serverTime": time.Now().UnixMilli()})
}

// SyncFavorites 增量拉取收藏
func SyncFavorites(c *gin.Context) {
	userID, valid := currentUserID(c)
	if !valid {
		return
	}
	since, valid := parseSince(c)
	if !valid {
		return
	}
	page, err := logic.SYL.Favorites(userID, since, parseSyncLimit(c))
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, page)
}

// ApplyFavorites 批量提交收藏变更
func ApplyFavorites(c *gin.Context) {
	userID, valid := currentUserID(c)
	if !valid {
		return
	}
	var req favoriteSyncRequest
	if !bindJSON(c, &req) {
		return
	}
	results, err := logic.SYL.ApplyFavorites(userID, req.Items)
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, gin.H{"results": results, "serverTime": time.Now().UnixMilli()})
}
