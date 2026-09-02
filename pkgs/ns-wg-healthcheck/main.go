package main

import (
	"bytes"
	"context"
	crand "crypto/rand"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	mrand "math/rand"
	"net"
	"net/http"
	"net/netip"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/windtf/wireproxy"
	"golang.org/x/net/icmp"
	"golang.org/x/net/ipv4"
	"golang.org/x/net/ipv6"
	"golang.zx2c4.com/wireguard/device"
	"gopkg.in/yaml.v3"
)

type config struct {
	Listen        string  `yaml:"listen"`
	ServersDir    string  `yaml:"servers_dir"`
	CheckTarget   string  `yaml:"check_target"`
	CheckInterval string  `yaml:"check_interval"`
	LossWindow    string  `yaml:"loss_window"`
	MaxPacketLoss float64 `yaml:"max_packet_loss"`
	PingTimeout   string  `yaml:"ping_timeout"`
	Primary       string  `yaml:"primary"`
	Backup        string  `yaml:"backup"`
}

type runtimeConfig struct {
	listen        string
	serversDir    string
	checkTarget   netip.Addr
	checkInterval time.Duration
	lossWindow    time.Duration
	maxPacketLoss float64
	pingTimeout   time.Duration
	primary       string
	backup        string
}

type server struct {
	id       string
	address  string
	endpoint string
	tun      *wireproxy.VirtualTun
	stats    *rollingStats
}

type sample struct {
	at time.Time
	ok bool
}

type rollingStats struct {
	mu      sync.Mutex
	window  time.Duration
	samples []sample
}

type statusResponse struct {
	Primary string                 `json:"primary"`
	Backup  string                 `json:"backup"`
	Servers map[string]serverState `json:"servers"`
}

type serverState struct {
	Address       string  `json:"address"`
	Endpoint      string  `json:"endpoint"`
	Healthy       bool    `json:"healthy"`
	PacketLoss    float64 `json:"packet_loss"`
	SampleCount   int     `json:"sample_count"`
	MaxPacketLoss float64 `json:"max_packet_loss"`
}

func main() {
	log.SetFlags(log.LstdFlags | log.Lmicroseconds)

	configPath := flag.String("config", "/config/wg-healthcheck.yaml", "path to wg-healthcheck YAML config")
	flag.Parse()

	cfg, err := loadConfig(*configPath)
	must(err)

	servers, err := loadServers(cfg)
	must(err)
	if _, ok := servers[cfg.primary]; !ok {
		must(fmt.Errorf("primary server %q not found", cfg.primary))
	}
	if _, ok := servers[cfg.backup]; !ok {
		must(fmt.Errorf("backup server %q not found", cfg.backup))
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	for _, srv := range servers {
		srv.stats = &rollingStats{window: cfg.lossWindow}
		go srv.runChecks(ctx, cfg.checkTarget, cfg.checkInterval, cfg.pingTimeout)
		log.Printf("started %s endpoint=%s address=%s target=%s interval=%s window=%s max_loss=%.2f timeout=%s", srv.id, srv.endpoint, srv.address, cfg.checkTarget, cfg.checkInterval, cfg.lossWindow, cfg.maxPacketLoss, cfg.pingTimeout)
	}

	httpServer := &http.Server{
		Addr:    cfg.listen,
		Handler: routes(cfg, servers),
	}

	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = httpServer.Shutdown(shutdownCtx)
	}()

	log.Printf("listening on %s", cfg.listen)
	err = httpServer.ListenAndServe()
	if !errors.Is(err, http.ErrServerClosed) {
		must(err)
	}
}

func loadConfig(path string) (runtimeConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return runtimeConfig{}, err
	}

	cfg := config{
		Listen:        "127.0.0.1:8088",
		ServersDir:    "/config/wg-healthcheck/servers",
		CheckTarget:   "1.1.1.1",
		CheckInterval: "5s",
		LossWindow:    "5m",
		MaxPacketLoss: 0.10,
		PingTimeout:   "2s",
		Primary:       "primary",
		Backup:        "backup",
	}
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return runtimeConfig{}, err
	}

	target, err := netip.ParseAddr(cfg.CheckTarget)
	if err != nil {
		return runtimeConfig{}, err
	}
	interval, err := time.ParseDuration(cfg.CheckInterval)
	if err != nil {
		return runtimeConfig{}, err
	}
	window, err := time.ParseDuration(cfg.LossWindow)
	if err != nil {
		return runtimeConfig{}, err
	}
	timeout, err := time.ParseDuration(cfg.PingTimeout)
	if err != nil {
		return runtimeConfig{}, err
	}

	if interval <= 0 || window <= 0 || timeout <= 0 {
		return runtimeConfig{}, errors.New("check_interval, loss_window and ping_timeout must be positive")
	}
	maxLoss := cfg.MaxPacketLoss
	if maxLoss > 1 {
		maxLoss = maxLoss / 100
	}
	if maxLoss < 0 {
		return runtimeConfig{}, errors.New("max_packet_loss must be non-negative")
	}

	return runtimeConfig{
		listen:        cfg.Listen,
		serversDir:    cfg.ServersDir,
		checkTarget:   target,
		checkInterval: interval,
		lossWindow:    window,
		maxPacketLoss: maxLoss,
		pingTimeout:   timeout,
		primary:       cfg.Primary,
		backup:        cfg.Backup,
	}, nil
}

func loadServers(cfg runtimeConfig) (map[string]*server, error) {
	entries, err := os.ReadDir(cfg.serversDir)
	if err != nil {
		return nil, err
	}

	servers := map[string]*server{}
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || !(strings.HasSuffix(name, ".conf") || strings.HasSuffix(name, ".ini")) {
			continue
		}

		id := strings.TrimSuffix(name, filepath.Ext(name))
		configPath := filepath.Join(cfg.serversDir, name)
		conf, err := wireproxy.ParseConfig(configPath)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", configPath, err)
		}
		if len(conf.Device.Peers) == 0 || conf.Device.Peers[0].Endpoint == nil {
			return nil, fmt.Errorf("%s: first peer must have an Endpoint", configPath)
		}

		endpoint := *conf.Device.Peers[0].Endpoint
		host, _, err := net.SplitHostPort(endpoint)
		if err != nil {
			return nil, fmt.Errorf("%s: invalid endpoint %q: %w", configPath, endpoint, err)
		}
		if net.ParseIP(host) == nil {
			return nil, fmt.Errorf("%s: endpoint host must be an IP address", configPath)
		}

		conf.Device.CheckAlive = nil
		tun, err := wireproxy.StartWireguard(conf, device.LogLevelSilent)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", configPath, err)
		}

		servers[id] = &server{
			id:       id,
			address:  host,
			endpoint: endpoint,
			tun:      tun,
		}
	}

	if len(servers) == 0 {
		return nil, fmt.Errorf("no WireGuard config files found in %s", cfg.serversDir)
	}
	return servers, nil
}

func routes(cfg runtimeConfig, servers map[string]*server) http.Handler {
	mux := http.NewServeMux()

	liveness := func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		_, _ = w.Write([]byte("ok\n"))
	}
	mux.HandleFunc("/healthz", liveness)
	mux.HandleFunc("/z", liveness)

	mux.HandleFunc("/servers", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(status(cfg, servers))
	})

	mux.HandleFunc("/health/", func(w http.ResponseWriter, r *http.Request) {
		writeServerHealth(w, r, cfg, servers, strings.TrimPrefix(r.URL.Path, "/health/"))
	})

	mux.HandleFunc("/p", func(w http.ResponseWriter, r *http.Request) {
		writeServerHealth(w, r, cfg, servers, cfg.primary)
	})

	mux.HandleFunc("/b", func(w http.ResponseWriter, r *http.Request) {
		writeServerHealth(w, r, cfg, servers, cfg.backup)
	})

	return mux
}

func writeServerHealth(w http.ResponseWriter, r *http.Request, cfg runtimeConfig, servers map[string]*server, id string) {
	if r.Method != http.MethodGet {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	srv, ok := servers[id]
	if !ok {
		w.WriteHeader(http.StatusNotFound)
		return
	}
	loss, samples, healthy := srv.stats.health(cfg.maxPacketLoss)
	if !healthy {
		w.WriteHeader(http.StatusServiceUnavailable)
	}
	_, _ = fmt.Fprintf(w, "healthy=%t loss=%.4f samples=%d\n", healthy, loss, samples)
}

func status(cfg runtimeConfig, servers map[string]*server) statusResponse {
	states := make(map[string]serverState, len(servers))
	for id, srv := range servers {
		loss, samples, healthy := srv.stats.health(cfg.maxPacketLoss)
		states[id] = serverState{
			Address:       srv.address,
			Endpoint:      srv.endpoint,
			Healthy:       healthy,
			PacketLoss:    loss,
			SampleCount:   samples,
			MaxPacketLoss: cfg.maxPacketLoss,
		}
	}

	return statusResponse{
		Primary: cfg.primary,
		Backup:  cfg.backup,
		Servers: states,
	}
}

func (srv *server) runChecks(ctx context.Context, target netip.Addr, interval, timeout time.Duration) {
	srv.stats.add(srv.pingOnce(target, timeout))

	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			srv.stats.add(srv.pingOnce(target, timeout))
		}
	}
}

func (srv *server) pingOnce(target netip.Addr, timeout time.Duration) bool {
	socket, err := srv.tun.Tnet.Dial("ping", target.String())
	if err != nil {
		log.Printf("%s ping %s failed to open socket: %v", srv.id, target, err)
		return false
	}
	defer socket.Close()

	data := make([]byte, 16)
	if _, err := crand.Read(data); err != nil {
		log.Printf("%s ping %s failed to create payload: %v", srv.id, target, err)
		return false
	}

	requestPing := icmp.Echo{
		Seq:  mrand.Intn(1 << 16),
		Data: data,
	}

	var icmpBytes []byte
	if target.Is4() {
		icmpBytes, _ = (&icmp.Message{Type: ipv4.ICMPTypeEcho, Code: 0, Body: &requestPing}).Marshal(nil)
	} else if target.Is6() {
		icmpBytes, _ = (&icmp.Message{Type: ipv6.ICMPTypeEchoRequest, Code: 0, Body: &requestPing}).Marshal(nil)
	} else {
		log.Printf("%s ping %s invalid target address", srv.id, target)
		return false
	}

	_ = socket.SetReadDeadline(time.Now().Add(timeout))
	if _, err := socket.Write(icmpBytes); err != nil {
		log.Printf("%s ping %s write failed: %v", srv.id, target, err)
		return false
	}

	n, err := socket.Read(icmpBytes[:])
	if err != nil {
		log.Printf("%s ping %s read failed: %v", srv.id, target, err)
		return false
	}

	proto := 1
	if target.Is6() {
		proto = 58
	}
	replyPacket, err := icmp.ParseMessage(proto, icmpBytes[:n])
	if err != nil {
		log.Printf("%s ping %s parse failed: %v", srv.id, target, err)
		return false
	}

	if target.Is4() {
		replyPing, ok := replyPacket.Body.(*icmp.Echo)
		if !ok {
			log.Printf("%s ping %s invalid reply type: %s", srv.id, target, replyPacket.Type)
			return false
		}
		return bytes.Equal(replyPing.Data, requestPing.Data) && replyPing.Seq == requestPing.Seq
	}

	replyPing, ok := replyPacket.Body.(*icmp.RawBody)
	if !ok || len(replyPing.Data) < 4 {
		log.Printf("%s ping %s invalid IPv6 reply body", srv.id, target)
		return false
	}
	seq := binary.BigEndian.Uint16(replyPing.Data[2:4])
	return bytes.Equal(replyPing.Data[4:], requestPing.Data) && int(seq) == requestPing.Seq
}

func (s *rollingStats) add(ok bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	s.samples = append(s.samples, sample{at: now, ok: ok})
	s.prune(now)
}

func (s *rollingStats) health(maxLoss float64) (float64, int, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	s.prune(now)
	if len(s.samples) == 0 {
		return 1, 0, false
	}

	lost := 0
	for _, sample := range s.samples {
		if !sample.ok {
			lost++
		}
	}
	loss := float64(lost) / float64(len(s.samples))
	return loss, len(s.samples), loss <= maxLoss
}

func (s *rollingStats) prune(now time.Time) {
	cutoff := now.Add(-s.window)
	keepFrom := 0
	for keepFrom < len(s.samples) && s.samples[keepFrom].at.Before(cutoff) {
		keepFrom++
	}
	if keepFrom > 0 {
		copy(s.samples, s.samples[keepFrom:])
		s.samples = s.samples[:len(s.samples)-keepFrom]
	}
}

func must(err error) {
	if err != nil {
		log.Fatal(err)
	}
}
