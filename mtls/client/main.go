// Command client is the mTLS client side of the X.509-SVID demo.
//
// It fetches its own X.509-SVID from the SPIRE Workload API via go-spiffe,
// dials the demo server over mTLS, and accepts only the server's SPIFFE ID.
// On a successful handshake it prints the authenticated server identity and
// the line the server echoed back.
//
// SPIFFE_ENDPOINT_SOCKET must point at the Workload API socket, for example
// unix:///tmp/spire-agent/public/api.sock.
package main

import (
	"bufio"
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"os"

	"github.com/spiffe/go-spiffe/v2/spiffetls"
	"github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
	"github.com/spiffe/go-spiffe/v2/spiffeid"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
)

func main() {
	addr := envOr("MTLS_SERVER_ADDR", "127.0.0.1:8443")
	serverID := mustEnv("MTLS_SERVER_SPIFFE_ID")

	allowed, err := spiffeid.FromString(serverID)
	if err != nil {
		log.Fatalf("invalid MTLS_SERVER_SPIFFE_ID %q: %v", serverID, err)
	}

	ctx := context.Background()
	source, err := workloadapi.NewX509Source(ctx)
	if err != nil {
		log.Fatalf("fetch X.509-SVID from Workload API: %v", err)
	}
	defer source.Close()

	svid, err := source.GetX509SVID()
	if err != nil {
		log.Fatalf("get SVID: %v", err)
	}
	fmt.Printf("[client] my identity: %s\n", svid.ID)

	// MTLSClientConfig presents this client's SVID and verifies the server's
	// SVID, accepting only the single allowed server SPIFFE ID.
	cfg := tlsconfig.MTLSClientConfig(source, source, tlsconfig.AuthorizeID(allowed))
	conn, err := tls.Dial("tcp", addr, cfg)
	if err != nil {
		log.Fatalf("dial: %v", err)
	}
	defer conn.Close()

	peer, err := spiffetls.PeerIDFromConnectionState(conn.ConnectionState())
	if err != nil {
		log.Fatalf("handshake ok but no server spiffe id: %v", err)
	}
	fmt.Printf("[client] authenticated server=%s\n", peer)

	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		log.Fatalf("read reply: %v", err)
	}
	fmt.Printf("[client] server replied: %s", line)
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("%s is required", key)
	}
	return v
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
