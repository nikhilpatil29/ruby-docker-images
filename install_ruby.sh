#!/bin/bash

set -ex

RUBY_VERSION=${RUBY_VERSION-2.6.0}
RUBY_MAJOR=$(echo $RUBY_VERSION | sed -E 's/\.[0-9]+(-.*)?$//g')
RUBYGEMS_VERSION=${RUBYGEMS_VERSION-3.0.1}
BUNDLER_VERSION=${BUNDLER_VERSION-1.17.2}

wget -O index.txt "https://cache.ruby-lang.org/pub/ruby/index.txt"

case $RUBY_VERSION in
  trunk:*)
    RUBY_TRUNK_COMMIT=$(echo $RUBY_VERSION | awk -F: '{print $2}' )
    RUBY_VERSION=trunk
    ;;
  2.6.1)
    RUBY_DOWNLOAD_SHA256=47b629808e9fd44ce1f760cdf3ed14875fc9b19d4f334e82e2cf25cb2898f2f2
    ;;
  *)
    entry=$(grep ruby-$RUBY_VERSION.tar.xz index.txt)
    if test -z "$entry"; then
      echo "Unsupported RUBY_VERSION ($RUBY_VERSION)" >2
      exit 1
    fi
    RUBY_DOWNLOAD_SHA256=$(echo $entry | awk '{print $4}')
    RUBY_DOWNLOAD_URI=$(echo $entry | awk '{print $2}')
    ;;
esac

case $RUBY_VERSION in
  2.3.*)
    # Need to down grade openssl to 1.0.x for Ruby 2.3.x
    apt-get install -y --no-install-recommends libssl1.0-dev
    ;;
esac

if test -n "$RUBY_TRUNK_COMMIT"; then
  if test -f /usr/src/ruby/configure.ac; then
    cd /usr/src/ruby
    git pull --rebase origin
  else
    rm -r /usr/src/ruby
    git clone https://github.com/ruby/ruby.git /usr/src/ruby
    cd /usr/src/ruby
  fi
  git checkout $RUBY_TRUNK_COMMIT
else
  if test -z "$RUBY_DOWNLOAD_URI"; then
    RUBY_DOWNLOAD_URI="https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR}/ruby-${RUBY_VERSION}.tar.xz"
  fi
  wget -O ruby.tar.xz $RUBY_DOWNLOAD_URI
  echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum -c -
  mkdir -p /usr/src/ruby
  tar -xJf ruby.tar.xz -C /usr/src/ruby --strip-components=1
  rm ruby.tar.xz
fi

(
  cd /usr/src/ruby
  autoconf

  mkdir -p /tmp/ruby-build
  pushd /tmp/ruby-build

  gnuArch=$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)
  /usr/src/ruby/configure \
    --build="$gnuArch" \
    --prefix=/usr/local \
    --disable-install-doc \
    --enable-shared \
    optflags="-O3 -mtune=native -march=native" \
    debugflags="-g"

  make -j "$(nproc)"
  make install

  popd
  rm -rf /tmp/ruby-build
)

if test $RUBY_VERSION != "trunk"; then
  gem update --system "$RUBYGEMS_VERSION"
fi

case $RUBY_VERSION in
  2.6.*)
    # DO NOTHING
    ;;
  *)
    gem install bundler --version "$BUNDLER_VERSION" --force
    ;;
esac

rm -r /usr/src/ruby /root/.gem/
