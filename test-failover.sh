#!/bin/bash

set -e

echo "=== Blue/Green Failover Test ==="
echo ""

# Test baseline (Blue active)
echo "1. Testing baseline - Blue should be active..."
response=$(curl -s http://localhost:8080/version)
echo "Response: $response"
echo ""

# Check headers
pool=$(curl -s -I http://localhost:8080/version | grep -i "x-app-pool" | awk '{print $2}' | tr -d '\r')
release=$(curl -s -I http://localhost:8080/version | grep -i "x-release-id" | awk '{print $2}' | tr -d '\r')

echo "Current Pool: $pool"
echo "Release ID: $release"
echo ""

if [[ "$pool" != "blue" ]]; then
    echo "❌ ERROR: Expected Blue to be active, got: $pool"
    exit 1
fi

echo "✅ Blue is active!"
echo ""

# Induce chaos on Blue
echo "2. Inducing chaos on Blue (port 8081)..."
curl -X POST http://localhost:8081/chaos/start?mode=error
echo "Chaos started!"
echo ""

# Wait a moment
sleep 2

# Test failover to Green
echo "3. Testing failover - Green should now be active..."
for i in {1..10}; do
    response=$(curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:8080/version)
    http_code=$(echo "$response" | grep "HTTP_CODE" | cut -d':' -f2)
    
    pool=$(curl -s -I http://localhost:8080/version | grep -i "x-app-pool" | awk '{print $2}' | tr -d '\r')
    
    echo "Request $i: HTTP $http_code - Pool: $pool"
    
    if [[ "$http_code" != "200" ]]; then
        echo "❌ ERROR: Got non-200 response: $http_code"
        exit 1
    fi
done
echo ""

# Final check
pool=$(curl -s -I http://localhost:8080/version | grep -i "x-app-pool" | awk '{print $2}' | tr -d '\r')
if [[ "$pool" != "green" ]]; then
    echo "❌ ERROR: Expected Green to be active after Blue failure, got: $pool"
    exit 1
fi

echo "✅ Failover successful! Green is now active!"
echo ""

# Stop chaos
echo "4. Stopping chaos on Blue..."
curl -X POST http://localhost:8081/chaos/stop
echo ""
echo "✅ All tests passed!"