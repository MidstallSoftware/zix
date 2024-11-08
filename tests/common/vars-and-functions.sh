set -eu -o pipefail

if [[ -z "${COMMON_VARS_AND_FUNCTIONS_SH_SOURCED-}" ]]; then

COMMON_VARS_AND_FUNCTIONS_SH_SOURCED=1

export PS4='+(${BASH_SOURCE[0]}:$LINENO) '

export TEST_ROOT=$(realpath ${TMPDIR:-/tmp}/nix-test)/${TEST_NAME:-default}
export NIX_STORE_DIR
if ! NIX_STORE_DIR=$(readlink -f $TEST_ROOT/store 2> /dev/null); then
    # Maybe the build directory is symlinked.
    export NIX_IGNORE_SYMLINK_STORE=1
    NIX_STORE_DIR=$TEST_ROOT/store
fi
export NIX_LOCALSTATE_DIR=$TEST_ROOT/var
export NIX_LOG_DIR=$TEST_ROOT/var/log/nix
export NIX_STATE_DIR=$TEST_ROOT/var/nix
export NIX_CONF_DIR=$TEST_ROOT/etc
export NIX_DAEMON_SOCKET_PATH=$TEST_ROOT/dSocket
unset NIX_USER_CONF_FILES
export _NIX_TEST_SHARED=$TEST_ROOT/shared
if [[ -n $NIX_STORE ]]; then
    export _NIX_TEST_NO_SANDBOX=1
fi
export _NIX_IN_TEST=$TEST_ROOT/shared
export _NIX_TEST_NO_LSOF=1
export NIX_REMOTE=${NIX_REMOTE_-}
unset NIX_PATH
export TEST_HOME=$TEST_ROOT/test-home
export HOME=$TEST_HOME
unset XDG_STATE_HOME
unset XDG_DATA_HOME
unset XDG_CONFIG_HOME
unset XDG_CONFIG_DIRS
unset XDG_CACHE_HOME
mkdir -p $TEST_HOME

export PATH=/home/bmc/sources/nix/outputs/out/bin:$PATH
if [[ -n "${NIX_CLIENT_PACKAGE:-}" ]]; then
  export PATH="$NIX_CLIENT_PACKAGE/bin":$PATH
fi
DAEMON_PATH="$PATH"
if [[ -n "${NIX_DAEMON_PACKAGE:-}" ]]; then
  DAEMON_PATH="${NIX_DAEMON_PACKAGE}/bin:$DAEMON_PATH"
fi
coreutils=/nix/store/a7gvj343m05j2s32xcnwr35v31ynlypr-coreutils-9.1/bin

export dot=
export SHELL="/nix/store/dsd5gz46hdbdk2rfdimqddhq6m8m8fqs-bash-5.1-p16/bin/bash"
export PAGER=cat
export busybox="/nix/store/7b943a2k4amjmam6dnwnxnj8qbba9lbq-busybox-static-x86_64-unknown-linux-musl-1.35.0/bin/busybox"

export version=2.15.0
export system=x86_64-linux

export BUILD_SHARED_LIBS=1

export IMPURE_VAR1=foo
export IMPURE_VAR2=bar

cacheDir=$TEST_ROOT/binary-cache

readLink() {
    ls -l "$1" | sed 's/.*->\ //'
}

clearProfiles() {
    profiles="$HOME"/.local/state/nix/profiles
    rm -rf "$profiles"
}

clearStore() {
    echo "clearing store..."
    chmod -R +w "$NIX_STORE_DIR"
    rm -rf "$NIX_STORE_DIR"
    mkdir "$NIX_STORE_DIR"
    rm -rf "$NIX_STATE_DIR"
    mkdir "$NIX_STATE_DIR"
    clearProfiles
}

clearCache() {
    rm -rf "$cacheDir"
}

clearCacheCache() {
    rm -f $TEST_HOME/.cache/nix/binary-cache*
}

startDaemon() {
    # Don’t start the daemon twice, as this would just make it loop indefinitely
    if [[ "${_NIX_TEST_DAEMON_PID-}" != '' ]]; then
        return
    fi
    # Start the daemon, wait for the socket to appear.
    rm -f $NIX_DAEMON_SOCKET_PATH
    PATH=$DAEMON_PATH nix-daemon &
    _NIX_TEST_DAEMON_PID=$!
    export _NIX_TEST_DAEMON_PID
    for ((i = 0; i < 300; i++)); do
        if [[ -S $NIX_DAEMON_SOCKET_PATH ]]; then
          DAEMON_STARTED=1
          break;
        fi
        sleep 0.1
    done
    if [[ -z ${DAEMON_STARTED+x} ]]; then
      fail "Didn’t manage to start the daemon"
    fi
    trap "killDaemon" EXIT
    # Save for if daemon is killed
    NIX_REMOTE_OLD=$NIX_REMOTE
    export NIX_REMOTE=daemon
}

killDaemon() {
    # Don’t fail trying to stop a non-existant daemon twice
    if [[ "${_NIX_TEST_DAEMON_PID-}" == '' ]]; then
        return
    fi
    kill $_NIX_TEST_DAEMON_PID
    for i in {0..100}; do
        kill -0 $_NIX_TEST_DAEMON_PID 2> /dev/null || break
        sleep 0.1
    done
    kill -9 $_NIX_TEST_DAEMON_PID 2> /dev/null || true
    wait $_NIX_TEST_DAEMON_PID || true
    rm -f $NIX_DAEMON_SOCKET_PATH
    # Indicate daemon is stopped
    unset _NIX_TEST_DAEMON_PID
    # Restore old nix remote
    NIX_REMOTE=$NIX_REMOTE_OLD
    trap "" EXIT
}

restartDaemon() {
    [[ -z "${_NIX_TEST_DAEMON_PID:-}" ]] && return 0

    killDaemon
    startDaemon
}

if [[ $(uname) == Linux ]] && [[ -L /proc/self/ns/user ]] && unshare --user true; then
    _canUseSandbox=1
fi

isDaemonNewer () {
  [[ -n "${NIX_DAEMON_PACKAGE:-}" ]] || return 0
  local requiredVersion="$1"
  local daemonVersion=$($NIX_DAEMON_PACKAGE/bin/nix-daemon --version | cut -d' ' -f3)
  [[ $(nix eval --expr "builtins.compareVersions ''$daemonVersion'' ''$requiredVersion''") -ge 0 ]]
}

requireDaemonNewerThan () {
  isDaemonNewer "$1" || exit 99
}

canUseSandbox() {
    if [[ ! ${_canUseSandbox-} ]]; then
        echo "Sandboxing not supported, skipping this test..."
        return 1
    fi

    return 0
}

fail() {
    echo "$1"
    exit 1
}

# Run a command failing if it didn't exit with the expected exit code.
#
# Has two advantages over the built-in `!`:
#
# 1. `!` conflates all non-0 codes. `expect` allows testing for an exact
# code.
#
# 2. `!` unexpectedly negates `set -e`, and cannot be used on individual
# pipeline stages with `set -o pipefail`. It only works on the entire
# pipeline, which is useless if we want, say, `nix ...` invocation to
# *fail*, but a grep on the error message it outputs to *succeed*.
expect() {
    local expected res
    expected="$1"
    shift
    "$@" && res=0 || res="$?"
    if [[ $res -ne $expected ]]; then
        echo "Expected '$expected' but got '$res' while running '${*@Q}'" >&2
        return 1
    fi
    return 0
}

# Better than just doing `expect ... >&2` because the "Expected..."
# message below will *not* be redirected.
expectStderr() {
    local expected res
    expected="$1"
    shift
    "$@" 2>&1 && res=0 || res="$?"
    if [[ $res -ne $expected ]]; then
        echo "Expected '$expected' but got '$res' while running '${*@Q}'" >&2
        return 1
    fi
    return 0
}

needLocalStore() {
  if [[ "$NIX_REMOTE" == "daemon" ]]; then
    echo "Can’t run through the daemon ($1), skipping this test..."
    return 99
  fi
}

# Just to make it easy to find which tests should be fixed
buggyNeedLocalStore() {
  needLocalStore "$1"
}

enableFeatures() {
    local features="$1"
    sed -i 's/experimental-features .*/& '"$features"'/' "$NIX_CONF_DIR"/nix.conf
}

set -x

onError() {
    set +x
    echo "$0: test failed at:" >&2
    for ((i = 1; i < ${#BASH_SOURCE[@]}; i++)); do
        if [[ -z ${BASH_SOURCE[i]} ]]; then break; fi
        echo "  ${FUNCNAME[i]} in ${BASH_SOURCE[i]}:${BASH_LINENO[i-1]}" >&2
    done
}

# `grep -v` doesn't work well for exit codes. We want `!(exist line l. l
# matches)`. It gives us `exist line l. !(l matches)`.
#
# `!` normally doesn't work well with `set -e`, but when we wrap in a
# function it *does*.
grepInverse() {
    ! grep "$@"
}

# A shorthand, `> /dev/null` is a bit noisy.
#
# `grep -q` would seem to do this, no function necessary, but it is a
# bad fit with pipes and `set -o pipefail`: `-q` will exit after the
# first match, and then subsequent writes will result in broken pipes.
#
# Note that reproducing the above is a bit tricky as it depends on
# non-deterministic properties such as the timing between the match and
# the closing of the pipe, the buffering of the pipe, and the speed of
# the producer into the pipe. But rest assured we've seen it happen in
# CI reliably.
grepQuiet() {
    grep "$@" > /dev/null
}

# The previous two, combined
grepQuietInverse() {
    ! grep "$@" > /dev/null
}

trap onError ERR

fi # COMMON_VARS_AND_FUNCTIONS_SH_SOURCED
