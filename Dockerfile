FROM alpine:edge

RUN apk add --no-cache bash \ 
    && mkdir -p /etc/kon \
    && mkdir -p /kon/script \
    && mkdir -p /kon/nomad/job

COPY kon.sh /kon/
COPY script /kon/script/
COPY nomad/job /kon/nomad/job/

VOLUME [ "/etc/kon" ]

ENTRYPOINT [ "/kon/kon.sh" ]

CMD [ "install_script" ]

