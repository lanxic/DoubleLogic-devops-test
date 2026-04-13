#!/bin/bash
# ============================================================
#  Retry Storm Simulator
#
#  Scenario nyata yang disimulasikan:
#    Buggy client melakukan infinite retry ke endpoint yang error
#    → CPU spike 100% → valet check-in froze → pelanggan komplain
#
#  Script ini memvalidasi bahwa Grafana alert fire SEBELUM
#  pelanggan sempat mengeluh.
#
#  Usage:
#    ./test-load.sh              # HTTP retry storm only
#    CPU_STRESS=1 ./test-load.sh # + CPU stress (test CPU alert)
#
#  Alert yang diharapkan fire dalam ~2 menit:
#    1. [HTTP]  Non-2xx Response Detected       (30 detik)
#    2. [API]   Error Rate > 5% selama 2 menit  (2 menit)
#    3. [CPU]   Usage > 85%                     (2 menit, jika CPU_STRESS=1)
# ============================================================

BASE_URL="${BASE_URL:-http://localhost:8080}"
CPU_STRESS="${CPU_STRESS:-0}"

declare -a PIDS=()

cleanup() {
    echo ""
    echo "[INFO] Menghentikan semua proses simulasi..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait "${PIDS[@]}" 2>/dev/null || true
    echo "[DONE] Simulasi dihentikan. Cek Mailpit untuk melihat email alert yang sudah masuk."
    echo "       http://localhost:8025"
}
trap cleanup INT TERM EXIT

# ---- Header ----
echo "========================================================="
echo "   VALET SERVICE - Retry Storm Load Simulation"
echo "========================================================="
echo ""
echo "   Prometheus : http://localhost:9090"
echo "   Grafana    : http://localhost:3000  [admin / admin]"
echo "   Mailpit    : http://localhost:8025  [cek email alert]"
echo ""
echo "   Alert yang akan fire:"
echo "   - [30s]  HTTP Non-2xx Response Detected"
echo "   - [2m]   API Error Rate > 5%  ← Custom retry storm alert"
if [[ "$CPU_STRESS" == "1" ]]; then
    echo "   - [2m]   CPU Usage > 85%"
fi
echo "---------------------------------------------------------"
echo ""

# Pastikan mock-api bisa diakses
echo "[CHECK] Memeriksa koneksi ke mock-api..."
if ! curl -sf -o /dev/null --max-time 5 "${BASE_URL}/status/200" 2>/dev/null; then
    echo "[ERROR] Tidak bisa terhubung ke ${BASE_URL}"
    echo "        Pastikan docker compose sudah berjalan:"
    echo "        docker compose up -d"
    exit 1
fi
echo "[OK]    mock-api siap di ${BASE_URL}"
echo ""

# ---- 1. Normal traffic (simulasi user legitimate) ----
(
    while true; do
        curl -sf -o /dev/null --max-time 2 "${BASE_URL}/status/200" 2>/dev/null || true
        sleep 1
    done
) &
PIDS+=($!)
echo "[1/3] Normal traffic    → GET /status/200  (1 req/sec)"

# ---- 2. Retry storm: buggy client tanpa delay ----
# Simulasi client yang tidak punya exponential backoff
# langsung retry terus-menerus ke endpoint yang error
(
    while true; do
        curl -sf -o /dev/null --max-time 2 "${BASE_URL}/status/500" 2>/dev/null || true
        curl -sf -o /dev/null --max-time 2 "${BASE_URL}/status/503" 2>/dev/null || true
        curl -sf -o /dev/null --max-time 2 "${BASE_URL}/status/429" 2>/dev/null || true
    done
) &
PIDS+=($!)
echo "[2/3] Retry storm       → GET /status/500|503|429  (tanpa delay = infinite retry)"

# ---- 3. CPU Stress (opsional) ----
if [[ "$CPU_STRESS" == "1" ]]; then
    CORES=$(nproc 2>/dev/null || echo 1)
    echo "[3/3] CPU stress        → $CORES core(s) tersaturasi"
    for _ in $(seq 1 "$CORES"); do
        (yes > /dev/null 2>&1) &
        PIDS+=($!)
    done
else
    echo "[3/3] CPU stress        → SKIP (gunakan: CPU_STRESS=1 ./test-load.sh)"
fi

echo ""
echo "Simulasi aktif... tekan Ctrl+C untuk berhenti."
echo "---------------------------------------------------------"
echo ""

# ---- Live progress ----
START=$(date +%s)
ALERT_NOTIFIED=false

while true; do
    sleep 10

    NOW=$(date +%s)
    ELAPSED=$(( NOW - START ))
    MINS=$(( ELAPSED / 60 ))
    SECS=$(( ELAPSED % 60 ))

    # Status pesan berdasarkan waktu
    if (( ELAPSED < 30 )); then
        STATUS="Menunggu evaluasi alert pertama..."
    elif (( ELAPSED < 120 )); then
        REMAINING=$(( 120 - ELAPSED ))
        STATUS="Alert 'API Error Rate' pending... fire dalam ~${REMAINING}s"
    else
        STATUS=">>> CEK MAILPIT: http://localhost:8025 untuk email alert <<<"
        if [[ "$ALERT_NOTIFIED" == "false" ]]; then
            echo ""
            echo "  ╔══════════════════════════════════════════════════╗"
            echo "  ║  2 MENIT TERCAPAI - Alert seharusnya sudah fire  ║"
            echo "  ║  Buka: http://localhost:8025 untuk lihat email   ║"
            echo "  ║  Atau:  http://localhost:3000/alerting/list      ║"
            echo "  ╚══════════════════════════════════════════════════╝"
            echo ""
            ALERT_NOTIFIED=true
        fi
    fi

    printf "  [%02d:%02d] %s\n" "$MINS" "$SECS" "$STATUS"
done
