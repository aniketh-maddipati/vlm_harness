-- Lumina parity sweep: a Lightroom Classic plug-in that exports the reference TIFFs the parity
-- harness measures against (Tools/parity/README.md, "The Lightroom sweep").
return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = 'com.lumina.parity.sweep',
    LrPluginName = 'Lumina parity sweep',
    LrPluginInfoUrl = 'https://github.com/aniketh-maddipati/vlm_harness',
    LrLibraryMenuItems = {
        { title = 'Lumina parity sweep…', file = 'Sweep.lua', enabledWhen = 'photosSelected' },
    },
    VERSION = { major = 1, minor = 0, revision = 0, build = 1 },
}
