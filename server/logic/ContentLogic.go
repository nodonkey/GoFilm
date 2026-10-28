package logic

import (
	"encoding/json"
	"fmt"
	"server/config"
	"server/model/system"
	"strings"
	"time"
	"unicode/utf8"
)

type ContentLogic struct {
}

var VCL = &ContentLogic{}

// ConfigResponse 客户端启动配置
type ConfigResponse struct {
	Site            system.BasicConfig `json:"site"`
	ApiVersion      string             `json:"apiVersion"`
	ServerTime      int64              `json:"serverTime"`
	Registration    bool               `json:"registration"`
	MaxSyncBatch    int                `json:"maxSyncBatch"`
	AccessTokenTTL  int64              `json:"accessTokenTtl"`
	RefreshTokenTTL int64              `json:"refreshTokenTtl"`
	MediaProxy      bool               `json:"mediaProxy"`
}

// FilmDetailResult 影片详情与相关推荐
type FilmDetailResult struct {
	Detail system.MovieDetailVo    `json:"detail"`
	Relate []system.MovieBasicInfo `json:"relate"`
}

// FilmPlayResult 播放页数据
type FilmPlayResult struct {
	Detail          system.MovieDetailVo    `json:"detail"`
	Current         system.PlayItem         `json:"current"`
	CurrentPlayFrom string                  `json:"currentPlayFrom"`
	CurrentEpisode  int                     `json:"currentEpisode"`
	Relate          []system.MovieBasicInfo `json:"relate"`
	Proxy           bool                    `json:"proxy"`
}

// FilmClassifyResult 分类首页数据
type FilmClassifyResult struct {
	Title   *system.CategoryTree   `json:"title"`
	Content map[string]interface{} `json:"content"`
}

// Config 获取站点配置
func (c *ContentLogic) Config() ConfigResponse {
	return ConfigResponse{
		Site:            system.GetSiteBasic(),
		ApiVersion:      "v1",
		ServerTime:      time.Now().UnixMilli(),
		Registration:    true,
		MaxSyncBatch:    config.V1SyncBatchLimit,
		AccessTokenTTL:  int64(config.V1AccessTokenTTL / time.Second),
		RefreshTokenTTL: int64(config.V1RefreshTokenTTL / time.Second),
		MediaProxy:      config.V1ProxyEnabled,
	}
}

// Nav 获取展示用的分类树
func (c *ContentLogic) Nav() []*system.CategoryTree {
	tree := system.GetCategoryTree()
	res := make([]*system.CategoryTree, 0, len(tree.Children))
	for _, child := range tree.Children {
		if child == nil || !child.Show {
			continue
		}
		res = append(res, cloneVisibleTree(child))
	}
	return res
}

// Index 获取首页数据, 复用 Web 首页的缓存
func (c *ContentLogic) Index() map[string]interface{} {
	page := (&IndexLogic{}).IndexPage()
	if page == nil {
		return nil
	}
	page["banners"] = playableBanners(page)
	return page
}

// maxPlayableBanners 客户端首页最多展示的轮播数量
const maxPlayableBanners = 4

type bannerEntry struct {
	Id      string `json:"id"`
	Mid     int64  `json:"mid"`
	Name    string `json:"name"`
	Year    int64  `json:"year"`
	CName   string `json:"cName"`
	Poster  string `json:"poster"`
	Picture string `json:"picture"`
	Remark  string `json:"remark"`
	Sort    int64  `json:"sort"`
}

type indexContentEntry struct {
	Movies []struct {
		Id      int64  `json:"id"`
		Name    string `json:"name"`
		CName   string `json:"cName"`
		Picture string `json:"picture"`
		Remarks string `json:"remarks"`
	} `json:"movies"`
}

// playableBanners 保证客户端轮播项都绑定真实影片, 未绑定且无法按片名匹配的轮播位用首页影片补齐
func playableBanners(page map[string]interface{}) []map[string]interface{} {
	var banners []bannerEntry
	if data, err := json.Marshal(page["banners"]); err == nil {
		_ = json.Unmarshal(data, &banners)
	}
	var pending []string
	for _, b := range banners {
		if b.Mid <= 0 && strings.TrimSpace(b.Name) != "" {
			pending = append(pending, b.Name)
		}
	}
	resolved := system.FindMidsByNames(pending)

	res := make([]map[string]interface{}, 0, maxPlayableBanners)
	seen := make(map[int64]struct{}, maxPlayableBanners)
	for _, b := range banners {
		mid := b.Mid
		if mid <= 0 {
			mid = resolved[b.Name]
		}
		if mid <= 0 {
			continue
		}
		if _, dup := seen[mid]; dup {
			continue
		}
		seen[mid] = struct{}{}
		res = append(res, map[string]interface{}{
			"id": b.Id, "mid": mid, "name": b.Name, "year": b.Year, "cName": b.CName,
			"poster": b.Poster, "picture": b.Picture, "remark": b.Remark, "sort": b.Sort,
		})
		if len(res) >= maxPlayableBanners {
			return res
		}
	}

	var content []indexContentEntry
	if data, err := json.Marshal(page["content"]); err == nil {
		_ = json.Unmarshal(data, &content)
	}
	for _, section := range content {
		for _, m := range section.Movies {
			if len(res) >= maxPlayableBanners {
				return res
			}
			if m.Id <= 0 || m.Picture == "" {
				continue
			}
			if _, dup := seen[m.Id]; dup {
				continue
			}
			seen[m.Id] = struct{}{}
			res = append(res, map[string]interface{}{
				"id":      fmt.Sprintf("auto-%d", m.Id),
				"mid":     m.Id,
				"name":    m.Name,
				"year":    0,
				"cName":   m.CName,
				"poster":  m.Picture,
				"picture": m.Picture,
				"remark":  m.Remarks,
				"sort":    len(res),
			})
		}
	}
	return res
}

// FilmDetail 获取影片详情与相关推荐
func (c *ContentLogic) FilmDetail(mid int64) (*FilmDetailResult, error) {
	if mid <= 0 {
		return nil, NewBadRequest("影片ID不合法")
	}
	detail := system.GetDetailByMid(mid)
	if detail.Mid <= 0 {
		return nil, NewNotFound("影片不存在")
	}
	sources := multipleSource(&detail)
	vo := system.ConvertMovieDetailVo(detail, sources)
	page := system.Page{Current: 0, PageSize: 14}
	relate := (&IndexLogic{}).RelateMovie(vo, &page)
	if relate == nil {
		relate = make([]system.MovieBasicInfo, 0)
	}
	return &FilmDetailResult{Detail: vo, Relate: relate}, nil
}

// FilmPlay 获取指定播放源和集数的播放信息
func (c *ContentLogic) FilmPlay(mid int64, playFrom string, episode int) (*FilmPlayResult, error) {
	if mid <= 0 {
		return nil, NewBadRequest("影片ID不合法")
	}
	if episode < 0 {
		return nil, NewBadRequest("集数不合法")
	}
	detail := system.GetDetailByMid(mid)
	if detail.Mid <= 0 {
		return nil, NewNotFound("影片不存在")
	}
	vo := system.ConvertMovieDetailVo(detail, multipleSource(&detail))
	if len(vo.List) == 0 {
		return nil, NewNotFound("暂无可播放资源")
	}
	source := vo.List[0]
	if playFrom != "" {
		found := false
		for _, s := range vo.List {
			if s.Id == playFrom {
				source = s
				found = true
				break
			}
		}
		if !found {
			return nil, NewNotFound("播放源不存在")
		}
	}
	if len(source.LinkList) == 0 {
		return nil, NewNotFound("当前播放源暂无剧集")
	}
	if episode >= len(source.LinkList) {
		return nil, NewBadRequest("集数超出范围")
	}
	page := system.Page{Current: 0, PageSize: 14}
	relate := (&IndexLogic{}).RelateMovie(vo, &page)
	if relate == nil {
		relate = make([]system.MovieBasicInfo, 0)
	}
	return &FilmPlayResult{
		Detail:          vo,
		Current:         source.LinkList[episode],
		CurrentPlayFrom: source.Id,
		CurrentEpisode:  episode,
		Relate:          relate,
	}, nil
}

// Search 关键字搜索
func (c *ContentLogic) Search(keyword string, page *system.Page) ([]system.MovieBasicInfo, error) {
	keyword = strings.TrimSpace(keyword)
	if keyword == "" {
		return nil, NewBadRequest("搜索关键词不能为空")
	}
	if utf8.RuneCountInString(keyword) > 64 {
		return nil, NewBadRequest("搜索关键词过长")
	}
	ids := system.SearchFilmKeyword(keyword, page)
	list := system.GetBasicInfoByIds(ids)
	if list == nil {
		list = make([]system.MovieBasicInfo, 0)
	}
	return list, nil
}

// FilmClassify 分类首页数据
func (c *ContentLogic) FilmClassify(pid int64) (*FilmClassifyResult, error) {
	if pid <= 0 {
		return nil, NewBadRequest("分类ID不合法")
	}
	title := (&IndexLogic{}).GetPidCategory(pid)
	if title == nil {
		return nil, NewNotFound("分类不存在")
	}
	page := system.Page{Current: 1, PageSize: 21}
	return &FilmClassifyResult{
		Title:   title,
		Content: (&IndexLogic{}).GetFilmClassify(pid, &page),
	}, nil
}

// FilmClassifySearch 按标签筛选影片
func (c *ContentLogic) FilmClassifySearch(params system.SearchTagsVO, page *system.Page) ([]system.MovieBasicInfo, error) {
	if params.Pid <= 0 {
		return nil, NewBadRequest("缺少分类信息")
	}
	title := (&IndexLogic{}).GetPidCategory(params.Pid)
	if title == nil {
		return nil, NewNotFound("分类不存在")
	}
	if params.Sort == "" {
		params.Sort = "update_stamp"
	}
	if !allowedSort(params.Sort) {
		return nil, NewBadRequest("排序方式不合法")
	}
	ids := system.GetSearchInfosByTags(params, page)
	list := system.GetBasicInfoByIds(ids)
	if list == nil {
		list = make([]system.MovieBasicInfo, 0)
	}
	return list, nil
}

// Category 获取指定一级分类
func (c *ContentLogic) Category(pid int64) *system.CategoryTree {
	return (&IndexLogic{}).GetPidCategory(pid)
}

// SearchTags 获取分类的筛选项
func (c *ContentLogic) SearchTags(pid int64) map[string]interface{} {
	return (&IndexLogic{}).SearchTags(pid)
}

func allowedSort(sort string) bool {
	switch sort {
	case "update_stamp", "hits", "score", "release_stamp":
		return true
	}
	return false
}

func cloneVisibleTree(node *system.CategoryTree) *system.CategoryTree {
	category := *node.Category
	res := &system.CategoryTree{Category: &category}
	res.Children = make([]*system.CategoryTree, 0, len(node.Children))
	for _, child := range node.Children {
		if child == nil || !child.Show {
			continue
		}
		res.Children = append(res.Children, cloneVisibleTree(child))
	}
	return res
}
