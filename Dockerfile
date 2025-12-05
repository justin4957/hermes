# Build stage
FROM elixir:1.16-alpine AS build

# Install build dependencies
RUN apk add --no-cache build-base git

# Set working directory
WORKDIR /app

# Set environment variables
ENV MIX_ENV=prod

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files first for better caching
COPY mix.exs mix.lock ./

# Install dependencies
RUN mix deps.get --only prod && \
    mix deps.compile

# Copy application code
COPY config config
COPY lib lib

# Compile application
RUN mix compile

# Build release
RUN mix release

# Runtime stage
FROM alpine:3.19 AS runtime

# Install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs

# Set working directory
WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1000 hermes && \
    adduser -u 1000 -G hermes -s /bin/sh -D hermes

# Copy release from build stage
COPY --from=build --chown=hermes:hermes /app/_build/prod/rel/hermes ./

# Switch to non-root user
USER hermes

# Expose default port
EXPOSE 4020

# Set default environment variables
ENV PORT=4020
ENV OLLAMA_URL=http://ollama:11434
ENV OLLAMA_TIMEOUT=30000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT}/v1/status || exit 1

# Start the application
CMD ["bin/hermes", "start"]
