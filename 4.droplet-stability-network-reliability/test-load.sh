#!/bin/bash
# test-load.sh – Tes load balancing dan rate limiting

BASE_URL="${1:-http://localhost:8080}"
ENDPOINT="$BASE_URL/api/status"

echo "======================================================"
echo " Test: Load Balancing + Rate Limiting"
echo " Target: $ENDPOINT"
echo "======================================================"

# ─── 1. Cek distribusi load balancing (20 request sekuensial) ─────────────
echo ""
echo "[1] Distribusi Load Balancing – 20 request:"
echo "----------------------------------------------"
declare -A counts
for i in $(seq 1 20); do
    upstream=$(curl -s -o /dev/null -D - "$ENDPOINT" | grep -i "x-upstream-addr" | awk '{print $2}' | tr -d '\r')
    counts["$upstream"]=$(( ${counts["$upstream"]:-0} + 1 ))
    echo -n "."
done
echo ""
echo "Distribusi per backend:"
for key in "${!counts[@]}"; do
    echo "  $key : ${counts[$key]} request"
done

# ─── 2. Tes rate limiting (burst request simultan) ───────────────────────
echo ""
echo "[2] Tes Rate Limiting – 60 request paralel (burst):"
echo "------------------------------------------------------"
PASS=0; RATE_LIMITED=0; OTHER=0
for i in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT") &
done
wait

# Cara lebih bersih: gunakan subshell array
RESPONSES=()
for i in $(seq 1 60); do
    RESPONSES+=("$(curl -s -o /dev/null -w "%{http_code}" "$ENDPOINT")")
done

for code in "${RESPONSES[@]}"; do
    if   [ "$code" = "200" ]; then ((PASS++))
    elif [ "$code" = "429" ]; then ((RATE_LIMITED++))
    else ((OTHER++))
    fi
done

echo "  200 OK              : $PASS"
echo "  429 Rate Limited    : $RATE_LIMITED"
echo "  Lainnya             : $OTHER"

# ─── 3. Health check ─────────────────────────────────────────────────────
echo ""
echo "[3] Health Check:"
echo "-----------------"
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
body=$(curl -s "$BASE_URL/health")
echo "  HTTP Status : $code"
echo "  Response    : $body"

echo ""
echo "======================================================"
echo " Selesai."
echo "======================================================"
