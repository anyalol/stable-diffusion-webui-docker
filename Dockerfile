# syntax=docker/dockerfile:1

# FROM bash:alpine3.15 as download
FROM alpine/git:2.36.2 as download

RUN apk update && apk add parallel aria2 bash
COPY . /docker
RUN chmod 755 /docker/download.sh
RUN bash /docker/download.sh

RUN git clone https://github.com/CompVis/stable-diffusion.git repositories/stable-diffusion && cd repositories/stable-diffusion && git reset --hard 69ae4b35e0a0f6ee1af8bb9a5d0016ccb27e36dc

RUN git clone https://github.com/sczhou/CodeFormer.git repositories/CodeFormer && cd repositories/CodeFormer && git reset --hard c5b4593074ba6214284d6acd5f1719b6c5d739af
RUN git clone https://github.com/salesforce/BLIP.git repositories/BLIP && cd repositories/BLIP && git reset --hard 48211a1594f1321b00f14c9f7a5b4813144b2fb9
RUN git clone https://github.com/Hafiidz/latent-diffusion.git repositories/latent-diffusion && cd repositories/latent-diffusion && git reset --hard abf33e7002d59d9085081bce93ec798dcabd49af

RUN <<EOF
# because taming-transformers is huge
git config --global http.postBuffer 1048576000
git clone https://github.com/CompVis/taming-transformers.git repositories/taming-transformers
git reset --hard 24268930bf1dce879235a7fddd0b2355b84d7ea6
rm -rf repositories/taming-transformers/data repositories/taming-transformers/assets
EOF


FROM continuumio/miniconda3:4.12.0

SHELL ["/bin/bash", "-ceuxo", "pipefail"]

ENV DEBIAN_FRONTEND=noninteractive

RUN conda install python=3.8.5 && conda clean -a -y
RUN conda install pytorch==1.11.0 torchvision==0.12.0 cudatoolkit=11.3 -c pytorch && conda clean -a -y

RUN apt-get update && apt install fonts-dejavu-core rsync -y && apt-get clean


RUN <<EOF
git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
cd stable-diffusion-webui
git reset --hard 7e77938230d4fefb6edccdba0b80b61d8416673e
pip install --prefer-binary --no-cache-dir -r requirements.txt
EOF

ENV ROOT=/stable-diffusion-webui \
  WORKDIR=/stable-diffusion-webui/repositories/stable-diffusion


COPY --from=download /git/ ${ROOT}
COPY --from=download /cache ./cache
RUN pip install --prefer-binary --no-cache-dir -r ${ROOT}/repositories/CodeFormer/requirements.txt

# Note: don't update the sha of previous versions because the install will take forever
# instead, update the repo state in a later step

ARG SHA=79e7c392989ad70a1c02cbfe6eb38ee5a78bdbce
RUN <<EOF
cd stable-diffusion-webui
git pull --rebase
git reset --hard ${SHA}
pip install --prefer-binary --no-cache-dir -r requirements.txt
pip install --prefer-binary --no-cache-dir -r requirements_versions.txt
EOF

RUN pip install --prefer-binary -U --no-cache-dir opencv-python-headless

ENV TRANSFORMERS_CACHE=/cache/transformers TORCH_HOME=/cache/torch CLI_ARGS=""

COPY . /docker
RUN chmod +x /docker/mount.sh && python3 /docker/info.py ${ROOT}/modules/ui.py


WORKDIR ${WORKDIR}
EXPOSE 8080
# run, -u to not buffer stdout / stderr
CMD /docker/mount.sh && \
  python3 -u ../../webui.py --listen --port 8080 --hide-ui-dir-config --ckpt-dir /cache/custom-models --ckpt /cache/models/model.ckpt --gfpgan-model /cache/models/GFPGANv1.3.pth --no-half --precision full
