#!/usr/bin/env bash

shell_quote_string() {
  echo "$1" | sed -e 's,\([^a-zA-Z0-9/_.=-]\),\\\1,g'
}

usage () {
    cat <<EOF
Usage: $0 [OPTIONS]
    The following options may be given :
        --builddir=DIR      Absolute path to the dir where all actions will be performed
        --get_sources       Source will be downloaded from github
        --build_src_rpm     If it is 1 src rpm will be built
        --build_source_deb  If it is 1 source deb package will be built
        --build_rpm         If it is 1 rpm will be built
        --build_deb         If it is 1 deb will be built
        --install_deps      Install build dependencies(root previlages are required)
        --branch            Branch for build
        --repo              Repo for build
        --rpm_release       RPM version( default = 1)
        --deb_release       DEB version( default = 1)
        --help) usage ;;
Example $0 --builddir=/tmp/patchelf --get_sources=1 --build_src_rpm=1 --build_rpm=1
EOF
        exit 1
}

append_arg_to_args () {
  args="$args "$(shell_quote_string "$1")
}

 parse_arguments() {
    pick_args=
    if test "$1" = PICK-ARGS-FROM-ARGV
    then
        pick_args=1
        shift
    fi

    for arg do
        val=$(echo "$arg" | sed -e 's;^--[^=]*=;;')
        case "$arg" in
            # these get passed explicitly to mysqld
            --builddir=*) WORKDIR="$val" ;;
            --build_src_rpm=*) SRPM="$val" ;;
            --build_source_deb=*) SDEB="$val" ;;
            --build_rpm=*) RPM="$val" ;;
            --build_deb=*) DEB="$val" ;;
            --get_sources=*) SOURCE="$val" ;;
            --branch=*) BRANCH="$val" ;;
            --install_deps=*) INSTALL="$val" ;;
            --branch=*) BRANCH="$val" ;;
            --repo=*) REPO="$val" ;;
            --rpm_release=*) RPM_RELEASE="$val" ;;
            --deb_release=*) DEB_RELEASE="$val" ;;
            --help) usage ;;
            *)
              if test -n "$pick_args"
              then
                  append_arg_to_args "$arg"
              fi
              ;;
        esac
    done
}

check_workdir(){
    if [ "x$WORKDIR" = "x$CURDIR" ]
    then
        echo >&2 "Current directory cannot be used for building!"
        exit 1
    else
        if ! test -d "$WORKDIR"
        then
            echo >&2 "$WORKDIR is not a directory."
            exit 1
        fi
    fi
    return
}

get_sources(){
    cd $WORKDIR
    if [ $SOURCE = 0 ]
    then
        echo "Sources will not be downloaded"
        return 0
    fi
    git clone "$REPO"
    retval=$?
    if [ $retval != 0 ]
    then
        echo "There were some issues during repo cloning from github. Please retry one more time"
        exit 1
    fi

    cd patchelf
    if [ ! -z $BRANCH ]
    then
        git reset --hard
        git clean -xdf
        git checkout $BRANCH
    fi

    REVISION=$(git rev-parse --short HEAD)
    git reset --hard
    #

    echo "VERSION=${VERSION}" > ${CURDIR}/patchelf.properties
    PRODUCT=patchelf
    BRANCH_NAME="${BRANCH}"
    PRODUCT_FULL=${PRODUCT}-${VERSION}

    echo "REVISION=${REVISION}" >> ${CURDIR}/patchelf.properties
    echo "RPM_RELEASE=${RPM_RELEASE}" >> ${CURDIR}/patchelf.properties
    echo "DEB_RELEASE=${DEB_RELEASE}" >> ${CURDIR}/patchelf.properties
    echo "GIT_REPO=${GIT_REPO}" >> ${CURDIR}/patchelf.properties
    echo "BRANCH_NAME=${BRANCH_NAME}" >> ${CURDIR}/patchelf.properties
    echo "PRODUCT=${PRODUCT}" >> ${CURDIR}/patchelf.properties
    echo "PRODUCT_FULL=${PRODUCT_FULL}" >> ${CURDIR}/patchelf.properties
    echo "BUILD_NUMBER=${BUILD_NUMBER}" >> ${CURDIR}/patchelf.properties
    echo "BUILD_ID=${BUILD_ID}" >> ${CURDIR}/patchelf.properties
    #
    if [ -z "${DESTINATION}" ]; then
    export DESTINATION=experimental
    fi 
    #
    TIMESTAMP=$(date "+%Y%m%d-%H%M%S")
    echo "DESTINATION=${DESTINATION}" >> ${CURDIR}/patchelf.properties
    echo "UPLOAD=UPLOAD/${DESTINATION}/BUILDS/${PRODUCT}/${PRODUCT_FULL}/${BRANCH_NAME}/${REVISION}${TIMESTAMP}" >> ${CURDIR}/patchelf.properties

    cd ${WORKDIR}
    git clone https://github.com/Percona-Lab/patchelf-packaging.git

    cp -ap ${WORKDIR}/patchelf-packaging/*.spec ${PRODUCT}/
    cp -ap ${WORKDIR}/patchelf-packaging/debian ${PRODUCT}/

    sed -i "s:@PACKAGE_VERSION@:${VERSION}:g" ${PRODUCT}/patchelf.spec


    cd ${WORKDIR}
    mv ${PRODUCT} ${PRODUCT_FULL}
    tar --owner=0 --group=0 --exclude=.bzr --exclude=.git -czf ${PRODUCT}-${VERSION}.tar.gz ${PRODUCT_FULL}
    rm -rf ${PRODUCT_FULL}

    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    cp ${PRODUCT}-${VERSION}.tar.gz $WORKDIR/source_tarball
    cp ${PRODUCT}-${VERSION}.tar.gz $CURDIR/source_tarball
    cd $CURDIR
    rm -rf patchelf
    return
}

get_system(){
    if [ -f /etc/redhat-release ]; then
        export RHEL=$(rpm --eval %rhel)
        export ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
        export OS_NAME="el$RHEL"
        export OS="rpm"
    else
        export ARCH=$(uname -m)
        export OS_NAME="$(lsb_release -sc)"
        export OS="deb"
    fi
    return
}

enable_venv(){
    if [ "$OS" == "rpm" ]; then
        if [ "${RHEL}" -eq 7 ]; then
            source /opt/rh/devtoolset-7/enable
            export CMAKE_BIN="cmake3"
        elif [ "${RHEL}" -eq 6 ]; then
            source /opt/rh/devtoolset-7/enable
        fi
    fi
}

install_deps() {
    if [ $INSTALL = 0 ]
    then
        echo "Dependencies will not be installed"
        return;
    fi
    if [ ! $( id -u ) -eq 0 ]
    then
        echo "It is not possible to instal dependencies. Please run as root"
        exit 1
    fi
    CURPLACE=$(pwd)
    if [ "x$OS" = "xrpm" ]
    then
        yum -y install git wget 
        if [[ "${RHEL}" -eq 8 ]]; then         
            PKGLIST+=" binutils-devel libev-devel bison make gcc"
            PKGLIST+=" rpm-build gcc-c++"
            PKGLIST+=" rpmlint autoconf automake "
            until yum -y install ${PKGLIST}; do
                echo "waiting"
                sleep 1
            done
        else
            until yum -y install epel-release centos-release-scl; do
                yum clean all
                sleep 1
                echo "waiting"
            done
            until yum -y makecache; do
                yum clean all
                sleep 1
                echo "waiting"
            done
            PKGLIST+=" devtoolset-7-gcc-c++ devtoolset-7-binutils"
            PKGLIST+=" make gcc gcc-c++ libev-devel rpm-build autoconf automake rpmlint"
            until yum -y install ${PKGLIST}; do
                echo "waiting"
                sleep 1
            done
        fi
    else
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get -y install lsb-release gnupg git wget

        PKGLIST+=" bison make devscripts debconf debhelper dpkg-dev automake bison autoconf automake"
        PKGLIST+=" build-essential rsync"

        until DEBIAN_FRONTEND=noninteractive apt-get -y install ${PKGLIST}; do
            sleep 1
            echo "waiting"
        done

    fi
    return;
}

get_tar(){
    TARBALL=$1
    TARFILE=$(basename $(find $WORKDIR/$TARBALL -name 'patchelf*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]
    then
        TARFILE=$(basename $(find $CURDIR/$TARBALL -name 'patchelf*.tar.gz' | sort | tail -n1))
        if [ -z $TARFILE ]
        then
            echo "There is no $TARBALL for build"
            exit 1
        else
            cp $CURDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
        fi
    else
        cp $WORKDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
    fi
    return
}

get_deb_sources(){
    param=$1
    echo $param
    FILE=$(basename $(find $WORKDIR/source_deb -name "patchelf*.$param" | sort | tail -n1))
    if [ -z $FILE ]
    then
        FILE=$(basename $(find $CURDIR/source_deb -name "patchelf*.$param" | sort | tail -n1))
        if [ -z $FILE ]
        then
            echo "There is no sources for build"
            exit 1
        else
            cp $CURDIR/source_deb/$FILE $WORKDIR/
        fi
    else
        cp $WORKDIR/source_deb/$FILE $WORKDIR/
    fi
    return
}

build_srpm(){
    if [ $SRPM = 0 ]
    then
        echo "SRC RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build src rpm here"
        exit 1
    fi
    cd $WORKDIR
    get_tar "source_tarball"
    if [ -d rpmbuild ]; then
        rm -fr rpmbuild
    fi
    ls | grep -v patchelf*.tar.* | xargs rm -rf
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}

    TARFILE=$(basename $(find . -name 'patchelf-*.tar.gz' | sort | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1}')
    VERSION_TMP=$(echo ${TARFILE}| awk -F '-' '{print $2}')
    VERSION=${VERSION_TMP%.tar.gz}
    #
    cd $WORKDIR/rpmbuild/SPECS
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*.spec' --strip=1
    #
    cd $WORKDIR
    #
    cd $WORKDIR/rpmbuild/SOURCES
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards "patchelf-$VERSION/debian/patches/*.patch" --strip=3
    mv -fv $WORKDIR/$TARFILE $WORKDIR/rpmbuild/SOURCES
    cd $WORKDIR
    #
    enable_venv

    rpmbuild -bs --define "_topdir $WORKDIR/rpmbuild" --define "dist .generic" rpmbuild/SPECS/patchelf.spec

    mkdir -p ${WORKDIR}/srpm
    mkdir -p ${CURDIR}/srpm
    cp $WORKDIR/rpmbuild/SRPMS/*.src.rpm $CURDIR/srpm
    cp $WORKDIR/rpmbuild/SRPMS/*.src.rpm $WORKDIR/srpm
    return
}

build_rpm(){
    if [ $RPM = 0 ]
    then
        echo "RPM will not be created"
        return;
    fi
    if [ "x$OS" = "xdeb" ]
    then
        echo "It is not possible to build rpm here"
        exit 1
    fi
        SRC_RPM=$(basename $(find $WORKDIR/srpm -name 'patchelf-*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]
    then
        SRC_RPM=$(basename $(find $CURDIR/srpm -name 'patchelf-*.src.rpm' | sort | tail -n1))
        if [ -z $SRC_RPM ]
        then
            echo "There is no src rpm for build"
            echo "You can create it using key --build_src_rpm=1"
            exit 1
        else
            cp $CURDIR/srpm/$SRC_RPM $WORKDIR
        fi
    else
        cp $WORKDIR/srpm/$SRC_RPM $WORKDIR
    fi
    cd $WORKDIR

    if [ -d rpmbuild ]; then
        rm -fr rpmbuild
    fi

    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    cp $SRC_RPM rpmbuild/SRPMS/
    #
    echo "RHEL=${RHEL}" >> ${CURDIR}/patchelf.properties
    echo "ARCH=${ARCH}" >> ${CURDIR}/patchelf.properties
    #
    SRCRPM=$(basename $(find . -name '*.src.rpm' | sort | tail -n1))

    enable_venv

    rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .el${RHEL}" --rebuild rpmbuild/SRPMS/${SRCRPM}
    return_code=$?
    if [ $return_code != 0 ]; then
        exit $return_code
    fi
    mkdir -p ${WORKDIR}/rpm
    mkdir -p ${CURDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${WORKDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${CURDIR}/rpm    
}

build_source_deb(){
    if [ $SDEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrmp" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    rm -rf patchelf*
    get_tar "source_tarball"
    rm -f *.dsc *.orig.tar.gz *.changes *.debian.tar.xz

    TARFILE=$(basename $(find . -name 'patchelf-*.tar.gz' | sort | tail -n1))
    NAME=$(echo ${TARFILE}| awk -F '-' '{print $1}')
    VERSION_TMP=$(echo ${TARFILE}| awk -F '-' '{print $2}')
    VERSION=${VERSION_TMP%.tar.gz}

    echo "DEB_RELEASE=${DEB_RELEASE}" >> ${CURDIR}/patchelf.properties

    NEWTAR=${NAME}_${VERSION}.orig.tar.gz
    mv ${TARFILE} ${NEWTAR}

    tar xzf ${NEWTAR}
    cd $NAME-$VERSION

    dch -D unstable --force-distribution -v "${VERSION}-${DEB_RELEASE}" "Update to new upstream release patchelf ${VERSION}-${DEB_RELEASE}"
    dpkg-buildpackage -S

    cd ${WORKDIR}

    mkdir -p $WORKDIR/source_deb
    mkdir -p $CURDIR/source_deb

    cp *.debian.tar.xz $WORKDIR/source_deb
    cp *.dsc $WORKDIR/source_deb
    cp *.orig.tar.gz $WORKDIR/source_deb
    cp *.changes $WORKDIR/source_deb
    cp *.debian.tar.xz $CURDIR/source_deb
    cp *.dsc $CURDIR/source_deb
    cp *.orig.tar.gz $CURDIR/source_deb
    cp *.changes $CURDIR/source_deb
    
}

build_deb(){
    if [ $DEB = 0 ]
    then
        echo "source deb package will not be created"
        return;
    fi
    if [ "x$OS" = "xrmp" ]
    then
        echo "It is not possible to build source deb here"
        exit 1
    fi
    for file in 'dsc' 'orig.tar.gz' 'changes' 'debian.tar.xz'
    do
        get_deb_sources $file
    done
    cd $WORKDIR


    DSC=$(basename $(find . -name '*.dsc' | sort | tail -n 1))
    DIRNAME=$(echo ${DSC} | sed -e 's:_:-:g' | awk -F'-' '{print $1"-"$2}')
    VERSION=$(echo ${DSC} | sed -e 's:_:-:g' | awk -F'-' '{print $2}')
    #
    echo "DEB_RELEASE=${DEB_RELEASE}" >> ${CURDIR}/patchelf.properties
    echo "DEBIAN_VERSION=${OS_NAME}" >> ${CURDIR}/patchelf.properties
    echo "ARCH=${ARCH}" >> ${CURDIR}/patchelf.properties

    dpkg-source -x $DSC
    cd $DIRNAME
    sed -i "s: serial-tests::g" configure.ac
    dch -m -D "$OS_NAME" --force-distribution -v "$VERSION-$DEB_RELEASE.$OS_NAME" 'Update distribution'
    dpkg-buildpackage -rfakeroot -uc -us -b

    cd ${WORKDIR}
    mkdir -p $CURDIR/deb
    mkdir -p $WORKDIR/deb
    cp $WORKDIR/*.deb $WORKDIR/deb
    cp $WORKDIR/*.deb $CURDIR/deb
}

CURDIR=$(pwd)
VERSION_FILE=$CURDIR/patchelf.properties
args=
WORKDIR=
SRPM=0
SDEB=0
RPM=0
DEB=0
SOURCE=0
TARBALL=0
OS_NAME=
ARCH=
OS=
REVISION=0
BRANCH="master"
INSTALL=0
RPM_RELEASE=1
DEB_RELEASE=1
REPO="https://github.com/NixOS/patchelf.git"
parse_arguments PICK-ARGS-FROM-ARGV "$@"

check_workdir
get_system
install_deps
get_sources
build_srpm
build_source_deb
build_rpm
build_deb
