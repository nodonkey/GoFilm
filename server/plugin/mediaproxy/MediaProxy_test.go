package mediaproxy

import (
	"context"
	"errors"
	"net/url"
	"strings"
	"testing"
	"time"
)

func TestSignAndVerify(t *testing.T) {
	target := "https://cdn.example.com/a/index.m3u8?x=1"
	exp := time.Now().Add(time.Minute).Unix()
	sig := Sign(KindPlaylist, target, exp)
	if err := Verify(KindPlaylist, target, exp, sig); err != nil {
		t.Fatalf("valid signature rejected: %v", err)
	}
	if err := Verify(KindPlaylist, target, exp, sig[:31]+"0"); err == nil {
		t.Fatal("tampered signature accepted")
	}
	if err := Verify(KindPlaylist, target+"x", exp, sig); err == nil {
		t.Fatal("tampered target accepted")
	}
	if err := Verify(KindImage, target, exp, sig); err == nil {
		t.Fatal("signature reused across kinds")
	}
	if err := Verify(KindPlaylist, target, time.Now().Add(-time.Minute).Unix(), sig); err == nil {
		t.Fatal("expired signature accepted")
	}
}

func TestRewritePlaylist(t *testing.T) {
	raw := "#EXTM3U\n" +
		"#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720\n" +
		"720p/index.m3u8\n" +
		"#EXT-X-KEY:METHOD=AES-128,URI=\"https://keys.example.com/k1\"\n" +
		"#EXT-X-MAP:URI=\"init.mp4\"\n" +
		"seg-1.ts\n"
	base, _ := url.Parse("https://cdn.example.com/live/index.m3u8")
	out := string(RewritePlaylist([]byte(raw), base, "https://api.example.com"))
	for _, want := range []string{"/api/v1/proxy/m3u8?", "/api/v1/proxy/resource?"} {
		if !strings.Contains(out, want) {
			t.Fatalf("rewritten playlist missing %s:\n%s", want, out)
		}
	}
	if !strings.Contains(out, "url=https%3A%2F%2Fcdn.example.com%2Flive%2F720p%2Findex.m3u8") {
		t.Fatalf("relative playlist not resolved correctly:\n%s", out)
	}
	if !strings.Contains(out, "url=https%3A%2F%2Fkeys.example.com%2Fk1") {
		t.Fatalf("key uri not rewritten:\n%s", out)
	}
	if strings.Contains(out, "\nseg-1.ts") {
		t.Fatalf("relative segment not rewritten:\n%s", out)
	}
}

func TestPrivateTargetsBlocked(t *testing.T) {
	c := NewClient()
	targets := []string{
		"http://127.0.0.1:3601/",
		"http://localhost/",
		"http://10.0.0.1/",
		"http://172.16.0.1/",
		"http://192.168.1.1/",
		"http://169.254.169.254/latest/meta-data/",
		"http://100.64.0.1/",
		"http://[::1]/",
	}
	for _, target := range targets {
		_, err := c.validateTarget(context.Background(), target)
		var pe *Error
		if !errors.As(err, &pe) || pe.Status != 403 {
			t.Fatalf("%s should be blocked, got %v", target, err)
		}
	}
}

func TestAllowList(t *testing.T) {
	c := NewClient()
	c.allowHosts = []string{"example.com", "*.mux.dev"}
	if !c.hostAllowed("cdn.example.com") || !c.hostAllowed("example.com") {
		t.Fatal("exact/suffix host should be allowed")
	}
	if !c.hostAllowed("test-streams.mux.dev") {
		t.Fatal("wildcard host should be allowed")
	}
	if c.hostAllowed("evil.com") || c.hostAllowed("mux.dev") {
		t.Fatal("unlisted host should be blocked")
	}
}
