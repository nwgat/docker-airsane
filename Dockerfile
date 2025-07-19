ARG BASE_IMAGE=library/debian:stable-slim

# --- Builder Stage ---
# Compiles the AirSane application
FROM docker.io/${BASE_IMAGE} AS builder

ARG AIRSANE_REPO=https://github.com/SimulPiscator/AirSane
ARG AIRSANE_TAG=v0.4.5

WORKDIR /opt/AirSane

RUN <<-EOT sh
	set -eu

	apt-get update
	env DEBIAN_FRONTEND=noninteractive \
		apt-get install -y --no-install-recommends \
		wget ca-certificates build-essential cmake g++ \
		libsane-dev libjpeg-dev libpng-dev libavahi-client-dev libusb-1.*-dev \
		-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
	apt-get clean && rm -rf /var/lib/apt/lists/*

	wget ${AIRSANE_REPO}/archive/refs/tags/${AIRSANE_TAG}.tar.gz -O - \
		| tar -xzv --strip-components=1
	mkdir ./build && cd ./build && cmake .. && make
EOT

# --- Final Image Stage ---
# Creates the final, smaller runtime image
FROM docker.io/${BASE_IMAGE}

RUN <<-EOT sh
	set -eu

	apt-get update
	# Install runtime dependencies for AirSane and the Epson scanner driver
	env DEBIAN_FRONTEND=noninteractive \
		apt-get install -y --no-install-recommends \
		sane-utils wget \
		libsane libjpeg62-turbo libpng16-16 libavahi-client3 libusb-1.0-0 \
		-o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

	# Download, extract, and install the Epson scanner driver
	wget https://download2.ebz.epson.net/iscan/plugin/gt-x770/deb/x64/iscan-gt-x770-bundle-2.30.4.x64.deb.tar.gz
	tar zxvf iscan-gt-x770-bundle-2.30.4.x64.deb.tar.gz
	sh iscan-gt-x770-bundle-2.30.4.x64.deb/install.sh --without-network --without-ocr-engine

	# Clean up downloaded files and apt cache
	rm -rf iscan-gt-x770-bundle-2.30.4.x64.deb.tar.gz iscan-gt-x770-bundle-2.30.4.x64.deb
	apt-get clean && rm -rf /var/lib/apt/lists/*
	
	mkdir -p /etc/airsane
EOT

# Copy the compiled application and default config from the builder stage
COPY --from=builder /opt/AirSane/etc/* /etc/airsane/
COPY --from=builder /opt/AirSane/build/airsaned /usr/local/bin
COPY rootfs/ /

# Modify the configuration to allow access from the local network
RUN sed -i '$a allow 192.168.1.0/24' /etc/airsane/access.conf

EXPOSE 8090/tcp

VOLUME /dev/bus/usb /run/dbus 

HEALTHCHECK --interval=1m --timeout=3s \
  CMD timeout 2 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/8090'

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--access-log=-", "--disclose-version=false", "--debug=true"]
```
