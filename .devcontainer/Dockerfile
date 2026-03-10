FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    build-essential \
    ca-certificates \
    curl \
    fish \
    git \
    libpq-dev \
    libyaml-dev \
    postgresql-client \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install starship prompt (needs root for /usr/local/bin)
RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes

# ubuntu user (uid 1000) already exists in ubuntu:24.04
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chsh -s /usr/bin/fish ubuntu

# Install mise for the ubuntu user
USER ubuntu
RUN curl https://mise.run | sh
COPY .mise.toml /tmp/.mise.toml
RUN cd /tmp && MISE_YES=1 ~/.local/bin/mise install && ~/.local/bin/mise reshim

# Configure fish to use mise shims and starship prompt
RUN mkdir -p ~/.config/fish \
    && echo 'set -gx PATH /home/ubuntu/.local/share/mise/shims /home/ubuntu/.local/bin $PATH' > ~/.config/fish/config.fish \
    && echo 'starship init fish | source' >> ~/.config/fish/config.fish

ENV PATH="/home/ubuntu/.local/share/mise/shims:/home/ubuntu/.local/bin:${PATH}"
USER root
