# media-go

```
docker run -d \
  --name media-go \
  --restart unless-stopped \
  --pids-limit 2048 \
  -p 8080:8080 \
  -e TZ=Asia/Shanghai \
  -e DATA_DIR=/data \
  -e HTTP_ADDR=:8080 \
  -v !!!YOUR!!!/data:/data:rw \
  ghcr.io/samuel-0-0/media-go:latest
  ```
