# This file define the verbose and quiet versions of each compilation/link/objcopy etc. action
# this file can be increase as needed to adapt the root and leaf Makefile accordingly
# This permits to support both quiet execution (standard mode) and verbose execution (using V=1 or V=2)
#
# When using silent mode, all action is written in the corresponding file (relative to $@) prefixed with a
# dot and finishing with a .cmd (same as the Linux kernel) to be able to read what command as been executed
#
# basic usage:
# there is two definition: the command itself and its pretty printing for the silent mode
# the command itself is always executed, but printed only in verbose mode (V>=1)
#
# to call a command depending on the prerequisites (typically for compilation, to detect change in any
# prerequisite files, use the following syntax:
# $(call if_changed,<command>) e.g. : $(call if_changed,cc_o_c)
#
# to call a command at each time (typically a clean or menuconfig target, use the following
# syntax:
# $(call cmd,<command>) e.g. : $(call cmd,clean)
#
# For advanced usage, read the tools/Kconfig.include file

# classical C Compiling (c => o)
quiet_cmd_cc_o_c        = CC       $@
      cmd_cc_o_c        = test -d $(dir $@) || mkdir -p $(dir $@); $(CROSS_CC) $< -c $(CFLAGS) -o $@

quiet_cmd_cc_o_asm      = ASM      $@
      cmd_cc_o_asm      = test -d $(dir $@) || mkdir -p $(dir $@); $(CROSS_CC) $< -c $(AFLAGS) -fno-builtin -nostdlib -o $@

quiet_cmd_ada_lib       = ADA      $@
      cmd_ada_lib       = ADA_ARCH=$(CONFIG_ADA_ARCH) ADA_RUNTIME=$(ADA_RUNTIME) ADA_PROFILE=$(CONFIG_ADA_PROFILE) BUILD_DIR=$(APP_BUILD_DIR) ARCH=$(CONFIG_ARCH) SOCNAME=$(CONFIG_SOCNAME) KERNEL_ADA_BUILDSIZE=$(CONFIG_KERNEL_ADA_BUILDSIZE) MODE=$(CONFIG_KERNEL_MODE) gprbuild -P$<

quiet_cmd_ada_exe       = ADA      $@
      cmd_ada_exe       = ADA_ARCH=$(CONFIG_ADA_ARCH) ADA_RUNTIME=$(ADA_RUNTIME) ADA_PROFILE=$(CONFIG_ADA_PROFILE) BUILD_DIR=$(APP_BUILD_DIR) ARCH=$(CONFIG_ARCH) SOCNAME=$(CONFIG_SOCNAME) KERNEL_ADA_BUILDSIZE=$(CONFIG_KERNEL_ADA_BUILDSIZE) MODE=$(CONFIG_KERNEL_MODE) gprbuild -P$<

quiet_cmd_ada_clean     = ADACLEAN $<
      cmd_ada_clean     = ADA_ARCH=$(CONFIG_ADA_ARCH) ADA_RUNTIME=$(ADA_RUNTIME) ADA_PROFILE=$(CONFIG_ADA_PROFILE) BUILD_DIR=$(APP_BUILD_DIR) ARCH=$(CONFIG_ARCH) SOCNAME=$(CONFIG_SOCNAME) KERNEL_ADA_BUILDSIZE=$(CONFIG_KERNEL_ADA_BUILDSIZE) MODE=$(CONFIG_KERNEL_MODE) gprclean -c -P$< >/dev/null 2>&1

quiet_cmd_ada_distclean = ADADCLEAN $<
      cmd_ada_distclean = ADA_ARCH=$(CONFIG_ADA_ARCH) ADA_RUNTIME=$(ADA_RUNTIME) ADA_PROFILE=$(CONFIG_ADA_PROFILE) BUILD_DIR=$(APP_BUILD_DIR) ARCH=$(CONFIG_ARCH) SOCNAME=$(CONFIG_SOCNAME) KERNEL_ADA_BUILDSIZE=$(CONFIG_KERNEL_ADA_BUILDSIZE) MODE=$(CONFIG_KERNEL_MODE) gprclean -P$< >/dev/null 2>&1

# classical Ada Compiling (adb => o)
quiet_cmd_gnat_o_ada    = GNAT     $@
      cmd_gnat_o_ada    = arm-eabi-gnatmake -gnat2012 --RTS=$(RTS) -c -cargs -c $(CONFIG_AFLAGS) -i $< -o $@

# managing fw and dfu build for apps
quiet_cmd_buildapp      = APP     $@
      cmd_buildapp      = make -C $@ alldeps; \
	                      cp $(BUILD_DIR)/libs/*/lib*.a $(BUILD_DIR)/apps/$@; \
						  cp $(BUILD_DIR)/drivers/*/lib*.a $(BUILD_DIR)/apps/$@; \
						  if [ -f $(BUILD_DIR)/apps/$@/$@.fw1.ld ]; then make -C $@ all EXTRA_LDFLAGS="-T$@.fw1.ld" APP_NAME=$@.fw1; fi; \
						  if [ ! -z "$(CONFIG_FIRMWARE_DUALBANK)" ]; then if [ -f $(BUILD_DIR)/apps/$@/$@.fw2.ld ]; then make -C $@ all EXTRA_LDFLAGS="-T$@.fw2.ld" APP_NAME=$@.fw2; fi; fi; \
						  if [ -f $(BUILD_DIR)/apps/$@/$@.dfu1.ld ]; then make -C $@ all EXTRA_LDFLAGS="-T$@.dfu1.ld -DMODE_DFU" APP_NAME=$@.dfu1; fi; \
						  if [ ! -z "$(CONFIG_FIRMWARE_DUALBANK)" ]; then if [ -f $(BUILD_DIR)/apps/$@/$@.dfu2.ld ]; then make -C $@ all EXTRA_LDFLAGS="-T$@.dfu2.ld" APP_NAME=$@.dfu2; fi; fi

# linking
quiet_cmd_ldscript      = LDSCRIPT $@
      cmd_ldscript      = $(PROJ_FILES)tools/gen_app_ld.pl $(BUILD_DIR) $(PROJ_FILES)/.config

# linking
quiet_cmd_k_ldscript    = LDSCRIPT $@
      cmd_k_ldscript    = sed -e 's:BUILDDIR:$(BUILD_DIR):g' $< | sed -e 's:APP_NAME:$(APP_NAME):g' |  perl -pe 's/^INCLUDE (.*)/`cat $$1`/e' > $(APP_BUILD_DIR)/$(APP_NAME).ld

# classical Ada Compiling (adb => o)
quiet_cmd_gnat_o_ali    = GNATBIND $@
      cmd_gnat_o_ali    = arm-eabi-gnatmake -gnat2012 --RTS=$(RTS) -b -bargs -n $(AALI)

# linking
# gcc symbols (see cc_a_syms) must be prefixed again here, to avoid collision
# of syms when generating the firmware. as they are resolved at link time,
# they can be prefixed after without arm
quiet_cmd_link_o_target = LD       $@
      cmd_link_o_target = $(CROSS_CC) $(CFLAGS) $(LDFLAGS) $(ARCH_OBJ) $(SOBJ) $(OBJ) $(DRVOBJ) $(CORE_OBJ) $(SOC_OBJ) $(BOARD_OBJ) $(SOCASM_OBJ) $(LD_LIBS) -o $@

# ADA linking
quiet_cmd_adalink_o_target = ADALD    $@
      cmd_adalink_o_target = arm-eabi-gnatmake -gnat2012 --RTS=$(RTS) -l -largs $(LD_LIBS) $(LDFLAGS) $(lastword $(AALI)) $(ARCH_OBJ) $(ROBJ) $(SOBJ) $(OBJ) $(DRVOBJ) $(CORE_OBJ) $(SOC_OBJ) $(BOARD_OBJ) -o $@

#####################################################################
# Kernel headers generation
#  Ewok is based on some autogenerated headers for application permissions
#  and layout. These headers are assumed to exist by the kernel build system
#  and are generated here.
#

quiet_cmd_prepare_kernel_header_for_fw1 = KERNHEADER_FW1
      cmd_prepare_kernel_header_for_fw1 = \
         ./kernel/tools/gen_ld.pl $(CONFIG_ARCH) $(CONFIG_BOARDNAME) $(BUILD_DIR)/apps_sections.fw1.ld fw1 $(PROJ_FILES)/.config; \
		 ./kernel/tools/gen_symhdr.pl $(CONFIG_ARCH) $(CONFIG_BOARDNAME) fw1 .config; \
	     ./kernel/tools/permissions.pl FW $(PROJ_FILES)/.config $(PROJ_FILES)/apps/ipc.config $(PROJ_FILES)/apps/dmashm.config

quiet_cmd_prepare_kernel_header_for_fw2 = KERNHEADER_FW2
      cmd_prepare_kernel_header_for_fw2 = \
         ./kernel/tools/gen_ld.pl $(CONFIG_ARCH) $(CONFIG_BOARDNAME) $(BUILD_DIR)/apps_sections.fw2.ld fw2 $(PROJ_FILES)/.config; \
		 ./kernel/tools/gen_symhdr.pl $(CONFIG_ARCH) $(CONFIG_BOARDNAME) fw2 .config; \
	     ./kernel/tools/permissions.pl FW $(PROJ_FILES)/.config $(PROJ_FILES)/apps/ipc.config $(PROJ_FILES)/apps/dmashm.config

quiet_cmd_prepare_kernel_header_for_dfu1 = KERNHEADER_DFU1
      cmd_prepare_kernel_header_for_dfu1 = \
         ./kernel/tools/gen_ld.pl $(CONFIG_ARCH) $(CONFIG_BOARDNAME) $(BUILD_DIR)/apps_sections.dfu1.ld dfu1 $(PROJ_FILES)/.config; \
		 ./kernel/tools/gen_symhdr.pl $(CONFIG_ARCH) $(CONFIG_BOARDNAME) dfu1 .config; \
	     ./kernel/tools/permissions.pl DFU $(PROJ_FILES)/.config $(PROJ_FILES)/apps/ipc.config $(PROJ_FILES)/apps/dmashm.config

quiet_cmd_prepare_kernel_header_for_dfu2 = KERNHEADER_DFU2
      cmd_prepare_kernel_header_for_dfu2 = \
         ./kernel/tools/gen_ld.pl $(CONFIG_ARCH) $(CONFIG_BOARDNAME) $(BUILD_DIR)/apps_sections.dfu2.ld dfu2 $(PROJ_FILES)/.config; \
		 ./kernel/tools/gen_symhdr.pl $(CONFIG_ARCH) $(CONFIG_BOARDNAME) dfu2 .config; \
	     ./kernel/tools/permissions.pl DFU $(PROJ_FILES)/.config $(PROJ_FILES)/apps/ipc.config $(PROJ_FILES)/apps/dmashm.config




# rust compilation
quiet_cmd_rc_o_rs       = RC       $@
      cmd_rc_o_rs       = $(RUSTC) $< --emit obj --target $(TARGET) -L $(LIBCORE_PATH) -o $@


# hex file generation
quiet_cmd_objcopy_ihex  = OBJ/HEX  $@
      cmd_objcopy_ihex  = $(CROSS_OBJCOPY) -O ihex $< $@

# bin file generation
quiet_cmd_objcopy_bin   = OBJ/BIN  $@
      cmd_objcopy_bin   = $(CROSS_OBJCOPY) -O binary $< $@

# layout build
quiet_cmd_layout        = LAYOUT   $@
      cmd_layout        = $(CROSS_CC) $(AFLAGS) $(WARN_CFLAGS) $(EMBED_CFLAGS) -E -x c $(MEM_LAYOUT_DEF) -I. -Iinclude/generated -Ikernel/src/arch/socs/$(SOC)/C -Ikernel/src/arch/cores/$(CONFIG_ARCH)/C -Ikernel/src/arch/boards/$(CONFIG_BOARDNAME) $(LDS) $(LDS_GEN) | grep -v '^\#' > $(MEM_LAYOUT); \
                          $(CROSS_CC) $(AFLAGS) $(WARN_CFLAGS) $(EMBED_CFLAGS) -E -x c $(MEM_APP_LAYOUT_DEF) -I. -Iinclude/generated -Ikernel/src/arch/socs/$(SOC)/C -Ikernel/src/arch/cores/$(CONFIG_ARCH)/C -Ikernel/src/arch/boards/$(CONFIG_BOARDNAME) $(LDS) $(LDS_GEN) | grep -v '^\#' > $(MEM_APP_LAYOUT)

# final layout build
quiet_cmd_final_layout  = END/LAY  $@
      cmd_final_layout  = sed -e 's:BUILDDIR:$(BUILD_DIR):g' $< | sed -e 's:APP_NAME:$(APP_NAME):g' > $@

# final elf file generation
quiet_cmd_final_elf     = END/ELF  $@
      cmd_final_elf     = $(CROSS_LD) -T$< -b elf32-littlearm -o $@ $(BUILD_DIR)/kernel/kernel.elf $(APPS_ELFFILES)

# final hex file generation
quiet_cmd_final_hex     = END/HEX  $@
      cmd_final_hex     = $(BUILDDFU) $^ $@ 0

# final hex file generation
quiet_cmd_final_bin     = END/BIN  $@
      cmd_final_bin     = $(CROSS_OBJCOPY) -I ihex --output-target=binary $< $@

# make static library
quiet_cmd_mklib         = AR       $@
      cmd_mklib         = $(CROSS_AR) $(CROSS_ARFLAGS) $@ $^

# make static library from multiple static libraries
quiet_cmd_fusionlib     = FUSION   $@
cmd_fusionlib           = for i in $^; do $(CROSS_AR) -x $$i; done; $(CROSS_AR) $(CROSS_ARFLAGS) $@ *.o; $(CROSS_RANLIB) $@; $(RM) *.o

# make static library
quiet_cmd_ranlib        = RANLIB   $@
      cmd_ranlib        = $(CROSS_RANLIB) $@

quiet_cmd_mkapplet      = APPLET   $@
      cmd_mkapplet      = mkdir -p $(BUILD_DIR)/javacard/applet; touch $(BUILD_DIR)/javacard/applet/.applet.cmd.ant; cd $(PROJ_FILES)/javacard/applet && ant -Dbuilddir=../$(BUILD_DIR)/javacard/applet -logfile ../$(BUILD_DIR)/javacard/applet/.applet.cmd.ant

# make build directory
quiet_cmd_mkdir         = MKDIR      $@
      cmd_mkdir         = mkdir -p $@

# make build directory
quiet_cmd_rm_builddir   = RMDIR  $(BUILD_DIR)
      cmd_rm_builddir   = if test -d "$(BUILD_DIR)"; then rm -rf $(BUILD_DIR); fi

# generic GNU target
quiet_cmd_clean         = CLEAN
      cmd_clean         = make -C . -npq --no-print-directory .DEFAULT 2>/dev/null |grep -q ^__clean && $(MAKE) __clean; rm -rf $(TODEL_CLEAN)

# generic GNU target
quiet_cmd_distclean     = DISTCLEAN
      cmd_distclean     = make -C . -npq --no-print-directory .DEFAULT 2>/dev/null |grep -q ^__distclean && $(MAKE) __distclean; rm -rf $(TODEL_DISTCLEAN)

# about menuconfig, oldconfig and so on...
quiet_cmd_menuconfig    = MENUCONFIG
      cmd_menuconfig    = $(MCONF) Kconfig

quiet_cmd_mkincludedir  = MKINCLUDEDIR
      cmd_mkincludedir  = mkdir -p $(PWD)/include && mkdir -p $(PWD)/include/config $(PWD)/include/generated

quiet_cmd_pepareada     = PREPAREADA
      cmd_prepareada    = if [ "y" = "$(ADAKERNEL)" ]; then for i in $(shell cat kernel/libgnat/gnat/link_list.txt); do ln -fs $(ADA_RUNTIME)/arm-eabi/lib/gnat/zfp-stm32f4/gnat/$$i $(PWD)/kernel/libgnat/gnat/$$i; done; fi

quiet_cmd_prepare       = PREPARE
      cmd_prepare       = $(CONF) $(CONF_ARGS) Kconfig; ./kernel/tools/gen_autoconf_ada.pl .config; \
						  $(CONFGEN) $(CONFGEN_ARGS) Kconfig

# tiny defconfig support, please don't call any other target depending on config here,
# m_config.mk should be relaoded
quiet_cmd_defconfig     = DEFCONFIG  $@
      cmd_defconfig     = cp configs/$@ .config && $(CONF) $(CONF_ARGS) Kconfig

quiet_cmd_listdefconfig = LISTDEFS   $@
cmd_listdefconfig = find  configs/ -type f -iname '*_defconfig' | sed -e 's:^configs/::g' |sort

# documentation part
quiet_cmd_mkman2        = MAN        $@
      cmd_mkman2        = rst2man --title="EwoK syscalls API"  --no-generator --no-datestamp --no-source-link $</$(patsubst %.2,%.rst,$(notdir $@)) $@

quiet_cmd_mkman3        = MAN        $@
      cmd_mkman3        = rst2man --title="EwoK syscalls API"  --no-generator --no-datestamp --no-source-link $</$(patsubst %.3,%.rst,$(notdir $@)) $@

quiet_cmd_mkhtml        = HTML       $@
      cmd_mkhtml        = rm -rf ../$@/html; BUILDDIR=../$@ make -C sphinx html >/dev/null 2>&1

quiet_cmd_mklatex       = LATEX      $@
      cmd_mklatex       = BUILDDIR=../$@ make -C sphinx latex >/dev/null 2>&1


quiet_cmd_techdoc       = TECHDOC
      cmd_techdoc       = rm -f $(PROJ_FILES)/doc/sphinx/source/publi.rst.gen; for i in $(PROJ_FILES)/drivers/socs/$(SOC)/* $(PROJ_FILES)/libs/* kernel; do if test -d $$i; then $(MAKE) -C $$i doc; fi; done; builddir=$(BUILD_DIR); for i in `find $$builddir/drivers -type f -iname '*.pdf'` `find $$builddir/libs -type f -iname '*.pdf'` $(BUILD_DIR)/kernel/doc/latex/ewok.pdf; do prefix=`basename $${i%%.pdf}`; cp $$i $(PROJ_FILES)/doc/sphinx/source/_downloads/; echo "   * $$prefix :download:\`technical manual <_downloads/$$prefix.pdf>\`" >> $(PROJ_FILES)/doc/sphinx/source/publi.rst.gen; done

# as apps are hosted by other repositories, applist is dynamic for Kconfig, and generated here
quiet_cmd_kconf_app_gen = KCONF
      cmd_kconf_app_gen = rm -f $(PROJ_FILES)/apps/Kconfig.gen; for i in $(shell find apps -maxdepth 1 -mindepth 1 -type d ! -iname '.git'); do /bin/echo "source \"$$i/Kconfig\"" >> $(PROJ_FILES)/apps/Kconfig.gen; done


# as drivers are hosted by other repositories, driverlist is dynamic for Kconfig, and generated here.
# The drivers CFLAGS list is also generated here using the below for-llop respecting the CONFIG_USR_DRV_<DRVNAME>_CFLAGS convention,
# where DRVNAME is the upercase word using the lib<drvname> structure of the driver dir.
quiet_cmd_kconf_drvlist_gen = KCONF
      cmd_kconf_drvlist_gen = rm -f $(PROJ_FILES)/drivers/Kconfig.gen; for i in $(shell find drivers -maxdepth 3 -mindepth 3 -type d ! -iname '.git'); do /bin/echo "source \"$$i/Kconfig\"" >> $(PROJ_FILES)/drivers/Kconfig.gen; done;


# as libs are hosted by other repositories, liblist is dynamic for Kconfig, and generated here.
# The drivers CFLAGS list is also generated here using the below for-llop respecting the CONFIG_USR_LIB_<LIBNAME>_CFLAGS convention,
# where DRVNAME is the upercase word using the lib<drvname> structure of the driver dir.
quiet_cmd_kconf_liblist_gen = KCONF
      cmd_kconf_liblist_gen = rm -f $(PROJ_FILES)/libs/Kconfig.gen; for i in $(shell find libs -maxdepth 1 -mindepth 1 -type d ! -iname '.git' -a ! -iname common -a ! -iname libbsp -a ! -iname libecc); do /bin/echo "source \"$$i/Kconfig\"" >> $(PROJ_FILES)/libs/Kconfig.gen; done

quiet_cmd_kconf_drv_gen = KCONF
      cmd_kconf_drv_gen = for i in $(shell find drivers/socs/*/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do upper=`/bin/echo "$$i" |tr '[:lower:]' '[:upper:]'`; /bin/echo "config USR_DRV_$${upper}_CFLAGS" >>$(PROJ_FILES)/drivers/Kconfig.gen; /bin/echo "  string" >>$(PROJ_FILES)/drivers/Kconfig.gen; /bin/echo "  default \" -I@PROJFILES@/drivers/socs/$(CONFIG_SOCNAME)/$$i/api \" if USR_DRV_$$upper" >>$(PROJ_FILES)/drivers/Kconfig.gen; /bin/echo "" >>$(PROJ_FILES)/drivers/Kconfig.gen; done; for i in $(shell find drivers/boards/$(CONFIG_BOARDNAME)/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do upper=`/bin/echo "$$i" |tr '[:lower:]' '[:upper:]'`; /bin/echo "config USR_DRV_$${upper}_CFLAGS" >>$(PROJ_FILES)/drivers/Kconfig.gen; /bin/echo "  string" >>$(PROJ_FILES)/drivers/Kconfig.gen; /bin/echo "  default \" -I@PROJFILES@/drivers/boards/$(CONFIG_BOARDNAME)/$$i/api \" if USR_DRV_$$upper" >>$(PROJ_FILES)/drivers/Kconfig.gen; /bin/echo "" >>$(PROJ_FILES)/drivers/Kconfig.gen; done

quiet_cmd_kconf_lib_gen = KCONF
      cmd_kconf_lib_gen = for i in $(shell find libs/ -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do upper=`/bin/echo "$$i" |tr '[:lower:]' '[:upper:]'`; /bin/echo "config USR_LIB_$${upper}_CFLAGS" >>$(PROJ_FILES)/libs/Kconfig.gen; /bin/echo "  string" >>$(PROJ_FILES)/libs/Kconfig.gen; /bin/echo "  default \" -I@PROJFILES@/libs/$$i/api \" if USR_LIB_$$upper" >>$(PROJ_FILES)/libs/Kconfig.gen; /bin/echo "" >>$(PROJ_FILES)/libs/Kconfig.gen; done


#
# Depending on the manifest, some Kconfig and Kconfig-associated files may not exsit. If not
# the file is simply 'touched' to avoid menuconfig error.
quiet_cmd_nokconfig  = KCONF
      cmd_nokconfig  = for i in kernel/Kconfig apps/ipc.config apps/dmashm.config; do \
					     if [ ! -e "$$i" ]; then touch "$$i"; fi; \
					   done

quiet_cmd_kconf_root  = KCONF
      cmd_kconf_root  = rm -f $(PROJ_FILES)/Kconfig.gen; if [ -f javacard/Kconfig ]; then /bin/echo "source javacard/Kconfig" > $(PROJ_FILES)/Kconfig.gen; else /bin/echo "" >> $(PROJ_FILES)/Kconfig.gen; fi

# generate makefile.objs directory listing from current list of dirs

quiet_cmd_mkobjlist_libs   = MAKEOBJS_LIBS
      cmd_mkobjlist_libs   = rm -f libs/Makefile.objs.gen; for i in $(shell find libs -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do upper=`/bin/echo "$$i" |tr '[:lower:]' '[:upper:]'`; /bin/echo "libs-\$$(CONFIG_USR_LIB_$${upper}) += $$i" >> libs/Makefile.objs.gen; done

quiet_cmd_mkobjlist_apps   = MAKEOBJS_APPS
      cmd_mkobjlist_apps   = rm -f apps/Makefile.objs.gen; for i in $(shell find apps -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do upper=`/bin/echo "$$i" |tr '[:lower:]' '[:upper:]'`; /bin/echo "app-fw-\$$(CONFIG_APP_$${upper}_FW) += $$i" >> apps/Makefile.objs.gen; /bin/echo "app-dfu-\$$(CONFIG_APP_$${upper}_DFU) += $$i" >> apps/Makefile.objs.gen; done

quiet_cmd_mkobjlist_drvs   = MAKEOBJS_DRVS
      cmd_mkobjlist_drvs   = /bin/echo "DRVSRC_DIR = \$$(PROJ_FILES)/drivers/socs/$(CONFIG_SOCNAME)" > drivers/socs/$(CONFIG_SOCNAME)/Makefile.objs; /bin/echo "drv-y :=" >> drivers/socs/$(CONFIG_SOCNAME)/Makefile.objs; rm -f drivers/socs/$(CONFIG_SOCNAME)/Makefile.objs.gen; for i in $(shell find drivers/socs/$(CONFIG_SOCNAME) -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do upper=`/bin/echo "$$i" |tr '[:lower:]' '[:upper:]'`; /bin/echo "drv-\$$(CONFIG_USR_DRV_$${upper}) += $$i" >> drivers/socs/$(CONFIG_SOCNAME)/Makefile.objs.gen; done; if [ -d $(PROJ_FILES)/drivers/boards/$(CONFIG_BOARDNAME) ]; then /bin/echo "BOARD_DRVSRC_DIR = \$$(PROJ_FILES)/drivers/boards/$(CONFIG_BOARDNAME)" > drivers/boards/$(CONFIG_BOARDNAME)/Makefile.objs; /bin/echo "board-drv-y :=" >> drivers/boards/$(CONFIG_BOARDNAME)/Makefile.objs; rm -f drivers/boards/$(CONFIG_BOARDNAME)/Makefile.objs.gen; for i in $(shell find drivers/boards/$(CONFIG_BOARDNAME) -mindepth 1 -maxdepth 1 -type d -exec basename {} \;); do upper=`/bin/echo "$$i" |tr '[:lower:]' '[:upper:]'`; /bin/echo "board-drv-\$$(CONFIG_USR_DRV_$${upper}) += $$i" >> drivers/boards/$(CONFIG_BOARDNAME)/Makefile.objs.gen; done; fi

quiet_cmd_devmap           = DEVMAP
      cmd_devmap           = $(PROJ_FILES)/kernel/tools/devmap.py ADA $(PROJ_FILES)/layouts/arch/socs/$(SOC)/soc-devmap-$(BOARDNAME)$(BOARDRELEASE).json > $(PROJ_FILES)/kernel/src/arch/socs/$(SOC)/generated/soc-devmap.ads; \
                             $(PROJ_FILES)/kernel/tools/devperm.py $(PROJ_FILES)/layouts/arch/socs/$(SOC)/soc-devmap-$(BOARDNAME)$(BOARDRELEASE).json > $(PROJ_FILES)/kernel/src/generated/ewok-devices-perms.ads; \
			     $(PROJ_FILES)/layouts/arch/socs/$(SOC)/tools/devheader.py $(PROJ_FILES)/layouts/arch/socs/$(SOC)/generated $(PROJ_FILES)/layouts/arch/socs/$(SOC)/soc-devmap-$(BOARDNAME)$(BOARDRELEASE).json

quiet_cmd_format_fw        = FORMAT
      cmd_format_fw        = $(PROJ_FILES)/tools/format_firmware.py $(PROJ_FILES)/layouts/arch/socs/$(SOC)/soc-devmap-$(BOARDNAME)$(BOARDRELEASE).json $(BUILD_DIR)/$(CONFIG_PROJ_NAME).hex

quiet_cmd_sign_flip        = SIGN_FLIP
      cmd_sign_flip        = $(PROJ_FILES)/tools/encrypt_sign_firmware.py $(CONFIG_PRIVATE_DIR) $< 1337 FLIP 1 16384 dead cafe

quiet_cmd_sign_flop        = SIGN_FLOP
      cmd_sign_flop        = $(PROJ_FILES)/tools/encrypt_sign_firmware.py $(CONFIG_PRIVATE_DIR) $< 1337 FLOP 1 16384 dead cafe

# extract existing sphinx doc from libs and drivers to fusion with wookeypedia in a single global website
quiet_cmd_load_libs_docs    = LOAD_LIBS_DOCS
      cmd_load_libs_docs    = echo ".. toctree::\n   :maxdepth: 2\n" > autogen.libs.rst; for i in $(shell find $(PROJ_FILES)/libs -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort); do if test -d $(PROJ_FILES)/libs/$$i/doc ; then rm -f lib$$i; ln -s $(PROJ_FILES)/libs/$$i/doc lib$$i; /bin/echo "   libs/$$i <lib$$i/index>" >> autogen.libs.rst; fi; done

quiet_cmd_load_drvs_docs    = LOAD_DRVS_DOCS
      cmd_load_drvs_docs    = echo ".. toctree::\n   :maxdepth: 2\n" > autogen.drvs.rst; for i in $(shell find $(PROJ_FILES)/drivers/socs/$(CONFIG_SOCNAME) -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort); do if test -d $(PROJ_FILES)/drivers/socs/$(CONFIG_SOCNAME)/$$i/doc ; then rm -f drv$$i; ln -s $(PROJ_FILES)/drivers/socs/$(CONFIG_SOCNAME)/$$i/doc drv$$i; /bin/echo "   drivers/$$i <drv$$i/index>" >> autogen.drvs.rst; fi; done; for i in $(shell find $(PROJ_FILES)/drivers/boards/$(CONFIG_BOARDNAME) -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort); do if test -d $(PROJ_FILES)/drivers/boards/$(CONFIG_BOARDNAME)/$$i/doc ; then rm -f drv$$i; ln -s $(PROJ_FILES)/drivers/boards/$(CONFIG_BOARDNAME)/$$i/doc drv$$i; /bin/echo "   drivers/$$i <drv$$i/index>" >> autogen.drvs.rst; fi; done

quiet_cmd_load_kern_docs    = LOAD_KERN_DOCS
      cmd_load_kern_docs    = if test -d $(PROJ_FILES)/kernel/doc; then rm -f ewok; ln -s $(PROJ_FILES)/kernel/doc ewok; fi

quiet_cmd_load_jvc_docs     = LOAD_JVC_DOCS
      cmd_load_jvc_docs     = if test -d $(PROJ_FILES)/javacard/applet/doc; then rm -f javacard; ln -s $(PROJ_FILES)/javacard/applet/doc javacard; fi

