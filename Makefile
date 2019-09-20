.PHONY: all clean

GL_EXT_ID = com.valvesoftware.SteamRuntime.GL
GL32_EXT_ID = $(GL_EXT_ID)32

REPO ?= repo
BUILDDIR ?= builddir

ARCH ?= x86_64
BRANCH ?= scout

NV_VERSION_F = $(subst .,-,$(NV_VERSION))

all: bundle

clean:
	rm -rf $(REPO) *.flatpak *.yml

$(GL_EXT_ID).nvidia-$(NV_VERSION_F).yml:
	sed \
		-e "s/@NV_VERSION_F@/$(NV_VERSION_F)/g" \
		-e "s/@NV_VERSION@/$(NV_VERSION)/g" \
		-e "s/@NV_SHA256@/$(NV_SHA256)/g" \
		$(GL_EXT_ID).nvidia-@NV_VERSION_F@.yml.in > $@

$(REPO)/config:
	ostree --verbose --repo=$(REPO) init --mode=bare-user

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

%-$(ARCH)-$(BRANCH).flatpak: \
	$(REPO)/refs/heads/runtime/%/$(ARCH)/$(BRANCH)

	flatpak build-bundle --runtime \
		--arch=$(ARCH) $(REPO) $@ $* $(BRANCH)

gl-ext: \
	$(REPO)/refs/heads/runtime/$(GL_EXT_ID).nvidia-$(NV_VERSION_F)/$(ARCH)/$(BRANCH)

gl32-ext: \
	$(REPO)/refs/heads/runtime/$(GL32_EXT_ID).nvidia-$(NV_VERSION_F)/$(ARCH)/$(BRANCH)

bundle: \
	$(GL_EXT_ID).nvidia-$(NV_VERSION_F)-$(ARCH)-$(BRANCH).flatpak
