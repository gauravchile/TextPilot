# ---------- Base Builder Stage ----------
FROM python:3.11-slim AS builder

WORKDIR /builder

# Install system dependencies for wheel compilation
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    build-essential gcc curl && \
    rm -rf /var/lib/apt/lists/*

# ---------- Speed Optimization ----------
# Preload pip cache and configure fast mirrors
ENV PIP_EXTRA_INDEX_URL=https://download.pytorch.org/whl/cpu \
    PIP_INDEX_URL=https://pypi.org/simple \
    PIP_TIMEOUT=200 \
    PIP_RETRIES=10 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

COPY app/requirements.txt .

RUN pip install --upgrade pip && \
    pip wheel --no-cache-dir --no-deps -r requirements.txt -w /wheels


# ---------- Runtime Stage ----------
FROM python:3.11-slim AS runtime

ARG FAST_MODE=false
ARG TORCH_DEVICE=cpu
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TORCH_DEVICE=${TORCH_DEVICE} \
    MODEL_CACHE_DIR=/models/.cache/huggingface \
    PIP_DEFAULT_TIMEOUT=200 \
    PIP_RETRIES=10 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_INDEX_URL=https://pypi.org/simple \
    PIP_EXTRA_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

WORKDIR /app

# Copy prebuilt wheels from builder
COPY --from=builder /wheels /wheels

# Install wheels with retries + network timeout
RUN pip install --retries 10 --timeout 200 --no-cache-dir /wheels/* && rm -rf /wheels

# Copy source code
COPY app ./app

# Create model cache dir
RUN mkdir -p $MODEL_CACHE_DIR

# Optional: Preload Hugging Face model (disabled in FAST_MODE)
RUN if [ "$FAST_MODE" != "true" ]; then \
        echo "⏳ Preloading sentiment-analysis model..."; \
        python -c "from transformers import pipeline; \
        p = pipeline('sentiment-analysis', model='distilbert-base-uncased-finetuned-sst-2-english'); \
        _ = p('TextPilot warmup'); \
        print('✅ Model cached successfully.')" ; \
    else \
        echo '⚡ FAST_MODE enabled — skipping model preload.' ; \
    fi

# Expose API port
EXPOSE 8000

# Healthcheck for Docker
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -fs http://localhost:8000/health || exit 1

# Run the Flask app via Gunicorn
CMD ["gunicorn", "-w", "2", "-b", "0.0.0.0:8000", "app.wsgi:app"]

