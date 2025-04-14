#!/bin/bash

# Exit on error, treat unset variables as errors, fail pipelines on first error
set -euo pipefail

# --- Configuration ---
# Array of RPM filenames in approximate build dependency order.
# Assumes these files are in the current directory when the script is run.
# NOTE: Add the correct filenames for clang-runtime and avro-libcxx if they exist.
install_order=(
    "irods-externals-cmake3.21.4-0-1.0-5.el8.x86_64.rpm"           # 1. cmake
    "irods-externals-clang13.0.1-0-1.0-2.el8.x86_64.rpm"           # 2. clang
    "irods-externals-catch22.13.8-0-1.0-3.el8.x86_64.rpm"          # 3. catch2
    "irods-externals-json3.10.4-0-1.0-3.el8.x86_64.rpm"            # 4. json
    "irods-externals-jsoncons0.178.0-0-1.0-0.el8.x86_64.rpm"      # 5. jsoncons
    "irods-externals-clang-runtime13.0.1-0-1.0-1.el8.x86_64.rpm" # 7. clang-runtime (VERIFY FILENAME!)
    "irods-externals-boost-libcxx1.81.0-1-1.0-2.el8.x86_64.rpm"    # 6. boost-libcxx
    "irods-externals-fmt-libcxx8.1.1-1-1.0-1.el8.x86_64.rpm"       # 8. fmt-libcxx
    "irods-externals-libarchive3.5.2-0-1.0-5.el8.x86_64.rpm"       # 9. libarchive
    "irods-externals-nanodbc-libcxx2.13.0-2-1.0-1.el8.x86_64.rpm"  # 10. nanodbc-libcxx
    "irods-externals-qpid-proton-libcxx0.36.0-2-1.0-2.el8.x86_64.rpm" # 11. qpid-proton-libcxx
    "irods-externals-zeromq4-1-libcxx4.1.8-1-1.0-2.el8.x86_64.rpm" # 12. zeromq4-1-libcxx
    "irods-externals-spdlog-libcxx1.9.2-2-1.0-1.el8.x86_64.rpm"   # 13. spdlog-libcxx
    "irods-externals-cppzmq4.8.1-1-1.0-5.el8.x86_64.rpm"          # 14. cppzmq
    "irods-externals-avro-libcxx1.11.0-3-1.0-1.el8.x86_64.rpm"  # 15. avro-libcxx (VERIFY FILENAME!)
)

# --- Installation Loop ---
echo "Starting installation of iRODS external RPMs..."

# Check if running as root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: This script must be run as root (or using sudo)." >&2
  exit 1
fi

# Loop through the array and install each RPM
for rpm_file in "${install_order[@]}"; do
  if [[ -f "$rpm_file" ]]; then
    echo "--------------------------------------------------"
    echo "Installing: $rpm_file"
    echo "--------------------------------------------------"
    dnf install -y "./$rpm_file" || { echo "Error installing $rpm_file"; exit 1; }
    echo "Successfully installed $rpm_file"
    echo ""
  else
    echo "--------------------------------------------------"
    echo "Warning: RPM file not found, skipping: $rpm_file"
    echo "--------------------------------------------------"
    echo ""
    # Decide if missing files should cause an error:
    # exit 1
  fi
done

echo "--------------------------------------------------"
echo "All specified RPMs installed successfully."
echo "--------------------------------------------------"

exit 0

