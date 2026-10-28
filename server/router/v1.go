package router

import (
	"github.com/gin-gonic/gin"
	v1 "server/controller/v1"
	"server/plugin/middleware"
)

// registerV1 多端客户端 API, 与旧版 Web API 独立
func registerV1(r *gin.Engine) {
	api := r.Group("/api/v1")
	{
		api.GET("/health", v1.Health)
		api.GET("/config", v1.Config)
		api.GET("/nav", v1.Nav)
		api.GET("/index", v1.Index)

		api.GET("/films/:mid", v1.FilmDetail)
		api.GET("/films/:mid/play", v1.FilmPlay)
		api.GET("/search", v1.Search)
		api.GET("/classify", v1.FilmClassify)
		api.GET("/classify/search", v1.FilmClassifySearch)

		// 签名媒体代理
		api.GET("/proxy/m3u8", v1.ProxyM3U8)
		api.GET("/proxy/image", v1.ProxyImage)
		api.GET("/proxy/resource", v1.ProxyResource)

		// TV 扫码登录
		api.POST("/auth/qr/create", v1.QRCreate)
		api.GET("/auth/qr/info", v1.QRInfo)
		api.GET("/auth/qr/poll", v1.QRPoll)
		api.POST("/auth/qr/scan", middleware.AuthV1(), v1.QRScan)
		api.POST("/auth/qr/confirm", middleware.AuthV1(), v1.QRConfirm)
	}
	// 扫码确认页, 手机系统相机直接打开
	r.GET("/qr", v1.QRConfirmPage)

	auth := api.Group("/auth")
	{
		auth.POST("/register", v1.Register)
		auth.POST("/login", v1.Login)
		auth.POST("/refresh", v1.Refresh)
		auth.POST("/logout", middleware.AuthV1(), v1.Logout)
		auth.POST("/logout-all", middleware.AuthV1(), v1.LogoutAll)
		auth.GET("/me", middleware.AuthV1(), v1.Me)
		auth.GET("/devices", middleware.AuthV1(), v1.Devices)
		auth.DELETE("/devices/:deviceId", middleware.AuthV1(), v1.RevokeDevice)
	}

	me := api.Group("/me", middleware.AuthV1())
	{
		me.GET("/history", v1.SyncHistory)
		me.POST("/history", v1.ApplyHistory)
		me.GET("/favorites", v1.SyncFavorites)
		me.POST("/favorites", v1.ApplyFavorites)
	}
}
