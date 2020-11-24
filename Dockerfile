FROM --platform=${BUILDPLATFORM} debian:buster AS builder-base

ARG BUILDPLATFORM
ARG TARGETPLATFORM

ENV FB_DIR /firebird-R2_5_9
ENV FB_VER 2.5.9.27139-0

ENV DEBIAN_FRONTEND noninteractive

RUN cp /etc/apt/sources.list /etc/apt/sources.list.d/deb-sources.list \
	&& sed -i 's/^deb /deb-src /g' /etc/apt/sources.list.d/deb-sources.list \
	&& apt-get update \
	&& apt-get -y install curl \
	&& apt-get -y build-dep firebird3.0 \
	&& mkdir /dist \
	&& curl https://codeload.github.com/FirebirdSQL/firebird/tar.gz/R2_5_9 -o /dist/firebird-R2_5_9.tar.gz \
	&& tar xzvf /dist/firebird-R2_5_9.tar.gz \
	#&& rm -rf /var/lib/apt/lists/* ) \
	#Patch rwlock.h (this has been fixed in later release of firebird 3.x)
	&& sed -i '194s/.*/#if 0/' ${FB_DIR}/src/common/classes/rwlock.h \
	&& sed -i '92s/ rpmfile debugfile//' ${FB_DIR}/builds/install/arch-specific/linux/Makefile.in \
	&& sed -i '/^#DatabaseAccess.*$/a DatabaseAccess = Restrict /srv/firebird' ${FB_DIR}/builds/install/misc/firebird.conf.in

FROM --platform=${BUILDPLATFORM} builder-base AS builder

RUN case ${TARGETPLATFORM} in \
	linux/amd64) \
		export AUTOCONF_ARGS="--host=x86_64-linux-gnu" \
		&& export ARCH=amd64 \
		&& export FB_ARCH=amd64 \
		&& export PLATFORM_PKG="liblsan0:${ARCH} libtsan0:${ARCH}" \
		;; \
	linux/386) \
		export AUTOCONF_ARGS="--host=i686-linux-gnu" \
		&& export ARCH=i386 \
		&& export FB_ARCH=i686 \
		&& export PLATFORM_PKG="" \
		;; \
	linux/arm/v7) \
		export AUTOCONF_ARGS="--host=arm-linux-gnueabihf" \
		&& export ARCH=armhf \
		&& export FB_ARCH=arm \
		&& export PLATFORM_PKG="liblsan0:${ARCH} libtsan0:${ARCH}" \
		;; \
	linux/arm64) \
		export AUTOCONF_ARGS="--host=aarch64-linux-gnu" \
		&& export ARCH=arm64 \
		&& export FB_ARCH=aarch64 \
		&& export PLATFORM_PKG="liblsan0:${ARCH} libtsan0:${ARCH}" \
		;; \
	esac \
	&& [ ${BUILDPLATFORM} != ${TARGETPLATFORM} ] && ( \
		dpkg --add-architecture ${ARCH} \
		&& apt-get update \
		&& apt-get -y install crossbuild-essential-${ARCH} libatomic-ops-dev:${ARCH} libncurses-dev:${ARCH} autotools-dev:${ARCH} \
			dpkg-dev:${ARCH} libasan5:${ARCH} libatomic1:${ARCH} libbinutils:${ARCH} libboost-dev:${ARCH} libboost1.67-dev:${ARCH} \
			libbsd-dev:${ARCH} libbsd0:${ARCH} libcc1-0:${ARCH} libcroco3:${ARCH} libdpkg-perl:${ARCH} libedit-dev:${ARCH} \
			libedit2:${ARCH} libgcc-8-dev:${ARCH} libgdbm-compat4:${ARCH} libgdbm6:${ARCH} libglib2.0-0:${ARCH} libgomp1:${ARCH} \
			libicu-dev:${ARCH} libicu63:${ARCH} libisl19:${ARCH} libitm1:${ARCH} libmagic-mgc:${ARCH} libmagic1:${ARCH} \
			libmpc3:${ARCH} libmpfr6:${ARCH} libperl5.28:${ARCH} libpipeline1:${ARCH} libreadline7:${ARCH} libsigsegv2:${ARCH} \
			libstdc++-8-dev:${ARCH} libtommath-dev:${ARCH} libtommath1:${ARCH} libtool:${ARCH} libubsan1:${ARCH} \
			libuchardet0:${ARCH} libxml2:${ARCH} ${PLATFORM_PKG} \
		&& rm -rf /var/lib/apt/lists/* \
	) || ( \
		unset AUTOCONF_ARGS \
	) \
	&& cd ${FB_DIR} \
	&& export PREFIX=/usr/local/firebird \
	&& export PREFIX2=/srv/firebird \
	&& export CXXFLAGS="-std=gnu++98 -fno-lifetime-dse -pthread" \
	&& ./autogen.sh \
		${AUTOCONF_ARGS} \
		--prefix=${PREFIX} --enable-superserver --with-system-editline --with-system-icu \
		--enable-binreloc=enable \
		--with-fbbin=${PREFIX}/bin \
		--with-fbsbin=${PREFIX}/bin \
		--with-fbconf=${PREFIX} \
		--with-fblib=${PREFIX}/lib \
		--with-fbinclude=${PREFIX}/include \
		--with-fbdoc=${PREFIX}/doc \
		--with-fbudf=${PREFIX}/UDF \
		--with-fbsample=${PREFIX}/examples \
		--with-fbsample-db=${PREFIX2} \
		--with-fbhelp=${PREFIX}/help \
		--with-fbintl=${PREFIX}/intl \
		--with-fbmisc=${PREFIX}/misc \
		--with-fbsecure-db=${PREFIX2} \
		--with-fbmsg=${PREFIX} \
		--with-fblog=${PREFIX2} \
		--with-fbglock=${PREFIX} \
		--with-fbplugins=${PREFIX} \
	&& make \
	&& make dist \
	&& export FB_TGT=FirebirdSS-${FB_VER}.${FB_ARCH} \
	&& mv ${FB_DIR}/gen/${FB_TGT}.tar.gz /dist \
	&& echo "#!/bin/bash" > /dist/setup.sh \
	&& echo "tar xzvf /dist/${FB_TGT}.tar.gz -C /" >> /dist/setup.sh \
	&& echo "cd /${FB_TGT}" >> /dist/setup.sh \
	&& echo "./install.sh -silent" >> /dist/setup.sh \
	&& echo "rm -rf /${FB_TGT}" >> /dist/setup.sh \
	&& echo "ln -s /usr/local/firebird/bin/isql /usr/local/firebird/bin/isql-fb" >> /dist/setup.sh \
	&& echo "mkdir -p /srv/firebird/backup" >> /dist/setup.sh \
	&& echo "mkdir -p /run/php" >> /dist/setup.sh \
	&& echo "cp /dist/start.sh /" >> /dist/setup.sh \
	&& chmod a+x /dist/setup.sh \
	&& echo "#!/bin/bash" > /dist/start.sh \
	&& echo "set -e" >> /dist/start.sh \
	&& echo "if [ \"\$1\" = 'fbguard' ]; then" >> /dist/start.sh \
	&& echo "    echo \"Starting Firebird\"" >> /dist/start.sh \
	&& echo "    exec /usr/local/firebird/bin/fbguard -pidfile /var/run/firebird.pid -forever" >> /dist/start.sh \
	&& echo "fi" >> /dist/start.sh \
	&& echo "exec \"\$@\"" >> /dist/start.sh \
	&& chmod a+x /dist/start.sh \
	&& rm -rf ${FB_DIR}

FROM debian:buster-slim AS image

ENV PATH /usr/local/firebird/bin:$PATH

COPY --from=builder /dist/* /dist/

RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get -y install libbsd0 libedit2 libgpm2 libicu63 libncurses6 libtommath1 lsb-base procps \
	&& rm -rf /var/lib/apt/lists/* \
	&& /dist/setup.sh 2>&1 | tee -a /setup.log

VOLUME ["/srv/firebird"]

EXPOSE 3050/tcp

ENTRYPOINT ["/start.sh"]
CMD ["fbguard"]