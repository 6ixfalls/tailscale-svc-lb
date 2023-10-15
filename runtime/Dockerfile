FROM tailscale/tailscale:v1.32.3
RUN apk add --no-cache haproxy jq curl bash kubectl
ADD *.sh /
CMD "/run.sh"
