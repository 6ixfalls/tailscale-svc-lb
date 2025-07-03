FROM tailscale/tailscale:v1.84.3
ARG TARGETPLATFORM
ARG KUBECTL_VERSION=v1.27.11

RUN apk add --no-cache haproxy jq curl bash
RUN case ${TARGETPLATFORM} in \
         "linux/amd64")  KUBE_ARCH=amd64  ;; \
         "linux/arm64")  KUBE_ARCH=arm64  ;; \
    esac \
 && wget -q https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBE_ARCH}/kubectl -O /usr/local/bin/kubectl \
 && chmod +x /usr/local/bin/kubectl

ADD entry.sh /
RUN chmod +x /entry.sh
CMD ["/entry.sh"]
