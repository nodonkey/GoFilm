package v1

import (
	"net/http"
	"server/config"
	"server/logic"
	"server/model/system"
	"server/plugin/mediaproxy"
	"strconv"

	"github.com/gin-gonic/gin"
)

// Config 客户端启动配置
func Config(c *gin.Context) {
	ok(c, logic.VCL.Config())
}

// Nav 导航分类
func Nav(c *gin.Context) {
	ok(c, gin.H{"items": logic.VCL.Nav()})
}

// Index 首页数据
func Index(c *gin.Context) {
	ok(c, logic.VCL.Index())
}

// FilmDetail 影片详情
func FilmDetail(c *gin.Context) {
	mid, valid := parsePathMid(c)
	if !valid {
		return
	}
	result, err := logic.VCL.FilmDetail(mid)
	if err != nil {
		handleError(c, err)
		return
	}
	proxyDetailLinks(c, &result.Detail)
	ok(c, result)
}

// FilmPlay 播放页数据
func FilmPlay(c *gin.Context) {
	mid, valid := parsePathMid(c)
	if !valid {
		return
	}
	episode := 0
	if raw := c.Query("episode"); raw != "" {
		v, err := strconv.Atoi(raw)
		if err != nil || v < 0 {
			fail(c, http.StatusBadRequest, config.V1CodeBadRequest, "集数不合法")
			return
		}
		episode = v
	}
	result, err := logic.VCL.FilmPlay(mid, c.Query("playFrom"), episode)
	if err != nil {
		handleError(c, err)
		return
	}
	proxyDetailLinks(c, &result.Detail)
	if config.V1ProxyEnabled {
		result.Current.Link = mediaproxy.SignedURL(requestBaseURL(c), mediaproxy.KindPlaylist, result.Current.Link)
		result.Proxy = true
	}
	ok(c, result)
}

// proxyDetailLinks 将详情内的播放地址统一替换为签名代理地址
func proxyDetailLinks(c *gin.Context, detail *system.MovieDetailVo) {
	if !config.V1ProxyEnabled || detail == nil {
		return
	}
	base := requestBaseURL(c)
	for i := range detail.List {
		for j := range detail.List[i].LinkList {
			detail.List[i].LinkList[j].Link = mediaproxy.SignedURL(
				base, mediaproxy.KindPlaylist, detail.List[i].LinkList[j].Link)
		}
	}
}

// Search 关键字搜索
func Search(c *gin.Context) {
	current, pageSize := parsePagination(c)
	page := system.Page{Current: current, PageSize: pageSize}
	list, err := logic.VCL.Search(c.Query("keyword"), &page)
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, gin.H{"list": list, "page": newPageMeta(page)})
}

// FilmClassify 分类首页
func FilmClassify(c *gin.Context) {
	pid, err := strconv.ParseInt(c.Query("pid"), 10, 64)
	if err != nil || pid <= 0 {
		fail(c, http.StatusBadRequest, config.V1CodeBadRequest, "缺少分类信息")
		return
	}
	result, err := logic.VCL.FilmClassify(pid)
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, result)
}

// FilmClassifySearch 分类标签筛选
func FilmClassifySearch(c *gin.Context) {
	pid, err := strconv.ParseInt(c.Query("pid"), 10, 64)
	if err != nil || pid <= 0 {
		fail(c, http.StatusBadRequest, config.V1CodeBadRequest, "缺少分类信息")
		return
	}
	cid, _ := strconv.ParseInt(c.Query("cid"), 10, 64)
	year, _ := strconv.ParseInt(c.Query("year"), 10, 64)
	params := system.SearchTagsVO{
		Pid:      pid,
		Cid:      cid,
		Plot:     c.Query("plot"),
		Area:     c.Query("area"),
		Language: c.Query("language"),
		Year:     year,
		Sort:     c.DefaultQuery("sort", "update_stamp"),
	}
	current, pageSize := parsePagination(c)
	page := system.Page{Current: current, PageSize: pageSize}
	list, err := logic.VCL.FilmClassifySearch(params, &page)
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, gin.H{
		"title":  logic.VCL.Category(pid),
		"list":   list,
		"search": logic.VCL.SearchTags(pid),
		"params": gin.H{
			"pid": params.Pid, "cid": params.Cid, "plot": params.Plot,
			"area": params.Area, "language": params.Language, "year": params.Year, "sort": params.Sort,
		},
		"page": newPageMeta(page),
	})
}
