# syntax = docker/dockerfile:1
FROM ruby:3.4

# Avoid debconf trying to use interactive frontends during build
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# 1) Base packages needed for adding an external apt repo/key and downloading packages
RUN apt update -qq; \
  apt install -y --no-install-recommends gpgv

# 2) Trixie: force apt to use gpgv (avoids sqv/SHA1 policy issues seen on Debian 13)
RUN echo 'APT::Key::gpgvcommand "/usr/bin/gpgv";' > /etc/apt/apt.conf.d/99force-gpgv

# 3) Add MongoDB 7.0 signing key (keyring file)
RUN curl -fsSL https://pgp.mongodb.com/server-7.0.asc \
  | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg

# 4) Add MongoDB apt repo (Ubuntu Jammy) — provides mongodb-database-tools for arm64+amd64
RUN echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-7.0.list

# 5) Install MongoDB Database Tools
RUN apt update -qq && apt install -y --no-install-recommends nodejs mongodb-database-tools; \
  rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

ENV BUNDLE_PATH=/usr/local/bundle

CMD ["bash"]
