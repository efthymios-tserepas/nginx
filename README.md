This Bash script automates the installation of Nginx on Linux systems, including package manager detection for CentOS, Red Hat, Debian, Ubuntu, and Raspberry Pi (32-bit and 64-bit). The script gives you the flexibility to choose between the latest stable and mainline versions of Nginx during installation. If an older version of Nginx is detected, the script provides options to upgrade to the latest stable or mainline release.

The script downloads the selected version of Nginx source code from the official site, compiles it, and performs the installation with additional configurable settings.

# Features

- **Package Manager Support:** Supports package managers such as yum (CentOS, Red Hat) and apt-get (Debian, Ubuntu).
- **Port Conflict Resolution:** Ensures port availability for Nginx installation (checks if port 80 is free or used by another application)
- **Nginx Version Management:** Checks for the existing Nginx installation and offers options to upgrade to the latest stable or mainline version.
- **Nginx Customization:** Downloads, compiles, and installs Nginx with configurable settings specified during the compilation process.
- **Systemd Integration:** Sets up systemd service for Nginx with convenient management commands.

**Additional Features based on ./configure:**

- **SSH Support** 
- **Gzip Compression** 
- **Status Module** 
- **Real IP Module** 
- **Streaming Module**

# Usage

To install Nginx with the default settings, run the following command:

```bash
sudo bash -c "$(curl -o- https://raw.githubusercontent.com/efthymios-tserepas/nginx/main/nginx.sh)"


