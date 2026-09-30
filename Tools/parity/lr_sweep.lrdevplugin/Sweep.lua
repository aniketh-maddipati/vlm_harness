-- The sweep (roadmap Prompt 2 §1). For every selected photo:
--   1. base: profile Adobe Color, every basic setting reset, capture sharpening 0
--      → <stem>__base.tif, plus <stem>__asshot.json (Lightroom's as-shot Temperature / Tint)
--   2. one slider at a time, 10 positions each          → <stem>__<Slider>__<value>.tif
--   3. 20 random three-slider combinations (seeded)     → <stem>__comboNN.tif + <stem>__comboNN.json
-- Every export: 16-bit ProPhoto RGB TIFF, uncompressed, 2048 px long edge, no output sharpening,
-- no watermark, minimal metadata. Develop settings are applied with LrPhoto:applyDevelopSettings
-- (catalog level, so the Develop module need not be open); the history gets one step per export
-- named "Lumina sweep …", and the photo is left at the base settings when the sweep ends.
--
-- Time: ~150 exports per photo; Lightroom Classic exports a 24 MP ARW to a 2048 px TIFF in about
-- 1–2 s on an M1, so ~4 minutes per photo, ~3 hours for the 50-image golden set. Run it overnight.

local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'
local LrExportSession = import 'LrExportSession'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrProgressScope = import 'LrProgressScope'
local LrPrefs = import 'LrPrefs'

local prefs = LrPrefs.prefsForPlugin()

-- The twelve sliders, their develop-setting keys and the ten positions. Temperature is absolute
-- Kelvin on a log-ish spread; the harness maps it onto Apple's as-shot by mired difference.
local SLIDERS = {
    { name = 'Exposure',    key = 'Exposure2012',   values = { -4, -3, -2, -1, -0.5, 0.5, 1, 2, 3, 4 } },
    { name = 'Temperature', key = 'Temperature',    values = { 2500, 3200, 4000, 4800, 5600, 6500, 8000, 10000, 14000, 20000 } },
    { name = 'Tint',        key = 'Tint',           values = { -100, -60, -40, -20, -10, 10, 20, 40, 60, 100 } },
    { name = 'Contrast',    key = 'Contrast2012',   values = { -100, -75, -50, -25, -10, 10, 25, 50, 75, 100 } },
    { name = 'Highlights',  key = 'Highlights2012', values = { -100, -75, -50, -25, -10, 10, 25, 50, 75, 100 } },
    { name = 'Shadows',     key = 'Shadows2012',    values = { -100, -75, -50, -25, -10, 10, 25, 50, 75, 100 } },
    { name = 'Whites',      key = 'Whites2012',     values = { -100, -75, -50, -25, -10, 10, 25, 50, 75, 100 } },
    { name = 'Blacks',      key = 'Blacks2012',     values = { -100, -75, -50, -25, -10, 10, 25, 50, 75, 100 } },
    { name = 'Vibrance',    key = 'Vibrance',       values = { -100, -75, -50, -25, -10, 10, 25, 50, 75, 100 } },
    { name = 'Saturation',  key = 'Saturation',     values = { -100, -75, -50, -25, -10, 10, 25, 50, 75, 100 } },
    { name = 'Clarity',     key = 'Clarity2012',    values = { -100, -75, -50, -25, -10, 10, 25, 50, 75, 100 } },
    { name = 'Sharpness',   key = 'Sharpness',      values = { 10, 25, 40, 55, 70, 85, 100, 115, 130, 150 } },
}
local COMBOS_PER_IMAGE = 20
local LONG_EDGE = 2048

-- The base: Adobe Color, everything the basic panel and detail panel can move at its reset value.
-- Capture sharpening is 0 (Lightroom's default for RAW is 40) so the Sharpness sweep starts from
-- nothing and the base compares the two RAW developments alone. Noise reduction keeps Lightroom's
-- defaults (colour 25, luminance 0), which is what Adobe Color looks like out of the box.
local function baseSettings()
    return {
        ProcessVersion = '11.0',
        CameraProfile = 'Adobe Color',
        WhiteBalance = 'As Shot',
        Exposure2012 = 0, Contrast2012 = 0, Highlights2012 = 0, Shadows2012 = 0, Whites2012 = 0, Blacks2012 = 0,
        Texture = 0, Clarity2012 = 0, Dehaze = 0, Vibrance = 0, Saturation = 0,
        ToneCurveName2012 = 'Linear', ParametricShadows = 0, ParametricDarks = 0, ParametricLights = 0, ParametricHighlights = 0,
        Sharpness = 0, SharpenRadius = 1.0, SharpenDetail = 25, SharpenEdgeMasking = 0,
        LuminanceSmoothing = 0, ColorNoiseReduction = 25,
        PostCropVignetteAmount = 0, GrainAmount = 0,
        EnableLensCorrections = false, LensProfileEnable = 0, AutoLateralCA = 0,
        EnableColorAdjustments = false, EnableSplitToning = false, EnableColorGrading = false, EnableCalibration = false,
        EnableGradientBasedCorrections = false, EnableCircularGradientBasedCorrections = false, EnablePaintBasedCorrections = false,
        EnableRetouch = false, EnableRedEye = false, EnableEffects = false, EnableDetail = true,
        ConvertToGrayscale = false,
    }
end

-- Minimal JSON for flat tables of numbers, strings and booleans (the SDK has no JSON module).
local function jsonValue(v)
    local t = type(v)
    if t == 'number' then return string.format('%.6g', v)
    elseif t == 'boolean' then return v and 'true' or 'false'
    elseif t == 'string' then return '"' .. v:gsub('[%c"\\]', function(c) return string.format('\\u%04x', c:byte()) end) .. '"'
    elseif t == 'table' then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do parts[#parts + 1] = jsonValue(k) .. ': ' .. jsonValue(v[k]) end
        return '{' .. table.concat(parts, ', ') .. '}'
    end
    return 'null'
end

local function writeFile(path, text)
    local f = io.open(path, 'w')
    if not f then error('cannot write ' .. path) end
    f:write(text)
    f:close()
end

local function stemOf(photo)
    return LrPathUtils.removeExtension(photo:getFormattedMetadata('fileName'))
end

local function valueName(v)
    local s = string.format('%.4g', v)
    return s
end

-- Deterministic pseudo-random values per image (so a re-run reproduces the same combos).
local function lcg(seed)
    local state = seed
    return function()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
end

local function applySettings(catalog, photo, settings, historyName)
    catalog:withWriteAccessDo(historyName, function()
        -- keepExistingSettings = false: anything not named goes back to its default.
        photo:applyDevelopSettings(settings, historyName, false)
    end, { timeout = 30 })
end

local function exportOne(photo, folder, name)
    local session = LrExportSession {
        photosToExport = { photo },
        exportSettings = {
            LR_exportServiceProvider = 'com.adobe.ag.export.file',
            LR_format = 'TIFF',
            LR_export_bitDepth = 16,
            LR_export_colorSpace = 'ProPhotoRGB',
            LR_tiff_compressionMethod = 'compressionMethod_None',
            LR_tiff_preserveTransparency = false,
            LR_size_doConstrain = true,
            LR_size_resizeType = 'longEdge',
            LR_size_maxWidth = LONG_EDGE,
            LR_size_maxHeight = LONG_EDGE,
            LR_size_units = 'pixels',
            LR_size_doNotEnlarge = true,
            LR_size_resolution = 240,
            LR_size_resolutionUnits = 'inch',
            LR_outputSharpeningOn = false,
            LR_export_destinationType = 'specificFolder',
            LR_export_destinationPathPrefix = folder,
            LR_export_useSubfolder = false,
            LR_collisionHandling = 'overwrite',
            LR_renamingTokensOn = true,
            LR_tokens = '{{custom_token}}',
            LR_tokenCustomString = name,
            LR_reimportExportedPhoto = false,
            LR_useWatermark = false,
            LR_minimizeEmbeddedMetadata = true,
            LR_removeLocationMetadata = true,
            LR_includeVideoFiles = false,
        },
    }
    session:doExportOnCurrentTask()
end

local function sweepPhoto(catalog, photo, folder, progress, index, doSingles, doCombos, skipExisting)
    local stem = stemOf(photo)
    local base = baseSettings()

    local function have(name)
        return skipExisting and LrFileUtils.exists(LrPathUtils.child(folder, name .. '.tif'))
    end

    -- 1. base + as shot
    applySettings(catalog, photo, base, 'Lumina sweep base')
    local dev = photo:getDevelopSettings()
    local asShot = { Temperature = dev.Temperature, Tint = dev.Tint, profile = dev.CameraProfile or 'Adobe Color',
                     processVersion = dev.ProcessVersion, sharpness = dev.Sharpness, colorNoiseReduction = dev.ColorNoiseReduction }
    writeFile(LrPathUtils.child(folder, stem .. '__asshot.json'), jsonValue(asShot))
    if not have(stem .. '__base') then exportOne(photo, folder, stem .. '__base') end

    -- 2. singles
    if doSingles then
        for _, s in ipairs(SLIDERS) do
            for _, v in ipairs(s.values) do
                if progress:isCanceled() then return false end
                local name = stem .. '__' .. s.name .. '__' .. valueName(v)
                progress:setCaption(string.format('%s · %s %s', stem, s.name, valueName(v)))
                if not have(name) then
                    local settings = baseSettings()
                    settings[s.key] = v
                    if s.key == 'Temperature' then settings.WhiteBalance = 'Custom'; settings.Tint = dev.Tint end
                    if s.key == 'Tint' then settings.WhiteBalance = 'Custom'; settings.Temperature = dev.Temperature end
                    applySettings(catalog, photo, settings, 'Lumina sweep ' .. s.name .. ' ' .. valueName(v))
                    exportOne(photo, folder, name)
                end
            end
        end
    end

    -- 3. combos: three distinct sliders, uniform values in their ranges, seeded by the image index
    if doCombos then
        local rnd = lcg(1000003 * index + 17)
        for n = 1, COMBOS_PER_IMAGE do
            if progress:isCanceled() then return false end
            local name = stem .. string.format('__combo%02d', n)
            progress:setCaption(string.format('%s · combo %d/%d', stem, n, COMBOS_PER_IMAGE))
            local picked, settings, record = {}, baseSettings(), {}
            while #picked < 3 do
                local s = SLIDERS[math.floor(rnd() * #SLIDERS) + 1]
                local dup = false
                for _, p in ipairs(picked) do if p == s then dup = true end end
                if not dup then picked[#picked + 1] = s end
            end
            for _, s in ipairs(picked) do
                local lo, hi = s.values[1], s.values[#s.values]
                local v = lo + rnd() * (hi - lo)
                if s.key == 'Exposure2012' then v = math.floor(v * 20 + 0.5) / 20 else v = math.floor(v + 0.5) end
                settings[s.key] = v
                record[s.name] = v
                if s.key == 'Temperature' then settings.WhiteBalance = 'Custom'; if settings.Tint == nil then settings.Tint = dev.Tint end end
                if s.key == 'Tint' then settings.WhiteBalance = 'Custom'; if settings.Temperature == nil then settings.Temperature = dev.Temperature end end
            end
            writeFile(LrPathUtils.child(folder, name .. '.json'), jsonValue({ settings = record, asShot = asShot }))
            if not have(name) then
                applySettings(catalog, photo, settings, 'Lumina sweep combo ' .. n)
                exportOne(photo, folder, name)
            end
        end
    end

    -- leave the photo at the base
    applySettings(catalog, photo, base, 'Lumina sweep base')
    return true
end

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos()
    if #photos == 0 then LrDialogs.message('Lumina parity sweep', 'Select the golden photos first.'); return end

    local choice = LrDialogs.confirm('Lumina parity sweep',
        string.format('%d photo(s): base + %d singles + %d combos each, 16-bit ProPhoto TIFF at %d px into a folder you pick next. Existing files are skipped.',
            #photos, 10 * #SLIDERS, COMBOS_PER_IMAGE, LONG_EDGE),
        'Everything', 'Cancel', 'Singles only')
    if choice == 'cancel' then return end
    local doCombos = choice == 'ok'

    local folders = LrDialogs.runOpenPanel {
        title = 'Folder for the reference TIFFs (e.g. ~/LuminaEvidence/parity/refs)',
        canChooseFiles = false, canChooseDirectories = true, canCreateDirectories = true, allowsMultipleSelection = false,
        initialDirectory = prefs.lastFolder,
    }
    if not folders or #folders == 0 then return end
    local folder = folders[1]
    prefs.lastFolder = folder

    local progress = LrProgressScope { title = 'Lumina parity sweep', functionContext = nil }
    progress:setCancelable(true)
    local done = 0
    for i, photo in ipairs(photos) do
        progress:setPortionComplete(i - 1, #photos)
        local ok, err = LrTasks.pcall(sweepPhoto, catalog, photo, folder, progress, i, true, doCombos, true)
        if not ok then
            LrDialogs.message('Lumina parity sweep', 'Stopped at ' .. stemOf(photo) .. ': ' .. tostring(err))
            break
        end
        if err == false then break end
        done = done + 1
    end
    progress:done()
    LrDialogs.message('Lumina parity sweep', string.format('%d of %d photo(s) exported to %s. Next: python3 Tools/parity/import_refs.py "%s"', done, #photos, folder, folder))
end)
