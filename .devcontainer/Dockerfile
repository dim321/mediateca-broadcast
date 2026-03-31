# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.2
FROM ghcr.io/rails/devcontainer/images/ruby:$RUBY_VERSION

# ffmpeg/ffprobe for media metadata in development
RUN sudo apt-get update -qq && \
    sudo apt-get install -y --no-install-recommends ffmpeg && \
    sudo rm -rf /var/lib/apt/lists/*

# Ensure binding is always 0.0.0.0
# Binds the server to all IP addresses of the container, so it can be accessed from outside the container.
ENV BINDING="0.0.0.0"
