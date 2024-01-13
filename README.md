Nginx Installation Script
This Bash script automates the installation of Nginx on Linux systems, including package manager detection for CentOS, Red Hat, Debian, Ubuntu, and Raspberry Pi (32-bit and 64-bit). It also checks for the availability of required packages, installs them, and performs additional configurations.

Features:
- Supports package managers: yum (CentOS, Red Hat), apt-get (Debian, Ubuntu), and Raspberry Pi
- Detects and resolves port conflicts (e.g., port 80)
- Checks for the existing Nginx installation and offers options to upgrade to the latest stable or mainline version
- Downloads, compiles, and installs Nginx with configurable settings
- Sets up systemd service for Nginx with convenient management commands

# Usage

You can install with the following command:

curl -o- https://raw.githubusercontent.com/efthymios-tserepas/nginx/main/nginx.sh | sudo bash
