# This is the root Makefile. This Makefile
# shall not be included in any other Makefile
# of the project. Use config.mk instead for
# generic target and .config variables inclusion.
# This Makefile manage the overall project
# build, based on the choice made at configuration time

IMAGE_TYPE = 1
VERSION = 1

#########################################
######### menuconfig inclusion.
# these rules are accessible only wen the configuration is done
# These rules requires a consistent .conf to use properly its content
include m_config.mk

# generic rules for all Makefiles. These rules can be used at
# any sublevel of the sources
include m_generic.mk

#########################################
######### apps, drivers, libs inclusion

# Applications hex files, define, through app-fw-y and app-dfu-y vars, the list of
# configured applications that need to be compiled
-include apps/Makefile.objs
-include apps/Makefile.objs.gen



#########################################
######### root Makefile variables declaration

# we have to generate the list of all app hex files with
# their relative path to the root Makefile.
# first we duplicate the app name (foreach+adduffix), to
# transform ldr/ in ldr/ldr/ then we get the perfix $(BUILD_DIR)
# to all app to finish we substitute the last '/' by .hex
# this require that the app name should finish with a '/'
APPS_FW1_HEXFILES = $(patsubst %,%.fw1.hex,$(addprefix $(BUILD_DIR)/apps/,$(foreach path, $(app-fw-y), $(addsuffix $(path),$(path)/))))
APPS_FW2_HEXFILES = $(patsubst %,%.fw2.hex,$(addprefix $(BUILD_DIR)/apps/,$(foreach path, $(app-fw-y), $(addsuffix $(path),$(path)/))))

APPS_DFU1_HEXFILES = $(patsubst %,%.dfu1.hex,$(addprefix $(BUILD_DIR)/apps/,$(foreach path, $(app-dfu-y), $(addsuffix $(path),$(path)/))))
APPS_DFU2_HEXFILES = $(patsubst %,%.dfu2.hex,$(addprefix $(BUILD_DIR)/apps/,$(foreach path, $(app-dfu-y), $(addsuffix $(path),$(path)/))))

APPS_HEXFILES = $(APPS_FW1_HEXFILES)
ifeq ($(CONFIG_FIRMWARE_DUALBANK),y)
  APPS_HEXFILES += $(APPS_FW2_HEXFILES)
endif

KERNEL_FW1_HEXFILE = $(BUILD_DIR)/kernel/kernel.fw1.hex
KERNEL_FW2_HEXFILE = $(BUILD_DIR)/kernel/kernel.fw2.hex

KERNEL_DFU1_HEXFILE = $(BUILD_DIR)/kernel/kernel.dfu1.hex
KERNEL_DFU2_HEXFILE = $(BUILD_DIR)/kernel/kernel.dfu2.hex

KERNEL_HEXFILES = $(KERNEL_FW1_HEXFILE)
ifeq ($(CONFIG_FIRMWARE_DUALBANK),y)
  KERNEL_HEXFILES += $(KERNEL_FW2_HEXFILE)
endif
ifeq ($(CONFIG_FIRMWARE_MODE_MONO_BANK_DFU),y)
  KERNEL_HEXFILES += $(KERNEL_DFU1_HEXFILE)
  APPS_HEXFILES   += $(APPS_DFU1_HEXFILES)
endif

ifeq ($(CONFIG_FIRMWARE_MODE_DUAL_BANK_DFU),y)
  KERNEL_HEXFILES += $(KERNEL_DFU1_HEXFILE)
  APPS_HEXFILES   += $(APPS_DFU1_HEXFILES)

  KERNEL_HEXFILES += $(KERNEL_DFU2_HEXFILE)
  APPS_HEXFILES   += $(APPS_DFU2_HEXFILES)
endif

# each instance of the kernel must be built independently of the other
.NOTPARALLEL: $(KERNEL_HEXFILES) loader

showapps:
	@echo $(APPS_FW1_HEXFILES)
	@echo $(APPS_FW2_HEXFILES)

# Memory layout
MEM_LAYOUT       = $(BUILD_DIR)/layout.ld
MEM_APP_LAYOUT   = $(BUILD_DIR)/layout.apps.ld
MEM_LAYOUT_DEF   = $(PROJ_FILES)/layouts/arch/socs/$(SOC)/layout.def
MEM_APP_LAYOUT_DEF   = $(PROJ_FILES)/layouts/arch/socs/$(SOC)/layout.apps.def

# project target binaries name, based on .config
BIN_NAME         = $(CONFIG_PROJ_NAME).bin
HEX_NAME         = $(CONFIG_PROJ_NAME).hex
ELF_NAME         = $(CONFIG_PROJ_NAME).elf

DOCU             = doxygen

BUILDDFU         = $(PROJ_FILES)/tools/gen_firmware.py
BUILD_LIBECC_DIR = $(PROJ_FILES)build/$(ARCH)/$(BOARD)

# Flags (deprecated, replaced by .config)
LDFLAGS         += -T$(MEM_LAYOUT) $(AFLAGS) -fno-builtin -nostdlib

# The apps dir(s)
APPS             = apps

# Documentation files
DOC_DIR ?= ./doc/

# local files to delete
TODEL_CLEAN = .config.old doc/doxygen $(BUILD_DIR)/$(BIN_NAME) $(BUILD_DIR)/$(HEX_NAME) $(BUILD_DIR)/$(ELF_NAME) $(BUILD_DIR)/$(BIN_NAME).sign
TODEL_DISTCLEAN = .config include $(CONFIG_BUILD_DIR) $(CONFIG_PRIVATE_DIR)

#########################################
######### root Makefile rules

# target for the classical menuconfig, the only one defined. In theory, we can
# also define make config (dialog) and make qconfig (qt) but menuconfig should
# be enough by now
# as nearly any modification of the configuration require a kernel recompilation,
# we clean the kernel build dir.
menuconfig: check-env
	rm -rf $(BUILD_DIR)/kernel
	$(call cmd,kconf_app_gen)
	$(call cmd,kconf_drvlist_gen)
	$(call cmd,kconf_drv_gen)
	$(call cmd,kconf_liblist_gen)
	$(call cmd,kconf_lib_gen)
	$(call cmd,kconf_root)
	$(call cmd,nokconfig)
	$(call cmd,mkincludedir)
	$(call cmd,prepareada)
	$(call cmd,menuconfig)
	$(call cmd,update_autoconf)
	$(call cmd,mkobjlist_libs)
	$(call cmd,mkobjlist_apps)
	$(call cmd,mkobjlist_drvs)
	$(call cmd,prepare)

#########################################
# from now on, a config file must exists before executing one of the following
# rules
ifeq ($(CONFIG_DONE),y)
all: check-env clean_kernel_headers prepare $(BUILD_DIR)/$(BIN_NAME)
else
all: check-env
	@echo "###########################################"
	@echo "# Wookey SDK information"
	@echo "###########################################"
	@echo "No configuration set. You must first configure the project"
	@echo "This can be done by selecting an existing configuration using:"
	@echo "  $$ make defconfig_list"
	@echo "You can also create a new one using:"
	@echo "  $$ make menuconfig"
	@echo "it is highly recommended to start with an existing configuration"
endif

ifeq ("$(CONFIG_DONE)","y")

#
# As any modification in the user apps permissions or configuration impact the kernel
# generated headers, the kernel headers and as a consequence the kernel binaries need
# to be built again. We decide to require a kernel rebuilt at each all target to be
# sure that the last potential configuration or userspace layout upgrade is taken into
# account in the kernel
#
clean_kernel_headers:
	$(Q)$(MAKE) -C kernel clean_headers
	rm -rf $(BUILD_DIR)/*.bin
	rm -rf $(BUILD_DIR)/*.hex

# prepare generate the include/generated/autoconf.h from the
# .config file. This allows source files to use configured values
# as defines in their code
__prepare:
	$(Q)$(MAKE) -C kernel prepare
	$(call cmd,kconf_app_gen)
	$(call cmd,kconf_drvlist_gen)
	$(call cmd,kconf_drv_gen)
	$(call cmd,kconf_liblist_gen)
	$(call cmd,kconf_lib_gen)
	$(call cmd,kconf_root)
	$(call cmd,nokconfig)
	$(call cmd,mkincludedir)
	$(call cmd,prepareada)
	$(call cmd,mkobjlist_libs)
	$(call cmd,mkobjlist_apps)
	$(call cmd,mkobjlist_drvs)
	$(call cmd,prepare)

prepare: $(BUILD_DIR) __prepare layout devmap $(CONFIG_PRIVATE_DIR)

devmap:
	$(call cmd,devmap)

# generate the memory layout for the target
layout: $(MEM_LAYOUT_DEF)
	$(call if_changed,layout)

# generate the permissions header for EwoK
# from now-on, and downto the endif, these rules
# depend on the existence of the .config file. This is
# checked using the CONFIG_DONE variable. If not,
# these rules are simply ignored, please use
# make prepare and make menuconfig to create the
# .config file.

.PHONY: libs drivers prepare loader prove $(APPS) $(APPS_PATHS) $(BUILD_LIBECC_DIR) $(BUILD_DIR)


applet: externals_java externals_libs
	$(Q)$(MAKE) -C javacard $@

$(BUILD_DIR)/kernel/kernel.fw1.hex: $(BUILD_DIR)/apps/.apps_done
	$(call cmd,prepare_kernel_header_for_fw1)
	$(Q)$(MAKE) -C kernel all EXTRA_LDFLAGS=-Tkernel.fw1.ld APP_NAME=kernel.fw1

$(BUILD_DIR)/kernel/kernel.fw2.hex: $(BUILD_DIR)/apps/.apps_done
ifeq ($(CONFIG_FIRMWARE_DUALBANK),y)
	$(call cmd,prepare_kernel_header_for_fw2)
	$(Q)$(MAKE) -C kernel all EXTRA_LDFLAGS=-Tkernel.fw2.ld APP_NAME=kernel.fw2
endif

$(BUILD_DIR)/kernel/kernel.dfu1.hex: $(BUILD_DIR)/apps/.apps_done
ifeq ($(CONFIG_FIRMWARE_MODE_MONO_BANK_DFU),y)
	$(call cmd,prepare_kernel_header_for_dfu1)
	$(Q)$(MAKE) -C kernel all EXTRA_LDFLAGS=-Tkernel.dfu1.ld APP_NAME=kernel.dfu1
endif
ifeq ($(CONFIG_FIRMWARE_MODE_DUAL_BANK_DFU),y)
	$(call cmd,prepare_kernel_header_for_dfu1)
	$(Q)$(MAKE) -C kernel all EXTRA_LDFLAGS=-Tkernel.dfu1.ld APP_NAME=kernel.dfu1
endif


$(BUILD_DIR)/kernel/kernel.dfu2.hex: $(BUILD_DIR)/apps/.apps_done
ifeq ($(CONFIG_FIRMWARE_MODE_DUAL_BANK_DFU),y)
	$(call cmd,prepare_kernel_header_for_dfu2)
	$(Q)$(MAKE) -C kernel all EXTRA_LDFLAGS=-Tkernel.dfu2.ld APP_NAME=kernel.dfu2
endif


$(BUILD_DIR)/apps/.apps_done: $(APPS)


loader:
	$(Q)$(MAKE) -C $@

$(APPS):
	$(Q)$(MAKE) -C $@

prove:
	$(Q)$(MAKE) -C kernel $@

################# final integration
#
# App1.fw1.elf    \
# App2.fw1.elf     -> wookey.hex -> wookey.bin
# App3.fw1.elf     |
# kernel.fw1.elf   |
# ...              |
#                  |
# App1.fw2.elf     |
# App2.fw2.elf     |
# App3.fw2.elf     |
# kernel.fw2.elf   |
# loader.elf      /
#
#
# user applications ldscripts have their sections prefixed with APP_NAME
# kernel ldscript has specific sections such as .isr_region
# these ldscript are not SoC dependent
#
# fw1.ld and fw2.ld host both app and kernel sections, mapped properly
# depending on the SoC.

# from all elf, finalize into one single binary file
$(BUILD_DIR)/loader/loader.hex: libs loader

$(APPS_FW1_HEXFILES): layout externals_libs libs drivers $(APPS)

$(APPS_FW2_HEXFILES): layout externals_libs libs drivers $(APPS)

libs:
	$(Q)$(MAKE) -C libs all

drivers:
	$(Q)$(MAKE) -C drivers all

$(APPS_HEXFILES):

# binary to flash through JTAG (initial flashing)
$(BUILD_DIR)/$(HEX_NAME): $(APPS_HEXFILES) $(KERNEL_HEXFILES) $(BUILD_DIR)/loader/loader.hex
	$(call if_changed,final_hex)
	$(call if_changed,format_fw)

# firmwares to flash through DFU

$(BUILD_DIR)/$(BIN_NAME): $(BUILD_DIR)/$(HEX_NAME)
	$(call if_changed,final_bin)

#sign: sign_flip sign_flop

sign_flip: $(BUILD_DIR)/flip_fw.bin
	$(call if_changed,sign_flip)

$(BUILD_DIR)/flip_fw.bin:
	$(call if_changed,format_fw)

ifeq ($(CONFIG_FIRMWARE_DUALBANK),y)
sign_flop: $(BUILD_DIR)/flop_fw.bin
	$(call if_changed,sign_flop)

$(BUILD_DIR)/flop_fw.bin:
	$(call if_changed,format_fw)

else
sign_flop:
	@echo "no flop firmware to sign."
endif

endif # CONFIG_DONE=y

# __clean is for local complement of generic clean target.
# the generic clean target will clean $(TODEL_CLEAN) and call __clean if
# the target exist. If not, it will not
__clean:
	$(MAKE) -C apps clean
	$(MAKE) -C kernel clean
	$(MAKE) -C libs clean
	$(MAKE) -C drivers clean
	$(MAKE) -C externals clean
	$(RM) $(RMFLAGS) include
	$(RM) $(RMFLAGS) Kconfig.gen
	$(RM) $(RMFLAGS) $(PROJ_FILES)/layouts/arch/socs/$(SOC)/generated

dumpconfig:
	@echo '======================'
	@echo 'ARCH         : $(ARCH)'
	@echo 'BOARD        : $(BOARD)'
	@echo 'BUILD_DIR    : $(BUILD_DIR)'
	@echo 'BIN_NAME     : $(BIN_NAME)'
	@echo '--------------'
	@echo 'CROSS_COMPILE: $(CROSS_COMPILE)'
	@echo 'CROSS_CC     : $(CROSS_CC)'
	@echo 'CROSS_LD     : $(CROSS_LD)'
	@echo 'CROSS_AR     : $(CROSS_AR)'
	@echo 'CROSS_ARFLAGS: $(CROSS_ARFLAGS)'
	@echo 'CROSS_OBJCOPY: $(CROSS_OBJCOPY)'
	@echo 'CROSS_GDB    : $(CROSS_GDB)'
	@echo 'CROSS_RANLIB : $(CROSS_RANLIB)'
	@echo 'CFLAGS       : $(CFLAGS)'
	@echo 'AFLAGS       : $(AFLAGS)'
	@echo 'DBGFLAGS     : $(DEBUG_CFLAGS)'
	@echo 'APPS_CFLAGS  : $(APPS_CFLAGS)'
	@echo 'LIBS_CFLAGS  : $(LIBS_CFLAGS)'
	@echo 'DRIVERS_CFLAGS: $(DRIVERS_CFLAGS)'
	@echo '--------------'
	@echo 'LIBS_INC     : $(LIB_INC_CFLAGS)'
	@echo 'DRIVERS_INC  : $(DRV_INC_CFLAGS)'
	@echo '--------------'
	@echo 'CC           : $(CC)'
	@echo 'LD           : $(LD)'
	@echo 'AS           : $(AS)'
	@echo 'AR           : $(AR)'
	@echo 'ARFLAGS      : $(ARFLAGS)'
	@echo 'OBJCOPY      : $(OBJCOPY)'
	@echo 'GDB          : $(GDB)'
	@echo 'RANLIB       : $(RANLIB)'
	@echo 'LIBTOOL      : $(LIBTOOL)'
	@echo '======================'
	@echo 'KERNEL_HEXFILES: $(KERNEL_HEXFILES)'
	@echo 'APPS_HEXFILES : $(APPS_HEXFILES)'
	@echo '======================'

#########################################
# these targets manage the device itself
# See the various README for complete information

burn:
	$(ST_FLASH) write $(BUILD_DIR)/$(BIN_NAME) 0x8000000

tburn: $(BUILD_DIR)/$(BIN_NAME)
	{ echo 'reset halt'; sleep 1; echo 'flash write_image erase build/armv7-m/wookey/wookey.hex'; sleep 60; echo 'reset run'; sleep 1; } | telnet localhost 4444 || true

flash: burn

debug: $(ELF_NAME)
	$(GDB) -x gdbfile $(ELF_NAME)

run: $(ELF_NAME)
	$(GDB) -x gdbfile_run $(ELF_NAME)

#########################################
# these targets manage all doc-related builds

#doc: $(PROJ_FILES)/tools/kernel-doc
#	$^ -html `find -name '*.[ch]'` > doc.html 2>/dev/null

.PHONY: doc

$(DOCDIR):
	$(MKDIR) $@

doc:
	$(call cmd,techdoc)
	$(MAKE) -C doc

#########################################
# defconfig support, small and easy

defconfig_list:
	$(call cmd,listdefconfig)

%_defconfig:
	$(call cmd,rm_builddir)
	$(call cmd,kconf_app_gen)
	$(call cmd,kconf_drvlist_gen)
	$(call cmd,kconf_liblist_gen)
	$(call cmd,kconf_drv_gen)
	$(call cmd,kconf_lib_gen)
	$(call cmd,kconf_root)
	$(call cmd,nokconfig)
	$(call cmd,mkincludedir)
	$(call cmd,defconfig)
	$(call cmd,mkobjlist_libs)
	$(call cmd,mkobjlist_apps)
	$(call cmd,mkobjlist_drvs)

#########################################
# these targets manage the test suite
test:
	$(foreach p, $(APPS_PATHS), $(Q)$(MAKE) -C $(p) &&  ) true


tests_suite: CFLAGS += -Itests/ -DTESTS

tests_suite: $(TESTSOBJ) $(ROBJ) $(OBJ) $(SOBJ) $(DRVOBJ)

tests: clean tests_suite $(LDS_GEN)
	$(CC) $(LDFLAGS) -o $(ELF_NAME) $(ROBJ) $(SOBJ) $(OBJ) $(DRVOBJ) $(TESTSOBJ)
	$(GDB) -x gdbfile_run $(ELF_NAME)


#########################################
# Rust related
# these target preemare the Rust libcore for the target
# in order to support Rust apps

libcore:
	if [ ! -f  "rust/libcore/$(TARGET)/$(RUSTBUILD)/libcore.rlib" ];then \
	    if [ ! -d  "rust/libcore/$(TARGET)/$(RUSTBUILD)/build" ];then mkdir -p \
			rust/libcore/$(TARGET)/$(RUSTBUILD)/build; \
		fi;\
		if [ ! -f  "rust/libcore/$(TARGET)/$(RUSTBUILD)/build/$(TARGET).json" ];\
			then cp $(TARGET).json rust/libcore/$(TARGET)/$(RUSTBUILD)/build/;\
		fi;\
		cd rust/libcore/$(TARGET)/$(RUSTBUILD)/build;\
		if [ ! -f  rust.tar.gz ]; then	\
			wget -q -O rust.tar.gz $(RUSTCOREURL); \
		fi;\
		tar -zx --strip-components=1 -f rust.tar.gz;\
		rm rust.tar.gz;\
		if [ ! -f  "../libcore.rlib" ]; \
			then $(RUSTC) -C opt-level=2 -Z \
			no-landing-pads --target $(TARGET) -g src/libcore/lib.rs \
			--out-dir ../; fi;\
		rm -rf ../build; \
	fi;

cleanlibcore:
	rm $(LIBCORE_PATH)/libcore.rlib


$(CONFIG_PRIVATE_DIR):
	if [ -d "$(PROJ_FILES)/javacard" ]; then \
	  if [ ! -d $@ ]; then \
		mkdir $(PROJ_FILES)/$@; $(MAKE) genkeys; \
	  fi; \
	fi

check-env:
ifndef WOOKEY_ENV
	$(error Please, edit 'setenv.sh' and run '. setenv.sh')
endif

######### Javacard applet compilation and provisioning targets

# first private keys generation
# Generate keys
genkeys:
	@# We need ec_utils to generate our keys. Build it
	@make -C externals/;
	@echo $(AUTH_TOKEN_MAX_PIN)  >  tmp_gen_keys_file
	@echo $(AUTH_TOKEN_MAX_SC)   >> tmp_gen_keys_file
	@echo $(DFU_TOKEN_MAX_PIN)   >> tmp_gen_keys_file
	@echo $(DFU_TOKEN_MAX_SC)    >> tmp_gen_keys_file
ifeq ("$(USE_SIG_TOKEN)","USE_SIG_TOKEN")
	@echo $(SIG_TOKEN_MAX_PIN)   >> tmp_gen_keys_file
	@echo $(SIG_TOKEN_MAX_SC)    >> tmp_gen_keys_file
endif
	@echo $(AUTH_TOKEN_PET_PIN)  >> tmp_gen_keys_file
	@echo $(AUTH_TOKEN_PET_NAME) >> tmp_gen_keys_file
	@echo $(DFU_TOKEN_PET_PIN)   >> tmp_gen_keys_file
	@echo $(DFU_TOKEN_PET_NAME)  >> tmp_gen_keys_file
ifeq ("$(USE_SIG_TOKEN)","USE_SIG_TOKEN")
	@echo $(SIG_TOKEN_PET_PIN)   >> tmp_gen_keys_file
	@echo $(SIG_TOKEN_PET_NAME)  >> tmp_gen_keys_file
else
	@echo $(LOCAL_PASSWORD)      >> tmp_gen_keys_file
endif
	@echo $(AUTH_TOKEN_USER_PIN) >> tmp_gen_keys_file
	@echo $(DFU_TOKEN_USER_PIN)  >> tmp_gen_keys_file
ifeq ("$(CONFIG_USE_SIG_TOKEN_BOOL)","y")
	@echo $(SIG_TOKEN_USER_PIN)  >> tmp_gen_keys_file
endif
	@$(GENKEYS) $(KEYS_DIR) $(EC_UTILS) $(ECC_CURVENAME) $(USE_SIG_TOKEN) < tmp_gen_keys_file
	@rm -f tmp_gen_keys_file

######### Firmware signature targets
# Sign the firmwares with user interactions
define sign_interactive_each_fn =
sign_interactive_each_fn_$(1):
	@if [ "$(3)" = "" ]; then \
		echo "\033[1;41m Error: you did not provide a firmware version, which is mandatory. Please provide it with 'version=XX'.\033[1;m"; false; \
	fi
	@# Get the firmware type from the ELF file
	@FIRMWARE_TYPE=$$$$(echo $(1) | tr '[:lower:]' '[:upper:]'); \
	if [ "$(2)" != "" ]; then \
		FIRMWARE_MAGIC=$(2); \
	else \
		FIRMWARE_MAGIC=123456789; \
	fi; \
	if [ "$(4)" != "" ]; then \
		FIRMWARE_CHUNK_SIZE=$(4); \
	else \
		FIRMWARE_CHUNK_SIZE=16384; \
	fi; \
	echo "++++++++++ Interactive signing $$$$FIRMWARE_TYPE, magic=$$$$FIRMWARE_MAGIC, version=$(3), chunk size=$$$$FIRMWARE_CHUNK_SIZE +++++++++++++++"; \
	$(SIGNFIRMWARE) $(KEYS_DIR) $(BUILD_DIR)/$(1)_fw.bin $$$$FIRMWARE_MAGIC $$$$FIRMWARE_TYPE $(3) $$$$FIRMWARE_CHUNK_SIZE "$(CONFIG_USB_DEV_VENDORID)" "$(CONFIG_USB_DEV_PRODUCTID)"
endef

define sign_interactive_fn =
	$(eval FIRM_TO_SIGN = $(subst :, ,$(1)))
	$(eval FIRM_MAGIC = $(2))
	$(eval FIRM_VERSION = $(3))
	$(eval FIRM_CHUNK_SIZE = $(4))
	$(foreach FIRM,$(FIRM_TO_SIGN), \
		$(eval $(call sign_interactive_each_fn,$(FIRM),$(FIRM_MAGIC),$(FIRM_VERSION),$(FIRM_CHUNK_SIZE))) \
	)
endef

define all_sign_interactive_rules_fn =
	$(eval FIRM_TO_SIGN = $(subst :, ,$(1)))
	$(foreach FIRM,$(FIRM_TO_SIGN), \
		$(eval SIGN_INTERACTIVE_RULES += sign_interactive_each_fn_$(FIRM)) \
	)
	$(SIGN_INTERACTIVE_RULES)
endef

sign_interactive_check:
	@if [ "$(tosign)" = "" ]; then \
		echo "Error: 'sign_interactive' rule expects as argument the firmware list to sign: 'tosign=flip:flop'"; \
	fi;:

$(eval $(call sign_interactive_fn,$(tosign),$(magic),$(version),$(chunksize)))
sign_interactive: sign_interactive_check $(call all_sign_interactive_rules_fn, $(tosign))

# Sign the firmwares with no user interactions
define sign_each_fn =
sign_each_fn_$(1):
	@if [ "$(3)" = "" ]; then \
		echo "\033[1;41m Error: you did not provide a firmware version, which is mandatory. Please provide it with 'version=XX'.\033[1;m"; false; \
	fi;
ifeq ("$(USE_SIG_TOKEN)","USE_SIG_TOKEN")
	@# First we check the PET name
	@echo $(SIG_TOKEN_PET_PIN) >  tmp_firmware_sig_file
	@echo "n"                  >> tmp_firmware_sig_file
	@# Get the firmware type
	@FIRMWARE_TYPE=$$$$(echo $(1) | tr '[:lower:]' '[:upper:]'); \
	if [ "$(2)" != "" ]; then \
		FIRMWARE_MAGIC=$(2); \
	else \
		FIRMWARE_MAGIC=123456789; \
	fi; \
	if [ "$(4)" != "" ]; then \
		FIRMWARE_CHUNK_SIZE=$(4); \
	else \
		FIRMWARE_CHUNK_SIZE=16384; \
	fi; \
	(($(SIGNFIRMWARE) $(KEYS_DIR) $(BUILD_DIR)/$(1)_fw.bin $$$$FIRMWARE_MAGIC $$$$FIRMWARE_TYPE $(3) $$$$FIRMWARE_CHUNK_SIZE < tmp_firmware_sig_file) 1> tmp_firmware_sig_log) | true
	@# Check for error
	@CHECK_ERROR=$$$$(cat tmp_firmware_sig_log | grep -i "Error"); \
	if [ "$$$$CHECK_ERROR" != "" ]; then \
		cat tmp_firmware_sig_log; \
		rm -f tmp_firmware_sig_file tmp_firmware_sig_log; \
		false; \
	fi
	@# Check the PET name
	@PET_NAME=$$$$(cat tmp_firmware_sig_log | grep "The PET name for the SIG token is " | sed "s/The PET name for the SIG token is '//g" | sed "s/', is it correct?.*//g"); \
	if [ "$$$$PET_NAME" != $(SIG_TOKEN_PET_NAME) ]; then \
		echo "\033[1;41m Sorry, PET name mismatch ('$$$$PET_NAME' != '$(SIG_TOKEN_PET_NAME)') for the SIG token.\033[1;m"; \
		echo "This can either be *dangerous* or due to an after production modification of the PET name! Please fall back to the interactive signature!"; \
		rm -f tmp_firmware_sig_file tmp_firmware_sig_log; \
		false; \
	fi
	@# If the PET name is OK, go on
	@echo $(SIG_TOKEN_PET_PIN) >  tmp_firmware_sig_file
	@echo "y"                  >> tmp_firmware_sig_file
	@echo $(SIG_TOKEN_USER_PIN)>> tmp_firmware_sig_file
else
	@echo $(LOCAL_PASSWORD)    > tmp_firmware_sig_file
endif
	@# Get the firmware type
	@FIRMWARE_TYPE=$$$$(echo $(1) | tr '[:lower:]' '[:upper:]'); \
	if [ "$(2)" != "" ]; then \
		FIRMWARE_MAGIC=$(2); \
	else \
		FIRMWARE_MAGIC=123456789; \
	fi; \
	if [ "$(4)" != "" ]; then \
		FIRMWARE_CHUNK_SIZE=$(4); \
	else \
		FIRMWARE_CHUNK_SIZE=16384; \
	fi; \
	echo "++++++++++ Automatic signing $$$$FIRMWARE_TYPE, magic=$$$$FIRMWARE_MAGIC, version=$(3), chunk size=$$$$FIRMWARE_CHUNK_SIZE +++++++++++++++"; \
	$(SIGNFIRMWARE) $(KEYS_DIR) $(BUILD_DIR)/$(1)_fw.bin $$$$FIRMWARE_MAGIC $$$$FIRMWARE_TYPE $(3) $$$$FIRMWARE_CHUNK_SIZE "$(CONFIG_USB_DEV_VENDORID)" "$(CONFIG_USB_DEV_PRODUCTID)" < tmp_firmware_sig_file
	@rm -f tmp_firmware_sig_file tmp_firmware_sig_log
endef

define sign_fn =
	$(eval FIRM_TO_SIGN = $(subst :, ,$(1)))
	$(eval FIRM_MAGIC = $(2))
	$(eval FIRM_VERSION = $(3))
	$(eval FIRM_CHUNK_SIZE = $(4))
	$(foreach FIRM,$(FIRM_TO_SIGN), \
  		$(eval $(call sign_each_fn,$(FIRM),$(FIRM_MAGIC),$(FIRM_VERSION),$(FIRM_CHUNK_SIZE))) \
	)
endef

define all_sign_rules_fn =
	$(eval FIRM_TO_SIGN = $(subst :, ,$(1)))
	$(foreach FIRM,$(FIRM_TO_SIGN), \
		$(eval SIGN_RULES += sign_each_fn_$(FIRM)) \
	)
	$(SIGN_RULES)
endef

sign_check:
	@if [ "$(tosign)" = "" ]; then \
		echo "Error: 'sign' rule expects as argument the firmware list to sign: 'tosign=flip:flop'"; \
	fi;

$(eval $(call sign_fn,$(tosign),$(magic),$(version),$(chunksize)))
sign: sign_check $(call all_sign_rules_fn, $(tosign))


######### Firmware verification targets
# Only print the verification information *without* decrypting the file
define verify_info_each_fn =
verify_info_each_fn_$(1):
	@echo "++++++++++ Info on $(1) ++++++++++++++++++++++++++++++"
	@$(VERIFYFIRMWARE) $(KEYS_DIR) $(BUILD_DIR)/$(APP_NAME)/$(1)_fw.bin.signed only_info
endef

define verify_info_fn =
	$(eval FIRM_TO_VERIFY = $(subst :, ,$(1)))
	$(foreach FIRM,$(FIRM_TO_VERIFY), \
  		$(eval $(call verify_info_each_fn,$(FIRM))) \
	)

endef

define all_verify_info_rules_fn =
	$(eval FIRM_TO_VERIFY = $(subst :, ,$(1)))
	$(foreach FIRM,$(FIRM_TO_VERIFY), \
		$(eval VERIFY_INFO_RULES += verify_info_each_fn_$(FIRM)) \
	)
	$(VERIFY_INFO_RULES)
endef

$(eval $(call verify_info_fn,$(toverify)))
verify_info: $(call all_verify_info_rules_fn, $(toverify))

# Verify the firmwares with user interactions
define verify_interactive_each_fn =
verify_interactive_each_fn_$(1):
	@echo "++++++++++ Automatic verification $(1) +++++++++++++++"
	@$(VERIFYFIRMWARE) $(KEYS_DIR) $(BUILD_DIR)/$(APP_NAME)/$(1)_fw.bin.signed
endef

define verify_interactive_fn =
	$(eval FIRM_TO_VERIFY = $(subst :, ,$(1)))
	$(foreach FIRM,$(FIRM_TO_VERIFY), \
  		$(eval $(call verify_interactive_each_fn,$(FIRM))) \
	)

endef

define all_verify_interactive_rules_fn =
	$(eval FIRM_TO_VERIFY = $(subst :, ,$(1)))
	$(foreach FIRM,$(FIRM_TO_VERIFY), \
		$(eval VERIFY_INTERACTIVE_RULES += verify_interactive_each_fn_$(FIRM)) \
	)
	$(VERIFY_INTERACTIVE_RULES)
endef

verify_interactive_check:
	@if [ "$(toverify)" = "" ]; then \
		echo "Error: 'verify_interactive' rule expects as argument the firmware list to verify: 'toverify=flip:flop'"; \
	fi;

$(eval $(call verify_interactive_fn,$(toverify)))
verify_interactive: verify_interactive_check $(call all_verify_interactive_rules_fn, $(toverify))


# Verify the firmwares without user interactions
define verify_each_fn =
verify_each_fn_$(1):
	@echo "++++++++++ Interactive verification $(1) +++++++++++++++"
	@# Clean stuff
	@rm -f tmp_firmware_verif_file tmp_firmware_verif_log;
	@# First we check the PET name
	@echo $(DFU_TOKEN_PET_PIN) >  tmp_firmware_verif_file
	@echo "n"                  >> tmp_firmware_verif_file
	@(($(VERIFYFIRMWARE) $(KEYS_DIR) $(BUILD_DIR)/$(1)_fw.bin.signed < tmp_firmware_verif_file) 1> tmp_firmware_verif_log) | true
	@# Check signature
	@CHECK_SIG=$$$$(cat tmp_firmware_verif_log | grep "bad signature"); \
	if [ "$$$$CHECK_SIG" != "" ]; then \
		echo "\033[1;41m Error: bad signature for $(1).bin.signed\033[1;m"; \
		rm -f tmp_firmware_verif_file tmp_firmware_verif_log; \
		false; \
	fi
	@# Check for error
	@CHECK_ERROR=$$$$(cat tmp_firmware_verif_log | grep -i "Error"); \
	if [ "$$$$CHECK_ERROR" != "" ]; then \
		cat tmp_firmware_verif_log; \
		rm -f tmp_firmware_verif_file tmp_firmware_verif_log; \
		false; \
	fi
	@# Check the PET name
	@PET_NAME=$$$$(cat tmp_firmware_verif_log | grep "The PET name for the DFU token is " | sed "s/The PET name for the DFU token is '//g" | sed "s/', is it correct?.*//g"); \
	if [ "$$$$PET_NAME" != $(DFU_TOKEN_PET_NAME) ]; then \
		echo "\033[1;41m Sorry, PET name mismatch ('$$$$PET_NAME' != '$(DFU_TOKEN_PET_NAME)') for the DFU token.\033[1;m"; \
		echo "This can either be *dangerous* or due to an after production modification of the PET name! Please fall back to the interactive verification!"; \
		rm -f tmp_firmware_verif_file tmp_firmware_verif_log; \
		false; \
	fi
	@# If the PET name is OK, go on
	@echo $(DFU_TOKEN_PET_PIN) >  tmp_firmware_verif_file
	@echo "y"                  >> tmp_firmware_verif_file
	@echo $(DFU_TOKEN_USER_PIN)>> tmp_firmware_verif_file
	@$(VERIFYFIRMWARE) $(KEYS_DIR) $(BUILD_DIR)/$(1)_fw.bin.signed < tmp_firmware_verif_file
	@rm -f tmp_firmware_verif_file tmp_firmware_verif_log
endef

define verify_fn =
	$(eval FIRM_TO_VERIFY = $(subst :, ,$(1)))
	$(foreach FIRM,$(FIRM_TO_VERIFY), \
  		$(eval $(call verify_each_fn,$(FIRM))) \
	)
endef

define all_verify_rules_fn =
	$(eval FIRM_TO_VERIFY = $(subst :, ,$(1)))
	$(foreach FIRM,$(FIRM_TO_VERIFY), \
		$(eval VERIFY_RULES += verify_each_fn_$(FIRM)) \
	)
	$(VERIFY_RULES)
endef

verify_check:
	@if [ "$(toverify)" = "" ]; then \
		echo "Error: 'verify' rule expects as argument the firmware list to verify: 'toverify=flip:flop'"; \
	fi;

$(eval $(call verify_fn,$(toverify)))
verify: verify_check $(call all_verify_rules_fn, $(toverify))




#
#

javacard_compile: externals_java
	@cd javacard && make applet_auth
	@cd javacard && make applet_dfu
ifeq ("$(USE_SIG_TOKEN)","USE_SIG_TOKEN")
	@cd javacard && make applet_sig
endif

javacard_clean:
	@cd javacard && make clean_applets

javacard_push_auth:
	@cd javacard && make push_auth

javacard_push_dfu:
	@cd javacard && make push_dfu

javacard_purge:
	@cd javacard && make purge_applets


ifeq ("$(USE_SIG_TOKEN)","USE_SIG_TOKEN")
javacard_push_sig:
	@cd javacard && make push_sig

javacard_push: javacard_push_auth javacard_push_dfu javacard_push_sig
else
javacard_push: javacard_push_auth javacard_push_dfu
endif


javacard: javacard_compile javacard_push

externals_java:
	@make -C externals java

externals_libs:
	@make -C externals libs

