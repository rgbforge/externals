sudo subscription-manager repos --enable codeready-builder-for-rhel-8-x86_64-rpms


sudo dnf install -y \
autoconf \
automake \
bzip2-devel \
ca-certificates \
cmake \
fuse \
fuse-devel \
gcc \
gcc-c++ \
git \
glibc-devel \
help2man \
libcurl-devel \
libicu-devel \
libmicrohttpd-devel \
libtool \
libuuid-devel \
libxml2-devel \
libzstd-devel \
openssl \
openssl-devel \
patch \
procps \
python3-distro \
python3-setuptools \
python3-devel \
python3.11 \
rpm-build \
rsync \
ruby-devel \
rubygems \
texinfo \
unixODBC-devel \
wget \
xz-devel \
zlib-devel \
curl \
gcc-toolset-11-gcc \
gcc-toolset-11-gcc-c++ \
gcc-toolset-11-libstdc++-devel \
redhat-lsb-core 

curl -sSL https://rvm.io/mpapis.asc | sudo gpg --import -
curl -sSL https://rvm.io/pkuczynski.asc | sudo gpg --import -

sudo bash -c '
    if ! command -v rvm >/dev/null 2>&1; then
        curl -sSL https://get.rvm.io | bash -s stable
    fi

    source /etc/profile.d/rvm.sh

    rvm reload && rvm requirements run
    if ! rvm list strings | grep -q "ruby-3.1.2"; then
        rvm install 3.1.2
    fi
    
    rvm use 3.1.2 --default
    gem install -v 1.14.1 --no-document fpm
'
