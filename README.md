# openssl-cupqc-provider

OpenSSL 3 provider that hooks NVIDIA cuPQC into ML‑KEM‑768. Goal: GPU keygen and clean KEYMGMT/KEM wiring so standard OpenSSL commands work.

## Requirements

- Ubuntu 22.04+
- OpenSSL 3.5.x (installed under /usr/local or adjust)
- CUDA Toolkit 12.6 + matching NVIDIA driver
- cuPQC shared library on the system (libcupqc.so)

Environment example:
- export CUDA_HOME=/usr/local/cuda-12.6
- export LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/cuda-12.6/lib64:$LD_LIBRARY_PATH

## Build

- mkdir -p build && cd build
- cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo -DOPENSSL_ROOT_DIR=/usr/local ..
- make -j

If OpenSSL/cuPQC are in custom locations, point CMake to them (OPENSSL_ROOT_DIR, CUPQC_ROOT or a FindcuPQC.cmake).

## Run (repro)

- scripts/run.sh

That sets LD_LIBRARY_PATH and runs:
- /usr/local/bin/openssl genpkey -algorithm ML-KEM-768 -provider cupqcprov -provider default -out /tmp/ignore.pem 2> logs/run-debug.log

Expect provider debug lines and artifacts written under artifacts/.

## Layout

- providers/cupqcprov/ — provider sources (KEYMGMT/KEM)
- cupqc_wrap.* — thin cuPQC wrapper
- CMakeLists.txt, cmake/ — build glue
- scripts/ — run.sh
- logs/ — run-debug.log, openssl-version.txt, nvidia-smi.txt, uname.txt
- artifacts/ — kem_pub.raw, ek_from_dk.raw, dk_exported.raw

## Current status

- Provider loads and calls cuPQC keygen on GPU (log shows “Keygen OK”).[1]
- Private/public buffers allocated as: dk 2400 bytes, ek 1184 bytes.[1]
- After keygen/import, the provider copies ek from dk and exports both.[1]
- Debug artifacts confirm:
  - kem_pub.raw (exported public) == ek_from_dk.raw (slice from dk). Byte‑for‑byte equal.[1]
- Still failing at OpenSSL import step with:
  - “explicit ML‑KEM‑768 public key does not match private.”[1]

What this means
- OpenSSL parses the 2400‑byte private octets into its own dk view and derives an ek′. Although our PUB matches our dk slice, OpenSSL’s ek′ differs, so it rejects. Likely cause: our dk layout isn’t the layout OpenSSL expects for ML‑KEM‑768. Hexdumps show dk tail is zeroed while a common layout puts ek at the tail (offset 1216).[2][1]

## What to fix

- Re‑encode dk before export so ek sits exactly where OpenSSL’s parser expects it (commonly the tail for ML‑KEM‑768). Then set PUB from those same bytes. That should make ek′ (OpenSSL) == PUB (ours).[2][1]
- Temporary diagnostic: export PRIV only (omit PUB) to check if OpenSSL accepts the dk format when it derives ek internally. Useful to isolate encoding issues, not a final solution.[1]

## Quick checks

- diff -u <(xxd -p -c 1184 artifacts/kem_pub.raw) <(xxd -p -c 1184 artifacts/ek_from_dk.raw)  # should be empty
- hexdump -C artifacts/dk_exported.raw | tail -n 16  # see if ek is actually at dk tail
- diff -u <(xxd -p -c 1184 artifacts/kem_pub.raw) <(tail -c 1184 artifacts/dk_exported.raw | xxd -p -c 1184)

If the last diff is empty and genpkey still fails, revisit dk field order (s, H(ek), z, ek) to match what OpenSSL expects.[2][1]

## Repro info

- /usr/local/bin/openssl version -a > logs/openssl-version.txt
- nvidia-smi > logs/nvidia-smi.txt
- uname -a > logs/uname.txt

## Notes

- Don’t commit CUDA or cuPQC binaries. Document install paths and library names. If you ship a FindcuPQC.cmake, fail clearly when libcupqc.so is missing.
- Long‑term: mirror liboqs provider’s pattern (single key object; import/export are thin wrappers) to avoid format drift.

