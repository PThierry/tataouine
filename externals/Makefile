PROJ_FILES = ../

VERSION = 1

#########################################
######### menuconfig inclusion.
# these rules are accessible only wen the configuration is done
# These rules requires a consistent .conf to use properly its content
include $(PROJ_FILES)/m_config.mk

# generic rules for all Makefiles. These rules can be used at
# any sublevel of the sources
include $(PROJ_FILES)/m_generic.mk

-include Makefile.objs

.PHONY: $(EC_UTILS) std gnat hmac aes $(libs-y)

KEY2HEADER       = $(PROJ_FILES)/tools/key2header.py

##########################################
##### Libecc cryptographic library

external_java_targets :=
external_libs_targets :=

ifeq ($(CONFIG_USR_LIB_SIGN),y)
external_libs_targets += libsign $(EC_UTILS)
endif

ifeq ($(CONFIG_EXT_GP_PRO),y)
external_java_targets += gp
endif

ifeq ($(CONFIG_EXT_ANT_JAVACARD),y)
external_java_targets += antjavacard
endif

ifeq ($(CONFIG_EXT_SECAES),y)
external_libs_targets += secaes
endif

ifeq ($(USE_LLVM),y)
HOST_CC=$(CLANG_PATH)
else
HOST_CC=gcc
endif

all: java libs

java: $(external_java_targets)

libs: $(external_libs_targets)

gp:
	if test ! -f $(PROJ_FILES)/javacard/applet/gp.jar; then \
	cd $(PROJ_FILES)/externals/globalplatformpro && mvn package; \
	cp $(PROJ_FILES)/../externals/globalplatformpro/target/gp.jar $(PROJ_FILES)/../javacard/applet/gp.jar; \
	fi

antjavacard:
	if test ! -f $(PROJ_FILES)/javacard/applet/ant-javacard.jar; then \
	cd $(PROJ_FILES)/externals/ant-javacard && mvn package && ant dist; \
	cp $(PROJ_FILES)/../externals/ant-javacard/ant-javacard.jar $(PROJ_FILES)/../javacard/applet/ant-javacard.jar; \
	fi

secaes: $(BUILD_DIR)/externals
	if ! test -f $(BUILD_DIR)/externals/libmaskedaes.a; then \
		CC=$(CROSS_CC) AR=$(CROSS_AR) COMPILER=$(CROSS_CC) EXTRA_CFLAGS="$(AFLAGS) -Os" $(MAKE) -C secaesstm32 libaes; \
		cp $(PROJ_FILES)/externals/secaesstm32/build/libmaskedaes.a $(BUILD_DIR)/externals/libmaskedaes.a; \
	fi

libsign: $(BUILD_DIR)/externals
	if ! test -f $(BUILD_DIR)/externals/libsign.a; then \
   	  if test -f $(PROJ_FILES)/externals/libecc/build/ec_utils; then \
	    CFLAGS="-DWITH_LIBECC_CONFIG_OVERRIDE $(LIBSIGN_CFLAGS)" $(MAKE) BUILD_DIR="$(BUILD_DIR)" -C $(PROJ_FILES)/externals/libecc clean; \
	  else \
	    mkdir -p $(PROJ_FILES)/externals/libecc/build; \
	  fi; \
	  if test ! -f $(BUILD_DIR)/externals/libsign.a; then \
	    AR_FLAGS=$(CROSS_ARFLAGS) RANLIB=$(CROSS_RANLIB) CC=$(CROSS_CC) AR=$(CROSS_AR) $(MAKE) -C $(PROJ_FILES)/externals/libecc CFLAGS="$(LIBSIGN_CFLAGS) $(AFLAGS) $(WARN_CFLAGS) $(HARDEN_CFLAGS) -pedantic -fno-builtin -std=c99 -Os -D_FORTIFY_SOURCE=2 $(LIB_OPTIM_CFLAGS) -ffunction-sections -fdata-sections -fno-pie -fno-pic" \
	    BUILD_DIR="build"  LIBECC_NOSTDLIB=1 build/libsign.a; \
	    cp $(PROJ_FILES)/externals/libecc/build/libsign.a $(BUILD_DIR)/externals/libsign.a; \
	  fi; \
	fi

$(EC_UTILS): $(BUILD_DIR)/tools
	if ! test -f $(BUILD_DIR)/tools/ec_utils; then \
	  mkdir -p $(PROJ_FILES)/externals/libecc/build; \
	  CFLAGS="-DWITH_LIBECC_CONFIG_OVERRIDE $(LIBSIGN_CFLAGS)" BUILD_DIR="build" make -C $(PROJ_FILES)/externals/libecc clean; \
	  CFLAGS="-DWITH_LIBECC_CONFIG_OVERRIDE $(LIBSIGN_CFLAGS) -fPIC" BUILD_DIR="build" CC=$(CC) AR=$(AR) AR_FLAGS=$(ARFLAGS) AS=$(AS) OBJCOPY=$(OBJCOPY) LD=$(LD) RANLIB=$(RANLIB) $(MAKE) -C $(PROJ_FILES)/externals/libecc; \
	  cp $(PROJ_FILES)/externals/libecc/build/ec_utils $@; \
	fi

$(BUILD_DIR)/tools:
	$(call cmd,mkdir)

$(BUILD_DIR)/externals:
	$(call cmd,mkdir)

