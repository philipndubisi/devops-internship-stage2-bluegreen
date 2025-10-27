# Implementation Decisions

## Overview
This document explains the technical decisions made for the Blue/Green 
deployment with automatic failover using Nginx.

## Key Design Decisions

### 1. Nginx Upstream Configuration
**Decision**: Use Nginx's built-in `backup` directive for automatic 
failover

**Why**:
- Native Nginx feature - no external dependencies
- Automatic failover without manual intervention
- Simple and reliable
- Well-tested in production environments

**How it works**:
```nginx
upstream backend {
    server app_blue:3000 max_fails=1 fail_timeout=5s;
    server app_blue:3000 backup;
    server app_green:3000 backup;
}
```
- The active pool (determined by `ACTIVE_POOL`) is listed first without 
the `backup` directive
- Both Blue and Green are listed with `backup` - Nginx automatically picks 
the non-active one
- When the primary fails, Nginx immediately routes to the backup

### 2. Timeout Configuration
**Decision**: Aggressive timeouts for quick failure detection

**Configuration**:
- `proxy_connect_timeout: 2s` - Quick connection failure detection
- `proxy_read_timeout: 3s` - Quick response timeout
- `proxy_send_timeout: 2s` - Quick send timeout
- `max_fails: 1` - Mark as down after just one failure
- `fail_timeout: 5s` - Keep marked as down for 5 seconds before retry

**Why**:
- Task requirement: Zero failed client requests during failover
- Tight timeouts ensure Nginx detects failures quickly
- `max_fails=1` means immediate failover on first error
- Total potential delay < 10s (task requirement)

### 3. Retry Policy
**Decision**: Retry on errors, timeouts, and 5xx responses

**Configuration**:
```nginx
proxy_next_upstream error timeout http_500 http_502 http_503 http_504;
proxy_next_upstream_tries 2;
proxy_next_upstream_timeout 8s;
```

**Why**:
- `error`: Covers connection errors
- `timeout`: Covers response timeouts
- `http_5xx`: Covers application errors (like chaos mode)
- `tries=2`: Try primary, then backup (max 2 attempts)
- Total timeout of 8s ensures we stay under 10s requirement

### 4. Header Preservation
**Decision**: Use `proxy_pass_request_headers on` and don't strip headers

**Why**:
- Task explicitly requires `X-App-Pool` and `X-Release-Id` to be forwarded
- Application sets these headers - Nginx just passes them through
- No custom header manipulation needed

### 5. Environment-Based Configuration
**Decision**: Use `envsubst` in entrypoint.sh to template the Nginx config

**Why**:
- Task requires parameterization via `.env`
- `ACTIVE_POOL` determines which service is primary
- Simple shell script with `envsubst` replaces `${ACTIVE_POOL}` at runtime
- No complex templating engines needed

**Implementation**:
```bash
envsubst '${ACTIVE_POOL}' < nginx.conf.template > default.conf
```

### 6. Docker Networking
**Decision**: Use a custom bridge network (`app_network`)

**Why**:
- Services can communicate by container name (e.g., `app_blue:3000`)
- Isolated from other Docker networks
- Better security and organization

### 7. Port Mapping
**Decision**: 
- Nginx: 8080 → 80 (internal)
- Blue: 8081 → 3000 (internal)
- Green: 8082 → 3000 (internal)

**Why**:
- Task specifies these exact ports
- Allows direct access to Blue/Green for chaos injection
- Main traffic goes through Nginx on 8080

### 8. Health Checks
**Decision**: Docker healthchecks hitting `/healthz` endpoint

**Configuration**:
```yaml
healthcheck:
  test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", 
"http://localhost:3000/healthz"]
  interval: 5s
  timeout: 3s
  retries: 3
```

**Why**:
- Docker can monitor container health
- Useful for debugging
- Nginx also uses its own health detection via timeouts

## Alternative Approaches Considered

### ❌ Lua Scripting in Nginx
**Why not**: Adds complexity, requires OpenResty, not needed for this use 
case

### ❌ HAProxy
**Why not**: Task specifically requires Nginx

### ❌ Manual reload on failover
**Why not**: Task requires automatic failover without manual intervention

### ❌ Service Mesh (Istio, Linkerd)
**Why not**: Task forbids this, and it's overkill for this use case

## Testing Strategy

### Verification Points
1. **Baseline**: All traffic to Blue when healthy
2. **Chaos injection**: POST to `/chaos/start` on Blue
3. **Automatic failover**: Traffic switches to Green
4. **Zero errors**: All requests return 200 during and after failover
5. **Header validation**: `X-App-Pool` and `X-Release-Id` match expected 
values

### Why This Works
- Nginx detects failure within 2-5 seconds (tight timeouts)
- Retry policy ensures client request is retried to Green
- Client sees 200 response with Green's headers
- No client-facing errors

## Potential Improvements

If this were a production system:
1. **Observability**: Add Prometheus metrics, structured logging
2. **Gradual rollout**: Canary deployments instead of full switch
3. **Circuit breaker**: More sophisticated failure detection
4. **Multiple backends**: Load balancing across multiple instances
5. **SSL/TLS**: HTTPS termination at Nginx
6. **Rate limiting**: Protect backends from overload

## Conclusion

This implementation prioritizes:
- ✅ Simplicity (no complex tooling)
- ✅ Reliability (battle-tested Nginx features)
- ✅ Zero-downtime (automatic failover)
- ✅ Observability (headers preserved for debugging)
- ✅ Compliance (meets all task requirements)

The solution is production-ready for this specific use case and can be 
extended as needed.
