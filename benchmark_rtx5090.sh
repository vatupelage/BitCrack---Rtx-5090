#!/bin/bash

# RTX 5090 Optimization Benchmark Script
# Tests various -b, -t, -p combinations to find maximum performance

BINARY="./bin/cuBitCrack"
ADDRESS_FILE="test_address.txt"
KEYSPACE="100000000000:1fffffffffff"
TEST_DURATION=15  # seconds per test
RESULTS_FILE="benchmark_results.csv"

echo "RTX 5090 Performance Optimization Test" | tee $RESULTS_FILE
echo "Started: $(date)" | tee -a $RESULTS_FILE
echo "" | tee -a $RESULTS_FILE
echo "Blocks,Threads,Points,Throughput_MKeys,Kernel_ms,Total_Keys,Status" | tee -a $RESULTS_FILE

run_test() {
    local blocks=$1
    local threads=$2
    local points=$3

    echo ""
    echo "========================================"
    echo "Testing: -b $blocks -t $threads -p $points"
    echo "========================================"

    # Run BitCrack in background
    timeout ${TEST_DURATION}s $BINARY -d 0 -b $blocks -t $threads -p $points \
        --keyspace $KEYSPACE -i $ADDRESS_FILE --compression compressed \
        > /tmp/bitcrack_output.txt 2>&1

    # Extract throughput from output (last line with MKey/s)
    local throughput=$(grep -oP '\d+\.\d+(?= MKey/s)' /tmp/bitcrack_output.txt | tail -1)

    # Extract kernel time from stderr
    local kernel_ms=$(grep "Kernel profiling" /tmp/bitcrack_output.txt | tail -1 | grep -oP 'avg \K\d+\.\d+(?= ms)')

    # Extract total keys tested
    local total_keys=$(grep -oP '\(\K\d+(?= total\))' /tmp/bitcrack_output.txt | tail -1)

    if [ -z "$throughput" ]; then
        throughput="FAILED"
        kernel_ms="N/A"
        total_keys="0"
        status="ERROR"
    else
        status="OK"
        echo "Result: $throughput MKey/s (kernel: ${kernel_ms}ms)"
    fi

    # Log results
    echo "$blocks,$threads,$points,$throughput,$kernel_ms,$total_keys,$status" | tee -a $RESULTS_FILE

    # Small delay between tests
    sleep 2
}

echo ""
echo "Phase 1: Testing BLOCKS (fixing t=512, p=1024)"
echo "=============================================="
for blocks in 64 80 96 112 128 144 160 176 192; do
    run_test $blocks 512 1024
done

# Find best blocks from Phase 1
echo ""
echo "Analyzing Phase 1 results..."
best_blocks=$(grep "OK" $RESULTS_FILE | grep ",512,1024," | sort -t',' -k4 -rn | head -1 | cut -d',' -f1)
echo "Best blocks from Phase 1: $best_blocks"

echo ""
echo "Phase 2: Testing THREADS (fixing b=$best_blocks, p=1024)"
echo "=========================================================="
for threads in 256 384 448 512 576 640 768; do
    run_test $best_blocks $threads 1024
done

# Find best threads from Phase 2
best_threads=$(grep "OK" $RESULTS_FILE | grep "^${best_blocks}," | grep ",1024," | sort -t',' -k4 -rn | head -1 | cut -d',' -f2)
echo "Best threads from Phase 2: $best_threads"

echo ""
echo "Phase 3: Testing POINTS (fixing b=$best_blocks, t=$best_threads)"
echo "================================================================="
for points in 256 384 512 640 768 896 1024 1152 1280 1536; do
    run_test $best_blocks $best_threads $points
done

# Find absolute best configuration
echo ""
echo "=============================================="
echo "FINAL RESULTS - Top 10 Configurations"
echo "=============================================="
grep "OK" $RESULTS_FILE | sort -t',' -k4 -rn | head -10 | \
    awk -F',' '{printf "%-3s blocks, %-3s threads, %-4s points = %8s MKey/s (kernel: %6sms)\n", $1, $2, $3, $4, $5}'

echo ""
echo "OPTIMAL CONFIGURATION:"
best_config=$(grep "OK" $RESULTS_FILE | sort -t',' -k4 -rn | head -1)
best_b=$(echo $best_config | cut -d',' -f1)
best_t=$(echo $best_config | cut -d',' -f2)
best_p=$(echo $best_config | cut -d',' -f3)
best_speed=$(echo $best_config | cut -d',' -f4)
best_kernel=$(echo $best_config | cut -d',' -f5)

echo ""
echo "  -b $best_b -t $best_t -p $best_p"
echo ""
echo "  Throughput: $best_speed MKey/s"
echo "  Kernel Time: ${best_kernel}ms"
echo ""
echo "Command to use:"
echo "./bin/cuBitCrack -d 0 -b $best_b -t $best_t -p $best_p --keyspace <START>:<END> -i addresses.txt"
echo ""
echo "Benchmark completed: $(date)"
