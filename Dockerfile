# Global ARGs
ARG FRONTEND_DIR=web
ARG PNPM_VERSION=10.18.1

# ----------------------------------------------------
# Stage 1: Frontend Build
# ----------------------------------------------------
FROM node:22-alpine AS frontend
ARG FRONTEND_DIR
ARG PNPM_VERSION

ENV PNPM_HOME=/root/.local/share/pnpm
ENV PNPM_STORE_DIR=${PNPM_HOME}/store
ENV PATH="${PNPM_HOME}:${PATH}"

# 使用 npm 安装 pnpm，比 corepack 更稳定
RUN npm install -g "pnpm@${PNPM_VERSION}"

WORKDIR /app/${FRONTEND_DIR}

COPY ${FRONTEND_DIR}/package.json ./package.json
COPY ${FRONTEND_DIR}/pnpm-lock.yaml ./pnpm-lock.yaml

RUN --mount=type=bind,source=${FRONTEND_DIR},target=/tmp/src,ro \
    if [ -f /tmp/src/pnpm-workspace.yaml ]; then cp /tmp/src/pnpm-workspace.yaml ./pnpm-workspace.yaml; fi

RUN --mount=type=cache,target=${PNPM_STORE_DIR} \
    pnpm install --frozen-lockfile

COPY ${FRONTEND_DIR} .

RUN pnpm build


# ----------------------------------------------------
# Stage 2: Backend Build (Goja only - 无需 CGO)
# ----------------------------------------------------
FROM golang:1.25-alpine AS backend
ARG FRONTEND_DIR

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download && go mod verify

COPY ./admin ./admin
COPY ./api ./api
COPY ./conf ./conf
COPY ./dao ./dao
COPY ./job ./job
COPY ./cmd ./cmd

# 复制嵌入资源目录
COPY ./adminui ./adminui
COPY --from=frontend /app/${FRONTEND_DIR}/dist/client ./web/dist/client
COPY --from=frontend /app/${FRONTEND_DIR}/dist/server ./web/dist/server
COPY ./${FRONTEND_DIR}/embed.go ./web/embed.go

# Goja 版本不需要 CGO
ENV CGO_ENABLED=0
RUN go build -tags nov8 -o build/server -ldflags "-w -s" ./cmd/website/...


# ----------------------------------------------------
# Stage 3: Final Runtime
# ----------------------------------------------------
FROM alpine:latest AS final

WORKDIR /app

RUN apk update && \
    apk add --no-cache tzdata && \
    rm -rf /var/cache/apk/*

COPY --from=backend /app/build/server /app/
COPY *.yaml /app/

ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

EXPOSE 8080

CMD ["/app/server"]
