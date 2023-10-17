FROM tailscale/tailscale:v1.50.1
ARG TARGETPLATFORM

RUN apk add --no-cache haproxy jq curl bash
RUN case ${TARGETPLATFORM} in \
         "linux/amd64")  KUBE_ARCH=amd64  ;; \
         "linux/arm64")  KUBE_ARCH=arm64  ;; \
    esac \
 && wget -q https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${KUBE_ARCH}/kubectl -O /usr/local/bin/kubectl \
 && chmod +x /usr/local/bin/kubectl

ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini
ENTRYPOINT ["/tini", "--"]

ADD *.sh /
CMD "/entry.sh"
