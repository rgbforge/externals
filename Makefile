# Build options:  -v for verbosity ( default: -p to package)
BUILD_OPTIONS = -v

# Generate the packages.mk, depends on versions.json and build.sh.
packages.mk: Makefile versions.json build.sh
	./build.sh packagesfile

# The "all" target requires that packages.mk is generated.
all: packages.mk

# --- Individual Targets ---

# avro: depends on boost, cmake, and clang; then build using build.sh.
$(AVRO_PACKAGE): $(BOOST_PACKAGE) $(CMAKE_PACKAGE) $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) avro > avro.log 2>&1
avro: $(AVRO_PACKAGE)

# avro-libcxx: depends on boost-libcxx, cmake, and clang.
$(AVRO_LIBCXX_PACKAGE): $(BOOST_LIBCXX_PACKAGE) $(CMAKE_PACKAGE) $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) avro-libcxx > avro-libcxx.log 2>&1
avro-libcxx: $(AVRO_LIBCXX_PACKAGE)

avro_clean:
	@echo "Cleaning avro..."
	@rm -rf avro*
	@rm -rf $(AVRO_PACKAGE) $(AVRO_LIBCXX_PACKAGE)

# boost: depends on clang.
$(BOOST_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) boost > boost.log 2>&1
boost: $(BOOST_PACKAGE)

# boost-libcxx: depends on clang.
$(BOOST_LIBCXX_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) boost-libcxx > boost-libcxx.log 2>&1
boost-libcxx: $(BOOST_LIBCXX_PACKAGE)

boost_clean:
	@echo "Cleaning boost..."
	@rm -rf boost*
	@rm -rf $(BOOST_PACKAGE) $(BOOST_LIBCXX_PACKAGE)

# catch2: depends on cmake.
$(CATCH2_PACKAGE): $(CMAKE_PACKAGE)
	./build.sh $(BUILD_OPTIONS) catch2 > catch2.log 2>&1
catch2: $(CATCH2_PACKAGE)

catch2_clean:
	@echo "Cleaning catch2..."
	@rm -rf catch2*
	@rm -rf $(CATCH2_PACKAGE)

# clang: depends on cmake.
$(CLANG_PACKAGE): $(CMAKE_PACKAGE)
	./build.sh $(BUILD_OPTIONS) clang > clang.log 2>&1
clang: $(CLANG_PACKAGE)

clang_clean:
	@echo "Cleaning clang..."
	@rm -rf clang*
	@rm -rf $(CLANG_PACKAGE)

# clang-runtime: depends on clang.
$(CLANG_RUNTIME_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) clang-runtime > clang-runtime.log 2>&1
clang-runtime: $(CLANG_RUNTIME_PACKAGE)

clang-runtime_clean:
	@echo "Cleaning clang-runtime..."
	@rm -rf clang-runtime*
	@rm -rf $(CLANG_RUNTIME_PACKAGE)

# cmake:
$(CMAKE_PACKAGE):
	./build.sh $(BUILD_OPTIONS) cmake > cmake.log 2>&1
cmake: $(CMAKE_PACKAGE)

cmake_clean:
	@echo "Cleaning cmake..."
	@rm -rf cmake*
	@rm -rf $(CMAKE_PACKAGE)

# cppzmq: depends on zeromq4_1.
$(CPPZMQ_PACKAGE): $(ZEROMQ4_1_PACKAGE)
	./build.sh $(BUILD_OPTIONS) cppzmq > cppzmq.log 2>&1
cppzmq: $(CPPZMQ_PACKAGE)

cppzmq_clean:
	@echo "Cleaning cppzmq..."
	@rm -rf cppzmq*
	@rm -rf $(CPPZMQ_PACKAGE)

# fmt:
$(FMT_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) fmt > fmt.log 2>&1
fmt: $(FMT_PACKAGE)

# fmt-libcxx:
$(FMT_LIBCXX_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) fmt-libcxx > fmt-libcxx.log 2>&1
fmt-libcxx: $(FMT_LIBCXX_PACKAGE)

fmt_clean:
	@echo "Cleaning fmt..."
	@rm -rf fmt*
	@rm -rf $(FMT_PACKAGE) $(FMT_LIBCXX_PACKAGE)

# json:
$(JSON_PACKAGE): $(CMAKE_PACKAGE)
	./build.sh $(BUILD_OPTIONS) json > json.log 2>&1
json: $(JSON_PACKAGE)

json_clean:
	@echo "Cleaning json..."
	@rm -rf json*
	@rm -rf $(JSON_PACKAGE)

# jsoncons:
$(JSONCONS_PACKAGE): $(CMAKE_PACKAGE)
	./build.sh $(BUILD_OPTIONS) jsoncons > jsoncons.log 2>&1
jsoncons: $(JSONCONS_PACKAGE)

jsoncons_clean:
	@echo "Cleaning jsoncons..."
	@rm -rf jsoncons*
	@rm -rf $(JSONCONS_PACKAGE)

# jwt-cpp: depends on cmake and json.
$(JWT_CPP_PACKAGE): $(CMAKE_PACKAGE) $(JSON_PACKAGE)
	./build.sh $(BUILD_OPTIONS) jwt-cpp > jwt-cpp.log 2>&1
jwt-cpp: $(JWT_CPP_PACKAGE)

jwt-cpp_clean:
	@echo "Cleaning jwt-cpp..."
	@rm -rf jwt-cpp*
	@rm -rf $(JWT_CPP_PACKAGE)

# libarchive: depends on cmake and clang.
$(LIBARCHIVE_PACKAGE): $(CMAKE_PACKAGE) $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) libarchive > libarchive.log 2>&1
libarchive: $(LIBARCHIVE_PACKAGE)

libarchive_clean:
	@echo "Cleaning libarchive..."
	@rm -rf libarchive*
	@rm -rf $(LIBARCHIVE_PACKAGE)

# mungefs: depends on cppzmq, libarchive, avro, clang-runtime, zeromq4_1.
$(MUNGEFS_PACKAGE): $(CPPZMQ_PACKAGE) $(LIBARCHIVE_PACKAGE) $(AVRO_PACKAGE) $(CLANG_RUNTIME_PACKAGE) $(ZEROMQ4_1_PACKAGE)
	./build.sh $(BUILD_OPTIONS) mungefs > mungefs.log 2>&1
mungefs: $(MUNGEFS_PACKAGE)

mungefs_clean:
	@echo "Cleaning mungefs..."
	@rm -rf mungefs*
	@rm -rf $(MUNGEFS_PACKAGE)

# nanodbc:
$(NANODBC_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) nanodbc > nanodbc.log 2>&1
nanodbc: $(NANODBC_PACKAGE)

# nanodbc-libcxx:
$(NANODBC_LIBCXX_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) nanodbc-libcxx > nanodbc-libcxx.log 2>&1
nanodbc-libcxx: $(NANODBC_LIBCXX_PACKAGE)

nanodbc_clean:
	@echo "Cleaning nanodbc..."
	@rm -rf nanodbc*
	@rm -rf $(NANODBC_PACKAGE) $(NANODBC_LIBCXX_PACKAGE)

# qpid-proton:
$(QPID_PROTON_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) qpid-proton > qpid-proton.log 2>&1
qpid-proton: $(QPID_PROTON_PACKAGE)

# qpid-proton-libcxx:
$(QPID_PROTON_LIBCXX_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) qpid-proton-libcxx > qpid-proton-libcxx.log 2>&1
qpid-proton-libcxx: $(QPID_PROTON_LIBCXX_PACKAGE)

qpid-proton_clean:
	@echo "Cleaning qpid-proton..."
	@rm -rf qpid-proton*
	@rm -rf $(QPID_PROTON_PACKAGE) $(QPID_PROTON_LIBCXX_PACKAGE)

# redis:
$(REDIS_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) redis > redis.log 2>&1
redis: $(REDIS_PACKAGE)

redis_clean:
	@echo "Cleaning redis..."
	@rm -rf redis*
	@rm -rf $(REDIS_PACKAGE)

# spdlog:
$(SPDLOG_PACKAGE): $(FMT_PACKAGE)
	./build.sh $(BUILD_OPTIONS) spdlog > spdlog.log 2>&1
spdlog: $(SPDLOG_PACKAGE)

# spdlog-libcxx:
$(SPDLOG_LIBCXX_PACKAGE): $(FMT_LIBCXX_PACKAGE)
	./build.sh $(BUILD_OPTIONS) spdlog-libcxx > spdlog-libcxx.log 2>&1
spdlog-libcxx: $(SPDLOG_LIBCXX_PACKAGE)

spdlog_clean:
	@echo "Cleaning spdlog..."
	@rm -rf spdlog*
	@rm -rf $(SPDLOG_PACKAGE) $(SPDLOG_LIBCXX_PACKAGE)

# zeromq4-1:
$(ZEROMQ4_1_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) zeromq4-1 > zeromq4-1.log 2>&1
zeromq4-1: $(ZEROMQ4_1_PACKAGE)

# zeromq4-1-libcxx:
$(ZEROMQ4_1_LIBCXX_PACKAGE): $(CLANG_PACKAGE)
	./build.sh $(BUILD_OPTIONS) zeromq4-1-libcxx > zeromq4-1-libcxx.log 2>&1
zeromq4-1-libcxx: $(ZEROMQ4_1_LIBCXX_PACKAGE)

zeromq4-1_clean:
	@echo "Cleaning zeromq4-1..."
	@rm -rf zeromq4-1*
	@rm -rf $(ZEROMQ4_1_PACKAGE) $(ZEROMQ4_1_LIBCXX_PACKAGE)


server-libstdcxx: avro boost catch2 clang cppzmq fmt json jsoncons libarchive nanodbc spdlog zeromq4-1

server-libcxx: avro-libcxx boost-libcxx catch2 clang clang-runtime cppzmq fmt-libcxx json jsoncons libarchive nanodbc-libcxx spdlog-libcxx zeromq4-1-libcxx

server: server-libstdcxx server-libcxx

clean: avro_clean boost_clean catch2_clean clang_clean clang-runtime_clean cmake_clean cppzmq_clean fmt_clean json_clean jsoncons_clean jwt-cpp_clean libarchive_clean mungefs_clean nanodbc_clean qpid-proton_clean redis_clean spdlog_clean zeromq4-1_clean
	@echo "Cleaning generated files..."
	@rm -rf packages.mk
	@echo "Done."
