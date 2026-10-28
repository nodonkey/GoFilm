package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

/*
 定义一些数据库存放的key值, 以及程序运行时的相关参数配置
*/

// -------------------------System Config-----------------------------------
const (

	// ListenerPort web服务监听的端口
	ListenerPort = "3601"

	// MAXGoroutine max goroutine, 执行spider中对协程的数量限制
	MAXGoroutine = 10

	// FilmSaveCacheThreshold 采集数据保存时直接保存 or 缓存到 redis ( h < 168, 缓存到redis)
	FilmSaveCacheThreshold = 168

	// FilmScanSize 同步影片数据时每次扫描的数据量
	FilmScanSize = 50

	FilmPictureUploadDir = "./static/upload/gallery"
	FilmPictureUrlPath   = "/upload/pic/poster/"
	FilmPictureAccess    = "/api/upload/pic/poster/"
)

// -------------------------redis key-----------------------------------
const (
	// CategoryTreeKey 分类树 key
	CategoryTreeKey = "CategoryTree"
	FilmExpired     = time.Hour * 24 * 365 * 10
	// MovieListInfoKey movies分类列表 key
	MovieListInfoKey = "MovieList:Cid%d"

	// MovieDetailKey movie detail影视详情信息 可以
	MovieDetailKey = "MovieDetail:Master"
	// MovieBasicInfoKey 影片基本信息, 简略版本
	MovieBasicInfoKey = "MovieBasicInfo:Cid%d:Id%d"

	// MultipleSiteDetailKey 多站点影片信息存储key
	MultipleSiteDetailKey = "MovieDetail:Slave:%s"

	MovieDetailTemp = "Temp:MovieDetail:%s"

	// SearchInfoTemp redis暂存检索数据信息
	SearchInfoTemp = "Search:SearchInfoTemp"

	// SearchTitle 影片分类标题key
	SearchTitle = "Search:Pid%d:Title"
	// SearchTag 影片剧情标签key
	SearchTag = "Search:Pid%d:%s"

	// VirtualPictureKey 待同步图片临时存储 key
	VirtualPictureKey = "Temp:VirtualPicture"
	// MaxScanCount redis Scan 操作每次扫描的数据量, 每次最多扫描300条数据
	MaxScanCount = 300
)

const (
	AuthUserClaims = "UserClaims"
)

// -------------------------manage 管理后台相关key----------------------------------
const (
	// FilmSourceListKey 采集 API 信息列表key
	FilmSourceListKey = "Config:Collect:FilmSource"
	// ManageConfigExpired 管理配置key 长期有效, 暂定10年
	ManageConfigExpired = time.Hour * 24 * 365 * 10
	// SiteConfigBasic 网站参数配置
	SiteConfigBasic = "SystemConfig:SiteConfig:Basic"
	// BannersKey 轮播组件key 你
	BannersKey = "SystemConfig:Banners"

	// FilmCrontabKey 定时任务列表信息
	FilmCrontabKey = "Cron:Task:Film"
	// DefaultUpdateSpec 每20分钟执行一次
	DefaultUpdateSpec = "0 */20 * * * ?"
	// EveryWeekSpec 每周日凌晨4点更新一次
	EveryWeekSpec  = "0 0 3 * * 0"
	PeriodSyncSpec = "0 0 4 * * 0"
	// DefaultUpdateTime 每次采集最近 3 小时内更新的影片
	DefaultUpdateTime = 3
)

// -------------------------Web API相关redis key-----------------------------------
const (
	// IndexCacheKey , 首页数据缓存
	IndexCacheKey = "IndexCache"
)

// -------------------------Database Connection Params-----------------------------------
const (
	// SearchTableName 存放检索信息的数据表名
	SearchTableName        = "search"
	UserTableName          = "users"
	MovieDetailName        = "movie_details"
	SlaveMovieInfo         = "slave_infos"
	UserIdInitialVal       = 10000
	FileTableName          = "files"
	FailureRecordTableName = "failure_records"
)

/*
	mysql / redis 连接信息, 支持通过环境变量覆盖,
	默认值对应本地开发容器 (docker-compose.local.yml)
*/
var (
	MysqlDsn = fmt.Sprintf("%s:%s@(%s:%s)/%s?charset=utf8mb4&parseTime=True&loc=Local",
		env("MYSQL_USER", "root"),
		env("MYSQL_PASSWORD", "root"),
		env("MYSQL_HOST", "127.0.0.1"),
		env("MYSQL_PORT", "3610"),
		env("MYSQL_DBNAME", "FilmSite"),
	)
	RedisAddr     = env("REDIS_HOST", "127.0.0.1") + ":" + env("REDIS_PORT", "3620")
	RedisPassword = env("REDIS_PASSWORD", "root")
	RedisDBNo     = envInt("REDIS_DB", 0)
)

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v, err := strconv.Atoi(os.Getenv(key)); err == nil {
		return v
	}
	return def
}
