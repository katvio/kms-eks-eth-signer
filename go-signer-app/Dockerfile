FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY . .

# Set architecture and build flags for cross-compilation
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64

RUN go build -ldflags="-w -s" -o /bin/transfer ./cmd/transfer

FROM gcr.io/distroless/base-debian12
COPY --from=builder /bin/transfer /bin/transfer
USER nonroot:nonroot
ENTRYPOINT ["/bin/transfer"]
