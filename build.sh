#!/bin/bash

set -euo pipefail

script_path=$(dirname "$(realpath "$0")")

ruby_version="3.1.2"
ruby_path="/usr/local/rvm/bin"

TARGET_DISTRO="rhel"
TARGET_VERSION="8"

error_exit() {
    echo "Error: $1" >&2
    exit 1
}

touch_file() {
    touch "$1"
}

set_environ_path() {
    export PATH="$1:$PATH"
}

set_clang_path() {
    :
}

get_version_info_obj() {
    local package="$1"
    local versions_json="${script_path}/versions.json"
    if [[ ! -f "$versions_json" ]]; then
        error_exit "versions.json not found at '$versions_json'"
    fi
    jq -c --arg pkg "$package" '.[$pkg]' "$versions_json" || error_exit "Failed to get version info for '$package'"
}

get_field() {
    local pkg="$1"
    local field="$2"
    local versions_json="${script_path}/versions.json"
    jq -re --arg pkg "$pkg" --arg fld "$field" '.[$pkg][$fld]' "$versions_json"
}

get_full_external_package_name() {
    local pkg="$1"
    local versions_json="${script_path}/versions.json"

    local version_string
    local build_number

    version_string=$(get_field "$pkg" "version_string") || error_exit "Cannot get 'version_string' for dependency '$pkg'"
    build_number=$(get_field "$pkg" "consortium_build_number") || error_exit "Cannot get 'consortium_build_number' for dependency '$pkg'"

    if [[ "$version_string" == "null" || "$build_number" == "null" ]]; then
        error_exit "Missing version/build info for dependency '$pkg' in $versions_json"
    fi

    echo "irods-externals-${pkg}${version_string}-${build_number}"
}

get_local_path() {
    local package_name="$1"
    local path_elements=("${@:2}")

    local version_string
    local build_number
    local externals_root

    version_string=$(get_field "$package_name" "version_string") || error_exit "Cannot get 'version_string' for '$package_name' in get_local_path"
    build_number=$(get_field "$package_name" "consortium_build_number") || error_exit "Cannot get 'consortium_build_number' for '$package_name' in get_local_path"
    externals_root=$(get_field "$package_name" "externals_root") || error_exit "Cannot get 'externals_root' for '$package_name' in get_local_path"

    if [[ "$version_string" == "null" || "$build_number" == "null" || "$externals_root" == "null" ]]; then
         error_exit "Missing version/build/root info for '$package_name' in get_local_path"
    fi

    local path_name="${package_name}${version_string}-${build_number}"
    local local_path="${script_path}/${path_name}_src/${externals_root}/${path_name}"

    for element in "${path_elements[@]}"; do
        local_path="${local_path}/${element}"
    done

    echo "$local_path"
}

run_cmd() {
    local cmd="$1"
    local check_rc_msg="${2:-Command failed}"
    local retries="${3:-0}"

    echo "Running: $cmd"

    if [[ "$retries" -gt 0 ]]; then
        if ! eval "$cmd"; then
            echo "Command failed. Retrying ($retries left)..." >&2
            sleep 1
            run_cmd "$cmd" "$check_rc_msg" "$((retries - 1))"
        fi
    else
        eval "$cmd" || error_exit "$check_rc_msg"
    fi
}

get_package_name_string() {
    local p="$1"
    local version_string
    local build_number
    version_string=$(get_field "$p" "version_string") || error_exit "Cannot get 'version_string' for '$p' in get_package_name_string"
    build_number=$(get_field "$p" "consortium_build_number") || error_exit "Cannot get 'consortium_build_number' for '$p' in get_package_name_string"
    echo "irods-externals-${p}${version_string}-${build_number}"
}

get_package_version() {
    echo "1.0"
}

get_package_revision() {
    local p="$1"
    local ver_pkgrev
    ver_pkgrev=$(jq -re --arg pkg "$p" '.[$pkg].package_revision // "0"' "${script_path}/versions.json")
    echo "${ver_pkgrev}.el8.10"
}

get_distro_type() { echo "rhel"; }
get_distro_version() { echo "8.10"; }
get_package_type() { echo "rpm"; }
get_package_extension() { echo "rpm"; }
get_package_architecture_string() { arch; }

get_package_filename() {
    local p="$1"
    local n v r a t
    n=$(get_package_name_string "$p")
    v=$(get_package_version "$p")
    r=$(get_package_revision "$p")
    a=$(get_package_architecture_string)
    t=$(get_package_extension)
    echo "${n}-${v}-${r}.${a}.${t}"
}

get_package_dependencies() {
    local package_name="$1"
    local versions_json="${script_path}/versions.json"

    command -v jq >/dev/null 2>&1 || error_exit "'jq' command is required but not found."

    local distro_deps_query=".[\"$package_name\"].distro_dependencies[\"$TARGET_DISTRO\"][\"$TARGET_VERSION\"] // [] | .[]"
    local distro_deps
    distro_deps=$(jq -r "$distro_deps_query" "$versions_json" | tr '\n' ' ')
    distro_deps=$(echo "$distro_deps" | sed 's/ *$//')

    local interdep_names_query=".[\"$package_name\"].interdependencies // [] | .[]"
    local interdep_names
    interdep_names=$(jq -r "$interdep_names_query" "$versions_json")

    local full_interdeps=""
    if [[ -n "$interdep_names" ]]; then
        local dep_name full_dep_name
        while IFS= read -r dep_name; do
            [[ -z "$dep_name" ]] && continue
            full_dep_name=$(get_full_external_package_name "$dep_name")
            full_interdeps+="$full_dep_name "
        done <<< "$interdep_names"
        full_interdeps=$(echo "$full_interdeps" | sed 's/ *$//')
    fi

    local all_deps=""
    if [[ -n "$distro_deps" ]]; then
        all_deps+="$distro_deps"
    fi
    if [[ -n "$full_interdeps" ]]; then
        [[ -n "$all_deps" ]] && all_deps+=" "
        all_deps+="$full_interdeps"
    fi

    echo "$all_deps"
}

get_jobs() {
    local detected jobs_to_use
    detected=$(nproc)
    jobs_to_use=$((detected > 1 ? detected - 1 : detected))
    echo "$jobs_to_use"
}

build_package() {
    local target="$1"
    local build_native_package="$2"

    echo "--- Building [$target] ---"

    local version_string consortium_build_number externals_root license patches_str build_steps_str external_build_steps_str fpm_dirs_str enable_sha git_repo commitish

    version_string=$(get_field "$target" "version_string") || error_exit "Missing 'version_string' for '$target'"
    consortium_build_number=$(get_field "$target" "consortium_build_number") || error_exit "Missing 'consortium_build_number' for '$target'"
    externals_root=$(get_field "$target" "externals_root") || error_exit "Missing 'externals_root' for '$target'"
    license=$(get_field "$target" "license") || license="Unknown"
    patches_str=$(jq -r --arg pkg "$target" '.[$pkg].patches // [] | .[]' "${script_path}/versions.json")
    build_steps_str=$(jq -r --arg pkg "$target" '.[$pkg].build_steps // [] | .[]' "${script_path}/versions.json")
    external_build_steps_str=$(jq -r --arg pkg "$target" '.[$pkg].external_build_steps // [] | .[]' "${script_path}/versions.json")
    fpm_dirs_str=$(jq -r --arg pkg "$target" '.[$pkg].fpm_directories // [] | .[]' "${script_path}/versions.json")
    enable_sha=$(get_field "$target" "enable_sha") || enable_sha="false"
    git_repo=$(get_field "$target" "git_repository") || git_repo="https://github.com/irods/${target}"
    commitish=$(get_field "$target" "commitish") || error_exit "Missing 'commitish' for '$target'"

    local package_subdirectory="${target}${version_string}-${consortium_build_number}"
    local build_dir="${script_path}/${package_subdirectory}_src"
    local install_prefix="${build_dir}/${externals_root}/${package_subdirectory}"

    echo "Install prefix: $install_prefix"
    mkdir -p "$install_prefix"

    apply_patches() {
        if [[ -n "$patches_str" ]]; then
            local patch_dir="${script_path}/patches"
            local patch patch_path
            echo "$patches_str" | while IFS= read -r patch; do
                [[ -z "$patch" ]] && continue
                echo "Applying patch [$patch]"
                patch_path="${patch_dir}/${patch}"
                if [[ ! -f "$patch_path" ]]; then
                     error_exit "Patch file not found: $patch_path"
                fi
                patch -p1 --dry-run -i "$patch_path" < /dev/null || error_exit "Patch dry run failed for $patch"
                patch -p1 -i "$patch_path" < /dev/null || error_exit "Failed to apply patch $patch (patch may be partially applied)"
            done
        else
             echo "No patches specified for $target."
        fi
    }

    cd "$script_path"
    local python_executable cmake_executable
    python_executable=$(which python3) || error_exit "python3 not found in PATH"
    echo "Python executable: [$python_executable]"
    cmake_executable=$(get_local_path "cmake" "bin" "cmake") || error_exit "Could not determine cmake path"
    echo "CMake executable: [$cmake_executable]"

    local cppzmq_root zmq_root avro_root avro_libcxx_root boost_root boost_libcxx_root
    local fmt_root fmt_libcxx_root json_root libarchive_root
    cppzmq_root=$(get_local_path "cppzmq")
    zmq_root=$(get_local_path "zeromq4-1")
    avro_root=$(get_local_path "avro")
    avro_libcxx_root=$(get_local_path "avro-libcxx")
    boost_root=$(get_local_path "boost")
    boost_libcxx_root=$(get_local_path "boost-libcxx")
    fmt_root=$(get_local_path "fmt")
    fmt_libcxx_root=$(get_local_path "fmt-libcxx")
    json_root=$(get_local_path "json")
    libarchive_root=$(get_local_path "libarchive")

    get_rpath() {
        local pkg="$1"
        local ver build ext_root subdir prefix rpath
        ver=$(get_field "$pkg" "version_string")
        build=$(get_field "$pkg" "consortium_build_number")
        ext_root="/opt/irods-externals"
        subdir="${pkg}${ver}-${build}"
        prefix="${ext_root}/${subdir}"
        rpath="${prefix}/lib"
        echo "$rpath"
    }
    local boost_rpath boost_libcxx_rpath fmt_rpath fmt_libcxx_rpath avro_rpath avro_libcxx_rpath
    local libarchive_rpath zmq_rpath zmq_libcxx_rpath clang_runtime_rpath qpid_proton_rpath qpid_proton_libcxx_rpath
    boost_rpath=$(get_rpath "boost")
    boost_libcxx_rpath=$(get_rpath "boost-libcxx")
    fmt_rpath=$(get_rpath "fmt")
    fmt_libcxx_rpath=$(get_rpath "fmt-libcxx")
    avro_rpath=$(get_rpath "avro")
    avro_libcxx_rpath=$(get_rpath "avro-libcxx")
    libarchive_rpath=$(get_rpath "libarchive")
    zmq_rpath=$(get_rpath "zeromq4-1")
    zmq_libcxx_rpath=$(get_rpath "zeromq4-1-libcxx")
    clang_runtime_rpath=$(get_rpath "clang-runtime")
    qpid_proton_rpath=$(get_rpath "qpid-proton")
    qpid_proton_libcxx_rpath=$(get_rpath "qpid-proton-libcxx")

    local clang_info_obj clang_subdirectory clang_executable clangpp_executable clang_cpp_headers clang_cpp_libraries
    clang_subdirectory="clang$(get_field clang version_string)-$(get_field clang consortium_build_number)"
    local clang_build_root
    clang_build_root=$(get_local_path "clang")
    clang_executable="${clang_build_root}/bin/clang"
    clangpp_executable="${clang_build_root}/bin/clang++"
    clang_cpp_headers="${clang_build_root}/include/c++/v1"
    clang_cpp_libraries="${clang_build_root}/lib"
    local clang_gcc_install_prefix="${IRODS_EXTERNALS_GCC_PREFIX:-}"

    local target_dir
    if [[ "$target" == "clang" ]]; then
        target_dir="${build_dir}/llvm-project"
        if [[ ! -d "${build_dir}/build" ]]; then
            mkdir -p "${build_dir}/build"
        fi
        if [[ ! -d "$target_dir" ]]; then
            mkdir -p "$build_dir"
            cd "$build_dir"
            echo "Cloning Clang/LLVM project (commitish: $commitish)..."
            git clone --depth 1 --branch "$commitish" https://github.com/irods/llvm-project || error_exit "git clone failed for clang"
            cd "$target_dir"
            echo "Applying patches to Clang/LLVM..."
            apply_patches
        else
            echo "Clang source directory already exists: $target_dir"
            cd "$target_dir"
        fi
    elif [[ "$target" == "clang-runtime" ]]; then
        target_dir="${build_dir}/${target}"
        if [[ ! -d "$target_dir" ]]; then
            echo "Creating directory for clang-runtime build steps..."
            mkdir -p "$target_dir"
        fi
         cd "$target_dir"
    else
        target_dir="${build_dir}/${target}"
        if [[ ! -d "$target_dir" ]]; then
            mkdir -p "$build_dir"
            cd "$build_dir"
            echo "Cloning source for $target (repo: $git_repo, commitish: $commitish)..."
            local git_cmd=("git" "clone" "--recurse-submodules")

            if [[ "$enable_sha" == "true" ]]; then
                git_cmd+=("$git_repo" "$target")
                "${git_cmd[@]}" || error_exit "git clone failed for $target"
                cd "$target_dir"
                git fetch || error_exit "git fetch failed for $target"
                git checkout "$commitish" || error_exit "git checkout failed for $target"
            else
                git_cmd+=("--depth" "1" "--branch" "$commitish" "$git_repo" "$target")
                "${git_cmd[@]}" || error_exit "git clone failed for $target"
                cd "$target_dir"
            fi
            echo "Applying patches to $target..."
            apply_patches
        else
            echo "Source directory already exists: $target_dir"
            cd "$target_dir"
        fi
    fi
    echo "Current directory for build: $(pwd)"

    if [[ "$target" == "boost" || "$target" == "boost-libcxx" ]]; then
        echo "Setting up RVM environment for Boost build..."
        if [[ -f "$ruby_path/rvm" ]]; then
             source "$ruby_path/rvm" use "$ruby_version" || error_exit "Failed to source RVM or use $ruby_version"
        else
             error_exit "RVM script not found at $ruby_path/rvm"
        fi
    fi

    if [[ "$target" != "clang" && "$target" != "cmake" ]]; then
        echo "Setting CC/CXX to use local clang..."
        export CC="${clang_executable}"
        export CXX="${clangpp_executable}"
        echo "CC=$CC"
        echo "CXX=$CXX"
        local clang_bindir
        clang_bindir=$(dirname "$clang_executable")
        set_environ_path "$clang_bindir"
        echo "Updated PATH=$PATH"
    fi

    echo "Processing build steps for $target..."
    local all_build_steps=()
    mapfile -t build_steps_array <<< "$build_steps_str"
    mapfile -t external_build_steps_array <<< "$external_build_steps_str"
    all_build_steps=("${build_steps_array[@]}" "${external_build_steps_array[@]}")

    if [[ ${#all_build_steps[@]} -eq 0 && "$target" != "clang-runtime" ]]; then
         echo "Warning: No build steps found for $target."
    fi

    for i in "${all_build_steps[@]}"; do
        [[ -z "$i" ]] && continue

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
        local qpid_proton_subdir="qpid-proton$(get_field qpid-proton version_string)-$(get_field qpid-proton consortium_build_number)"
        local qpid_proton_libcxx_subdir="qpid-proton-libcxx$(get_field qpid-proton-libcxx version_string)-$(get_field qpid-proton-libcxx consortium_build_number)"
        i=${i//TEMPLATE_QPID_PROTON_SUBDIRECTORY/$qpid_proton_subdir}
        i=${i//TEMPLATE_QPID_PROTON_RPATH/$qpid_proton_rpath}
        i=${i//TEMPLATE_QPID_PROTON_LIBCXX_RPATH/$qpid_proton_libcxx_rpath}
        i=${i//TEMPLATE_PYTHON_EXECUTABLE/$python_executable}
        i=${i//TEMPLATE_BOOST_ROOT/$boost_root}
        i=${i//TEMPLATE_BOOST_LIBCXX_ROOT/$boost_libcxx_root}
        i=${i//TEMPLATE_BOOST_RPATH/$boost_rpath}
        i=${i//TEMPLATE_BOOST_LIBCXX_RPATH/$boost_libcxx_rpath}
        i=${i//TEMPLATE_LIBARCHIVE_PATH/$libarchive_root}
        i=${i//TEMPLATE_LIBARCHIVE_RPATH/$libarchive_rpath}
        i=${i//TEMPLATE_AVRO_RPATH/$avro_rpath}
        i=${i//TEMPLATE_AVRO_PATH/$avro_root}
        i=${i//TEMPLATE_AVRO_LIBCXX_RPATH/$avro_libcxx_rpath}
        i=${i//TEMPLATE_AVRO_LIBCXX_PATH/$avro_libcxx_root}
        i=${i//TEMPLATE_ZMQ_RPATH/$zmq_rpath}
        i=${i//TEMPLATE_ZMQ_PATH/$zmq_root}
        i=${i//TEMPLATE_ZMQ_LIBCXX_RPATH/$zmq_libcxx_rpath}
        i=${i//TEMPLATE_CPPZMQ_PATH/$cppzmq_root}
        i=${i//TEMPLATE_FMT_PATH/$fmt_root}
        i=${i//TEMPLATE_FMT_RPATH/$fmt_rpath}
        i=${i//TEMPLATE_FMT_LIBCXX_PATH/$fmt_libcxx_root}
        i=${i//TEMPLATE_FMT_LIBCXX_RPATH/$fmt_libcxx_rpath}
        i=${i//TEMPLATE_JSON_PATH/$json_root}

        run_cmd "$i" "Build step failed for $target"
    done

    if [[ "$build_native_package" != "true" ]]; then
        echo "Skipping packaging for [$target]."
        echo "--- Building [$target] ... Build Complete (No Packaging) ---"
        return
    fi

    echo "Packaging [$target]..."

    echo "Setting up RVM environment for FPM..."
     if [[ -f "$ruby_path/rvm" ]]; then
        source "$ruby_path/rvm" use "$ruby_version" || error_exit "Failed to source RVM or use $ruby_version for FPM"
    else
        error_exit "RVM script not found at $ruby_path/rvm for FPM"
    fi

    local fpm_binary
    fpm_binary=$(which fpm) || fpm_binary=""
    if [[ -z "$fpm_binary" ]]; then
        echo "fpm not found, attempting to install fpm 1.14.1..."
        if ! command -v gem >/dev/null; then error_exit "gem command not found after sourcing RVM"; fi
        gem install -v 1.14.1 fpm --no-document || error_exit "Failed to install fpm"
        fpm_binary=$(which fpm) || error_exit "fpm still not found after install attempt"
    else
         echo "Found fpm at: $fpm_binary"
    fi

    cd "$script_path"

    local package_cmd=("$fpm_binary" "-f" "-s" "dir")
    package_cmd+=("-t" "$(get_package_type)")
    package_cmd+=("-n" "$(get_package_name_string "$target")")
    package_cmd+=("-v" "$(get_package_version "$target")")
    package_cmd+=("-a" "$(get_package_architecture_string)")
    package_cmd+=("--iteration" "$(get_package_revision "$target")")

    if [[ "$target" == "clang-runtime" ]]; then
        package_cmd+=("--rpm-tag" "%define _build_id_links none")
    fi

    local deps_string dep_array
    deps_string=$(get_package_dependencies "$target") || error_exit "Dependency calculation failed for $target"

    if [[ -n "$deps_string" ]]; then
        read -ra dep_array <<< "$deps_string"
        echo "Adding dependencies: ${dep_array[*]}"
        for d in "${dep_array[@]}"; do
            package_cmd+=("-d" "$d")
        done
    else
         echo "No dependencies calculated for $target."
    fi

    package_cmd+=("-m" "<packages@irods.org>")
    package_cmd+=("--vendor" "iRODS Consortium")
    package_cmd+=("--license" "$license")
    package_cmd+=("--description" "iRODS Build Dependency: $target")
    package_cmd+=("--url" "https://irods.org")
    package_cmd+=("-C" "$build_dir")

    local fpm_dirs=()
    mapfile -t fpm_dirs <<< "$fpm_dirs_str"

    if [[ ${#fpm_dirs[@]} -eq 0 ]]; then
        echo "No fpm directories specified for $target. Creating empty package file."
        touch_file "$(get_package_filename "$target")"
    else
        local files_to_package=()
        for i in "${fpm_dirs[@]}"; do
            local addpath="${externals_root}/${package_subdirectory}/${i}"
            local fullpath="${install_prefix}/${i}"
            if [[ -e "$fullpath" ]]; then
                 files_to_package+=("$addpath")
            else
                 echo "Skipping [$fullpath] for packaging (does not exist)"
            fi
        done

        if [[ ${#files_to_package[@]} -gt 0 ]]; then
            package_cmd+=("${files_to_package[@]}")
            echo "Running FPM command:"
            printf "%q " "${package_cmd[@]}"
            echo
            "${package_cmd[@]}" || error_exit "FPM packaging failed for $target"
        else
             echo "No valid files/directories found to package for $target based on fpm_directories. Creating empty package file."
             touch_file "$(get_package_filename "$target")"
        fi
    fi

    echo "--- Building [$target] ... Complete ---"
}

main() {
    command -v jq >/dev/null 2>&1 || error_exit "'jq' command is required but not installed."
    command -v git >/dev/null 2>&1 || error_exit "'git' command is required but not installed."
    command -v patch >/dev/null 2>&1 || error_exit "'patch' command is required but not installed."
    command -v nproc >/dev/null 2>&1 || error_exit "'nproc' command is required but not installed."
    command -v arch >/dev/null 2>&1 || error_exit "'arch' command is required but not installed."
    command -v realpath >/dev/null 2>&1 || error_exit "'realpath' command is required but not installed."
    if [[ ! -x "$ruby_path/rvm" ]]; then
         error_exit "RVM executable not found or not executable at '$ruby_path/rvm'"
    fi

    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 [options] <target>"
        echo "Options:"
        echo "  -v, --verbose      Increase verbosity level (set -x)"
        echo "  -q, --quiet        Decrease verbosity level (suppress script echo)"
        echo "  -p, --package      Build package (default)"
        echo "  -n, --no-package   Skip package building"
        echo "Available targets: "
        jq -r 'keys[] | select(. != "comment")' "${script_path}/versions.json" | sort | paste -sd ' ' -
        exit 1
    fi

    local args=()
    local verbosity=1
    local package="true"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                verbosity=$((verbosity + 1))
                shift
                ;;
            -q|--quiet)
                verbosity=0
                shift
                ;;
            -p|--package)
                package="true"
                shift
                ;;
            -n|--no-package)
                package="false"
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    if [[ ${#args[@]} -ne 1 ]]; then
        error_exit "Incorrect number of arguments. Please provide exactly one target."
    fi

    if [[ "$verbosity" -le 0 ]]; then
         echo "Quiet mode enabled."
    elif [[ "$verbosity" -ge 2 ]]; then
         echo "Verbose mode enabled (set -x)."
         set -x
    fi

    local target="${args[0]}"

    if [[ "$target" == "packagesfile" ]]; then
        echo "Generating packages.mk..."
        local packages_mk_file="${script_path}/packages.mk"
        local packages
        packages=$(jq -r 'keys[] | select(. != "comment")' "${script_path}/versions.json" | sort)
        echo "# Auto-generated by buildv2.sh" > "$packages_mk_file"
        echo "" >> "$packages_mk_file"
        local p filename pkg_var
        while IFS= read -r p; do
            filename=$(get_package_filename "$p")
            pkg_var=$(echo "$p" | tr '[:lower:]-' '[:upper:]_')
            echo "${pkg_var}_PACKAGE=$filename" >> "$packages_mk_file"
        done <<< "$packages"
        echo "Generated $packages_mk_file"

    elif jq -e --arg pkg "$target" '.[$pkg]' "${script_path}/versions.json" >/dev/null; then
        build_package "$target" "$package"
    else
        echo "Error: Build target [$target] not found or invalid in versions.json" >&2
        echo "Available targets: " >&2
        jq -r 'keys[] | select(. != "comment")' "${script_path}/versions.json" | sort | paste -sd ' ' - >&2
        exit 1
    fi
}

main "$@"
