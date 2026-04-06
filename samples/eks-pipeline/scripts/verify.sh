#!/bin/bash
set -e

echo "=== EKS Pipeline Verification ==="
echo ""

echo ">>> Nodes:"
kubectl get nodes -o wide
echo ""

echo ">>> Redis Enterprise:"
kubectl get rec,redb -n redis
echo ""

echo ">>> Pods:"
kubectl get pods -n korvet
echo ""

echo ">>> Topic Info:"
kubectl exec kafka-cli -n korvet -- kafka-topics \
  --bootstrap-server korvet.korvet.svc.cluster.local:9092 \
  --describe --topic logs 2>/dev/null || echo "kafka-cli not ready"
echo ""

echo ">>> Message Offsets:"
kubectl exec kafka-cli -n korvet -- kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list korvet.korvet.svc.cluster.local:9092 --topic logs --time -1 2>/dev/null || true
echo ""

echo ">>> Sample Messages:"
kubectl exec kafka-cli -n korvet -- kafka-console-consumer \
  --bootstrap-server korvet.korvet.svc.cluster.local:9092 \
  --topic logs --from-beginning --max-messages 3 2>/dev/null || true
echo ""

echo ">>> Logstash Metrics:"
kubectl port-forward deployment/logstash 9600:9600 -n korvet &
PF_PID=$!
sleep 3
curl -s http://localhost:9600/_node/stats/pipelines 2>/dev/null | jq '.pipelines.main.events' || true
kill $PF_PID 2>/dev/null || true
echo ""

echo "=== Verification Complete ==="
