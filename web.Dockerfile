# Build stage
FROM swift:5.9-focal as builder

ARG env

RUN apt-get -qq update && apt-get -q -y install \
  tzdata \
  && rm -r /var/lib/apt/lists/*
WORKDIR /app
COPY . .
RUN mkdir -p /build/lib && cp -R /usr/lib/swift/linux/*.so* /build/lib
RUN swift build -c release && mv `swift build -c release --show-bin-path` /build/bin

# Production image
FROM ubuntu:22.04
ARG env
RUN apt-get -qq update && apt-get install -y \
  libicu70 libxml2 libbsd0 libcurl4 libatomic1 \
  tzdata \
  && rm -r /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /build/bin/Run .
COPY --from=builder /build/lib/* /usr/lib/
COPY --from=builder /app/Public ./Public
COPY --from=builder /app/Resources ./Resources
ENV ENVIRONMENT=$env

ENTRYPOINT ./Run serve --env $ENVIRONMENT --hostname 0.0.0.0 --port 80
