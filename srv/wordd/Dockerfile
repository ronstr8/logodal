# Build Stage
# Pinned: `latest` drifts (toolchain and Debian release). Keep the builder's
# Debian release in step with the runtime stage below, or the binary may link
# against a newer glibc than bookworm-slim provides.
FROM rust:1.100.0-bookworm AS builder

WORKDIR /usr/src/wordd

# Copy dependency files first for efficient caching
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release
RUN rm -f target/release/deps/wordd*

# Copy actual source code separately to avoid unnecessary rebuilds
COPY . .

# Build the binary in release mode. COPY keeps the sources' original mtimes,
# which are older than the dummy build above, so cargo would consider wordd
# up to date and ship the empty `fn main() {}`. Touch to force a rebuild.
RUN touch src/main.rs && cargo build --release

# Runtime Stage (Debian Slim)
FROM debian:bookworm-slim

WORKDIR /app

# Copy the compiled binary
COPY --from=builder /usr/src/wordd/target/release/wordd /usr/local/bin/wordd

# Copy the share directory to /app/share
COPY --from=builder /usr/src/wordd/share /app/share

# Expose necessary ports
EXPOSE 8080

# Default command
CMD ["wordd"]
