.PHONY: all clean

BASE_ID = com.valvesoftware.SteamRuntime
SDK_ID = $(BASE_ID).Sdk
RUNTIME_ID = $(BASE_ID).Platform
GL_EXT_ID = org.freedesktop.Platform.GL
GL32_EXT_ID = $(GL_EXT_ID)32
GL_COMMON_BRANCH = 1.4
GL_MERGE_DIRS = vulkan/icd.d;vulkan/explicit_layer.d;vulkan/implicit_layer.d;glvnd/egl_vendor.d;egl/egl_external_platform.d;OpenCL/vendors;lib/dri;lib/d3d;lib/gbm

REPO ?= repo
BUILDDIR ?= builddir
TMPDIR ?= tmp

ARCH ?= $(shell flatpak --default-arch)
ifeq ($(ARCH),x86_64)
define COMPAT_ARCH
i386
endef
endif
BRANCH ?= soldier

SRT_SNAPSHOT ?= 0.20211013.0
SRT_VERSION ?= $(SRT_SNAPSHOT)
SRT_DATE ?= $(shell date -d $(shell cut -d. -f2 <<<$(SRT_VERSION)) +'%Y-%m-%d')

SRT_MIRROR ?= http://repo.steampowered.com/steamrt-images-$(BRANCH)/snapshots
SRT_URI := $(SRT_MIRROR)/$(SRT_SNAPSHOT)
ifeq ($(ARCH),x86_64)
	FLATDEB_ARCHES := amd64,i386
else
	FLATDEB_ARCHES := $(ARCH)
endif

all: sdk runtime

clean:
	rm -vf *.flatpak *.yml
	rm -rf $(BUILDDIR) $(TMPDIR)

$(REPO)/config:
	ostree --verbose --repo=$(REPO) init --mode=bare-user-only

# Download and extract

.PRECIOUS: $(TMPDIR)/%-$(FLATDEB_ARCHES)-$(BRANCH)-runtime.tar.gz

$(TMPDIR)/%-$(FLATDEB_ARCHES)-$(BRANCH)-runtime.tar.gz:
	mkdir -p $(@D)
	wget $(SRT_URI)/$(@F) -O $@

# Extract original tarball

$(BUILDDIR)/%/$(ARCH)/$(BRANCH)/.extracted: \
	$(TMPDIR)/%-$(FLATDEB_ARCHES)-$(BRANCH)-runtime.tar.gz

	mkdir -p $(@D)
	tar -xf $< -C $(@D)

	touch $@

# Finilze flatpak

define gl_ext_finish_args
--extension="$(1)"="directory"="lib/$(2)-linux-gnu/GL" \
--extension="$(1)"="add-ld-path"="lib" \
--extension="$(1)"="merge-dirs"="$(GL_MERGE_DIRS)" \
--extension="$(1)"="version"="$(BRANCH)" \
--extension="$(1)"="versions"="$(GL_COMMON_BRANCH);$(BRANCH)" \
--extension="$(1)"="subdirectories"="true" \
--extension="$(1)"="no-autodownload"="true" \
--extension="$(1)"="autodelete"="false" \
--extension="$(1)"="download-if"="active-gl-driver" \
--extension="$(1)"="enable-if"="active-gl-driver" \

endef

$(BUILDDIR)/%/$(ARCH)/$(BRANCH)/metadata: \
	$(BUILDDIR)/%/$(ARCH)/$(BRANCH)/.extracted \
	data/ld.so.conf

	mkdir -p $(@D)/files/lib/$(ARCH)-linux-gnu/GL
	$(if $(COMPAT_ARCH),mkdir -p $(@D)/files/lib/$(COMPAT_ARCH)-linux-gnu/GL)

	#FIXME stock ld.so.conf is broken, replace it
	install -Dm644 -v data/ld.so.conf $(@D)/files/etc/ld.so.conf

	#FIXME fix broken dri drivers symlinks
	for s in $(@D)/files/lib/*-linux-gnu/dri/*_dri.so; do \
		test -L $$s && ln -sfv $$(basename $$(readlink $$s)) $$s ||:; \
	done

	flatpak build-finish \
		--env=__EGL_EXTERNAL_PLATFORM_CONFIG_DIRS=/etc/egl/egl_external_platform.d:/usr/lib/$(ARCH)-linux-gnu/GL/egl/egl_external_platform.d:/usr/share/egl/egl_external_platform.d \
		--env=__EGL_VENDOR_LIBRARY_DIRS=/etc/glvnd/egl_vendor.d:/usr/lib/$(ARCH)-linux-gnu/GL/glvnd/egl_vendor.d:/usr/share/glvnd/egl_vendor.d \
		--env=LIBGL_DRIVERS_PATH="/usr/lib/$(ARCH)-linux-gnu/GL/lib/dri:/usr/lib/$(ARCH)-linux-gnu/dri" \
		--env=XDG_DATA_DIRS="/app/share:/usr/lib/$(ARCH)-linux-gnu/GL:/usr/share:/usr/share/runtime/share:/run/host/user-share:/run/host/share" \
		$(call gl_ext_finish_args,$(GL_EXT_ID),$(ARCH)) \
		$(if $(COMPAT_ARCH),$(call gl_ext_finish_args,$(GL32_EXT_ID),$(COMPAT_ARCH))) \
		$(@D)

# Prepare appstream

define prepare_appstream
$(BUILDDIR)/$(1)/$(ARCH)/$(BRANCH)/files/share/appdata/$(1).appdata.xml: \
	data/$(1).appdata.xml.in \
	$(BUILDDIR)/$(1)/$(ARCH)/$(BRANCH)/.extracted

	mkdir -p $$(@D)
	sed \
		-e "s/@SRT_VERSION@/$(SRT_VERSION)/g" \
		-e "s/@SRT_DATE@/$(SRT_DATE)/g" \
		$$< > $$@
endef
$(foreach id,$(SDK_ID) $(RUNTIME_ID),$(eval $(call prepare_appstream,$(id))))

# Compose appstream

define compose_appstream
$(BUILDDIR)/$(1)/$(ARCH)/$(BRANCH)/files/share/app-info/xmls/$(1).xml.gz: \
	$(BUILDDIR)/$(1)/$(ARCH)/$(BRANCH)/files/share/appdata/$(1).appdata.xml

	appstream-compose --origin=flatpak \
		--basename=$(1) \
		--prefix=$(BUILDDIR)/$(1)/$(ARCH)/$(BRANCH)/files \
		$(1)
endef
$(foreach id,$(SDK_ID) $(RUNTIME_ID),$(eval $(call compose_appstream,$(id))))

# Export to repo

define build_export
$(REPO)/refs/heads/runtime/$(1)/$(ARCH)/$(BRANCH): \
	$(REPO)/config \
	$(BUILDDIR)/$(1)/$(ARCH)/$(BRANCH)/metadata \
	$(BUILDDIR)/$(1)/$(ARCH)/$(BRANCH)/files/share/app-info/xmls/$(1).xml.gz

	flatpak build-export --files=files --arch=$(ARCH) \
		$(REPO) $(BUILDDIR)/$(1)/$(ARCH)/$(BRANCH) $(BRANCH)
	flatpak build-update-repo --prune $(REPO)
endef
$(foreach id,$(SDK_ID) $(RUNTIME_ID),$(eval $(call build_export,$(id))))


sdk: $(REPO)/refs/heads/runtime/$(SDK_ID)/$(ARCH)/$(BRANCH)

runtime: $(REPO)/refs/heads/runtime/$(RUNTIME_ID)/$(ARCH)/$(BRANCH)


%-$(ARCH)-$(BRANCH).flatpak: \
	$(REPO)/refs/heads/runtime/%/$(ARCH)/$(BRANCH)

	flatpak build-bundle --runtime \
		--arch=$(ARCH) $(REPO) $@ $* $(BRANCH)

sdk-bundle: $(SDK_ID)-$(ARCH)-$(BRANCH).flatpak

runtime-bundle: $(RUNTIME_ID)-$(ARCH)-$(BRANCH).flatpak
