package v1

import (
	"net/http"
	"server/config"
	"server/logic"
	"strings"

	"github.com/gin-gonic/gin"
)

type qrCreateRequest struct {
	DeviceID   string `json:"deviceId"`
	DeviceName string `json:"deviceName"`
	Platform   string `json:"platform"`
	AppVersion string `json:"appVersion"`
}

type qrActionRequest struct {
	QID string `json:"qid"`
}

// QRCreate TV 创建扫码登录二维码
func QRCreate(c *gin.Context) {
	var req qrCreateRequest
	if !bindJSON(c, &req) {
		return
	}
	result, err := logic.QL.Create(logic.DeviceInfo{
		DeviceID:   req.DeviceID,
		DeviceName: req.DeviceName,
		Platform:   req.Platform,
		AppVersion: req.AppVersion,
	}, requestBaseURL(c), c.ClientIP())
	if err != nil {
		handleError(c, err)
		return
	}
	created(c, result)
}

// QRInfo 二维码公开信息
func QRInfo(c *gin.Context) {
	info, err := logic.QL.Info(c.Query("qid"))
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, info)
}

// QRPoll TV 轮询扫码状态
func QRPoll(c *gin.Context) {
	result, err := logic.QL.Poll(c.Query("qid"), c.Query("token"))
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, result)
}

// QRScan 手机扫码后标记
func QRScan(c *gin.Context) {
	userID, valid := currentUserID(c)
	if !valid {
		return
	}
	var req qrActionRequest
	if !bindJSON(c, &req) {
		return
	}
	status, err := logic.QL.Scan(req.QID, userID)
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, gin.H{"status": status})
}

// QRConfirm 手机确认登录
func QRConfirm(c *gin.Context) {
	userID, valid := currentUserID(c)
	if !valid {
		return
	}
	var req qrActionRequest
	if !bindJSON(c, &req) {
		return
	}
	status, err := logic.QL.Confirm(req.QID, userID)
	if err != nil {
		handleError(c, err)
		return
	}
	ok(c, gin.H{"status": status})
}

// requestBaseURL 生成客户端可访问的绝对地址
func requestBaseURL(c *gin.Context) string {
	if config.V1PublicBaseURL != "" {
		return config.V1PublicBaseURL
	}
	scheme := "http"
	if c.Request.TLS != nil || strings.EqualFold(c.GetHeader("X-Forwarded-Proto"), "https") {
		scheme = "https"
	}
	host := c.GetHeader("X-Forwarded-Host")
	if host == "" {
		host = c.Request.Host
	}
	return scheme + "://" + host
}

// QRConfirmPage 扫码确认 H5 页面, 与 Web 前台相互独立
func QRConfirmPage(c *gin.Context) {
	c.Header("Content-Type", "text/html; charset=utf-8")
	c.Header("Cache-Control", "no-store")
	c.Header("X-Frame-Options", "DENY")
	c.Header("Referrer-Policy", "no-referrer")
	c.Header("Content-Security-Policy", "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'self' data:; connect-src 'self'")
	c.String(http.StatusOK, qrConfirmHTML)
}

const qrConfirmHTML = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<title>登录确认 - GoFilm</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; background: #0f1115; color: #e8eaf0;
         font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Microsoft YaHei", sans-serif;
         display: flex; align-items: center; justify-content: center; padding: 24px; }
  .card { width: 100%; max-width: 380px; background: #171a21; border: 1px solid #262b36; border-radius: 16px; padding: 28px 24px; }
  h1 { font-size: 20px; margin: 0 0 8px; }
  .muted { color: #8b93a7; font-size: 13px; line-height: 1.6; }
  .device { margin: 18px 0; padding: 14px; background: #11141a; border-radius: 12px; border: 1px solid #262b36; }
  .device b { color: #6ea8fe; }
  label { display: block; font-size: 13px; color: #a7aec0; margin: 14px 0 6px; }
  input { width: 100%; padding: 12px; border-radius: 10px; border: 1px solid #2b3140; background: #10131a; color: #e8eaf0; font-size: 15px; outline: none; }
  input:focus { border-color: #3b82f6; }
  button { width: 100%; margin-top: 18px; padding: 12px; border: 0; border-radius: 10px; background: #3b82f6; color: #fff; font-size: 15px; font-weight: 600; }
  button:disabled { opacity: .55; }
  .msg { margin-top: 14px; font-size: 13px; line-height: 1.6; min-height: 20px; }
  .err { color: #f87171; }
  .ok { color: #4ade80; }
  .hidden { display: none; }
  .success { text-align: center; padding: 20px 0 8px; }
  .success .icon { width: 56px; height: 56px; border-radius: 50%; background: #14351f; color: #4ade80; font-size: 30px; line-height: 56px; margin: 0 auto 14px; }
</style>
</head>
<body>
<div class="card">
  <h1>登录确认</h1>
  <p class="muted" id="subtitle">正在读取二维码信息…</p>
  <div class="device" id="deviceBox">
    <div class="muted">即将登录的设备</div>
    <div id="deviceName" style="margin-top:6px;font-size:16px;">-</div>
    <div class="muted" id="countdown" style="margin-top:6px;"></div>
  </div>
  <form id="form" class="hidden">
    <label for="account">用户名</label>
    <input id="account" autocomplete="username" required>
    <label for="password">密码</label>
    <input id="password" type="password" autocomplete="current-password" required>
    <button id="submit" type="submit">确认登录</button>
    <div class="msg" id="msg"></div>
  </form>
  <div class="success hidden" id="success">
    <div class="icon">✓</div>
    <div style="font-size:16px;margin-bottom:6px;">已确认登录</div>
    <div class="muted">请回到电视上继续，本页面可以关闭。</div>
  </div>
  <div class="msg err hidden" id="fatal"></div>
</div>
<script>
(function () {
  var qid = new URLSearchParams(location.search).get('qid') || '';
  var form = document.getElementById('form');
  var msg = document.getElementById('msg');
  var fatal = document.getElementById('fatal');
  var submit = document.getElementById('submit');
  var token = '';
  var timer = null;

  function showFatal(text) {
    document.getElementById('subtitle').textContent = '无法完成确认';
    document.getElementById('deviceBox').classList.add('hidden');
    form.classList.add('hidden');
    fatal.textContent = text;
    fatal.classList.remove('hidden');
  }
  function setMsg(text, ok) {
    msg.textContent = text || '';
    msg.className = 'msg ' + (ok ? 'ok' : 'err');
  }
  function postJSON(url, body, withAuth) {
    var headers = { 'Content-Type': 'application/json' };
    if (withAuth && token) headers['Authorization'] = 'Bearer ' + token;
    return fetch(url, { method: 'POST', headers: headers, body: JSON.stringify(body) })
      .then(function (res) {
        return res.json().catch(function () { return {}; }).then(function (data) {
          if (!res.ok || data.code !== 0) {
            throw new Error(data.msg || ('请求失败 (' + res.status + ')'));
          }
          return data.data;
        });
      });
  }
  function startCountdown(seconds) {
    var left = seconds;
    var el = document.getElementById('countdown');
    function tick() {
      if (left <= 0) {
        el.textContent = '二维码已过期，请在电视上刷新';
        form.classList.add('hidden');
        return;
      }
      el.textContent = '二维码 ' + left + ' 秒后过期';
      left -= 1;
    }
    tick();
    timer = setInterval(tick, 1000);
  }

  if (!/^[A-Za-z0-9_-]{16,64}$/.test(qid)) {
    showFatal('二维码链接不完整，请重新扫码。');
    return;
  }

  fetch('/api/v1/auth/qr/info?qid=' + encodeURIComponent(qid))
    .then(function (res) { return res.json(); })
    .then(function (data) {
      if (data.code !== 0 || !data.data) {
        throw new Error(data.msg || '二维码已过期');
      }
      var info = data.data;
      document.getElementById('deviceName').textContent = info.deviceName || '未知设备';
      if (info.status === 'confirmed') {
        document.getElementById('subtitle').textContent = '该二维码已完成确认';
        document.getElementById('deviceBox').classList.add('hidden');
        document.getElementById('success').classList.remove('hidden');
        return;
      }
      if (info.status === 'expired' || info.status === 'canceled') {
        throw new Error('二维码已过期，请在电视上刷新');
      }
      document.getElementById('subtitle').textContent = '使用 GoFilm 账号确认后，电视将自动登录';
      form.classList.remove('hidden');
      startCountdown(info.expiresIn || 0);
    })
    .catch(function (err) { showFatal(err.message || '二维码无效'); });

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var account = document.getElementById('account').value.trim();
    var password = document.getElementById('password').value;
    if (!account || !password) { setMsg('请输入用户名和密码', false); return; }
    submit.disabled = true;
    setMsg('正在确认…', true);
    var deviceId = 'h5-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
    postJSON('/api/v1/auth/login', {
      account: account, password: password,
      deviceId: deviceId, deviceName: '扫码确认页', platform: 'h5'
    }, false).then(function (auth) {
      token = auth.accessToken;
      return postJSON('/api/v1/auth/qr/confirm', { qid: qid }, true).then(function () {
        return postJSON('/api/v1/auth/logout', {}, true).catch(function () {});
      });
    }).then(function () {
      if (timer) clearInterval(timer);
      form.classList.add('hidden');
      document.getElementById('deviceBox').classList.add('hidden');
      document.getElementById('subtitle').textContent = '';
      document.getElementById('success').classList.remove('hidden');
    }).catch(function (err) {
      submit.disabled = false;
      setMsg(err.message || '确认失败，请重试', false);
    });
  });
})();
</script>
</body>
</html>
`
