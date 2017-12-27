#! /usr/bin/env bash
#
# Build optimized version of Midnight Commander including patches into custom location
#

# Set repo and latest release version
owner=MidnightCommander
project=mc
version=4.8.20

# Specify git branch/commit for project to compile from: [master|218dcea]
export git_project="218dcea"         # 2017-12-24 master



#
# HERE BE DRAGONS!
#

# Support only git version of project (not major releases) ?
only_git_project=false

# Set main project variables
export rel_major=${version%.*}
export rel_minor=${version##*.}

# Let's fake the version number of the git version to be compatible with our patching system
export git_minor=$[$rel_minor + 1]

set_git_env_vars() { # Reset project env var if git is used
    export version=${rel_major}.${git_minor}
}

# Only support git version or dealing with optional 2nd "git" argument: update necessary variables
[[ $only_git_project = true ]] || [[ $2 = "git" ]] && set_git_env_vars



# Define tag name
tag_name="$project-$version"

# Set source directory
SRC_DIR=$(cd $(dirname $0) && pwd)

# Extra options handling (set some overridable defaults)
#: ${INSTALL_ROOT:=$HOME}
: ${INSTALL_ROOT:=/home/user}
INST_DIR="$INSTALL_ROOT/lib/$tag_name"
: ${ROOT_SYS_DIR:=/usr/local}
: ${ROOT_PKG_DIR:=/opt}
ROOT_SYMLINK_DIR="$ROOT_PKG_DIR/$project"
PKG_INST_DIR="$ROOT_SYMLINK_DIR-$version"
TARBALLS_DIR="$SRC_DIR/tarballs"
: ${CURL_OPTS:=-sLS}
: ${CFG_OPTS:=}
: ${OPTIMIZE_BUILD:=yes}
[[ "$OPTIMIZE_BUILD" = yes ]] && : ${MAKE_OPTS:=-j4}
export INSTALL_ROOT INST_DIR CURL_OPTS CFG_OPTS MAKE_OPTS TARBALLS_DIR


# Fix people's broken systems
[[ "$(tr A-Z a-z <<<${LANG/*.})" = "utf-8" ]] || export LANG=en_US.UTF-8
unset LC_ALL
export LC_ALL

# Select build tools (prefer 'g' variants if available)
command which gmake >/dev/null && export MAKE=gmake || export MAKE=make
command which glibtoolize >/dev/null && export LIBTOOLIZE=glibtoolize || export LIBTOOLIZE=libtoolize

# Set sed command
export SED_I="sed -i -e"

# Platform magic
platform=$(uname -s | tr '[:upper:]' '[:lower:]')

case "$platform" in
    freebsd)
        export SED_I="sed -i '' -e"
        ;;
esac


# Debian-like package deps
#BUILD_PKG_DEPS=( e2fslibs-dev gettext libaspell-dev libglib2.0-dev libgpm-dev libslang2-dev libssh2-1-dev libx11-dev unzip locales )
BUILD_PKG_DEPS=( e2fsprogs-devel gettext aspell-devel glib2-devel gpm-devel slang-devel libssh2-devel libx11-devel groff unzip )


# gcc optimization
[[ "$OPTIMIZE_BUILD" = yes ]] && export CFLAGS="-march=native -pipe -O2 -fomit-frame-pointer${CFLAGS:+ }${CFLAGS}"
[[ -z "${CXXFLAGS+x}" ]] && [[ -z "${CFLAGS+x}" ]] || \
    export CXXFLAGS="${CFLAGS}${CXXFLAGS:+ }${CXXFLAGS}"


display_env_vars() { # Display env vars
    echo
    echo "${BOLD}Env for building $project into $INST_DIR$OFF"
    echo
    printf "export OPTIMIZE_BUILD=%q\n"     "${OPTIMIZE_BUILD}"
    [[ -z "${CFLAGS+x}" ]] || \
        printf "export CFLAGS=%q\n"         "${CFLAGS}"
    [[ -z "${CXXFLAGS+x}" ]] || \
        printf "export CXXFLAGS=%q\n"       "${CXXFLAGS}"
    echo
    printf 'export INST_DIR=%q\n'           "$INST_DIR"
    echo
    printf 'export CURL_OPTS=%q\n'          "$CURL_OPTS"
    printf 'export MAKE_OPTS=%q\n'          "$MAKE_OPTS"
    printf 'export CFG_OPTS=%q\n'           "$CFG_OPTS"
    echo
}



# Source
TARBALLS=( https://github.com/$owner/$project/archive/$version.tar.gz )

# Source package md5 hashes
SRC_PKG_HASHES=$(cat <<.
4.8.19.tar.gz:6d9e8f8460466055e7fb867b067811e4
4.8.20.tar.gz:05bbbe11037db12e812d66fa00479c3e
.
)


# Directory definition
SUBDIRS="$project-*[0-9]"


# Command dependency
BUILD_CMD_DEPS=$(cat <<.
coreutils:md5sum
curl:curl
grep:egrep
build-essential:$MAKE
build-essential:g++
libtool:$LIBTOOLIZE
automake:aclocal
autoconf:autoconf
automake:automake
autopoint:autopoint
pkg-config:pkg-config
.
)


set -e
set +x
ESC=$(echo -en \\0033)
BOLD="$ESC[1m"
OFF="$ESC[0m"



#
# HELPERS
#

bold() { # [message] : Display bold message
    echo "$BOLD$1$OFF"
}

fail() { # [message] : Display bold message and exit immediately
    bold "ERROR: $@"
    exit 1
}

clean() { # [package-version] : Clean up generated files in directory of packages
    for i in $SUBDIRS; do
        [[ -n "$1" && ! "$i" = "$1" ]] && continue
        sdir=${i%%-*}
        ( cd $i && $MAKE clean && rm -rf $TARBALLS_DIR/DONE-$sdir >/dev/null )
    done
}

clean_all() { # [package-version] : Remove all created directories in the working directory
    [[ -d $TARBALLS_DIR ]] && [[ -f $TARBALLS_DIR/DONE-PKG ]] && rm -f $TARBALLS_DIR/DONE-PKG >/dev/null
    [[ -n "$1" ]] || [[ -f $TARBALLS_DIR/latest_release_info ]] && rm -f $TARBALLS_DIR/latest_release_info >/dev/null
    [[ -n "$1" ]] || [[ -f $TARBALLS_DIR/$tag_name.tar.gz.md5 ]] && rm -f $TARBALLS_DIR/$tag_name.tar.gz.md5 >/dev/null

    for i in $SUBDIRS; do
        [[ -n "$1" && ! "$i" = "$1" ]] && continue
        sdir=${i%%-*}
        [[ ! -d $i ]] || rm -rf $i >/dev/null && rm -rf $TARBALLS_DIR/DONE-$sdir >/dev/null
    done
}

check_deps() { # Check command and package dependency
    for dep in $BUILD_CMD_DEPS; do
        pkg=${dep%%:*}
        cmd=${dep##*:}
        if which $cmd >/dev/null; then :; else
            echo "You don't have the '$cmd' command available, you likely need to:"
            bold "    sudo apt-get install $pkg"
            exit 1
        fi
    done

    local have_dep=''
    local installer=''

    if which dpkg >/dev/null; then
        have_dep='dpkg -l'
        installer='apt-get install'
    elif which pacman >/dev/null; then
        have_dep='pacman -Q'
        installer='pacman -S'
    fi

    if [[ -n "$installer" ]]; then
        for dep in "${BUILD_PKG_DEPS[@]}"; do
            if ! $have_dep "$dep" >/dev/null; then
                echo "You don't have the '$dep' package installed, you likely need to:"
                bold "    sudo $installer $dep"
                exit 1
            fi
        done
    fi
}

prep() { # root_dir : Check dependency and create basic directories
#    check_deps

    if [ "$1" == "$HOME" ]; then
        [[ -f $INST_DIR/bin/$project ]] && fail "Current '$tag_name' version is already built in '$INST_DIR', it has to be removed manually before a new compilation."

        mkdir -p "$INSTALL_ROOT/bin"
        mkdir -p "$INST_DIR/bin"
    else
        [[ -d "$PKG_INST_DIR" ]] && [[ -f "$PKG_INST_DIR/bin/$project" ]] && fail "Could not clean install into dir '$PKG_INST_DIR', dir already exists."
    fi

    mkdir -p "$TARBALLS_DIR"
}

check_hash() { # [package-version.tar.gz] : md5 hashcheck downloaded packages
    for srchash in ${SRC_PKG_HASHES[@]}; do
        pkg=${srchash%%:*}
        hash=${srchash##*:}

        if [ "$1" == "$pkg" ]; then
            echo "$hash  $TARBALLS_DIR/$pkg" | md5sum -c --status 2>/dev/null && break
            rm -f "$TARBALLS_DIR/$pkg" && fail "Checksum failed for $pkg"
        fi
    done
}

download() { # [package-version] : Download and unpack sources
    [[ -d $TARBALLS_DIR ]] && [[ -f $TARBALLS_DIR/DONE-PKG ]] && rm -f $TARBALLS_DIR/DONE-PKG >/dev/null

    for url in "${TARBALLS[@]}"; do
        url_base=${url##*/}
        # skip downloading project here if git version should be used
        [[ "$version" = "${rel_major}.${git_minor}" ]] && continue
        tarball_dir=${url_base%.tar.gz}
        [[ -n "$1" && ! "$tarball_dir" = "$1" ]] && continue
        [[ -f $TARBALLS_DIR/${url_base} ]] || ( echo "Getting $url_base" && command cd $TARBALLS_DIR && curl -O $CURL_OPTS $url )
        [[ -d $tarball_dir ]] || ( check_hash "${url_base}" && echo "Unpacking ${url_base}" && tar xfz $TARBALLS_DIR/${url_base} || fail "Tarball ${url_base} could not be unpacked." )
    done

    if [ "$version" = "${rel_major}.${git_minor}" ]; then
        # getting project from GitHub
        if [ -z ${1+x} ]; then
            download_git $owner $project $git_project
        elif [ "$project-$git_project" = "$1" ]; then
            download_git $owner $project $git_project
        fi
    fi

    touch $TARBALLS_DIR/DONE-PKG
}

download_git() { # owner project commit|branch : Download from GitHub
    owner="$1"; repo="$2"; repo_ver="$3";
    url="https://github.com/$owner/$repo/archive/$repo_ver.tar.gz"
    [[ -f $TARBALLS_DIR/$repo-$repo_ver.tar.gz ]] || ( echo "Getting $repo-$repo_ver.tar.gz" && command cd $TARBALLS_DIR && curl $CURL_OPTS -o $repo-$repo_ver.tar.gz $url )
    [[ -d $repo-$repo_ver* ]] || ( check_hash "$repo-$repo_ver.tar.gz" && echo "Unpacking $repo-$repo_ver.tar.gz" && tar xfz $TARBALLS_DIR/$repo-$repo_ver.tar.gz || fail "Tarball $repo-$repo_ver.tar.gz could not be unpacked.")
    mv $repo-$repo_ver* $repo-$version
}

patch_project() { # Patch project
    echo $tag_name
    [[ -e $TARBALLS_DIR/DONE-PKG ]] && [[ -d $tag_name ]] || fail "You need to '$0 download' first!"

    bold "~~~~~~~~~~~~~~~~~~~~~~~~   Patching $project   ~~~~~~~~~~~~~~~~~~~~~~~~~~"

    pushd $tag_name

    for corepatch in $SRC_DIR/patches/{backport,debian,override}_{*${version}*,all}_*.patch; do
        [[ ! -e "$corepatch" ]] || { bold "$(basename $corepatch)"; patch -uNp1 -i "$corepatch"; }
    done

    popd

    # Bump version number (it's needed since we don't have a full git repo locally)
    $SED_I s%MC_CURRENT_VERSION\ \"\${CURR_MC_VERSION}\"%MC_CURRENT_VERSION\ \"$version\"% "$tag_name/maint/utils/version.sh"
}

copy_contrib() { # Copy files from contrib dir
    # Skins into final place
    [[ -d "$SRC_DIR/contrib/skins/" && -d "$INST_DIR/share/$project/skins/" ]] && cp -f "$SRC_DIR/contrib/skins/"* "$INST_DIR/share/$project/skins/"
}

build_project() { # Build project
    [[ -e $TARBALLS_DIR/DONE-PKG ]] || fail "You need to '$0 download' first!"
    [[ -d $TARBALLS_DIR ]] && [[ -f $TARBALLS_DIR/DONE-$project ]] && rm -f $TARBALLS_DIR/DONE-$project >/dev/null

    bold "~~~~~~~~~~~~~~~~~~~~~~~~   Building $project   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
    ( set +x ; cd $tag_name \
        && ./autogen.sh \
        && ./configure --prefix=$INST_DIR --with-x --with-screen=slang --enable-aspell --enable-vfs-sftp --enable-vfs-undelfs --enable-vfs-smb=yes $CFG_OPTS \
        && $MAKE $MAKE_OPTS \
        && $MAKE install \
        || fail "during building '$project'!" )

    touch $TARBALLS_DIR/DONE-$project

    copy_contrib
}

install() { # Install project
    [[ -e $TARBALLS_DIR/DONE-PKG ]] || fail "You need to '$0 download' first!"
    [[ -d $TARBALLS_DIR ]] && [[ -f $TARBALLS_DIR/DONE-$project ]] && rm -f $TARBALLS_DIR/DONE-$project >/dev/null
    [[ -d "$PKG_INST_DIR" ]] && [[ -f "$PKG_INST_DIR/bin/$project" ]] && fail "Could not clean install into dir '$PKG_INST_DIR', dir already exists."

    bold "~~~~~~~~~~~~~~~~~~~~~~~~   Installing $project   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

    INST_DIR=$PKG_INST_DIR
    build_project
}

symlink_binary_home() { # Symlink binary in HOME
    [[ ! -f "$INST_DIR/bin/$project" ]] && fail "Compilation hasn't been finished, try it again."

    cd "$INSTALL_ROOT/lib"
    ln -nfs "$tag_name" "$project"
    cd "$INSTALL_ROOT/bin"
    ln -nfs "../lib/$project/bin/$project" "$project"
    ln -nfs "$project" mcdiff
    ln -nfs "$project" mcedit
    ln -nfs "$project" mcview
    cd "$SRC_DIR"
}

symlink_binary_inst() { # Symlink binary after it's installed into $ROOT_PKG_DIR dir
    [[ ! -f "$PKG_INST_DIR/bin/$project" ]] && fail "Installation hasn't been finished, try it again."
    [[ -f "$ROOT_SYS_DIR/bin/$project" ]] && [[ ! -L "$ROOT_SYS_DIR/bin/$project" ]] && fail "Could not create symlink '$project' in '$ROOT_SYS_DIR/bin/'"
    [[ -d "$ROOT_SYS_DIR/lib/$project" || -f "$ROOT_SYS_DIR/lib/$project" ]] && [[ ! -L "$ROOT_SYS_DIR/lib/$project" ]] && fail "Could not create symlink '$project' in '$ROOT_SYS_DIR/lib/'"
    [[ -d "$ROOT_SYMLINK_DIR" || -f "$ROOT_SYMLINK_DIR" ]] && [[ ! -L "$ROOT_SYMLINK_DIR" ]] && fail "Could not create symlink '$project' in '$ROOT_PKG_DIR/'"

    ln -nfs "$ROOT_SYMLINK_DIR" "$ROOT_SYS_DIR/lib/$project"
    ln -nfs "$ROOT_SYMLINK_DIR/bin/$project" "$ROOT_SYS_DIR/bin/$project"
    cd "$ROOT_SYS_DIR/bin"
    ln -nfs "$project" mcdiff
    ln -nfs "$project" mcedit
    ln -nfs "$project" mcview
    cd "$ROOT_PKG_DIR"
    ln -nfs "$tag_name" "$project"
    cd "$SRC_DIR"
}

check() { # root_dir : Print some diagnostic success indicators
    if [ "$1" == "$HOME" ]; then
        echo "$1/lib/$project" "->" $(readlink $1/lib/$project) | sed -e "s:$1:~:g"
        echo "$1/bin/$project" "->" $(readlink $1/bin/$project) | sed -e "s:$1:~:g"
    else
        echo "$ROOT_SYMLINK_DIR" "->" $(readlink $ROOT_SYMLINK_DIR)
        echo "$1/lib/$project" "->" $(readlink $1/lib/$project)
        echo "$1/bin/$project" "->" $(readlink $1/bin/$project)
    fi

    # This first selects the rpath dependencies, and then filters out libs not found in the install dirs.
    # If anything is left, we have an external dependency that sneaked in.
    echo
    echo -n "Check that static linking worked: "
    libs=$(ldd "$1/bin/$project")		#"
    if [[ "$(echo "$libs" | egrep "$1/bin" | wc -l)" -eq 0 ]]; then
        echo OK; echo
    else
        echo FAIL; echo; echo "Suspicious library paths are:"
        echo "$libs" | egrep "$1/bin" || :
        echo
    fi

    echo "Dependency library paths:"
    echo "$libs" | sed -e "s:$1/bin/::g"
}



#
# MAIN
#
cd "$SRC_DIR"
case "$1" in
    mc)         ## Build all components into $(sed -e s:$HOME/:~/: <<<$INST_DIR)
                display_env_vars
                prep "$HOME"
                clean_all
                download
                patch_project
                build_project
                display_env_vars
                symlink_binary_home
                check "$HOME"
                ;;
    install)    ## Build all components into $PKG_INST_DIR
                display_env_vars
                prep "$ROOT_SYS_DIR"
                clean_all
                download
                patch_project
                install
                display_env_vars
                symlink_binary_inst
                check "$ROOT_SYS_DIR"
                ;;

    # Dev related actions
    env-vars)   display_env_vars ;;
    clean)      clean ;;
    clean_all)  clean_all ;;
    download)   prep "$HOME"; download ;;
    patch-mc)   display_env_vars; download "$tag_name"; patch_project ;;
    build-mc)   display_env_vars; prep "$HOME"; clean_all "$tag_name"; download "$tag_name"; build_project ;;
    patchbuild) display_env_vars; prep "$HOME"; clean_all "$tag_name"; download "$tag_name"; patch_project; build_project ;;
    sm-home)    symlink_binary_home ;;
    sm-inst)    symlink_binary_inst ;;
    check-home) check "$HOME" ;;
    check-inst) check "$ROOT_SYS_DIR" ;;
    *)
        echo >&2 "${BOLD}Usage: $0 ($project [git] | install [git])$OFF"
        echo >&2 "Build $project into $(sed -e s:$HOME/:~/: <<<$INST_DIR)"
        echo >&2
        echo >&2 "Custom environment variables:"
        echo >&2 "    CURL_OPTS=\"${CURL_OPTS}\" (e.g. --insecure)"
        echo >&2 "    MAKE_OPTS=\"${MAKE_OPTS}\""
        echo >&2 "    CFG_OPTS=\"${CFG_OPTS}\" (e.g. --enable-debug --enable-extra-debug)"
        echo >&2
        echo >&2 "Build actions:"
        grep ").\+##" $0 | grep -v grep | sed -e "s:^:  :" -e "s:): :" -e "s:## ::" | while read i; do
            eval "echo \"   $i\""
        done
        exit 1
        ;;
esac
