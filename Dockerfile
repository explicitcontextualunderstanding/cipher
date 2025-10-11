################################################################################
# Build stage - includes dev dependencies

################################################################################
# Build stage - optimized for smaller final image
FROM node:20.18.1-alpine AS builder

# Build arguments
ARG BUILD_UI=false
ARG NODE_VERSION=20.18.1

# Install build dependencies for native modules
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    && rm -rf /var/cache/apk/*

WORKDIR /app

# Copy package files first for better caching
COPY package*.json pnpm-lock.yaml ./

# Install pnpm
RUN npm install -g pnpm@9.14.0

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source and build
COPY . .
# Use conditional build based on BUILD_UI arg
RUN if [ "$BUILD_UI" = "true" ]; then pnpm run build; else pnpm run build:no-ui; fi

# Clean up and prepare production node_modules
RUN pnpm prune --prod && \
    pnpm store prune && \
    rm -rf /root/.npm /tmp/* /usr/lib/node_modules/npm/man /usr/lib/node_modules/npm/doc /usr/lib/node_modules/npm/html /usr/lib/node_modules/npm/scripts

################################################################################
# Production stage - minimal Alpine
FROM node:20.18.1-alpine AS production

WORKDIR /app

# Create non-root user
RUN addgroup -g 1001 -S cipher && adduser -S cipher -u 1001

# Create .cipher directory with proper permissions for database
RUN mkdir -p /app/.cipher/database && \
    chown -R cipher:cipher /app/.cipher

# Install bash and Chrome for Puppeteer web search functionality
RUN apk add --no-cache \
    bash \
    chromium \
    nss \
    freetype \
    freetype-dev \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    && rm -rf /var/cache/apk/*

# Tell Puppeteer to skip installing Chrome since we installed it manually
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Copy only essential production files
COPY --from=builder --chown=cipher:cipher /app/dist ./dist
COPY --from=builder --chown=cipher:cipher /app/node_modules ./node_modules
COPY --from=builder --chown=cipher:cipher /app/package.json ./
COPY --from=builder --chown=cipher:cipher /app/memAgent ./memAgent

# Copy the repository-provided universal entrypoint into the image and make it executable.
# Ensure the entrypoint is owned by the runtime user so it can be executed without extra
# permissions adjustments at container start time.
COPY --chown=cipher:cipher scripts/run/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh


# Create a minimal .env file for Docker (environment variables will be passed via docker)
RUN echo "# Docker environment - variables passed via docker run" > .env

# Environment variables
ENV NODE_ENV=production \
    PORT=3000 \
    CONFIG_FILE=/app/memAgent/cipher.yml

# Switch to non-root user
USER cipher

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "const http = require('http'); const req = http.request({host:'localhost',port:process.env.PORT||3000,path:'/health'}, (res) => process.exit(res.statusCode === 200 ? 0 : 1)); req.on('error', () => process.exit(1)); req.end();"

# Single port for deployment platform
EXPOSE $PORT

# API server mode: REST APIs on single port
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sh", "-c", "node dist/src/app/index.cjs --mode api --port $PORT --host 0.0.0.0 --agent $CONFIG_FILE"]