#!/usr/bin/env bash
# apply-patches.sh — Apply Risos AI customizations to whisperx-risos repo
#
# Jalanin script ini dari root folder cloned whisperx-risos repo:
#   cd whisperx-risos
#   chmod +x apply-patches.sh
#   ./apply-patches.sh
#
# Patches yang diterapkan:
#   1. src/rp_handler.py — hapus token leak log + force-prefix block (security)
#   2. src/predict.py    — INITIAL_PROMPT default ke konteks akademik Indonesia
#   3. Dockerfile        — tambah OCI labels (brand metadata)
#   4. Dockerfile        — hapus apt-get upgrade + tambah defensive statoverride cleanup

set -euo pipefail

# Sanity check — pastikan kita di root repo
if [ ! -f "Dockerfile" ] || [ ! -f "src/predict.py" ] || [ ! -f "src/rp_handler.py" ]; then
    echo "ERROR: Run this script from the ROOT of cloned whisperx-risos repo"
    echo "Expected files: Dockerfile, src/predict.py, src/rp_handler.py"
    exit 1
fi

echo "=================================="
echo "Patch 1/4: src/rp_handler.py (security)"
echo "=================================="
python3 <<'PYEOF'
with open("src/rp_handler.py") as f:
    content = f.read()

# Remove force-prefix block (3 lines + trailing blank)
old1 = '''if not hf_token.startswith("hf_"):
    print(f"Token malformed or missing 'hf_' prefix. Forcing correction...")
    hf_token = "h" + hf_token  # Force adding the 'h' (temporary fix)

'''

# Remove token leak log
old2 = '''        logger.debug(f"HF_TOKEN Loaded: {repr(hf_token[:10])}...")  # Show only start of token for security
'''

changed = []
if old1 in content:
    content = content.replace(old1, "")
    changed.append("force-prefix block removed")

if old2 in content:
    content = content.replace(old2, "")
    changed.append("token leak log removed")

if changed:
    with open("src/rp_handler.py", "w") as f:
        f.write(content)
    print("  OK:", ", ".join(changed))
else:
    print("  WARN: No patterns found — may already be patched")
PYEOF

echo ""
echo "=================================="
echo "Patch 2/4: src/predict.py (INITIAL_PROMPT akademik ID)"
echo "=================================="
python3 <<'PYEOF'
with open("src/predict.py") as f:
    content = f.read()

old = '''            initial_prompt: str = Input(
                description="Optional text to provide as a prompt for the first window",
                default=None),'''

new = '''            initial_prompt: str = Input(
                description="Optional prompt untuk steering Whisper. Default: konteks akademik Indonesia (Risos AI).",
                default="Berikut adalah rekaman wawancara penelitian akademik dalam Bahasa Indonesia. Pembicara menggunakan istilah ilmiah, metodologi penelitian, hipotesis, variabel, populasi, sampel, kuesioner, analisis data, kerangka konseptual, dan terminologi akademik formal. Transkripsi dalam Bahasa Indonesia baku dengan tanda baca tepat."),'''

if old in content:
    content = content.replace(old, new)
    with open("src/predict.py", "w") as f:
        f.write(content)
    print("  OK: INITIAL_PROMPT default set to Indonesian academic context")
else:
    print("  WARN: Pattern not found — may already be patched")
PYEOF

echo ""
echo "=================================="
echo "Patch 3/4: Dockerfile (OCI labels)"
echo "=================================="
python3 <<'PYEOF'
with open("Dockerfile") as f:
    lines = f.readlines()

labels = '''LABEL org.opencontainers.image.title="WhisperX Risos AI"
LABEL org.opencontainers.image.description="WhisperX serverless worker untuk transkripsi akademik Bahasa Indonesia. Fork of hapnan/whisperx-worker."
LABEL org.opencontainers.image.vendor="PT Riset Sinergi Sosial"
LABEL org.opencontainers.image.source="https://github.com/rio9921/whisperx-risos"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.risos.ai.component="audio-transcription"
LABEL org.risos.ai.context="academic-indonesian"

'''

# Idempotent check
if "org.risos.ai.component" in "".join(lines):
    print("  WARN: Labels already present, skipping")
else:
    new_lines = [lines[0], labels] + lines[1:]
    with open("Dockerfile", "w") as f:
        f.writelines(new_lines)
    print("  OK: OCI labels added after FROM line")
PYEOF

echo ""
echo "=================================="
echo "Patch 4/4: Dockerfile (skip apt upgrade + statoverride cleanup)"
echo "=================================="
python3 <<'PYEOF'
with open("Dockerfile") as f:
    content = f.read()

changed = []

# Fix A: Hapus apt-get upgrade (penyebab messagebus error di banyak base images)
old1 = "    apt-get upgrade -y && \\\n"
if old1 in content:
    content = content.replace(old1, "")
    changed.append("apt-get upgrade removed")

# Fix B: Defensive cleanup statoverride sebelum apt commands
old2 = "RUN rm -f /etc/apt/sources.list.d/*.list\n"
new2 = """RUN rm -f /etc/apt/sources.list.d/*.list && \\
    rm -f /var/lib/dpkg/statoverride && \\
    touch /var/lib/dpkg/statoverride
"""

if old2 in content:
    content = content.replace(old2, new2)
    changed.append("statoverride cleanup added")

if changed:
    with open("Dockerfile", "w") as f:
        f.write(content)
    print("  OK:", ", ".join(changed))
else:
    print("  WARN: No patterns matched — may already be patched")
PYEOF

echo ""
echo "=================================="
echo "DONE! Verify dengan:"
echo "=================================="
echo "  git diff --stat"
echo "  git diff Dockerfile"
echo "  git diff src/predict.py"
echo "  git diff src/rp_handler.py"
echo ""
echo "Expected: 3 files changed, ~14 insertions(+), ~7 deletions(-)"
