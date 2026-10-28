package v1

import (
	"encoding/json"
	"net/url"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestProxyImageURLs(t *testing.T) {
	base := "http://192.168.1.10:3601"
	src := "https://img.example.com/poster.jpg"
	data := gin.H{
		"id":      json.Number("9223372036854775807"),
		"name":    "演示影片",
		"picture": src,
		"nested": []any{
			gin.H{"poster": src, "blurb": "https://example.com/not-an-image"},
		},
		"local": gin.H{"picture": "/upload/local.jpg"},
	}

	out, ok := proxyImageURLs(data, base).(map[string]any)
	if !ok {
		t.Fatal("expected map output")
	}
	if out["name"] != "演示影片" {
		t.Fatalf("unexpected name: %v", out["name"])
	}
	if out["id"] != json.Number("9223372036854775807") {
		t.Fatalf("id lost precision: %v", out["id"])
	}

	assertProxyURL(t, out["picture"].(string), base, src)

	nested := out["nested"].([]any)[0].(map[string]any)
	assertProxyURL(t, nested["poster"].(string), base, src)
	if nested["blurb"] != "https://example.com/not-an-image" {
		t.Fatalf("non-image field rewritten: %v", nested["blurb"])
	}

	local := out["local"].(map[string]any)
	if local["picture"] != "/upload/local.jpg" {
		t.Fatalf("local path rewritten: %v", local["picture"])
	}
}

func assertProxyURL(t *testing.T, got, base, want string) {
	t.Helper()
	u, err := url.Parse(got)
	if err != nil {
		t.Fatalf("invalid proxy url %q: %v", got, err)
	}
	if u.Scheme+"://"+u.Host+u.Path != base+"/api/v1/proxy/image" {
		t.Fatalf("unexpected proxy url: %s", got)
	}
	if u.Query().Get("url") != want {
		t.Fatalf("unexpected target: %s", u.Query().Get("url"))
	}
	if u.Query().Get("sign") == "" || u.Query().Get("exp") == "" {
		t.Fatalf("missing signature params: %s", got)
	}
}
