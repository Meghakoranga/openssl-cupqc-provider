#!/usr/bin/env bash
set -euo pipefail
export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH
/usr/local/bin/openssl genpkey -algorithm ML-KEM-768 -provider cupqcprov -provider default -out /tmp/ignore.pem 2> logs/run-debug.log
