FROM node:22-alpine AS builder

WORKDIR /app

ARG NODE_REGISTRY="https://registry.npmjs.org/"
RUN npm config set registry "$NODE_REGISTRY"

COPY admin/package*.json ./
RUN npm ci

COPY admin/ ./
ARG VITE_VERSION=genericim-local
ENV VITE_BASE_URL=/
ENV VITE_API_URL=/api/v1
ENV VITE_API_PROXY_URL=http://api:8080
ENV VITE_ACCESS_MODE=frontend
ENV VITE_VERSION=$VITE_VERSION
RUN npx vite build --mode production

FROM nginx:1.27-alpine
ARG BUILD_INFO=local-static

ARG ALPINE_MIRROR=""
RUN if [ -n "$ALPINE_MIRROR" ]; then \
      sed -i "s|https://dl-cdn.alpinelinux.org/alpine|$ALPINE_MIRROR|g" /etc/apk/repositories; \
    fi

COPY --from=builder /app/dist /usr/share/nginx/html
COPY docker/genericim/admin-nginx.conf /etc/nginx/conf.d/default.conf
RUN printf '{"build":"%s"}\n' "$BUILD_INFO" > /usr/share/nginx/html/build-info.json

EXPOSE 80
