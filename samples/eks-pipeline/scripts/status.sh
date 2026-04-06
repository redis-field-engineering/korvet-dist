#!/bin/bash

# Usage: ./status.sh [component...]
# Components: logstash, korvet, redis, s3, eks
# If no component specified, shows all

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

run_with_timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

cleanup_port_forward() {
    local pid="$1"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
}

show_eks() {
    echo "=== EKS Status ==="
    echo ""
    echo "Cluster:"
    kubectl cluster-info 2>/dev/null | head -2 || echo "  Not connected"
    echo ""
    echo "Nodes:"
    kubectl get nodes -o wide 2>/dev/null | sed 's/^/  /' || echo "  Not available"
    echo ""
}

show_redis() {
    echo "=== Redis Enterprise Status ==="
    echo ""
    echo "Cluster:"
    kubectl get rec -n redis 2>/dev/null | sed 's/^/  /' || echo "  Not deployed"
    echo ""
    echo "Database:"
    kubectl get redb -n redis 2>/dev/null | sed 's/^/  /' || echo "  Not deployed"
    echo ""
    echo "Pods:"
    kubectl get pods -n redis -l app=redis-enterprise 2>/dev/null | sed 's/^/  /' || echo "  Not running"
    echo ""
    
    # Health check - get port dynamically from REDB status
    REDIS_PORT=$(kubectl get redb korvet-db -n redis -o jsonpath='{.status.internalEndpoints[0].port}' 2>/dev/null)
    REDIS_PASSWORD=$(kubectl get secret redb-korvet-db -n redis -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
    if [ -n "$REDIS_PASSWORD" ] && [ -n "$REDIS_PORT" ]; then
        kubectl port-forward svc/korvet-db -n redis 16379:${REDIS_PORT} >/dev/null 2>&1 &
        PF_PID=$!
        sleep 2
        PING=$(run_with_timeout 10 redis-cli -h localhost -p 16379 -a "$REDIS_PASSWORD" --no-auth-warning PING 2>/dev/null)
        cleanup_port_forward "$PF_PID"
        if [ "$PING" = "PONG" ]; then
            echo "Health: ✓ Connected (port $REDIS_PORT)"
        else
            echo "Health: ✗ Cannot connect to port $REDIS_PORT"
        fi
    fi
    echo ""
}

show_korvet() {
    echo "=== Korvet Status ==="
    echo ""
    echo "Deployment:"
    kubectl get deployment korvet -n korvet 2>/dev/null | sed 's/^/  /' || echo "  Not deployed"
    echo ""
    echo "Pods:"
    kubectl get pods -l app=korvet -n korvet 2>/dev/null | sed 's/^/  /' || echo "  Not running"
    echo ""
    echo "Service:"
    kubectl get svc korvet -n korvet 2>/dev/null | sed 's/^/  /' || echo "  Not available"
    echo ""

    # Health check
    kubectl port-forward deployment/korvet 8080:8080 -n korvet >/dev/null 2>&1 &
    PF_PID=$!
    sleep 2
    HEALTH=$(run_with_timeout 10 curl -s http://localhost:8080/actuator/health 2>/dev/null | jq -r '.status' 2>/dev/null)
    cleanup_port_forward "$PF_PID"

    if [ "$HEALTH" = "UP" ]; then
        echo "Health: ✓ UP"
    else
        echo "Health: ✗ $HEALTH"
    fi
    echo ""

    # Kafka CLI reachability
    echo "Kafka CLI:"
    kubectl get pod kafka-cli -n korvet 2>/dev/null | sed 's/^/  /' || echo "  Not available"
    echo ""
}

show_logstash() {
    echo "=== Logstash Status ==="
    echo ""
    echo "Deployment:"
    kubectl get deployment logstash -n korvet 2>/dev/null | sed 's/^/  /' || echo "  Not deployed"
    echo ""
    echo "Pods:"
    kubectl get pods -l app=logstash -n korvet 2>/dev/null | sed 's/^/  /' || echo "  Not running"
    echo ""

    # Health check
    kubectl port-forward deployment/logstash 9600:9600 -n korvet >/dev/null 2>&1 &
    PF_PID=$!
    sleep 2
    STATUS=$(run_with_timeout 10 curl -s http://localhost:9600/ 2>/dev/null | jq -r '.status' 2>/dev/null)
    cleanup_port_forward "$PF_PID"

    if [ "$STATUS" = "green" ]; then
        echo "Health: ✓ $STATUS"
    elif [ -n "$STATUS" ]; then
        echo "Health: ⚠ $STATUS"
    else
        echo "Health: ✗ Not responding"
    fi
    echo ""
}

show_s3() {
    echo "=== S3 Status ==="
    echo ""
    
    # Get bucket name
    if [ -n "$S3_BUCKET" ]; then
        : # Use existing
    elif [ -f "$ROOT_DIR/terraform/terraform.tfstate" ]; then
        cd "$ROOT_DIR/terraform"
        S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)
    else
        S3_BUCKET=$(aws s3 ls 2>/dev/null | grep korvet-poc | awk '{print $3}' | head -1)
    fi
    
    if [ -z "$S3_BUCKET" ]; then
        echo "Bucket: Not found"
        echo ""
        return
    fi
    
    echo "Bucket: $S3_BUCKET"
    
    # Check if bucket exists and is accessible
    if run_with_timeout 15 aws s3 ls "s3://$S3_BUCKET" >/dev/null 2>&1; then
        echo "Access: ✓ Accessible"
    else
        echo "Access: ✗ Cannot access"
    fi
    
    # Get object count
    COUNT=$(run_with_timeout 20 sh -c "aws s3 ls 's3://$S3_BUCKET/' --recursive 2>/dev/null | wc -l | tr -d ' '")
    echo "Objects: $COUNT"
    
    # Last modified (sort by time to get actual latest)
    LAST=$(run_with_timeout 20 sh -c "aws s3 ls 's3://$S3_BUCKET/' --recursive 2>/dev/null | sort -k1,2 | tail -1 | awk '{print \$1 \" \" \$2}'")
    if [ -n "$LAST" ]; then
        echo "Last write: $LAST"
    fi
    echo ""
}

# Parse arguments
COMPONENTS="$@"

# If no arguments, show all
if [ -z "$COMPONENTS" ]; then
    COMPONENTS="eks redis korvet logstash s3"
fi

# Show requested components
for component in $COMPONENTS; do
    case "$component" in
        eks)
            show_eks
            ;;
        redis)
            show_redis
            ;;
        korvet)
            show_korvet
            ;;
        logstash)
            show_logstash
            ;;
        s3)
            show_s3
            ;;
        *)
            echo "Unknown component: $component"
            echo "Available: eks, redis, korvet, logstash, s3"
            exit 1
            ;;
    esac
done
