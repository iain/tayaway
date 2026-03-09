FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    build-essential \
    ca-certificates \
    curl \
    git \
    libpq-dev \
    libyaml-dev \
    postgresql-client \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# ubuntu user (uid 1000) already exists in ubuntu:24.04
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu

# Install mise for the ubuntu user
USER ubuntu
RUN curl https://mise.run | sh
COPY .mise.toml /tmp/.mise.toml
RUN cd /tmp && MISE_YES=1 ~/.local/bin/mise install && ~/.local/bin/mise reshim
ENV PATH="/home/ubuntu/.local/share/mise/shims:/home/ubuntu/.local/bin:${PATH}"
USER root
