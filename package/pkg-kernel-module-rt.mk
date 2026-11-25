################################################################################
#
# kernel-module-rt -- build a kernel-module package a second time, for linux-rt
#
################################################################################

# Builds a kernel-module package again against linux-rt, in a copy of its source.
# Use after $(eval $(kernel-module)); docs/buildroot-config.md §5.47 has the why.
define inner-kernel-module-rt

ifndef $(2)_KERNEL_MODULES_BUILD
$$(error $(1): $$$$(eval $$$$(kernel-module-rt)) must follow $$$$(eval $$$$(kernel-module)))
endif

ifeq ($$(BR2_PACKAGE_LINUX_RT),y)

$(2)_DEPENDENCIES += linux-rt
$(2)_RT_SRCDIR = $$($(2)_DIR)/.mister-rt

define $(2)_RT_COPY_SOURCE
	rsync -a --delete --exclude=/.mister-rt $$(@D)/ $$($(2)_RT_SRCDIR)/
endef
$(2)_POST_PATCH_HOOKS += $(2)_RT_COPY_SOURCE

define $(2)_RT_KERNEL_MODULES_BUILD
	@$$(call MESSAGE,"Building kernel module(s) for linux-rt")
	$$(foreach d,$$($(2)_MODULE_SUBDIRS), \
		$$(LINUX_RT_MAKE_ENV) $$($$(PKG)_MAKE) \
			-C $$(LINUX_RT_DIR) \
			$$(LINUX_RT_MAKE_FLAGS) \
			$$($(2)_MODULE_MAKE_OPTS) \
			$$($(2)_RT_MODULE_MAKE_OPTS) \
			PWD=$$($(2)_RT_SRCDIR)/$$(d) \
			M=$$($(2)_RT_SRCDIR)/$$(d) \
			modules$$(sep))
endef
$(2)_POST_BUILD_HOOKS += $(2)_RT_KERNEL_MODULES_BUILD

define $(2)_RT_KERNEL_MODULES_INSTALL
	@$$(call MESSAGE,"Installing kernel module(s) for linux-rt")
	$$(foreach d,$$($(2)_MODULE_SUBDIRS), \
		$$(LINUX_RT_MAKE_ENV) $$($$(PKG)_MAKE) \
			-C $$(LINUX_RT_DIR) \
			$$(LINUX_RT_MAKE_FLAGS) \
			$$($(2)_MODULE_MAKE_OPTS) \
			$$($(2)_RT_MODULE_MAKE_OPTS) \
			PWD=$$($(2)_RT_SRCDIR)/$$(d) \
			M=$$($(2)_RT_SRCDIR)/$$(d) \
			modules_install$$(sep))
endef
$(2)_POST_INSTALL_TARGET_HOOKS += $(2)_RT_KERNEL_MODULES_INSTALL

endif # BR2_PACKAGE_LINUX_RT

endef

kernel-module-rt = $(call inner-kernel-module-rt,$(pkgname),$(call UPPERCASE,$(pkgname)))
