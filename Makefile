.PHONY: all clean

BASE_ID = com.valvesoftware.SteamRuntime
SDK_ID = $(BASE_ID).Sdk
RUNTIME_ID = $(BASE_ID).Platform
GL_EXT_ID = $(BASE_ID).GL
GL32_EXT_ID = $(GL_EXT_ID)32

REPO ?= repo
BUILDDIR ?= builddir
TMPDIR ?= tmp

ARCH ?= x86_64
BRANCH ?= scout

SRT_MIRROR ?= http://repo.steampowered.com/steamrt-images-scout/snapshots
SRT_SNAPSHOT ?= 0.20190913.0
SRT_URI := $(SRT_MIRROR)/$(SRT_SNAPSHOT)
ifeq ($(ARCH),x86_64)
	FLATDEB_ARCHES := amd64,i386
else
	FLATDEB_ARCHES := $(ARCH)
endif
SDK_ARCHIVE := $(SDK_ID)-$(FLATDEB_ARCHES)-$(BRANCH)-runtime.tar.gz
RUNTIME_ARCHIVE := $(RUNTIME_ID)-$(FLATDEB_ARCHES)-$(BRANCH)-runtime.tar.gz

NV_VERSION_F = $(subst .,-,$(NV_VERSION))

all: sdk runtime

clean:
	rm -vf *.flatpak *.yml
	rm -rf $(BUILDDIR) $(TMPDIR)

$(TMPDIR):
	mkdir -p $(TMPDIR)

$(REPO)/config:
	ostree --verbose --repo=$(REPO) init --mode=bare-user


$(TMPDIR)/$(SDK_ARCHIVE) $(TMPDIR)/$(RUNTIME_ARCHIVE): $(TMPDIR)
	wget $(SRT_URI)/$(@F) -O $@
	touch $@

$(BUILDDIR)/$(SDK_ID)/$(ARCH)/$(BRANCH): $(TMPDIR)/$(SDK_ARCHIVE)
	mkdir -p $@
	tar -xf $(TMPDIR)/$(SDK_ARCHIVE) -C $@

$(BUILDDIR)/$(RUNTIME_ID)/$(ARCH)/$(BRANCH): $(TMPDIR)/$(RUNTIME_ARCHIVE)
	mkdir -p $@
	tar -xf $(TMPDIR)/$(RUNTIME_ARCHIVE) -C $@

$(REPO)/refs/heads/runtime/$(SDK_ID)/$(ARCH)/$(BRANCH): $(BUILDDIR)/$(SDK_ID)/$(ARCH)/$(BRANCH)
	flatpak build-export --files=files --arch=$(ARCH) \
		$(REPO) $(BUILDDIR)/$(SDK_ID)/$(ARCH)/$(BRANCH) $(BRANCH)

$(REPO)/refs/heads/runtime/$(RUNTIME_ID)/$(ARCH)/$(BRANCH): $(BUILDDIR)/$(RUNTIME_ID)/$(ARCH)/$(BRANCH)
	flatpak build-export --files=files --arch=$(ARCH) \
		$(REPO) $(BUILDDIR)/$(RUNTIME_ID)/$(ARCH)/$(BRANCH) $(BRANCH)


$(GL_EXT_ID).nvidia-$(NV_VERSION_F).yml:
	sed \
		-e "s/@BRANCH@/$(BRANCH)/g" \
		-e "s/@NV_VERSION_F@/$(NV_VERSION_F)/g" \
		-e "s/@NV_VERSION@/$(NV_VERSION)/g" \
		-e "s/@NV_SHA256@/$(NV_SHA256)/g" \
		$(GL_EXT_ID).nvidia-@NV_VERSION_F@.yml.in > $@

$(REPO)/refs/heads/runtime/$(GL_EXT_ID).nvidia-$(NV_VERSION_F)/%/$(BRANCH): \
	$(GL_EXT_ID).nvidia-$(NV_VERSION_F).yml \
	$(REPO)/config

	flatpak-builder \
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
