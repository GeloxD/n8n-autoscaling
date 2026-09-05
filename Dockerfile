# Multi-stage build to add tools to n8n image
ARG N8N_VERSION=2.36.8
FROM alpine:3.23 AS builder
RUN apk add --no-cache ffmpeg git openssh-client graphicsmagick jq curl
FROM n8nio/n8n:${N8N_VERSION}
USER root
COPY --from=builder /usr/bin/ffmpeg /usr/bin/ffmpeg
COPY --from=builder /usr/bin/ffprobe /usr/bin/ffprobe
COPY --from=builder /usr/bin/git /usr/bin/git
COPY --from=builder /usr/bin/gm /usr/bin/gm
COPY --from=builder /usr/bin/jq /usr/bin/jq
COPY --from=builder /usr/bin/curl /usr/bin/curl
COPY --from=builder /usr/lib/libav*.so* /usr/lib/
COPY --from=builder /usr/lib/libsw*.so* /usr/lib/
COPY --from=builder /usr/lib/libcurl*.so* /usr/lib/
COPY --from=builder /usr/lib/libjq*.so* /usr/lib/
COPY --from=builder /usr/lib/libonig*.so* /usr/lib/
EXPOSE 5678 5679
USER node
