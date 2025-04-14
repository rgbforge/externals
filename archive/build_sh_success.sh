#!/bin/bash

# Exit on error, treat unset variables as errors, disable globbing, fail pipelines on first error
set -euo pipefail

# Get the directory where the script resides
script_path=$(dirname "$(realpath "$0")")

# --- Configuration ---
# Define the Ruby version and RVM path, similar to the Python script
readonly ruby_version="3.1.2"
readonly rvm_path="/usr/local/rvm" # Hardcoded, like in python's set_ruby_path

# Target OS/Distro for dependencies (can be overridden if needed)
TARGET_DISTRO="rhel"
TARGET_VERSION="8"

# --- Helper Functions ---

# Function to print error messages and exit
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Function to touch a file (create if not exists, update timestamp if exists)
touch_file() {
    touch "$1" || error_exit "Failed to touch file '$1'"
}

# Function to prepend a directory to the PATH environment variable
# Note: This modifies the PATH for the current script execution and its children
set_environ_path() {
    local bin_path="$1"
    if [[ -d "$bin_path" ]]; then
        export PATH="${bin_path}:${PATH}"
        # echo "DEBUG: Added to PATH: ${bin_path}" # Uncomment for debugging PATH
        # echo "DEBUG: New PATH: ${PATH}"        # Uncomment for debugging PATH
    else
        echo "Warning: Directory not found, not adding to PATH: ${bin_path}" >&2
    fi
}

# Function to get package info field from versions.json using jq
get_field() {
    local pkg="$1"
    local field="$2"
    local versions_json="${script_path}/versions.json"
    local filter # Variable to hold the constructed jq filter

    # Debug print
    printf "DEBUG: get_field: pkg=[%s], field=[%s]\n" "$pkg" "$field" >&2

    # *** MODIFIED jq call - Constructing filter string in bash ***
    # Ensure the package name is quoted correctly within the filter, especially if it contains hyphens.
    filter=".[\"${pkg}\"].${field}"
    printf "DEBUG: get_field: filter=[%s]\n" "$filter" >&2

    # Execute jq with the constructed filter string
    jq -re "$filter" "$versions_json" || error_exit "Failed to get field '$field' for package '$pkg' using filter '$filter' from '$versions_json'"
}

# Function to get the full external package name string (e.g., irods-externals-...)
get_full_external_package_name() {
    local pkg="$1"
    local version_string build_number
    version_string=$(get_field "$pkg" "version_string")
    # Handle potential null from simplified get_field if key missing
    [[ "$version_string" == "null" ]] && error_exit "Missing 'version_string' for dependency '$pkg'"
    build_number=$(get_field "$pkg" "consortium_build_number")
     [[ "$build_number" == "null" ]] && error_exit "Missing 'consortium_build_number' for dependency '$pkg'"
    echo "irods-externals-${pkg}${version_string}-${build_number}"
}

# Function to calculate the local path to a built dependency's artifact
get_local_path() {
    local package_name="$1"
    # Capture remaining arguments as path elements
    local path_elements=("${@:2}")
    local version_string build_number externals_root path_name local_path element

    version_string=$(get_field "$package_name" "version_string")
    [[ "$version_string" == "null" ]] && error_exit "Missing 'version_string' for '$package_name' in get_local_path"
    build_number=$(get_field "$package_name" "consortium_build_number")
    [[ "$build_number" == "null" ]] && error_exit "Missing 'consortium_build_number' for '$package_name' in get_local_path"
    externals_root=$(get_field "$package_name" "externals_root")
    [[ "$externals_root" == "null" ]] && error_exit "Missing 'externals_root' for '$package_name' in get_local_path"

    path_name="${package_name}${version_string}-${build_number}"
    local_path="${script_path}/${path_name}_src/${externals_root}/${path_name}"

    # Append additional path elements if provided
    for element in "${path_elements[@]}"; do
        local_path="${local_path}/${element}"
    done

    # Check if the path actually exists before returning it
    # if [[ ! -e "$local_path" ]]; then
    #     echo "Warning: Calculated local path does not exist: $local_path" >&2
    # fi
    echo "$local_path"
}

# Function to run a command, with optional retries and error checking
run_cmd() {
    local cmd="$1"
    local check_rc_msg="${2:-Command failed}"
    local retries="${3:-0}"
    local attempt=$((retries + 1)) # For logging

    echo "Running (attempt ${attempt}): ${cmd}"

    # Use eval carefully, ensure commands from versions.json are trusted
    # Consider alternatives like temporary script files if eval is too risky
    if eval "$cmd"; then
        # Command succeeded
        return 0
    else
        # Command failed
        local rc=$?
        echo "Command failed with status ${rc}: ${cmd}" >&2
        if [[ $retries -gt 0 ]]; then
            echo "Retrying (${retries} left)..." >&2
            sleep 1
            # Recursive call with decremented retries
            run_cmd "$cmd" "$check_rc_msg" "$((retries - 1))"
        else
            error_exit "${check_rc_msg} (rc: ${rc})"
        fi
    fi
}

# --- Package Information Functions ---

# Gets the base package name string (e.g., irods-externals-...)
get_package_name_string() {
    local p="$1"
    local version_string build_number
    version_string=$(get_field "$p" "version_string")
    # Handle potential null from simplified get_field if key missing
    [[ "$version_string" == "null" ]] && error_exit "Missing 'version_string' for '$p' in get_package_name_string"
    build_number=$(get_field "$p" "consortium_build_number")
    [[ "$build_number" == "null" ]] && error_exit "Missing 'consortium_build_number' for '$p' in get_package_name_string"
    echo "irods-externals-${p}${version_string}-${build_number}"
}

# Gets the package version (currently hardcoded like Python)
get_package_version() {
    echo "1.0"
}

# Gets the package revision/release string
get_package_revision() {
    local p="$1"
    local ver_pkgrev ver_pkgrev_suffix1 ver_pkgrev_suffix2 dt dv
    # Use default value "0" directly in jq query if package_revision is missing
    # Using safe navigation here just in case
    ver_pkgrev=$(jq -re --arg pkg "$p" '.[$pkg]?.package_revision? // "0"' "${script_path}/versions.json") || ver_pkgrev="0" # Default if jq fails

    # Determine suffix based on distro type (simplified version)
    dt=$(get_distro_type)
    dv=$(get_distro_version) # Assuming this returns major version like "8"

    if [[ "$(get_package_extension)" == "deb" ]]; then
        ver_pkgrev_suffix1="~"
        # Need a way to get codename if required, hardcoding for now if needed
        ver_pkgrev_suffix2="dist" # Placeholder for codename like focal, buster etc.
    else # Assuming RPM based
         ver_pkgrev_suffix2="$dv" # Use distribution version like "8"
        if [[ "$dt" == "rhel" || "$dt" == "centos" || "$dt" == "rocky" || "$dt" == "almalinux" ]]; then
            ver_pkgrev_suffix1=".el"
        elif [[ "$dt" == "fedora" ]]; then
            ver_pkgrev_suffix1=".fc"
        else
            ver_pkgrev_suffix1=".${dt}" # Suse?
        fi
    fi
    echo "${ver_pkgrev}${ver_pkgrev_suffix1}${ver_pkgrev_suffix2}"
}

# --- Distro Information Functions (Simplified - assumes external info or defaults) ---
# These would ideally use lsb_release, /etc/os-release etc. like the python distro_info
get_distro_type() { echo "${TARGET_DISTRO}"; } # Use variable set at top
get_distro_version() { echo "${TARGET_VERSION}"; } # Use variable set at top
get_package_type() { [[ "$(get_distro_type)" == "debian" || "$(get_distro_type)" == "ubuntu" ]] && echo "deb" || echo "rpm"; }
get_package_extension() { get_package_type; } # rpm or deb
get_package_architecture_string() { arch; } # Assumes 'arch' command is available

# Constructs the final package filename
get_package_filename() {
    local p="$1"
    local n v r a t
    n=$(get_package_name_string "$p")
    v=$(get_package_version "$p")
    r=$(get_package_revision "$p")
    a=$(get_package_architecture_string)
    t=$(get_package_extension)
    # Format differs slightly between deb and rpm
    if [[ "$t" == "rpm" ]]; then
        echo "${n}-${v}-${r}.${a}.${t}"
    else # Assuming deb
        echo "${n}_${v}-${r}_${a}.${t}"
    fi
}

# Gets dependencies (distro + interdependencies)
get_package_dependencies() {
    local package_name="$1"
    local versions_json="${script_path}/versions.json"
    local distro_type distro_version

    distro_type=$(get_distro_type)
    distro_version=$(get_distro_version)

    command -v jq >/dev/null 2>&1 || error_exit "'jq' command is required but not found."

    # Get distro dependencies using safe navigation in jq
    local distro_deps_query=".[\"$package_name\"]? .distro_dependencies? .[\"$distro_type\"]? .[\"$distro_version\"]? // [] | .[]"
    local distro_deps
    distro_deps=$(jq -r "$distro_deps_query" "$versions_json" | tr '\n' ' ')
    distro_deps=$(echo "${distro_deps}" | sed 's/ *$//') # Trim trailing space

    # Get interdependencies using safe navigation in jq
    local interdep_names_query=".[\"$package_name\"]? .interdependencies? // [] | .[]"
    local interdep_names
    interdep_names=$(jq -r "$interdep_names_query" "$versions_json")

    local full_interdeps=""
    if [[ -n "$interdep_names" ]]; then
        local dep_name full_dep_name
        # Process each dependency name
        while IFS= read -r dep_name; do
            [[ -z "$dep_name" ]] && continue # Skip empty lines
            # Need error handling here if get_full_external_package_name fails
            full_dep_name=$(get_full_external_package_name "$dep_name") || { echo "Warning: Failed to get full name for interdependency '$dep_name' of '$package_name'" >&2; continue; }
            full_interdeps+="${full_dep_name} "
        done <<< "$interdep_names"
        full_interdeps=$(echo "${full_interdeps}" | sed 's/ *$//') # Trim trailing space
    fi

    # Combine dependencies
    local all_deps=""
    if [[ -n "$distro_deps" ]]; then
        all_deps+="$distro_deps"
    fi
    if [[ -n "$full_interdeps" ]]; then
        [[ -n "$all_deps" ]] && all_deps+=" " # Add space if both types exist
        all_deps+="$full_interdeps"
    fi

    echo "$all_deps"
}

# Gets the number of jobs for parallel builds (e.g., make -j)
get_jobs() {
    local detected jobs_to_use
    detected=$(nproc) || detected=1 # Default to 1 if nproc fails
    jobs_to_use=$((detected > 1 ? detected - 1 : 1)) # Use n-1, but at least 1
    echo "$jobs_to_use"
}

# --- Main Build Function ---
build_package() {
    local target="$1"
    local build_native_package="$2" # Should be "true" or "false"

    echo "--- Building [$target] ---"

    # Get package metadata from versions.json
    local version_string consortium_build_number externals_root license patches_str build_steps_str external_build_steps_str fpm_dirs_str enable_sha git_repo commitish
    version_string=$(get_field "$target" "version_string") || error_exit "Missing 'version_string' for '$target'"
    [[ "$version_string" == "null" ]] && error_exit "Missing 'version_string' for '$target' in versions.json"
    consortium_build_number=$(get_field "$target" "consortium_build_number") || error_exit "Missing 'consortium_build_number' for '$target'"
    [[ "$consortium_build_number" == "null" ]] && error_exit "Missing 'consortium_build_number' for '$target' in versions.json"
    externals_root=$(get_field "$target" "externals_root") || error_exit "Missing 'externals_root' for '$target'"
    [[ "$externals_root" == "null" ]] && error_exit "Missing 'externals_root' for '$target' in versions.json"

    license=$(get_field "$target" "license") || license="Unknown" # Allow license to be missing
    [[ "$license" == "null" ]] && license="Unknown"

    # Read multi-line outputs into arrays safely using process substitution and mapfile
    mapfile -t patches_array < <(jq -r --arg pkg "$target" '.[$pkg]?.patches? // [] | .[]' "${script_path}/versions.json")
    mapfile -t build_steps_array < <(jq -r --arg pkg "$target" '.[$pkg]?.build_steps? // [] | .[]' "${script_path}/versions.json")
    mapfile -t external_build_steps_array < <(jq -r --arg pkg "$target" '.[$pkg]?.external_build_steps? // [] | .[]' "${script_path}/versions.json")
    mapfile -t fpm_dirs_array < <(jq -r --arg pkg "$target" '.[$pkg]?.fpm_directories? // [] | .[]' "${script_path}/versions.json")

    enable_sha=$(get_field "$target" "enable_sha") || enable_sha="false"
    [[ "$enable_sha" == "null" ]] && enable_sha="false"

    git_repo=$(get_field "$target" "git_repository") || git_repo="https://github.com/irods/${target}" # Default repo
    [[ "$git_repo" == "null" ]] && git_repo="https://github.com/irods/${target}"

    commitish=$(get_field "$target" "commitish") || error_exit "Missing 'commitish' for '$target'"
    [[ "$commitish" == "null" ]] && error_exit "Missing 'commitish' for '$target' in versions.json"


    # Define paths
    local package_subdirectory="${target}${version_string}-${consortium_build_number}"
    local build_dir="${script_path}/${package_subdirectory}_src"
    local install_prefix="${build_dir}/${externals_root}/${package_subdirectory}"

    echo "Install prefix: $install_prefix"
    mkdir -p "$install_prefix" || error_exit "Failed to create install prefix '$install_prefix'"

    # --- Patching ---
    apply_patches() {
        if [[ ${#patches_array[@]} -gt 0 && -n "${patches_array[0]}" ]]; then # Check if array is non-empty and first element isn't empty
            local patch_dir="${script_path}/patches"
            local patch patch_path
            echo "Applying patches..."
            for patch in "${patches_array[@]}"; do
                [[ -z "$patch" ]] && continue # Skip empty lines
                echo "Applying patch [$patch]"
                patch_path="${patch_dir}/${patch}"
                if [[ ! -f "$patch_path" ]]; then
                    error_exit "Patch file not found: $patch_path"
                fi
                # Use patch command directly
                patch -p1 --dry-run -i "$patch_path" < /dev/null || error_exit "Patch dry run failed for $patch"
                patch -p1 -i "$patch_path" < /dev/null || error_exit "Failed to apply patch $patch (patch may be partially applied)"
            done
        else
            echo "No patches specified or found for $target."
        fi
    }

    # --- Get Source Code ---
    local target_dir # Directory where build commands will run
    if [[ "$target" == "clang" ]]; then
        target_dir="${build_dir}/llvm-project" # Special case for clang source structure
        # Ensure build subdirectory exists for CMake out-of-source build
        mkdir -p "${build_dir}/build" || error_exit "Failed to create build dir for clang"
        if [[ ! -d "$target_dir" ]]; then
            mkdir -p "$build_dir" || error_exit "Failed to create base build dir for clang"
            cd "$build_dir" || error_exit "Failed to cd into $build_dir"
            echo "Cloning Clang/LLVM project (commitish: $commitish)..."
            # Clone only the specific branch/tag to save time/space
            run_cmd "git clone --depth 1 --branch \"$commitish\" https://github.com/irods/llvm-project" "git clone failed for clang"
            cd "$target_dir" || error_exit "Failed to cd into $target_dir"
            echo "Applying patches to Clang/LLVM..."
            apply_patches
        else
            echo "Clang source directory already exists: $target_dir"
            cd "$target_dir" || error_exit "Failed to cd into $target_dir"
        fi
    elif [[ "$target" == "clang-runtime" ]]; then
        # clang-runtime doesn't have source, just build steps
        target_dir="${build_dir}/${target}" # Use a dedicated directory
        mkdir -p "$target_dir" || error_exit "Failed to create directory for clang-runtime"
        cd "$target_dir" || error_exit "Failed to cd into $target_dir"
    else
        # Standard package source handling
        target_dir="${build_dir}/${target}"
        if [[ ! -d "$target_dir" ]]; then
            mkdir -p "$build_dir" || error_exit "Failed to create base build dir for $target"
            cd "$build_dir" || error_exit "Failed to cd into $build_dir"
            echo "Cloning source for $target (repo: $git_repo, commitish: $commitish)..."
            local git_cmd_array=("git" "clone" "--recurse-submodules")

            if [[ "$enable_sha" == "true" ]]; then
                # Clone full history if checking out a specific SHA
                git_cmd_array+=("$git_repo" "$target")
                run_cmd "${git_cmd_array[*]}" "git clone failed for $target"
                cd "$target_dir" || error_exit "Failed to cd into $target_dir"
                # Fetch might not be needed if clone worked, but doesn't hurt
                # run_cmd "git fetch" "git fetch failed for $target"
                run_cmd "git checkout \"$commitish\"" "git checkout failed for $target"
            else
                # Clone only the specific branch/tag with depth 1
                git_cmd_array+=("--depth" "1" "--branch" "$commitish" "$git_repo" "$target")
                run_cmd "${git_cmd_array[*]}" "git clone failed for $target"
                cd "$target_dir" || error_exit "Failed to cd into $target_dir"
            fi
            echo "Applying patches to $target..."
            apply_patches
        else
            echo "Source directory already exists: $target_dir"
            cd "$target_dir" || error_exit "Failed to cd into $target_dir"
        fi
    fi
    echo "Current directory for build: $(pwd)"

    # --- Prepare Build Environment ---
    # Note: RVM PATH/GEM_HOME setup is now done in main()

    # Prepare paths to dependencies and executables needed for template replacement
    local python_executable cmake_executable
    # Ensure python3 is available
    if ! python_executable=$(command -v python3); then
         error_exit "python3 command not found in PATH"
    fi
    echo "Python executable: [$python_executable]"

    # CMake is built first, so its local path should exist if needed
    # Add check if target is not cmake itself
    if [[ "$target" != "cmake" ]]; then
        if ! cmake_executable=$(get_local_path "cmake" "bin" "cmake"); then
             error_exit "Could not determine cmake path via get_local_path"
        fi
         echo "CMake executable: [$cmake_executable]"
    else
        # CMake is building itself, doesn't need path to external cmake
        cmake_executable="cmake" # Or leave empty? Build steps might handle it.
         echo "CMake target building itself."
    fi


    # Get local paths for dependencies (only those potentially needed in templates)
    # Use helper function to safely get paths, return empty string if dep not found/built?
    safe_get_local_path() {
        get_local_path "$@" 2>/dev/null || echo ""
    }
    local cppzmq_root avro_libcxx_root boost_libcxx_root fmt_libcxx_root json_root libarchive_root zmq_libcxx_root
    cppzmq_root=$(safe_get_local_path "cppzmq")
    avro_libcxx_root=$(safe_get_local_path "avro-libcxx")
    boost_libcxx_root=$(safe_get_local_path "boost-libcxx")
    fmt_libcxx_root=$(safe_get_local_path "fmt-libcxx")
    json_root=$(safe_get_local_path "json")
    libarchive_root=$(safe_get_local_path "libarchive")
    zmq_libcxx_root=$(safe_get_local_path "zeromq4-1-libcxx")

    # Calculate RPATHs (pointing to final /opt install location)
    get_rpath() {
        local pkg="$1"
        local ver build ext_root subdir prefix rpath
        # Add check if get_field fails
        ver=$(get_field "$pkg" "version_string") || { echo "Warning: Could not get version_string for rpath of $pkg" >&2; return 1; }
        build=$(get_field "$pkg" "consortium_build_number") || { echo "Warning: Could not get build_number for rpath of $pkg" >&2; return 1; }
        ext_root="/opt/irods-externals" # Final install root
        subdir="${pkg}${ver}-${build}"
        prefix="${ext_root}/${subdir}"
        rpath="${prefix}/lib" # Assume libraries are in 'lib'
        # Check if lib64 exists? Might be needed for some distros/packages
        # if [[ -d "${prefix}/lib64" ]]; then rpath="${prefix}/lib64:${rpath}"; fi
        echo "$rpath"
    }
    local boost_libcxx_rpath fmt_libcxx_rpath avro_libcxx_rpath libarchive_rpath zmq_libcxx_rpath clang_runtime_rpath qpid_proton_libcxx_rpath
    boost_libcxx_rpath=$(get_rpath "boost-libcxx") || boost_libcxx_rpath=""
    fmt_libcxx_rpath=$(get_rpath "fmt-libcxx") || fmt_libcxx_rpath=""
    avro_libcxx_rpath=$(get_rpath "avro-libcxx") || avro_libcxx_rpath=""
    libarchive_rpath=$(get_rpath "libarchive") || libarchive_rpath=""
    zmq_libcxx_rpath=$(get_rpath "zeromq4-1-libcxx") || zmq_libcxx_rpath=""
    clang_runtime_rpath=$(get_rpath "clang-runtime") || clang_runtime_rpath=""
    qpid_proton_libcxx_rpath=$(get_rpath "qpid-proton-libcxx") || qpid_proton_libcxx_rpath=""

    # Clang specific paths (using locally built clang)
    local clang_build_root clang_executable clangpp_executable clang_cpp_headers clang_cpp_libraries clang_subdirectory
    # Only define these if clang has been built (i.e., target is not clang or cmake)
    if [[ "$target" != "clang" && "$target" != "cmake" ]]; then
        clang_build_root=$(get_local_path "clang") || error_exit "Could not get clang build root"
        clang_executable="${clang_build_root}/bin/clang"
        clangpp_executable="${clang_build_root}/bin/clang++"
        clang_cpp_headers="${clang_build_root}/include/c++/v1" # Path to libc++ headers
        clang_cpp_libraries="${clang_build_root}/lib"          # Path to libc++ libraries
        clang_subdirectory="clang$(get_field clang version_string)-$(get_field clang consortium_build_number)" || clang_subdirectory="clang-unknown"

        # Set CC/CXX environment variables for build steps that need clang
        # Export them so they are available to sub-processes run by run_cmd
        echo "Setting CC/CXX to use local clang..."
        export CC="${clang_executable}"
        export CXX="${clangpp_executable}"
        echo "CC=$CC"
        echo "CXX=$CXX"
        # Also add clang's bin to PATH for this build step's duration
        local clang_bindir
        clang_bindir=$(dirname "$clang_executable")
        set_environ_path "$clang_bindir" # Modifies exported PATH
        echo "Updated PATH for build: $PATH"
    else
        # Avoid errors when building clang/cmake itself
        clang_executable="clang"
        clangpp_executable="clang++"
        clang_cpp_headers="/usr/include/c++/v1" # Placeholder
        clang_cpp_libraries="/usr/lib"          # Placeholder
        clang_subdirectory="clang-building"
        echo "Building clang or cmake, using system compilers initially."
    fi


    # GCC path (optional, from environment)
    local clang_gcc_install_prefix="${IRODS_EXTERNALS_GCC_PREFIX:-}"


    # --- Execute Build Steps ---
    echo "Processing build steps for $target..."
    local all_build_steps=("${build_steps_array[@]}" "${external_build_steps_array[@]}")

    if [[ ${#all_build_steps[@]} -eq 0 && "$target" != "clang-runtime" ]]; then
        echo "Warning: No build steps found for $target."
    fi

    local i # Loop variable for build step command
    for i in "${all_build_steps[@]}"; do
        [[ -z "$i" ]] && continue # Skip empty lines

        # Replace placeholders using parameter expansion for safety
        i=${i//TEMPLATE_JOBS/$(get_jobs)}
        i=${i//TEMPLATE_SCRIPT_PATH/$script_path}
        i=${i//TEMPLATE_INSTALL_PREFIX/$install_prefix}
        i=${i//TEMPLATE_GCC_INSTALL_PREFIX/$clang_gcc_install_prefix}
        i=${i//TEMPLATE_CLANG_CPP_HEADERS/$clang_cpp_headers}
        i=${i//TEMPLATE_CLANG_CPP_LIBRARIES/$clang_cpp_libraries}
        i=${i//TEMPLATE_CLANG_SUBDIRECTORY/$clang_subdirectory}
        i=${i//TEMPLATE_CLANG_EXECUTABLE/$clang_executable}
        i=${i//TEMPLATE_CLANGPP_EXECUTABLE/$clangpp_executable}
        i=${i//TEMPLATE_CLANG_RUNTIME_RPATH/$clang_runtime_rpath}
        i=${i//TEMPLATE_CMAKE_EXECUTABLE/$cmake_executable}
        # Note: Removed references to non-libcxx paths/roots (boost_root, avro_path, etc.)
        # Ensure templates in versions.json only use the libcxx versions where applicable
        local qpid_proton_libcxx_subdir="qpid-proton-libcxx$(get_field qpid-proton-libcxx version_string)-$(get_field qpid-proton-libcxx consortium_build_number)" || qpid_proton_libcxx_subdir=""
        i=${i//TEMPLATE_QPID_PROTON_LIBCXX_SUBDIRECTORY/$qpid_proton_libcxx_subdir} # Added LIBCXX here
        # i=${i//TEMPLATE_QPID_PROTON_RPATH/$qpid_proton_rpath} # Removed non-libcxx
        i=${i//TEMPLATE_QPID_PROTON_LIBCXX_RPATH/$qpid_proton_libcxx_rpath}
        i=${i//TEMPLATE_PYTHON_EXECUTABLE/$python_executable}
        # i=${i//TEMPLATE_BOOST_ROOT/$boost_root} # Removed non-libcxx
        i=${i//TEMPLATE_BOOST_LIBCXX_ROOT/$boost_libcxx_root}
        # i=${i//TEMPLATE_BOOST_RPATH/$boost_rpath} # Removed non-libcxx
        i=${i//TEMPLATE_BOOST_LIBCXX_RPATH/$boost_libcxx_rpath}
        i=${i//TEMPLATE_LIBARCHIVE_PATH/$libarchive_root} # Common dependency
        i=${i//TEMPLATE_LIBARCHIVE_RPATH/$libarchive_rpath} # Common dependency
        # i=${i//TEMPLATE_AVRO_RPATH/$avro_rpath} # Removed non-libcxx
        # i=${i//TEMPLATE_AVRO_PATH/$avro_root} # Removed non-libcxx
        i=${i//TEMPLATE_AVRO_LIBCXX_RPATH/$avro_libcxx_rpath}
        i=${i//TEMPLATE_AVRO_LIBCXX_PATH/$avro_libcxx_root}
        # i=${i//TEMPLATE_ZMQ_RPATH/$zmq_rpath} # Removed non-libcxx
        # i=${i//TEMPLATE_ZMQ_PATH/$zmq_root} # Removed non-libcxx
        i=${i//TEMPLATE_ZMQ_LIBCXX_RPATH/$zmq_libcxx_rpath}
        i=${i//TEMPLATE_ZMQ_LIBCXX_PATH/$zmq_libcxx_root} # Added LIBCXX path
        i=${i//TEMPLATE_CPPZMQ_PATH/$cppzmq_root} # Common dependency
        # i=${i//TEMPLATE_FMT_PATH/$fmt_root} # Removed non-libcxx
        # i=${i//TEMPLATE_FMT_RPATH/$fmt_rpath} # Removed non-libcxx
        i=${i//TEMPLATE_FMT_LIBCXX_PATH/$fmt_libcxx_root}
        i=${i//TEMPLATE_FMT_LIBCXX_RPATH/$fmt_libcxx_rpath}
        i=${i//TEMPLATE_JSON_PATH/$json_root} # Common dependency

        # Run the processed build step command
        run_cmd "$i" "Build step failed for $target"
    done

    # --- Packaging Step ---
    if [[ "$build_native_package" != "true" ]]; then
        echo "Skipping packaging for [$target]."
        echo "--- Building [$target] ... Build Complete (No Packaging) ---"
        # Clean up exported CC/CXX? Maybe not necessary if script exits soon.
        return
    fi

    echo "Packaging [$target]..."

    # Ensure fpm is available (using the PATH set in main())
    local fpm_binary
    fpm_binary=$(which fpm) || fpm_binary=""
    if [[ -z "$fpm_binary" ]]; then
        # Attempt to install fpm if not found - requires gem to be in PATH and working
        echo "fpm not found, attempting to install fpm 1.14.1..."
        if ! command -v gem >/dev/null; then error_exit "gem command not found (needed to install fpm)"; fi
        # Run gem install using the ruby environment set up via PATH/GEM_HOME
        gem install -v 1.14.1 fpm --no-document || error_exit "Failed to install fpm via gem"
        fpm_binary=$(which fpm) || error_exit "fpm still not found after install attempt"
        echo "Installed fpm: $fpm_binary"
    else
         echo "Found fpm at: $fpm_binary"
    fi

    # Change to the script directory before running fpm
    cd "$script_path" || error_exit "Failed to cd to script path '$script_path' before packaging"

    # Construct fpm command array
    local package_cmd=("$fpm_binary" "-f" "-s" "dir") # -f overwrites existing package
    package_cmd+=("-t" "$(get_package_type)")
    package_cmd+=("-n" "$(get_package_name_string "$target")")
    package_cmd+=("-v" "$(get_package_version "$target")")
    package_cmd+=("-a" "$(get_package_architecture_string)")
    package_cmd+=("--iteration" "$(get_package_revision "$target")")

    # Add RPM specific tag for clang-runtime if needed
    if [[ "$(get_package_type)" == "rpm" && "$target" == "clang-runtime" ]]; then
        package_cmd+=("--rpm-tag" "%define _build_id_links none")
    fi

    # Add dependencies
    local deps_string dep_array
    deps_string=$(get_package_dependencies "$target") || error_exit "Dependency calculation failed for $target"
    if [[ -n "$deps_string" ]]; then
        # Split string into array based on spaces
        read -r -a dep_array <<< "$deps_string"
        echo "Adding dependencies: ${dep_array[*]}"
        for d in "${dep_array[@]}"; do
            package_cmd+=("-d" "$d")
        done
    else
         echo "No dependencies calculated for $target."
    fi

    # Add metadata
    package_cmd+=("-m" "<packages@irods.org>")
    package_cmd+=("--vendor" "iRODS Consortium")
    package_cmd+=("--license" "$license")
    package_cmd+=("--description" "iRODS Build Dependency: $target")
    package_cmd+=("--url" "https://irods.org")
    # Set the source directory for fpm
    package_cmd+=("-C" "$build_dir")

    # Determine files/directories to package
    local files_to_package=()
    # Check if fpm_dirs_array is non-empty and first element is non-empty
    if [[ ${#fpm_dirs_array[@]} -gt 0 && -n "${fpm_dirs_array[0]}" ]]; then
        local fpm_dir addpath fullpath
        for fpm_dir in "${fpm_dirs_array[@]}"; do
             [[ -z "$fpm_dir" ]] && continue # Skip empty lines
            # Path relative to build_dir for fpm's -C option
            addpath="${externals_root}/${package_subdirectory}/${fpm_dir}"
            # Full path to check existence
            fullpath="${install_prefix}/${fpm_dir}"
            if [[ -e "$fullpath" ]]; then
                files_to_package+=("$addpath")
            else
                echo "Skipping [$fullpath] for packaging (does not exist in staging area)"
            fi
        done
    else
        echo "Warning: No fpm_directories specified or found for $target in versions.json. Package may be empty."
    fi

    # Add files/dirs to fpm command if any were found
    if [[ ${#files_to_package[@]} -gt 0 ]]; then
        package_cmd+=("${files_to_package[@]}")
    else
        # If no files were found based on fpm_directories, should we error or create empty?
        # The original python script used touch_file here. Let's mimic that for now,
        # although creating an empty RPM might be unexpected.
        echo "No valid files/directories found to package for $target based on fpm_directories. Creating empty placeholder file."
        touch_file "$(get_package_filename "$target")"
        echo "--- Building [$target] ... Complete (Empty Placeholder Created) ---"
        return # Skip running fpm
    fi

    # Run fpm
    echo "Running FPM command:"
    printf "%q " "${package_cmd[@]}" # Print quoted command for debugging
    echo
    # Execute the fpm command array safely
    "${package_cmd[@]}" || error_exit "FPM packaging failed for $target"

    echo "--- Building [$target] ... Complete ---"
    # Clean up exported CC/CXX?
    # unset CC CXX # Maybe? Or let the script exit manage env cleanup.
}

# --- Main Execution Logic ---
main() {
    # Check essential command dependencies
    command -v jq >/dev/null 2>&1 || error_exit "'jq' command is required but not installed."
    command -v git >/dev/null 2>&1 || error_exit "'git' command is required but not installed."
    command -v patch >/dev/null 2>&1 || error_exit "'patch' command is required but not installed."
    command -v nproc >/dev/null 2>&1 || error_exit "'nproc' command is required but not installed."
    command -v arch >/dev/null 2>&1 || error_exit "'arch' command is required but not installed."
    command -v realpath >/dev/null 2>&1 || error_exit "'realpath' command is required but not installed."
    command -v dirname >/dev/null 2>&1 || error_exit "'dirname' command is required but not installed."
    command -v mkdir >/dev/null 2>&1 || error_exit "'mkdir' command is required but not installed."
    # command -v cd >/dev/null 2>&1 || error_exit "'cd' command is required but not installed." # cd is shell builtin
    command -v rm >/dev/null 2>&1 || error_exit "'rm' command is required but not installed."
    command -v cp >/dev/null 2>&1 || error_exit "'cp' command is required but not installed."
    command -v ls >/dev/null 2>&1 || error_exit "'ls' command is required but not installed."
    command -v touch >/dev/null 2>&1 || error_exit "'touch' command is required but not installed."
    command -v sleep >/dev/null 2>&1 || error_exit "'sleep' command is required but not installed."
    command -v printf >/dev/null 2>&1 || error_exit "'printf' command is required but not installed."
    command -v sed >/dev/null 2>&1 || error_exit "'sed' command is required but not installed."
    command -v tr >/dev/null 2>&1 || error_exit "'tr' command is required but not installed."


    # Argument Parsing using getopt (more robust than manual loop)
    local target=""
    local build_native_package="true" # Default to packaging
    local verbosity=1 # Default verbosity

    # Use getopt to parse options - adjust based on needed options
    # Example: TEMP=$(getopt -o vqp:n --long verbose,quiet,package:,no-package -n "$0" -- "$@")
    # This part needs careful implementation if complex options are needed.
    # Sticking to the simpler loop for now, matching previous script.

    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                # Increase verbosity - could use a counter if needed
                verbosity=$((verbosity + 1))
                shift
                ;;
            -q|--quiet)
                verbosity=0
                shift
                ;;
            -p|--package)
                build_native_package="true"
                shift
                ;;
            -n|--no-package)
                build_native_package="false"
                shift
                ;;
            -*)
                # Handle unknown options
                error_exit "Unknown option: $1"
                ;;
            *)
                # Assume it's the target argument
                args+=("$1")
                shift
                ;;
        esac
    done

    # Basic logging setup based on verbosity
    if [[ "$verbosity" -le 0 ]]; then
         echo "Quiet mode enabled."
         # Redirect stdout/stderr? Maybe not needed if script is quiet.
    elif [[ "$verbosity" -ge 2 ]]; then
         echo "Verbose mode enabled (set -x)."
         set -x # Print commands
    fi

    # Validate arguments
    if [[ ${#args[@]} -ne 1 ]]; then
        echo "Usage: $0 [options] <target>" >&2
        echo "Options:" >&2
        echo "  -v, --verbose      Increase verbosity level (set -x at level 2+)" >&2
        echo "  -q, --quiet        Decrease verbosity level" >&2
        echo "  -p, --package      Build package (default)" >&2
        echo "  -n, --no-package   Skip package building" >&2
        echo "Available targets: " >&2
        jq -r 'keys[] | select(. != "comment")' "${script_path}/versions.json" | sort | paste -sd ' ' - >&2 || echo "(Could not read targets from versions.json)" >&2
        exit 1
    fi
    target="${args[0]}"

    # --- Main Logic ---
    if [[ "$target" == "packagesfile" ]]; then
        # Generate packages.mk
        echo "Generating packages.mk..."
        local packages_mk_file="${script_path}/packages.mk"
        # Ensure versions.json exists
        [[ ! -f "${script_path}/versions.json" ]] && error_exit "versions.json not found at '${script_path}/versions.json'"
        # Get package keys, sort them
        local packages
        # Ensure jq can read the file before proceeding
        jq -e . "${script_path}/versions.json" > /dev/null || error_exit "versions.json is not valid JSON or not readable."
        mapfile -t packages < <(jq -r 'keys[] | select(. != "comment")' "${script_path}/versions.json" | sort)
        # Write header
        echo "# Auto-generated by build.sh" > "$packages_mk_file" || error_exit "Failed to write to $packages_mk_file"
        echo "" >> "$packages_mk_file"
        # Loop through packages and generate definitions
        local p filename pkg_var
        for p in "${packages[@]}"; do
            # Add check to ensure get_package_filename succeeds
            if filename=$(get_package_filename "$p"); then
                # Convert package name to uppercase Makefile variable name
                pkg_var=$(echo "$p" | tr '[:lower:]-' '[:upper:]_')
                echo "${pkg_var}_PACKAGE=$filename" >> "$packages_mk_file" || error_exit "Failed to write to $packages_mk_file"
            else
                echo "Warning: Failed to generate filename for package '$p'. Skipping in packages.mk." >&2
                # Optionally exit here if this is critical: error_exit "..."
            fi
        done
        echo "Generated $packages_mk_file"

    elif jq -e --arg pkg "$target" '.[$pkg]' "${script_path}/versions.json" >/dev/null; then
        # Build a specific package target

        # --- RVM/Ruby Environment Setup (Python Style) ---
        echo "Setting up Ruby environment using PATH and GEM_HOME..."
        local ruby_bin_path="${rvm_path}/rubies/ruby-${ruby_version}/bin"
        local rvm_bin_path="${rvm_path}/bin"
        local gem_home="${rvm_path}/gems/ruby-${ruby_version}"
        local gem_path="${gem_home}:${gem_home}@global" # Typical RVM GEM_PATH

        set_environ_path "$ruby_bin_path" # Add specific ruby bin to PATH
        set_environ_path "$rvm_bin_path"  # Add rvm base bin to PATH (for rvm commands if needed, though we avoid 'use')

        export GEM_HOME="$gem_home"
        export GEM_PATH="$gem_path"
        echo "GEM_HOME=$GEM_HOME"
        echo "GEM_PATH=$GEM_PATH"
        echo "PATH=$PATH" # Show the modified PATH for verification

        # Call the build function for the target
        build_package "$target" "$build_native_package"

    else
        # Invalid target
        echo "Error: Build target [$target] not found or invalid in versions.json" >&2
        echo "Available targets: " >&2
        jq -r 'keys[] | select(. != "comment")' "${script_path}/versions.json" | sort | paste -sd ' ' - >&2 || echo "(Could not read targets from versions.json)" >&2
        exit 1
    fi
}

# Execute the main function with all script arguments
main "$@"


