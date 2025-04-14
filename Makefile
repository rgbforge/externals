# Makefile for building external dependencies (libc++ focused)

# Build options: -v for verbosity (default: -p to package)
BUILD_OPTIONS = -v

# Include generated package definitions. Use -include to avoid errors
# if packages.mk doesn't exist on the very first run.
# This defines variables like $(AVRO_LIBCXX_PACKAGE).
-include packages.mk

# Generate the packages.mk file, which defines package-specific variables.
# Depends on versions.json and build.sh.
packages.mk: Makefile versions.json build.sh
	./build.sh packagesfile

# The "all" target: This is the main entry point.
# It now builds the server-libcxx target by default.
all: packages.mk server-libcxx

# --- Individual Targets ---
#
# Structure for each package:
# 1. $(PACKAGE_VAR): $(DEPENDENCY_PACKAGE_VARS...)
#    -> This rule defines the actual package file as the target.
#    -> It lists other *package files* it depends on.
#    -> The command runs build.sh to create the package file.
# 2. package-name: $(PACKAGE_VAR)
#    -> This is the convenience target you type (e.g., make avro-libcxx).
#    -> It simply depends on the package file being built.
#
# The '2>&1 | tee <package>.log' pattern shows output and logs it.

# --- Avro (libc++ only) ---
$(AVRO_LIBCXX_PACKAGE): $(BOOST_LIBCXX_PACKAGE) $(CMAKE_PACKAGE) $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) avro-libcxx 2>&1 | tee avro-libcxx.log
avro-libcxx: $(AVRO_LIBCXX_PACKAGE)

avro_clean:
	@echo "Cleaning avro..."
	@rm -rf avro* # Cleans both potential source dirs
	@rm -rf $(AVRO_LIBCXX_PACKAGE)

# --- Boost (libc++ only) ---
$(BOOST_LIBCXX_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) boost-libcxx 2>&1 | tee boost-libcxx.log
boost-libcxx: $(BOOST_LIBCXX_PACKAGE)

boost_clean:
	@echo "Cleaning boost..."
	@rm -rf boost* # Cleans both potential source dirs
	@rm -rf $(BOOST_LIBCXX_PACKAGE)

# --- Catch2 (Common dependency) ---
$(CATCH2_PACKAGE): $(CMAKE_PACKAGE)
	./build.sh $(BUILD_OPTIONS) catch2 2>&1 | tee catch2.log
catch2: $(CATCH2_PACKAGE)

catch2_clean:
	@echo "Cleaning catch2..."
	@rm -rf catch2*
	@rm -rf $(CATCH2_PACKAGE)

# --- Clang (Common dependency) ---
$(CLANG_PACKAGE): $(CMAKE_PACKAGE)
	./build.sh $(BUILD_OPTIONS) clang 2>&1 | tee clang.log
clang: $(CLANG_PACKAGE)

clang_clean:
	@echo "Cleaning clang..."
	@rm -rf clang*
	@rm -rf $(CLANG_PACKAGE)

# --- Clang Runtime (Common dependency) ---
$(CLANG_RUNTIME_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) clang-runtime 2>&1 | tee clang-runtime.log
clang-runtime: $(CLANG_RUNTIME_PACKAGE)

clang-runtime_clean:
	@echo "Cleaning clang-runtime..."
	@rm -rf clang-runtime*
	@rm -rf $(CLANG_RUNTIME_PACKAGE)

# --- CMake (Common dependency) ---
$(CMAKE_PACKAGE):
	./build.sh $(BUILD_OPTIONS) cmake 2>&1 | tee cmake.log
cmake: $(CMAKE_PACKAGE)

cmake_clean:
	@echo "Cleaning cmake..."
	@rm -rf cmake*
	@rm -rf $(CMAKE_PACKAGE)

# --- CppZMQ (Common dependency) ---
$(CPPZMQ_PACKAGE): $(ZEROMQ4_1_LIBCXX_PACKAGE) # Depends on the libc++ version of zeromq
	./build.sh $(BUILD_OPTIONS) cppzmq 2>&1 | tee cppzmq.log
cppzmq: $(CPPZMQ_PACKAGE)

cppzmq_clean:
	@echo "Cleaning cppzmq..."
	@rm -rf cppzmq*
	@rm -rf $(CPPZMQ_PACKAGE)

# --- fmt (libc++ only) ---
$(FMT_LIBCXX_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) fmt-libcxx 2>&1 | tee fmt-libcxx.log
fmt-libcxx: $(FMT_LIBCXX_PACKAGE)

fmt_clean:
	@echo "Cleaning fmt..."
	@rm -rf fmt* # Cleans both potential source dirs
	@rm -rf $(FMT_LIBCXX_PACKAGE)

# --- JSON (Common dependency) ---
$(JSON_PACKAGE): $(CMAKE_PACKAGE)
	./build.sh $(BUILD_OPTIONS) json 2>&1 | tee json.log
json: $(JSON_PACKAGE)

json_clean:
	@echo "Cleaning json..."
	@rm -rf json*
	@rm -rf $(JSON_PACKAGE)

# --- JSONCONS (Common dependency) ---
$(JSONCONS_PACKAGE): $(CMAKE_PACKAGE)
	./build.sh $(BUILD_OPTIONS) jsoncons 2>&1 | tee jsoncons.log
jsoncons: $(JSONCONS_PACKAGE)

jsoncons_clean:
	@echo "Cleaning jsoncons..."
	@rm -rf jsoncons*
	@rm -rf $(JSONCONS_PACKAGE)

# --- JWT-CPP (Common dependency) ---
$(JWT_CPP_PACKAGE): $(CMAKE_PACKAGE) $(JSON_PACKAGE)
	./build.sh $(BUILD_OPTIONS) jwt-cpp 2>&1 | tee jwt-cpp.log
jwt-cpp: $(JWT_CPP_PACKAGE)

jwt-cpp_clean:
	@echo "Cleaning jwt-cpp..."
	@rm -rf jwt-cpp*
	@rm -rf $(JWT_CPP_PACKAGE)

# --- Libarchive (Common dependency) ---
$(LIBARCHIVE_PACKAGE): $(CMAKE_PACKAGE) $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) libarchive 2>&1 | tee libarchive.log
libarchive: $(LIBARCHIVE_PACKAGE)

libarchive_clean:
	@echo "Cleaning libarchive..."
	@rm -rf libarchive*
	@rm -rf $(LIBARCHIVE_PACKAGE)

# --- MungeFS (Optional common dependency) ---
# Note: Depends on the libc++ versions of its dependencies where applicable
$(MUNGEFS_PACKAGE): $(CPPZMQ_PACKAGE) $(LIBARCHIVE_PACKAGE) $(AVRO_LIBCXX_PACKAGE) $(CLANG_RUNTIME_PACKAGE) $(ZEROMQ4_1_LIBCXX_PACKAGE)
	./build.sh $(BUILD_OPTIONS) mungefs 2>&1 | tee mungefs.log
mungefs: $(MUNGEFS_PACKAGE)

mungefs_clean:
	@echo "Cleaning mungefs..."
	@rm -rf mungefs*
	@rm -rf $(MUNGEFS_PACKAGE)

# --- Nanodbc (libc++ only) ---
$(NANODBC_LIBCXX_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) nanodbc-libcxx 2>&1 | tee nanodbc-libcxx.log
nanodbc-libcxx: $(NANODBC_LIBCXX_PACKAGE)

nanodbc_clean:
	@echo "Cleaning nanodbc..."
	@rm -rf nanodbc* # Cleans both potential source dirs
	@rm -rf $(NANODBC_LIBCXX_PACKAGE)

# --- Qpid-Proton (libc++ only) ---
$(QPID_PROTON_LIBCXX_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) qpid-proton-libcxx 2>&1 | tee qpid-proton-libcxx.log
qpid-proton-libcxx: $(QPID_PROTON_LIBCXX_PACKAGE)

qpid-proton_clean:
	@echo "Cleaning qpid-proton..."
	@rm -rf qpid-proton* # Cleans both potential source dirs
	@rm -rf $(QPID_PROTON_LIBCXX_PACKAGE)

# --- Redis (Common dependency) ---
$(REDIS_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) redis 2>&1 | tee redis.log
redis: $(REDIS_PACKAGE)

redis_clean:
	@echo "Cleaning redis..."
	@rm -rf redis*
	@rm -rf $(REDIS_PACKAGE)

# --- Spdlog (libc++ only) ---
$(SPDLOG_LIBCXX_PACKAGE): $(FMT_LIBCXX_PACKAGE) # Depends on the libc++ version of fmt
	./build.sh $(BUILD_OPTIONS) spdlog-libcxx 2>&1 | tee spdlog-libcxx.log
spdlog-libcxx: $(SPDLOG_LIBCXX_PACKAGE)

spdlog_clean:
	@echo "Cleaning spdlog..."
	@rm -rf spdlog* # Cleans both potential source dirs
	@rm -rf $(SPDLOG_LIBCXX_PACKAGE)

# --- ZeroMQ (libc++ only) ---
$(ZEROMQ4_1_LIBCXX_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) zeromq4-1-libcxx 2>&1 | tee zeromq4-1-libcxx.log
zeromq4-1-libcxx: $(ZEROMQ4_1_LIBCXX_PACKAGE)

zeromq4-1_clean:
	@echo "Cleaning zeromq4-1..."
	@rm -rf zeromq4-1* # Cleans both potential source dirs
	@rm -rf $(ZEROMQ4_1_LIBCXX_PACKAGE)


# --- Group Target ---
#
# Defines the set of packages needed for the server-libcxx build.
# These are the *convenience targets*, not the package file targets.

server-libcxx: avro-libcxx boost-libcxx catch2 clang clang-runtime cppzmq fmt-libcxx json jsoncons libarchive nanodbc-libcxx qpid-proton-libcxx spdlog-libcxx zeromq4-1-libcxx

# --- Cleaning ---
#
# The 'clean' target removes all generated files for the remaining targets.
clean: avro_clean boost_clean catch2_clean clang_clean clang-runtime_clean cmake_clean cppzmq_clean fmt_clean json_clean jsoncons_clean jwt-cpp_clean libarchive_clean mungefs_clean nanodbc_clean qpid-proton_clean redis_clean spdlog_clean zeromq4-1_clean
	@echo "Cleaning generated files..."
	@rm -rf packages.mk *.log # Also remove log files
	@echo "Done."


