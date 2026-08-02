# syntax = docker/dockerfile:1
FROM ruby:3.4

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

ENV BUNDLE_PATH=/usr/local/bundle

CMD ["bash"]
