FROM ubuntu:20.04
ENV DEBIAN_FRONTEND noninteractive

# (Temporary: replace URL for fast download during development)
RUN sed -i 's/archive.ubuntu.com/ftp.daumkakao.com/g' /etc/apt/sources.list

ENV DEBIAN_FRONTEND="noninteractive"
RUN apt-get update && apt-get upgrade -y
RUN apt-get install -yy libc6-dev binutils libgcc-9-dev
RUN apt-get install -yy \
      wget apt-transport-https git unzip \
      build-essential libtool libtool-bin gdb \
      automake autoconf bison flex python python3 sudo vim

# Copied from OSS-FUZZ
ENV OUT=/out
ENV SRC=/src
ENV WORK=/work
ENV PATH="$PATH:/out"
RUN mkdir -p $OUT $SRC $WORK
ENV CMAKE_VERSION 3.21.1
RUN wget https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-Linux-x86_64.sh && \
    chmod +x cmake-$CMAKE_VERSION-Linux-x86_64.sh && \
    ./cmake-$CMAKE_VERSION-Linux-x86_64.sh --skip-license --prefix="/usr/local" && \
    rm cmake-$CMAKE_VERSION-Linux-x86_64.sh && \
    rm -rf /usr/local/doc/cmake /usr/local/bin/cmake-gui

# Install packages needed for fuzzers and benchmark
RUN apt-get update && \
    apt-get install -yy \
      # Several packages get uninstalled after LLVM setup.
      git build-essential bc \
      # For ParmeSan
      golang \
      # For Beacon
      libncurses5 \
      # For libming
      libfreetype6 libfreetype6-dev \
      # For libxml
      python-dev \
      # For libjpeg
      nasm \
      # For lrzip
      libbz2-dev liblzo2-dev \
      # For 32bit binaries
      gcc-multilib \
      # install clang
      clang-12 llvm-12-dev

ENV PATH="/usr/lib/llvm-12/bin:/usr/lib/llvm-12/lib:$PATH"

# Create a fuzzer directory and setup fuzzers there.
RUN mkdir /fuzzer
WORKDIR /fuzzer
COPY docker-setup/setup_AFL.sh /fuzzer/setup_AFL.sh
RUN ./setup_AFL.sh

COPY docker-setup/setup_AFLGo.sh /fuzzer/setup_AFLGo.sh
RUN ./setup_AFLGo.sh

# Create a benchmark directory and start working there.
RUN mkdir -p /benchmark/bin && \
    mkdir -p /benchmark/seed && \
    mkdir -p /benchmark/poc
COPY docker-setup/seed/empty /benchmark/seed/empty
WORKDIR /benchmark

# To use ASAN during the benchmark build, these option are needed.
ENV ASAN_OPTIONS=allocator_may_return_null=1,detect_leaks=0

# Build benchmark with AFL/AFLGo.
COPY docker-setup/benchmark-project /benchmark/project
COPY docker-setup/build_bench_common.sh /benchmark/build_bench_common.sh
COPY docker-setup/build_bench_ASAN.sh /benchmark/build_bench_ASAN.sh
RUN ./build_bench_ASAN.sh
COPY docker-setup/build_bench_AFL.sh /benchmark/build_bench_AFL.sh
RUN ./build_bench_AFL.sh

COPY docker-setup/target/stack-trace /benchmark/target/stack-trace
COPY docker-setup/build_bench_AFLGo.sh /benchmark/build_bench_AFLGo.sh
RUN ./build_bench_AFLGo.sh

# Setup smAFL.
WORKDIR /fuzzer
COPY smAFL /fuzzer/smAFL
RUN cd smAFL && make clean all && cd llvm_mode && make clean all && cd ../distance_calculator && cmake -GNinja ./ && cmake --build ./


# Build benchmarks with smAFL.
WORKDIR /benchmark
COPY docker-setup/build_bench_smAFL.sh /benchmark/build_bench_smAFL.sh
RUN ./build_bench_smAFL.sh

# Copy tool running scripts.
COPY docker-setup/tool-script /tool-script

# Reset the working directory to top-level directory.
WORKDIR /