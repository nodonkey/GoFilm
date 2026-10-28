package mediaproxy

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"server/config"
	"strings"
	"time"
)

const (
	proxyUserAgent = "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) GoFilmProxy/1.0"
	maxRedirects   = 3
	dialTimeout    = 6 * time.Second
)

// Client 带 SSRF 防护的上游请求客户端
type Client struct {
	transport  *http.Transport
	httpClient *http.Client
	allowHosts []string
	timeout    time.Duration
}

var Default = NewClient()

func NewClient() *Client {
	c := &Client{
		allowHosts: config.V1ProxyAllowedHosts,
		timeout:    config.V1ProxyTimeout,
	}
	dialer := &net.Dialer{Timeout: dialTimeout, KeepAlive: 30 * time.Second}
	c.transport = &http.Transport{
		Proxy:                 http.ProxyFromEnvironment,
		DialContext:           c.dialContext(dialer),
		ForceAttemptHTTP2:     true,
		MaxIdleConns:          64,
		MaxIdleConnsPerHost:   8,
		IdleConnTimeout:       90 * time.Second,
		TLSHandshakeTimeout:   10 * time.Second,
		ResponseHeaderTimeout: config.V1ProxyTimeout,
		ExpectContinueTimeout: 2 * time.Second,
	}
	c.httpClient = &http.Client{
		Transport: c.transport,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= maxRedirects {
				return newError(502, "上游重定向次数过多")
			}
			_, err := c.validateTarget(req.Context(), req.URL.String())
			return err
		},
	}
	return c
}

// Fetch 请求上游资源, 调用方负责关闭 Body 并控制读取上限
func (c *Client) Fetch(ctx context.Context, rawURL, rangeHeader string) (*http.Response, error) {
	target, err := c.validateTarget(ctx, rawURL)
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target.String(), nil)
	if err != nil {
		cancel()
		return nil, newError(400, "资源地址不合法")
	}
	req.Header.Set("User-Agent", proxyUserAgent)
	req.Header.Set("Accept", "*/*")
	req.Header.Set("Referer", target.Scheme+"://"+target.Host+"/")
	if rangeHeader != "" {
		req.Header.Set("Range", rangeHeader)
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		cancel()
		var pe *Error
		if errors.As(err, &pe) {
			return nil, pe
		}
		return nil, newError(502, "上游资源请求失败")
	}
	resp.Body = &cancelReadCloser{ReadCloser: resp.Body, cancel: cancel}
	return resp, nil
}

// FetchBytes 读取指定上限内的完整响应
func (c *Client) FetchBytes(ctx context.Context, rawURL string, max int64) ([]byte, string, *http.Response, error) {
	resp, err := c.Fetch(ctx, rawURL, "")
	if err != nil {
		return nil, "", nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, "", resp, newError(502, fmt.Sprintf("上游返回状态码 %d", resp.StatusCode))
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, max+1))
	if err != nil {
		return nil, "", resp, newError(502, "上游资源读取失败")
	}
	if int64(len(data)) > max {
		return nil, "", resp, newError(413, "上游资源超过大小限制")
	}
	return data, resp.Header.Get("Content-Type"), resp, nil
}

func (c *Client) validateTarget(ctx context.Context, raw string) (*url.URL, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, newError(400, "缺少资源地址")
	}
	u, err := url.Parse(raw)
	if err != nil {
		return nil, newError(400, "资源地址不合法")
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return nil, newError(400, "仅支持 http/https 资源")
	}
	if u.User != nil {
		return nil, newError(400, "资源地址不合法")
	}
	host := strings.ToLower(u.Hostname())
	if host == "" {
		return nil, newError(400, "资源地址不合法")
	}
	if !c.hostAllowed(host) {
		return nil, newError(403, "上游域名不在允许列表内")
	}
	ips, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil || len(ips) == 0 {
		return nil, newError(502, "上游域名解析失败")
	}
	for _, ip := range ips {
		if !isPublicIP(ip.IP) {
			return nil, newError(403, "禁止访问内网地址")
		}
	}
	return u, nil
}

func (c *Client) hostAllowed(host string) bool {
	if len(c.allowHosts) == 0 {
		return true
	}
	for _, pattern := range c.allowHosts {
		if pattern == "*" {
			return true
		}
		if strings.HasPrefix(pattern, "*.") {
			if strings.HasSuffix(host, pattern[1:]) {
				return true
			}
			continue
		}
		if host == pattern || strings.HasSuffix(host, "."+pattern) {
			return true
		}
	}
	return false
}

// dialContext 校验实际解析到的 IP, 防止 DNS rebinding
func (c *Client) dialContext(dialer *net.Dialer) func(ctx context.Context, network, addr string) (net.Conn, error) {
	return func(ctx context.Context, network, addr string) (net.Conn, error) {
		host, port, err := net.SplitHostPort(addr)
		if err != nil {
			return nil, err
		}
		ips, err := net.DefaultResolver.LookupIPAddr(ctx, host)
		if err != nil || len(ips) == 0 {
			return nil, newError(502, "上游域名解析失败")
		}
		for _, ip := range ips {
			if !isPublicIP(ip.IP) {
				return nil, newError(403, "禁止访问内网地址")
			}
		}
		var lastErr error
		for _, ip := range ips {
			conn, err := dialer.DialContext(ctx, network, net.JoinHostPort(ip.IP.String(), port))
			if err == nil {
				return conn, nil
			}
			lastErr = err
		}
		if lastErr == nil {
			lastErr = newError(502, "上游连接失败")
		}
		return nil, lastErr
	}
}

func isPublicIP(ip net.IP) bool {
	if ip == nil || ip.IsLoopback() || ip.IsPrivate() || ip.IsUnspecified() ||
		ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() ||
		ip.IsMulticast() || ip.IsInterfaceLocalMulticast() {
		return false
	}
	if v4 := ip.To4(); v4 != nil {
		switch {
		case v4[0] == 0:
			return false
		case v4[0] == 100 && v4[1] >= 64 && v4[1] <= 127: // CGNAT
			return false
		case v4[0] == 198 && (v4[1] == 18 || v4[1] == 19):
			return false
		case v4[0] == 192 && v4[1] == 0 && v4[2] == 0:
			return false
		case v4[0] >= 224:
			return false
		}
		return true
	}
	// 文档地址段
	if len(ip) == net.IPv6len && ip[0] == 0x20 && ip[1] == 0x01 && ip[2] == 0x0d && ip[3] == 0xb8 {
		return false
	}
	return true
}

type cancelReadCloser struct {
	io.ReadCloser
	cancel context.CancelFunc
}

func (c *cancelReadCloser) Close() error {
	err := c.ReadCloser.Close()
	c.cancel()
	return err
}
