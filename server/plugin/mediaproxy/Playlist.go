package mediaproxy

import (
	"net/url"
	"regexp"
	"strings"
)

var uriAttrPattern = regexp.MustCompile(`URI="([^"]*)"`)

// RewritePlaylist 将 m3u8 内的切片、密钥、子播放列表全部改写为签名代理地址
func RewritePlaylist(data []byte, playlistURL *url.URL, proxyBase string) []byte {
	text := strings.TrimPrefix(string(data), "\ufeff")
	lines := strings.Split(text, "\n")
	for i, line := range lines {
		raw := strings.TrimSpace(strings.TrimSuffix(line, "\r"))
		if raw == "" {
			lines[i] = strings.TrimSuffix(line, "\r")
			continue
		}
		if strings.HasPrefix(raw, "#") {
			if strings.Contains(raw, `URI="`) {
				lines[i] = uriAttrPattern.ReplaceAllStringFunc(raw, func(m string) string {
					sub := uriAttrPattern.FindStringSubmatch(m)[1]
					return `URI="` + rewriteReference(sub, playlistURL, proxyBase) + `"`
				})
			} else {
				lines[i] = strings.TrimSuffix(line, "\r")
			}
			continue
		}
		lines[i] = rewriteReference(raw, playlistURL, proxyBase)
	}
	return []byte(strings.Join(lines, "\n"))
}

func rewriteReference(ref string, base *url.URL, proxyBase string) string {
	ref = strings.TrimSpace(ref)
	if ref == "" {
		return ref
	}
	lower := strings.ToLower(ref)
	if strings.HasPrefix(lower, "data:") || strings.HasPrefix(lower, "skd:") ||
		strings.HasPrefix(lower, "blob:") || strings.HasPrefix(lower, "file:") {
		return ref
	}
	u, err := url.Parse(ref)
	if err != nil {
		return ref
	}
	abs := base.ResolveReference(u)
	switch abs.Scheme {
	case "http", "https":
	default:
		return ref
	}
	kind := KindResource
	if isPlaylistReference(abs) {
		kind = KindPlaylist
	}
	return SignedURL(proxyBase, kind, abs.String())
}

func isPlaylistReference(u *url.URL) bool {
	path := strings.ToLower(u.Path)
	return strings.HasSuffix(path, ".m3u8") || strings.HasSuffix(path, ".m3u")
}
