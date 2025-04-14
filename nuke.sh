#!/bin/bash

# --- WARNING ---
# This script attempts to undo the changes made by the iRODS setup script (bap.sh).
# It is DESTRUCTIVE and will remove packages, configuration, logs,
# and the ENTIRE PostgreSQL data directory (/var/lib/pgsql/data).
# Review carefully and backup data before running.
# Run as the same user who executed the original setup script.
# --- WARNING ---

echo "This script will attempt to:"
echo " - Stop iRODS and PostgreSQL services"
echo " - Remove irods-* packages"
echo " - Remove iRODS configuration (/etc/irods), libraries (/var/lib/irods), logs (/var/log/irods)"
echo " - Remove iRODS yum repository and rsyslog config"
echo " - Disable PostgreSQL service"
echo " - COMPLETELY REMOVE PostgreSQL data directory: /var/lib/pgsql/data"
echo " - Remove test files/dirs from your home directory (~/.irods, ~/testenv, etc.)"
echo " - Remove temporary files from /tmp"
echo ""
read -p "ARE YOU ABSOLUTELY SURE YOU WANT TO PROCEED? (yes/no): " CONFIRMATION

if [[ "$CONFIRMATION" != "yes" ]]; then
  echo "Aborted."
  exit 1
fi

echo "*** Proceeding with cleanup... ***"

# Stop services first
echo "--> Stopping iRODS service..."
sudo systemctl stop irods.service || echo "iRODS service likely already stopped."
echo "--> Stopping PostgreSQL service..."
sudo systemctl stop postgresql.service || echo "PostgreSQL service likely already stopped."

# Remove iRODS components
echo "--> Removing iRODS packages..."
#sudo dnf remove -y 'irods-*'

echo "--> Removing iRODS directories..."
sudo rm -rf /etc/irods
sudo rm -rf /var/lib/irods
sudo rm -rf /var/log/irods

echo "--> Removing iRODS repository file..."
sudo rm -f /etc/yum.repos.d/renci-irods.yum.repo

echo "--> Removing iRODS rsyslog configuration..."
sudo rm -f /etc/rsyslog.d/00-irods.conf
echo "--> Restarting rsyslog..."
sudo systemctl restart rsyslog.service || echo "Failed to restart rsyslog, it might not be running."

# Remove PostgreSQL components
echo "--> Disabling PostgreSQL service..."
sudo systemctl disable postgresql.service || echo "PostgreSQL service likely already disabled."

echo "--> !!! REMOVING POSTGRESQL DATA DIRECTORY !!!"
sudo rm -rf /var/lib/pgsql/data
if [ -d "/var/lib/pgsql/data" ]; then
   echo "ERROR: Failed to remove /var/lib/pgsql/data" >&2
   # exit 1 # Optional: halt script if removal fails
else
   echo "PostgreSQL data directory removed."
fi

# Clean up user-specific files (run as the user who ran bap.sh)
echo "--> Removing user-specific files/directories from $HOME..."
rm -rf "$HOME/.irods"
rm -rf "$HOME/testenv"
rm -f "$HOME/zap.py"
rm -f "$HOME/test_upload_file.txt" # If zap.py was interrupted
rm -f "$HOME/test.csv" # If iput was interrupted

# Clean up /tmp files (specific names from the script)
echo "--> Removing temporary files from /tmp..."
sudo rm -f /tmp/test.r
sudo rm -f /tmp/core.py
# irods_setup.input was removed by the original script, but just in case:
sudo rm -f /tmp/irods_setup.input
# Remove other potential temp files if necessary (be cautious with wildcards in /tmp)

# Clean dnf cache
echo "--> Cleaning dnf cache..."
sudo dnf clean all

echo "*** Cleanup Script Finished ***"
echo "Notes:"
echo "- The PostgreSQL data directory /var/lib/pgsql/data has been removed."
echo "- You may need to manually review and remove entries from /etc/hosts if the setup script added one."
echo "- Some dependencies (like python3.12, gcc-c++, jq) were NOT removed as they might be used by other applications."
echo "- System should be ready for a fresh run of the setup script (after potentially rebooting or ensuring services are stopped)."
