FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY . .
RUN go build -o /bin/transfer ./cmd/transfer

FROM gcr.io/distroless/base-debian12
COPY --from=builder /bin/transfer /bin/transfer
USER nonroot:nonroot
ENTRYPOINT ["/bin/transfer"]
