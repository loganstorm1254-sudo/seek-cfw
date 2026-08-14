package mods

import (
	"strings"
	"testing"
)

func TestSeekHoundifyAuthGolden(t *testing.T) {
	clientAuth, requestAuth, err := seekHoundifyAuth(
		"test-client",
		"c2VjcmV0LWtleS1ieXRlcy0zMiEheHh4eA==",
		"vector",
		"req1",
		1700000000,
	)
	if err != nil {
		t.Fatal(err)
	}
	wantClient := "test-client;1700000000;MgELzEA_Cnhd0oQ_trbX5B7WvqOjgdRsOAMabqphAhE="
	wantReq := "vector;req1"
	if clientAuth != wantClient {
		t.Fatalf("clientAuth=%q want %q", clientAuth, wantClient)
	}
	if requestAuth != wantReq {
		t.Fatalf("requestAuth=%q want %q", requestAuth, wantReq)
	}
}

func TestSeekParseHoundifySpoken(t *testing.T) {
	raw := []byte(`{
		"Status": "OK",
		"AllResults": [{
			"SpokenResponseLong": "Paris is the capital of France.",
			"SpokenResponse": "Paris.",
			"WrittenResponse": "what is the capital of France",
			"Transcription": "what is the capital of France"
		}]
	}`)
	tr, ans, err := seekParseHoundify(raw)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(ans, "Paris") {
		t.Fatalf("answer=%q", ans)
	}
	if tr != "what is the capital of France" {
		t.Fatalf("transcript=%q", tr)
	}
}

func TestSeekHoundifyUnescapePadding(t *testing.T) {
	got := seekHoundifyUnescapeBase64URL("c2VjcmV0LWtleS1ieXRlcy0zMiEheHh4eA")
	if !strings.HasSuffix(got, "==") {
		t.Fatalf("expected padding, got %q", got)
	}
}
