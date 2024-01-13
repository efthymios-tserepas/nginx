Nginx Installation Script
This Bash script automates the installation of Nginx on Linux systems, including package manager detection for CentOS, Red Hat, Debian, Ubuntu, and Raspberry Pi (32-bit and 64-bit). It also checks for the availability of required packages, installs them, and performs additional configurations.

# Features

- **Package Manager Support:** Supports package managers such as yum (CentOS, Red Hat) and apt-get (Debian, Ubuntu).
- **Port Conflict Resolution:** Detects and resolves port conflicts, including conflicts on port 80.
- **Nginx Version Management:** Checks for the existing Nginx installation and offers options to upgrade to the latest stable or mainline version.
- **Nginx Customization:** Downloads, compiles, and installs Nginx with configurable settings specified during the compilation process.
- **Systemd Integration:** Sets up systemd service for Nginx with convenient management commands.

**Additional Features based on ./configure:**

- **SSH Support:** 
- **Gzip Compression:** 
- **Status Module:** 
- **Real IP Module:** 


# Usage

To install Nginx with the default settings, run the following command:

```bash
sudo bash -c "$(curl -o- https://raw.githubusercontent.com/efthymios-tserepas/nginx/main/nginx.sh)"


