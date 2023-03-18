FROM golang:1.19-alpine AS builder

WORKDIR /app
COPY go.* ./
RUN go mod download

COPY . ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -v -o helloworld
RUN chmod +x helloworld

EXPOSE 8400

FROM ubuntu:latest
COPY --from=builder /app/helloworld helloworld
CMD ["./helloworld"]
