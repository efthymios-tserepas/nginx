#!/bin/bash

# Check for sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[1;31mPlease run this script with sudo: sudo $0\e[0m"
    exit 1
fi

# Function to check if a package is installed
function is_package_installed() {
    local package_name="$1"

    if command -v rpm &> /dev/null; then
        # CentOS, Red Hat
        rpm -q "$package_name" &> /dev/null && echo -e "\e[1;32mPackage is installed.\e[0m" || echo -e "\e[1;31mPackage is not installed.\e[0m"
    elif command -v dpkg &> /dev/null; then
        # Debian, Ubuntu
        dpkg -s "$package_name" 2>/dev/null | grep -q "Status: install ok installed" && echo -e "\e[1;32mPackage is installed.\e[0m" || echo -e "\e[1;31mPackage is not installed.\e[0m"
    else
        echo "Unsupported package manager. Exiting..."
        exit 1
    fi
}

# List of packages to install
if command -v yum &> /dev/null; then
    # CentOS, Red Hat
    packages=("net-tools" "gcc" "make" "pcre" "pcre-devel" "openssl-devel" "zlib-devel" "curl")
elif command -v apt &> /dev/null; then
    # Debian, Ubuntu
    packages=("net-tools" "build-essential" "libpcre3" "libpcre3-dev" "libssl-dev" "zlib1g-dev" "curl")
else
    echo "Unsupported package manager. Exiting..."
    exit 1
fi

# Update package sources and install packages
if command -v yum &> /dev/null; then
    # CentOS, Red Hat
    sudo yum update -y
    sudo yum install "${packages[@]}" -y
elif command -v apt-get &> /dev/null; then
    # Debian, Ubuntu
    sudo apt update
    sudo apt install "${packages[@]}" -y
else
    echo "Unsupported package manager. Exiting..."
    exit 1
fi

# Check for broken packages and fix if needed
if command -v yum &> /dev/null; then
    if sudo yum -y check-update; then
        echo -e "\e[1;32mNo broken packages found.\e[0m"
    else
        echo -e "\e[1;31mError: Broken packages found. Please run 'sudo yum check-update' and resolve the issues manually.\e[0m"
        exit 1
    fi
elif command -v apt-get &> /dev/null; then
    # Debian, Ubuntu
    if sudo apt -y --fix-broken install; then
        echo -e "\e[1;32mDependency issues resolved.\e[0m"
    else
        echo -e "\e[1;31mError: Unable to fix broken dependencies. Please run 'sudo apt --fix-broken install' manually.\e[0m"
        exit 1
    fi
else
    echo "Unsupported package manager. Exiting..."
    exit 1
fi

# Check for port 80 usage by any process
nginx_port_in_use=$(netstat -tuln | awk '$6 == "LISTEN" && $4 ~ ":80$"{print "true"}')

if [ "$nginx_port_in_use" == "true" ]; then
    echo -e "\e[1;32mPort 80 is in use by Nginx. Proceeding with the script...\e[0m"
else
    # Get the process using port 80
    process_info=$(sudo lsof -i :80 | awk 'NR==2 {print $1, $2}')
    if [ -n "$process_info" ]; then
        process_name=$(echo "$process_info" | cut -d ' ' -f 1)
        process_pid=$(echo "$process_info" | cut -d ' ' -f 2)
        echo -e "\e[1;31mPort 80 is in use by the process: $process_name (PID: $process_pid)\e[0m"
        echo -e "\e[1;31mPlease make sure it is free before running this script.\e[0m"
        exit 1
    else
        echo -e "\e[1;33mPort 80 is not in use by any process. Proceeding with the script...\e[0m"
    fi
fi

# Check if Nginx is installed
if command -v nginx &> /dev/null; then
    installed_version=$(nginx -v 2>&1 | awk -F "/" '/nginx/ {print $2}')
    latest_stable_version=$(curl -s https://nginx.org/en/download.html | grep -oP 'Stable version.*?nginx-\K\d+\.\d+\.\d+' | head -n 1)
    latest_mainline_version=$(curl -s https://nginx.org/en/download.html | grep -oP 'nginx-\K\d+\.\d+\.\d+' | head -n 1)

    if [ "$installed_version" == "$latest_stable_version" ]; then
        echo -e "\e[1;33mYou have the latest stable version of Nginx installed: $installed_version\e[0m"
        read -p $'\e[1;32mDo you want to install the latest mainline version? (y/n): \e[0m' choice
        if [ "$choice" == "y" ]; then
            echo -e "\e[1;32mProceeding with the installation of the latest mainline version...\e[0m"
            nginx_version=$(curl -s https://nginx.org/en/download.html | grep -oP 'nginx-\K\d+\.\d+\.\d+' | head -n 1)
        else
            exit 0
        fi
    elif [ "$installed_version" == "$latest_mainline_version" ]; then
        echo -e "\e[1;33mYou have the latest mainline version of Nginx installed: $installed_version\e[0m"
        read -p $'\e[1;32mDo you want to install the latest stable version ? (y/n): \e[0m' choice
        if [ "$choice" == "y" ]; then
            echo -e "\e[1;32mProceeding with the installation of the latest stable version...\e[0m"
            nginx_version=$(curl -s https://nginx.org/en/download.html | grep -oP 'Stable version.*?nginx-\K\d+\.\d+\.\d+' | head -n 1)
        else
            exit 0
        fi
    else
        echo -e "\e[1;33mYour current version is $installed_version.\e[0m"
        echo -e "\e[1;35mThere is a new version available: $latest_stable_version (Stable) / $latest_mainline_version (Mainline).\e[0m"
        # Ask for the Nginx version to install
        echo -e "\e[1;34mSelect Nginx version to install:\e[0m"
        echo -e "\e[1;34m1) Install the latest stable version of nginx\e[0m"
        echo -e "\e[1;34m2) Install the latest mainline version of nginx\e[0m"
        echo -e "\e[1;31m\u2022 Or any other choice to exit\e[0m"
        read -p "Enter your choice (1 or 2 or any other to exit): " choice
 
        # Step 1: Download the selected version of Nginx
        if [ "$choice" == "1" ]; then
            # Download the latest stable version
            nginx_version=$(curl -s https://nginx.org/en/download.html | grep -oP 'Stable version.*?nginx-\K\d+\.\d+\.\d+' | head -n 1)
        elif [ "$choice" == "2" ]; then
            # Download the latest mainline version   
            nginx_version=$(curl -s https://nginx.org/en/download.html | grep -oP 'nginx-\K\d+\.\d+\.\d+' | head -n 1)
        else
            echo -e "\e[1;31mInvalid choice. Exiting...\e[0m"
            exit 1
        fi
    fi
else
    echo -e "\e[1;32mNginx is not installed. Proceeding with installation...\e[0m"
        # Ask for the Nginx version to install
        echo -e "\e[1;34mSelect Nginx version to install:\e[0m"
        echo -e "\e[1;34m1) Install the latest stable version of nginx\e[0m"
        echo -e "\e[1;34m2) Install the latest mainline version of nginx\e[0m"
        echo -e "\e[1;31m\u2022 Or any other choice to exit\e[0m"
        read -p "Enter your choice (1 or 2 or any other to exit): " choice
 
        # Step 1: Download the selected version of Nginx
        if [ "$choice" == "1" ]; then
            # Download the latest stable version
            nginx_version=$(curl -s https://nginx.org/en/download.html | grep -oP 'Stable version.*?nginx-\K\d+\.\d+\.\d+' | head -n 1)
        elif [ "$choice" == "2" ]; then
            # Download the latest mainline version   
            nginx_version=$(curl -s https://nginx.org/en/download.html | grep -oP 'nginx-\K\d+\.\d+\.\d+' | head -n 1)
        else
            echo -e "\e[1;31mInvalid choice. Exiting...\e[0m"
            exit 1
        fi
fi

# Step 2: Download Nginx
nginx_url="https://nginx.org/download/nginx-${nginx_version}.tar.gz"
wget "$nginx_url"

# Step 3: Extract the folder
nginx_folder="nginx-${nginx_version}"
tar -zxvf "${nginx_folder}.tar.gz"
sudo rm "${nginx_folder}.tar.gz"
cd "$nginx_folder"

# Step 4: Configure and install Nginx
./configure --sbin-path=/usr/bin/nginx \
            --conf-path=/etc/nginx/nginx.conf \
            --error-log-path=/var/log/nginx/error.log \
            --http-log-path=/var/log/nginx/access.log \
            --with-pcre \
            --pid-path=/var/run/nginx.pid \
            --with-http_ssl_module \
            --with-http_gzip_static_module \
            --with-http_stub_status_module \
            --with-http_realip_module \
            --with-stream=dynamic \
            --with-stream_ssl_module \
            --with-http_v2_module \
            --with-ngx_http_sub_module --prefix=/usr/local/nginx
                        
make
sudo make install

# Step 5: Check Nginx version
nginx_version_installed=$(nginx -v 2>&1 | awk -F "/" '/nginx/ {print $2}')

if [[ "$nginx_version_installed" == "$nginx_version" ]]; then
    echo "Successful installation of nginx."

# Reload daemon-reload
sudo systemctl daemon-reload

    # Get the main process ID of Nginx
    nginx_main_pid=$(ps aux | grep 'nginx: master process' | grep -v grep | awk '{print $2}')

    # Create the nginx.service file
    nginx_service_file="/lib/systemd/system/nginx.service"
    echo "[Unit]" > "$nginx_service_file"
    echo "Description=The NGINX HTTP and reverse proxy server" >> "$nginx_service_file"
    echo "After=syslog.target network-online.target remote-fs.target nss-lookup.target" >> "$nginx_service_file"
    echo "Wants=network-online.target" >> "$nginx_service_file"
    echo "" >> "$nginx_service_file"
    echo "[Service]" >> "$nginx_service_file"
    echo "Type=forking" >> "$nginx_service_file"
    echo "PIDFile=/var/run/nginx.pid" >> "$nginx_service_file"
    echo "ExecStartPre=/usr/bin/nginx -t" >> "$nginx_service_file"
    echo "ExecStart=/usr/bin/nginx" >> "$nginx_service_file"
    echo "ExecReload=/usr/sbin/nginx -s reload" >> "$nginx_service_file"
    echo "ExecStop=/bin/kill -s QUIT $nginx_main_pid" >> "$nginx_service_file"
    echo "PrivateTmp=true" >> "$nginx_service_file"
    echo "" >> "$nginx_service_file"
    echo "[Install]" >> "$nginx_service_file"
    echo "WantedBy=multi-user.target" >> "$nginx_service_file"
  
    # Checks and updates ExecReload
    if grep -q "ExecReload=/usr/sbin/nginx" "$nginx_service_file"; then
        sed -i 's|ExecReload=/usr/sbin/nginx -s reload|ExecReload=/usr/bin/nginx -s reload|' "$nginx_service_file"
        echo "ExecReload in $nginx_service_file updated."
    fi
        
    # Start and enable nginx
    sudo systemctl start nginx
    sudo systemctl enable nginx

else
    echo -e "\e[1;31mError: Installation of nginx failed.\e[0m"
fi

# Check nginx service status
nginx_status=$(systemctl is-active nginx)

if [ "$nginx_status" = "active" ]; then
    echo -e "\e[1;32mNginx is running successfully. You can use the following IP address to access it:\e[0m"
    
    # Find the IP address
    ip_address=$(hostname -I | awk '{print $1}')
    echo -e "\e[1;32mhttp://$ip_address\e[0m"
    
    # Open in the default browser
    xdg-open "http://$ip_address" >/dev/null 2>&1 &
else
    echo -e "\e[1;31mError: Nginx is not running successfully.\e[0m"
    read -p "System will be restarted. Press Enter to continue..." -r
    echo -e "\e[1;32mAfter the restart, it's possible that the issue will be resolved. Open the following page: http://$ip_address\e[0m"
    sudo shutdown -r now
fi

