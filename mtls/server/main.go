// Command server is the mTLS server side of the X.509-SVID demo.
//
// It fetches its own X.509-SVID from the SPIRE Workload API via go-spiffe,
// listens for mTLS connections, and accepts only the demo client's SPIFFE ID.
// On a successful handshake it prints the authenticated client identity and
// echoes one line back so the client proves the channel carries data.
//
// SPIFFE_ENDPOINT_SOCKET must point at the Workload API socket, for example
// unix:///tmp/spire-agent/public/api.sock.
package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"os"

	"github.com/spiffe/go-spiffe/v2/spiffetls"
	"github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
	"github.com/spiffe/go-spiffe/v2/spiffeid"
	"github.com/spiffe/go-spiffe/v2/workloadapi"
)

func main() {
	addr := envOr("MTLS_LISTEN_ADDR", "127.0.0.1:8443")
	clientID := mustEnv("MTLS_CLIENT_SPIFFE_ID")

	allowed, err := spiffeid.FromString(clientID)
	if err != nil {
		log.Fatalf("invalid MTLS_CLIENT_SPIFFE_ID %q: %v", clientID, err)
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
	fmt.Printf("[server] my identity: %s\n", svid.ID)

	// MTLSServerConfig presents this server's SVID and requires + verifies a
	// client SVID, authorizing it against the single allowed SPIFFE ID.
	tlsCfg := tlsconfig.MTLSServerConfig(source, source, tlsconfig.AuthorizeID(allowed))
	ln, err := tls.Listen("tcp", addr, tlsCfg)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	defer ln.Close()
	fmt.Printf("[server] listening on %s, accepting only %s\n", addr, allowed)

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("accept: %v", err)
			continue
		}
		handle(conn)
	}
}

func handle(conn net.Conn) {
	defer conn.Close()
	tlsConn := conn.(*tls.Conn)
	if err := tlsConn.Handshake(); err != nil {
		log.Printf("client handshake failed: %v", err)
		return
	}
	state := tlsConn.ConnectionState()
	peer, err := spiffetls.PeerIDFromConnectionState(state)
	if err != nil {
		log.Printf("handshake ok but no peer spiffe id (peer certs=%d): %v", len(state.PeerCertificates), err)
		return
	}
	fmt.Printf("[server] authenticated client=%s\n", peer)
	if _, err := fmt.Fprintf(conn, "hello from the %s server\n", peer.String()); err != nil {
		log.Printf("write reply: %v", err)
	}
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
