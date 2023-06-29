FROM golang:1.20-alpine AS build
COPY  . /app
WORKDIR /app
RUN go build -o test-app

FROM alpine:latest
COPY --from=build /app/test-app .
EXPOSE 7777
ENTRYPOINT [ "./test-app" ]

RUN apk add --no-cache bash curl jq
