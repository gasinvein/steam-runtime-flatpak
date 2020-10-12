.PHONY: all clean

BASE_ID = com.valvesoftware.SteamRuntime
SDK_ID = $(BASE_ID).Sdk
RUNTIME_ID = $(BASE_ID).Platform
GL_EXT_ID = $(BASE_ID).GL
GL32_EXT_ID = $(GL_EXT_ID)32

REPO ?= repo
BUILDDIR ?= builddir
TMPDIR ?= tmp

ARCH ?= $(shell flatpak --default-arch)
BRANCH ?= scout

SRT_SNAPSHOT ?= 0.20191217.0
SRT_VERSION ?= $(SRT_SNAPSHOT)
SRT_DATE ?= $(shell date -d $(shell cut -d. -f2 <<<$(SRT_VERSION)) +'%Y-%m-%d')

SRT_MIRROR ?= http://repo.steampowered.com/steamrt-images-scout/snapshots
SRT_URI := $(SRT_MIRROR)/$(SRT_SNAPSHOT)
ifeq ($(ARCH),x86_64)
	FLATDEB_ARCHES := amd64,i386
else
	FLATDEB_ARCHES := $(ARCH)
endif

NV_VERSION ?= $(shell cat /sys/module/nvidia/version)
NV_VERSION_F = $(subst .,-,$(NV_VERSION))
#TODO arch here this conditional
NV_RUNFILE = NVIDIA-Linux-x86_64-$(NV_VERSION).run
NV_DL_MIRROR = https://download.nvidia.com/XFree86/Linux-x86_64

all: sdk runtime

clean:
	rm -vf *.flatpak *.yml
	rm -rf $(BUILDDIR) $(TMPDIR)

$(REPO)/config:
	ostree --verbose --repo=$(REPO) init --mode=bare-user-only

# Download and extract

$(TMPDIR)/%-$(FLATDEB_ARCHES)-$(BRANCH)-runtime.tar.gz:
	mkdir -p $(@D)
	wget $(SRT_URI)/$(@F) -O $@

$(BUILDDIR)/%/$(ARCH)/$(BRANCH)/metadata: \
	$(TMPDIR)/%-$(FLATDEB_ARCHES)-$(BRANCH)-runtime.tar.gz \
	data/ld.so.conf

	mkdir -p $(@D)
	tar -xf $< -C $(@D)
	#FIXME stock ld.so.conf is broken, replace it
	install -Dm644 -v data/ld.so.conf $(@D)/files/etc/ld.so.conf
	#FIXME hackish way to add GL extension vulkan ICD path
	test -d $(@D)/files/etc/vulkan/icd.d && rmdir $(@D)/files/etc/vulkan/icd.d ||:
	ln -srv $(@D)/files/lib/GL/vulkan/icd.d $(@D)/files/etc/vulkan/icd.d
	touch $@

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

# Nvidia GL extension

$(TMPDIR)/$(NV_RUNFILE):
	mkdir -p $(@D)
	wget $(NV_DL_MIRROR)/$(NV_VERSION)/$(NV_RUNFILE) -O $@

$(GL_EXT_ID).nvidia-$(NV_VERSION_F).yml: \
	$(GL_EXT_ID).nvidia-@NV_VERSION_F@.yml.in

	sed \
		-e "s/@BRANCH@/$(BRANCH)/g" \
		-e "s/@NV_VERSION_F@/$(NV_VERSION_F)/g" \
		-e "s/@NV_VERSION@/$(NV_VERSION)/g" \
		-e "s|@NV_RUNFILE_PATH@|$(TMPDIR)/$(NV_RUNFILE)|g" \
		$< > $@

$(REPO)/refs/heads/runtime/$(GL_EXT_ID).nvidia-$(NV_VERSION_F)/%/$(BRANCH): \
	$(GL_EXT_ID).nvidia-$(NV_VERSION_F).yml \
	$(REPO)/refs/heads/runtime/$(SDK_ID)/$(ARCH)/$(BRANCH) \
	$(REPO)/refs/heads/runtime/$(RUNTIME_ID)/$(ARCH)/$(BRANCH)

	flatpak -v remote-add --if-not-exists --no-gpg-verify --user steamrt-local $(REPO)

	flatpak-builder \
		--install-deps-from=steamrt-local --user \
		--sandbox --force-clean $(FB_ARGS) --repo=$(REPO) --arch=$* \
		$(BUILDDIR)/$(GL_EXT_ID).nvidia-$(NV_VERSION_F)/$*/$(BRANCH) $<

$(REPO)/refs/heads/runtime/$(GL32_EXT_ID).nvidia-$(NV_VERSION_F)/x86_64/$(BRANCH): \
	$(REPO)/refs/heads/runtime/$(GL_EXT_ID).nvidia-$(NV_VERSION_F)/i386/$(BRANCH)

	flatpak build-commit-from $(REPO) \
		--src-ref=runtime/$(GL_EXT_ID).nvidia-$(NV_VERSION_F)/i386/$(BRANCH) \
		runtime/$(GL32_EXT_ID).nvidia-$(NV_VERSION_F)/x86_64/$(BRANCH)


sdk: $(REPO)/refs/heads/runtime/$(SDK_ID)/$(ARCH)/$(BRANCH)

runtime: $(REPO)/refs/heads/runtime/$(RUNTIME_ID)/$(ARCH)/$(BRANCH)

gl-ext: $(REPO)/refs/heads/runtime/$(GL_EXT_ID).nvidia-$(NV_VERSION_F)/$(ARCH)/$(BRANCH)

gl32-ext: $(REPO)/refs/heads/runtime/$(GL32_EXT_ID).nvidia-$(NV_VERSION_F)/$(ARCH)/$(BRANCH)


%-$(ARCH)-$(BRANCH).flatpak: \
	$(REPO)/refs/heads/runtime/%/$(ARCH)/$(BRANCH)

	flatpak build-bundle --runtime \
		--arch=$(ARCH) $(REPO) $@ $* $(BRANCH)

sdk-bundle: $(SDK_ID)-$(ARCH)-$(BRANCH).flatpak

runtime-bundle: $(RUNTIME_ID)-$(ARCH)-$(BRANCH).flatpak

gl-ext-bundle: $(GL_EXT_ID).nvidia-$(NV_VERSION_F)-$(ARCH)-$(BRANCH).flatpak

gl32-ext-bundle: $(GL32_EXT_ID).nvidia-$(NV_VERSION_F)-$(ARCH)-$(BRANCH).flatpak
