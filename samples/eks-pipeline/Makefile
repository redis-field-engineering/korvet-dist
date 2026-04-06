.PHONY: deploy verify check-s3 destroy logs-korvet logs-logstash metrics status topic consume help

# Deploy the full pipeline
deploy:
	./scripts/deploy.sh

# Verify pipeline status
verify:
	./scripts/verify.sh

# Check S3 bucket contents
check-s3:
	./scripts/check-s3.sh

# Destroy all resources
destroy:
	./scripts/destroy.sh

# View Korvet logs
logs-korvet:
	kubectl logs -l app=korvet -n korvet -f

# View Logstash logs
logs-logstash:
	kubectl logs -l app=logstash -n korvet -f

# =============================================================================
# Metrics - usage: make metrics [COMPONENT=<component>]
# Examples:
#   make metrics                      - Show all metrics
#   make metrics COMPONENT=logstash   - Show Logstash metrics only
#   make metrics COMPONENT="korvet redis" - Show Korvet and Redis metrics
# Components: logstash, korvet, redis, s3
# =============================================================================
COMPONENT ?=
metrics:
	@./scripts/metrics.sh $(COMPONENT)

# =============================================================================
# Status - usage: make status [COMPONENT=<component>]
# Examples:
#   make status                       - Show all component status
#   make status COMPONENT=korvet      - Show Korvet status only
#   make status COMPONENT="redis s3"  - Show Redis and S3 status
# Components: eks, redis, korvet, logstash, s3
# =============================================================================
status:
	@./scripts/status.sh $(COMPONENT)

# =============================================================================
# Topic Management
# =============================================================================

# Create/recreate topic with tiered storage settings
# Usage: make topic [PARTITIONS=4] [BUCKET_DURATION_MS=300000] [RETENTION_MS=1800000]
PARTITIONS ?= 4
BUCKET_DURATION_MS ?= 300000
RETENTION_MS ?= 1800000
topic:
	@echo "Creating topic 'logs' with $(PARTITIONS) partitions..."
	@kubectl exec kafka-cli -n korvet -- kafka-topics \
		--bootstrap-server korvet.korvet.svc.cluster.local:9092 \
		--delete --topic logs 2>/dev/null || true
	@sleep 2
	@kubectl exec kafka-cli -n korvet -- kafka-topics \
		--bootstrap-server korvet.korvet.svc.cluster.local:9092 \
		--create --topic logs --partitions $(PARTITIONS)
	@echo "Configuring tiered storage: bucket=$(BUCKET_DURATION_MS)ms, retention=$(RETENTION_MS)ms"
	@kubectl exec kafka-cli -n korvet -- kafka-configs \
		--bootstrap-server korvet.korvet.svc.cluster.local:9092 \
		--entity-type topics --entity-name logs \
		--alter --add-config 'bucket.duration.ms=$(BUCKET_DURATION_MS),retention.ms=$(RETENTION_MS),remote.storage.enable=true'
	@echo "Topic 'logs' created successfully"

# =============================================================================
# Other targets
# =============================================================================

# Consume messages from topic
consume:
	kubectl exec kafka-cli -n korvet -- kafka-console-consumer \
		--bootstrap-server korvet.korvet.svc.cluster.local:9092 \
		--topic logs --from-beginning --max-messages 10

# Check Redis keys
redis-keys:
	@REDIS_PASSWORD=$$(kubectl get secret redb-korvet-db -n redis -o jsonpath='{.data.password}' | base64 -d) && \
	kubectl exec rec-0 -n redis -- redis-cli -h korvet-db -p 11030 -a "$$REDIS_PASSWORD" --no-auth-warning KEYS 'korvet:stream:logs:*'

# Get all pods
pods:
	kubectl get pods -n redis
	kubectl get pods -n korvet

# Port forward to Korvet actuator
actuator:
	kubectl port-forward deployment/korvet 8080:8080 -n korvet

help:
	@echo "Available targets:"
	@echo ""
	@echo "  Deployment:"
	@echo "    deploy        - Deploy the full pipeline"
	@echo "    destroy       - Destroy all resources"
	@echo ""
	@echo "  Status & Metrics:"
	@echo "    make status                       - Show status of all components"
	@echo "    make status COMPONENT=korvet      - Show Korvet status"
	@echo "    make metrics                      - Show metrics for all components"
	@echo "    make metrics COMPONENT=logstash   - Show Logstash metrics"
	@echo ""
	@echo "  Components: eks, redis, korvet, logstash, s3"
	@echo ""
	@echo "  Topic Management:"
	@echo "    make topic                              - Recreate topic with defaults"
	@echo "    make topic BUCKET_DURATION_MS=60000     - 1 minute buckets"
	@echo "    make topic PARTITIONS=8 RETENTION_MS=3600000  - 8 partitions, 1hr retention"
	@echo ""
	@echo "  Logs:"
	@echo "    logs-korvet   - Follow Korvet logs"
	@echo "    logs-logstash - Follow Logstash logs"
	@echo ""
	@echo "  Data:"
	@echo "    check-s3      - Check S3 bucket contents"
	@echo "    consume       - Consume messages from topic"
	@echo "    redis-keys    - List Redis stream keys"
	@echo ""
	@echo "  Other:"
	@echo "    pods          - List all pods"
	@echo "    actuator      - Port forward to Korvet actuator"
