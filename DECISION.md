# Design Decisions

## Architecture Choices

### 1. Nginx Upstream Configuration
I chose to use Nginx's built-in upstream module with the `backup` directive because:
- Simple and battle-tested solution
- No external dependencies
- Automatic failover without manual intervention
- Minimal configuration

### 2. Failover Strategy
- **Primary/Backup model**: Blue is primary, Green is backup
- **Fast failure detection**: `max_fails=1` and `fail_timeout=5s`
- **Automatic retry**: `proxy_next_upstream` handles retries within the same request
- **Tight timeouts**: 2-3 second timeouts ensure quick failure detection

### 3. Health Checks
Used Docker's built-in health checks instead of Nginx health checks because:
- Simpler setup for beginners
- No additional Nginx modules required
- Integrated with Docker Compose status

### 4. Environment Variables
All configuration is externalized through `.env` to meet the requirement for full parameterization without code changes.

## Trade-offs

### What I Prioritized
- **Simplicity**: Minimal moving parts
- **Reliability**: Proven Nginx features
- **Zero downtime**: Client requests never fail during failover

### What I Avoided
- Complex health check plugins
- Custom scripts for failover detection
- Load balancing (not required for primary/backup)

## Testing Strategy
The test script verifies:
1. Blue is active by default
2. Chaos mode triggers failover
3. All requests return 200 during failover
4. Green becomes active after Blue fails

## Potential Improvements
For production use, consider:
- Prometheus metrics for monitoring
- Automated rollback mechanisms
- Canary deployments
- External health check endpoints