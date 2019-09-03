#!/usr/bin/env sh

export WOOKEY_ENV=true

# this is the script for setting user environment in order to set the various
# tools paths and names
# this script is separated from the Kconfig content in order to allow the user
# to specify its own paths and name without having them overloaded when using
# defconfig files.
# This file is keeped in git, as it contains all the explanation for all
# requested variables. As the user is intented to update this very variables with
# this own values, this script is sourcing the local file named 'setenv.local.sh'
# in the same way as OpenBSD configuration scripts.
# This permit the user to write a setenv.local.conf file with its own variables
# set, with a fallback to the following variables if not needed.
# The setenv.local.sh file is not requested if the following variables are
# correctly set for the local user's configuration.

# 1) The Ada runtime installation path. This path is the parent directory of
# the gnat cross-toolchain. It should contains directories such as arm-eabi/
# (for the target runtime), /bin (for the host tools), and so on.
# Setting this directory *does not* means that you can avoid adding the bin/ subdir
# of the Ada toolchain to you PATH. This is a required action.

export ADA_RUNTIME=$(dirname $(dirname $(which arm-eabi-gnat)))

# 3) This is the path (including the name) of the st-flash tool. This tool
# is used to flash STM32 boards. Setting this path is not required as you
# can flash the target with another tool (gdb+openocd, telnet+openocd, and so
# on).

export ST_FLASH="/usr/local/bin/st-flash"

# 4) This is the path (including the name) of the st-util tool. This tool
# is used to interact with the STM32 boards. Setting this path is not required
# as this is only a helper tool and is not required to build and flash the
# target. Although, it can be helpfull to get back some information about your
# board as it is used by the tataouine 'burn' helper target which compile the
# firmware and flash the device.

export ST_UTIL="/usr/local/bin/st-flash"

# 5) The classical "CROSS_COMPILE" variable, specifying the cross-toolchain prefix.
# This variable is used only for the C compiler (not for Ada which is using its
# own in its gpr files). Depending on your C cross-compiler installation, this
# prefix may varies.
# WARNING: if you use the Ada toochain, please be sure to use the Ada toolchain C compiler
# to avoid unexpected link and run problems due to incompatible compilers versions.
# The AdaCore Ada toolchain is using the arm-eabi- prefix for its toolchain

export CROSS_COMPILE="arm-none-eabi-"

# 6) By default, the SDK is using GCC for cross-compiling. It is possible to
# use LLVM to get a better static analysis through clang and build-check.
# Although, *this requires clang 7 and higher*. By now, LLVM support is
# *EXPERIMENTAL* and is not yet fully integrated.
# Using LLVM still requires GNU LD greater than 2.30 (which is typically not
# the case if you use the Ada Cross-toolchain integrated CC compiler suite).
# set this variable to 'y' if you which to use LLVM/Clang instead of gcc

export USE_LLVM=n

# 7) Specify clang path, if you clang installation is not standard (multiple
# versions, etc.).
#
export CLANG_PATH="/usr/bin/clang"

# 8) Specify the Javacard Oracle SDK installation path. This SDK is used in
# order to compile the Javacard applets. Please specify the SDK root directory
# (for e.g. /opt/java_sc_3.0.4)
export JAVA_SC_SDK="$PWD/javacard/applet/sdks/jc303_kit/"

# All the above variables are "standard values". Now you can override any of
# them by rewriting 'export VARNAME="content" on your own setenv.local.sh file
# if needed to overload any of the above. For that, just create the setenv.local.sh
# file in this same directory and update the variables you need.

# overriding the above variable with the user configuration, if the file exists.
if test -f setenv.local.sh; then
  source setenv.local.sh
fi

which ${CROSS_COMPILE}gcc > /dev/null
if [ $? -ne 0 ]; then
    echo "ERROR: your cross-toolchain is not in your path !"
    echo "please update your PATH variable first by including your cross-toolchain"
    echo "bin/ directory"
    return 1
fi

# Let's print you current configuration

echo "========================================================="
echo "=== Tataouine environment configuration"
echo "========================================================="
echo
echo "  *: required to fully build the project"
echo
echo " *ADA_RUNTIME   = $ADA_RUNTIME"
echo "  ST_FLASH      = $ST_FLASH"
echo "  ST_UTIL       = $ST_UTIL"
echo " *CROSS_COMPILE = $CROSS_COMPILE"
echo "  USE_LLVM      = $USE_LLVM"
echo "  CLANG_PATH    = $CLANG_PATH"
echo " *JAVA_SC_SDK   = $JAVA_SC_SDK"
echo
echo "========================================================="

if test -z "$ADA_RUNTIME"; then
    echo "Invalid ADA_RUNTIME! Please check that your Ada toolchain binaries are in your PATH"
fi
