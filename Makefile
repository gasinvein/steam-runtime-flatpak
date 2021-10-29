.PHONY: all clean

BASE_ID = com.valvesoftware.SteamRuntime
SDK_ID = $(BASE_ID).Sdk
RUNTIME_ID = $(BASE_ID).Platform
GL_EXT_ID = org.freedesktop.Platform.GL
GL32_EXT_ID = $(GL_EXT_ID)32
GL_COMMON_BRANCH = 1.4

REPO ?= repo
BUILDDIR ?= builddir
TMPDIR ?= tmp

ARCH ?= $(shell flatpak --default-arch)
BRANCH ?= scout

SRT_SNAPSHOT ?= 0.20191217.0
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

$(BUILDDIR)/%/$(ARCH)/$(BRANCH)/metadata: \
	$(TMPDIR)/%-$(FLATDEB_ARCHES)-$(BRANCH)-runtime.tar.gz \
	data/ld.so.conf

	mkdir -p $(@D)
	tar -xf $< -C $(@D)

	mkdir -p $(@D)/files/lib/{x86_64,i386}-linux-gnu/GL

	#FIXME stock ld.so.conf is broken, replace it
	install -Dm644 -v data/ld.so.conf $(@D)/files/etc/ld.so.conf

	#FIXME hackish way to add GL extension vulkan ICD path
	test -d $(@D)/files/etc/vulkan/icd.d && rmdir $(@D)/files/etc/vulkan/icd.d ||:
	ln -srv $(@D)/files/lib/x86_64-linux-gnu/GL/vulkan/icd.d $(@D)/files/etc/vulkan/icd.d

	flatpak build-finish \
		--extension="$(GL_EXT_ID)"="directory"="lib/x86_64-linux-gnu/GL" \
		--extension="$(GL_EXT_ID)"="add-ld-path"="lib" \
		--extension="$(GL_EXT_ID)"="merge-dirs"="vulkan/icd.d;glvnd/egl_vendor.d;OpenCL/vendors" \
		--extension="$(GL_EXT_ID)"="version"="$(BRANCH)" \
		--extension="$(GL_EXT_ID)"="versions"="$(GL_COMMON_BRANCH);$(BRANCH)" \
		--extension="$(GL_EXT_ID)"="subdirectories"="true" \
		--extension="$(GL_EXT_ID)"="no-autodownload"="true" \
		--extension="$(GL_EXT_ID)"="autodelete"="false" \
		--extension="$(GL_EXT_ID)"="download-if"="active-gl-driver" \
		--extension="$(GL_EXT_ID)"="enable-if"="active-gl-driver" \
		--extension="$(GL32_EXT_ID)"="directory"="lib/i386-linux-gnu/GL" \
		--extension="$(GL32_EXT_ID)"="add-ld-path"="lib" \
		--extension="$(GL32_EXT_ID)"="merge-dirs"="vulkan/icd.d;glvnd/egl_vendor.d;OpenCL/vendors" \
		--extension="$(GL32_EXT_ID)"="version"="$(BRANCH)" \
		--extension="$(GL32_EXT_ID)"="versions"="$(GL_COMMON_BRANCH);$(BRANCH)" \
		--extension="$(GL32_EXT_ID)"="subdirectories"="true" \
		--extension="$(GL32_EXT_ID)"="no-autodownload"="true" \
		--extension="$(GL32_EXT_ID)"="autodelete"="false" \
		--extension="$(GL32_EXT_ID)"="download-if"="active-gl-driver" \
		--extension="$(GL32_EXT_ID)"="enable-if"="active-gl-driver" \
		$(@D)

# Prepare appstream

$(BUILDDIR)/$(SDK_ID)/$(ARCH)/$(BRANCH)/files/share/appdata/$(SDK_ID).appdata.xml: data/$(SDK_ID).appdata.xml.in
	mkdir -p $(@D)
	sed \
		-e "s/@SRT_VERSION@/$(SRT_VERSION)/g" \
		-e "s/@SRT_DATE@/$(SRT_DATE)/g" \
		$< > $@

$(BUILDDIR)/$(RUNTIME_ID)/$(ARCH)/$(BRANCH)/files/share/appdata/$(RUNTIME_ID).appdata.xml: data/$(RUNTIME_ID).appdata.xml.in
	mkdir -p $(@D)
	sed \
		-e "s/@SRT_VERSION@/$(SRT_VERSION)/g" \
		-e "s/@SRT_DATE@/$(SRT_DATE)/g" \
		$< > $@

# Compose appstream

$(BUILDDIR)/$(SDK_ID)/$(ARCH)/$(BRANCH)/files/share/app-info/xmls/$(SDK_ID).xml.gz: \
	$(BUILDDIR)/$(SDK_ID)/$(ARCH)/$(BRANCH)/files/share/appdata/$(SDK_ID).appdata.xml

	appstream-compose --origin=flatpak \
		--basename=$(SDK_ID) \
		--prefix=$(BUILDDIR)/$(SDK_ID)/$(ARCH)/$(BRANCH)/files \
		$(SDK_ID)

$(BUILDDIR)/$(RUNTIME_ID)/$(ARCH)/$(BRANCH)/files/share/app-info/xmls/$(RUNTIME_ID).xml.gz: \
	$(BUILDDIR)/$(RUNTIME_ID)/$(ARCH)/$(BRANCH)/files/share/appdata/$(RUNTIME_ID).appdata.xml

	appstream-compose --origin=flatpak \
		--basename=$(RUNTIME_ID) \
		--prefix=$(BUILDDIR)/$(RUNTIME_ID)/$(ARCH)/$(BRANCH)/files \
		$(RUNTIME_ID)

# Export to repo

$(REPO)/refs/heads/runtime/$(SDK_ID)/$(ARCH)/$(BRANCH): \
	$(REPO)/config \
	$(BUILDDIR)/$(SDK_ID)/$(ARCH)/$(BRANCH)/metadata \
	$(BUILDDIR)/$(SDK_ID)/$(ARCH)/$(BRANCH)/files/share/app-info/xmls/$(SDK_ID).xml.gz

	flatpak build-export --files=files --arch=$(ARCH) \
		$(REPO) $(BUILDDIR)/$(SDK_ID)/$(ARCH)/$(BRANCH) $(BRANCH)
	flatpak build-update-repo --prune $(REPO)

$(REPO)/refs/heads/runtime/$(RUNTIME_ID)/$(ARCH)/$(BRANCH): \
	$(REPO)/config \
	$(BUILDDIR)/$(RUNTIME_ID)/$(ARCH)/$(BRANCH)/metadata \
	$(BUILDDIR)/$(RUNTIME_ID)/$(ARCH)/$(BRANCH)/files/share/app-info/xmls/$(RUNTIME_ID).xml.gz

	flatpak build-export --files=files --arch=$(ARCH) \
		$(REPO) $(BUILDDIR)/$(RUNTIME_ID)/$(ARCH)/$(BRANCH) $(BRANCH)
	flatpak build-update-repo --prune $(REPO)


sdk: $(REPO)/refs/heads/runtime/$(SDK_ID)/$(ARCH)/$(BRANCH)

runtime: $(REPO)/refs/heads/runtime/$(RUNTIME_ID)/$(ARCH)/$(BRANCH)


%-$(ARCH)-$(BRANCH).flatpak: \
	$(REPO)/refs/heads/runtime/%/$(ARCH)/$(BRANCH)

	flatpak build-bundle --runtime \
		--arch=$(ARCH) $(REPO) $@ $* $(BRANCH)

sdk-bundle: $(SDK_ID)-$(ARCH)-$(BRANCH).flatpak

runtime-bundle: $(RUNTIME_ID)-$(ARCH)-$(BRANCH).flatpak
