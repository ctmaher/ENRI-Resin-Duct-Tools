// ============================================================
// ENRI resin duct tools — ImageJ/Fiji Toolset
//
// Three macros for dendrochronology resin duct analysis:
//   1. ImportCoordsCrop-1.0  [keyboard: i]
//   2. RingTracerCORE-1.0    [keyboard: g]
//   3. ResinDuctSummary-1.0  [keyboard: d]
//
// Installation:
//   Copy this file to:  Fiji.app/macros/toolsets/
//   Add to AutoRun_Scripts.ijm:
//     runMacro(getDirectory("imagej") + "macros/toolsets/ENRI resin duct tools.ijm");
//   Macros will then appear in Plugins > Macros on every startup.
// ============================================================


// ============================================================
// MACRO 1: ImportCoordsCrop-1.0
// ============================================================

macro "ImportCoordsCrop-1.0 [i]" {

/**
 * ImportCoordsCrop-1.0.ijm
 *
 * Workflow:
 *   1. Prompts for a CSV file named "sampleID_coords.csv".
 *   2. Reads x, y, type columns (calibrated units). Types: "reg", "multi1", "pith".
 *      Each point is added to the ROI Manager with its type as the ROI name.
 *   3. Prompts the user to draw a rectangular selection around the core of interest.
 *   4. Crops the image to that selection (ROI coordinates adjust automatically).
 *   5. Saves the cropped image as "sampleID.tif" in the same directory as the CSV.
 *   6. Logs the pith pixel coordinates both before and after cropping — the pith
 *      may fall outside the crop region (negative pixel coords are valid and will
 *      be used by RingTracker v2.5 for the polar DP).
 *
 * CSV format (header row required):
 *   x,y,type
 *   1.23,4.56,reg
 *   2.34,5.67,multi1
 *   0.10,2.50,pith
 *   ...
 *
 * Notes:
 *   - "pith" should appear exactly once. If multiple pith rows exist, the last
 *     one is used.
 *   - "multi1" marks the last point of a measurement segment before a y-restart.
 *     RingTracker v2.5 uses this to prevent inter-anchor normals from crossing
 *     segment boundaries.
 *   - Points are sorted left-to-right (by x) within each segment for the ROI
 *     Manager; the original CSV order is preserved in the ROI names' index suffix.
 */

// ── Select CSV ──────────────────────────────────────────────────────────────
csvPath = File.openDialog("Select coords CSV  (sampleID_coords.csv)");
if (csvPath == "") exit("No file selected.");

csvDir    = File.getDirectory(csvPath);
csvName   = File.getName(csvPath);

// Derive sampleID: strip "_coords.csv" suffix
if (endsWith(csvName, "_coords.csv"))
    sampleID = substring(csvName, 0, lengthOf(csvName) - lengthOf("_coords.csv"));
else
    sampleID = replace(csvName, ".csv", "");

print("Sample ID: " + sampleID);
print("CSV dir:   " + csvDir);

// ── Read image calibration ──────────────────────────────────────────────────
getPixelSize(unit, pixelWidth, pixelHeight);
print("Pixel size: " + pixelWidth + " x " + pixelHeight + " " + unit);

// ── Parse CSV ───────────────────────────────────────────────────────────────
content = File.openAsString(csvPath);
lines   = split(content, "\n");

roiManager("reset");

pithFound  = false;
pithX_px   = 0; pithY_px = 0;   // original-image pixel coords of pith
nImported  = 0;

for (i = 1; i < lines.length; i++) {
    line = trim(lines[i]);
    if (line == "") continue;
    cols = split(line, ",");
    if (cols.length < 2) continue;

    xCal = parseFloat(cols[0]);
    yCal = parseFloat(cols[1]);
    type = "reg";
    if (cols.length >= 3) {
        type = toLowerCase(trim(cols[2]));
        type = replace(type, "\"", "");   // strip R write.csv() quotes
        type = replace(type, "\r", "");
        type = replace(type, "\n", "");
    }

    x_px = xCal / pixelWidth;
    y_px = yCal / pixelHeight;

    if (startsWith(type, "pith")) {
        // Record pith separately; still add as a named ROI so RingTracker can read it
        pithX_px  = x_px;
        pithY_px  = y_px;
        pithFound = true;
        makePoint(x_px, y_px);
        roiManager("Add");
        roiManager("Select", roiManager("count") - 1);
        roiManager("Rename", "pith");
        print("Pith loaded: (" + x_px + ", " + y_px + ") px  [" + xCal + ", " + yCal + " " + unit + "]");
    } else {
        makePoint(x_px, y_px);
        roiManager("Add");
        // Name format: type_NNNN (zero-padded index preserves original CSV order)
        roiManager("Select", roiManager("count") - 1);
        roiManager("Rename", type + "_" + IJ.pad(nImported, 4));
        nImported++;
    }
}

roiManager("Show All");
print("Imported " + nImported + " ring anchor points  (" + (lines.length - 1) + " data rows).");
if (!pithFound) print("WARNING: No 'pith' row found in CSV.");

// ── Create overlay so points are visible during crop selection ─────────────
run("From ROI Manager");

// ── Prompt user for rectangular crop ───────────────────────────────────────
waitForUser("Draw crop rectangle",
    "Draw a rectangular selection around the core of interest,\n" +
    "then click OK.\n\n" +
    "The image will be cropped and saved as:\n" +
    "  " + sampleID + ".tif");

if (selectionType() != 0)
    exit("No rectangular selection found. Please draw a rectangle and re-run.");

// Record crop origin BEFORE cropping (needed to adjust pith coords)
getSelectionBounds(cropX, cropY, cropW, cropH);
print("Crop region: x=" + cropX + "  y=" + cropY + "  w=" + cropW + "  h=" + cropH);

// ── Crop ────────────────────────────────────────────────────────────────────
run("Crop");
// After cropping, ImageJ adjusts the OVERLAY coordinates but leaves the ROI
// Manager with stale pre-crop coordinates. Sync adjusted overlay back to the
// ROI Manager so RingTracker reads crop-adjusted anchor positions.
roiManager("reset");
run("To ROI Manager");
// ImageJ auto-adjusts ROI Manager coords for ROIs inside the crop region,
// but DROPS ROIs outside the crop bounds. Pith is often outside.
// We therefore explicitly store the crop-adjusted pith coords in image
// metadata so RingTracker can read them regardless of whether the ROI survived.

// ── Store and log pith coordinates in the cropped image frame ───────────────
if (pithFound) {
    pithX_cropped = pithX_px - cropX;
    pithY_cropped = pithY_px - cropY;
    print("Pith in cropped image: (" + d2s(pithX_cropped, 6) + ", " + d2s(pithY_cropped, 6) + ") px");
    if (pithX_cropped < 0 || pithX_cropped >= cropW ||
        pithY_cropped < 0 || pithY_cropped >= cropH)
        print("  (Pith is outside the cropped image — this is normal. RingTracker handles it.)");
    else
        print("  (Pith is inside the cropped image.)");

    // Store crop-adjusted pith coords in a sidecar file alongside the TIFF.
    // This is more reliable than TIFF metadata, which may not survive save/reopen.
    // Format: two lines, "pithX_px=<value>" and "pithY_px=<value>".
    pithSidecarPath = csvDir + sampleID + "_pith_px.txt";
    pithFileContent = "pithX_px=" + d2s(pithX_cropped, 6) + "\npithY_px=" + d2s(pithY_cropped, 6);
    File.saveString(pithFileContent, pithSidecarPath);
    print("Pith sidecar saved: " + pithSidecarPath);

    // Also try to store in image metadata as a secondary mechanism
    existingInfo = getImageInfo();
    setMetadata("Info", existingInfo + "\npithX_px=" + pithX_cropped + "\npithY_px=" + pithY_cropped);

    // Remove old pith ROI(s) and re-add at cropped coordinates
    n = roiManager("count");
    for (r = n - 1; r >= 0; r--) {
        roiManager("Select", r);
        rname = Roi.getName();
        if (startsWith(toLowerCase(rname), "pith")) roiManager("Delete");
    }
    makePoint(pithX_cropped, pithY_cropped);
    roiManager("Add");
    roiManager("Select", roiManager("count") - 1);
    roiManager("Rename", "pith");
    print("Pith ROI updated to cropped coordinates.");
}

// ── Save cropped image ──────────────────────────────────────────────────────
savePath = csvDir + sampleID + ".tif";
saveAs("Tiff", savePath);
print("Saved: " + savePath);
print("Done. ROI Manager contains all points; run RingTracerCORE-1.0 next.");

} // end macro ImportCoordsCrop-1.0


// ============================================================
// ============================================================
// ============================================================
// MACRO 2: RingTracerCORE-1.0
// ============================================================

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.2;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 0.2;
var GP_MARGIN_BOT_MM = 0.2;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 2;
var GP_ALPHA        = 5.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

// ============================================================
// RingTracerCORE-1.0.ijm
//
// Auto-orientation: W > H → vertical rings (walk top-to-bottom)
//
// Requires the image to have a pixel scale set (pixels/mm).
// All distance parameters are specified and stored in mm;
// conversion to pixels happens at the dialog boundary via gp_pxMm.
//
// SIMPLE PARAMETERS:
//   GP_BLUR_MM      Gaussian pre-blur sigma (mm).
//   GP_HW_MM        Perpendicular search half-width (mm). Default = min
//                   nearest-neighbour distance among seed points, floored
//                   at 0.05 mm. ~half narrowest ring.
//   GP_MAX_TURN     Max heading change per step (degrees). Hard geometric
//                   guarantee: no single step can ever turn more than this.
//   GP_SMOOTH       Heading smoothing window (steps).
//   GP_ALPHA        Trajectory-preference penalty (magnitude units / pixel).
//                   Scores each perpendicular candidate as:
//                     score = edge_magnitude - GP_ALPHA * |lateral_offset|
//                   Higher values strongly prefer edges near the predicted
//                   trajectory; 0 = pure edge strength (old behavior).
//                   Default 1.0. Increase if tracer jumps to threads/debris.
//
// ADVANCED PARAMETERS (shown below a divider in the same dialog):
//   GP_OUTLIER_MM   Remove Outliers radius (mm). 0 = skip step.
//   GP_STEP_MM      Walk step size (mm).
//   GP_SUBSAMPLE    Output 1 polyline vertex per this many steps.
// ============================================================

var GP_HW_MM        = 0.05;
var GP_BLUR_MM      = 0.01;
var GP_STEP_MM      = 0.1;
var GP_OUTLIER_MM   = 0.1;
var GP_MARGIN_TOP_MM = 1.5;
var GP_MARGIN_BOT_MM = 1.5;
var GP_SMOOTH       = 4;
var GP_MAX_TURN     = 15;
var GP_ALPHA        = 3.0;
var GP_SUBSAMPLE    = 2;
var gp_showOverlays = false;

macro "RingTracerCORE-1.0 [g]" {

    if (nImages == 0) exit("No image open.");
    gp_origID = getImageID();
    gp_W = getWidth(); gp_H = getHeight();

    // ---- Close stale processing windows from a prior interrupted run ----
    // If an earlier run errored out before its cleanup, intermediate windows
    // (1_Blurred…, 2_Find_Edges, 3_Edge_magnitude) may still be open. They
    // can steal window focus and cause operations to land on the wrong image.
    // Close any whose title starts with our processing-step prefixes.
    gp_titles = getList("image.titles");
    for (gp_ti = 0; gp_ti < gp_titles.length; gp_ti++) {
        if (startsWith(gp_titles[gp_ti], "1_Blurred") ||
            startsWith(gp_titles[gp_ti], "2_Find_Edges") ||
            startsWith(gp_titles[gp_ti], "3_Edge_magnitude")) {
            selectWindow(gp_titles[gp_ti]);
            close();
        }
    }
    // Restore selection to the original image
    selectImage(gp_origID);

    // ---- Require a calibrated scale ----
    getPixelSize(gp_unit, gp_pixW, gp_pixH);
    // getPixelSize returns dimensions in the calibrated unit per pixel.
    // We need pixels per mm, so we invert. Accept "mm" only; anything else
    // (including "pixel" / "" / unknown) is treated as uncalibrated.
    if (gp_unit != "mm") {
        exit("No mm scale set on this image.\n" +
             "Please set the image scale (Analyze > Set Scale) with unit = mm before running RingTracerCORE-1.0.");
    }
    // gp_pixW is mm/pixel; invert to get pixels/mm
    gp_pxMm = 1.0 / gp_pixW;
    print("Scale: " + gp_pxMm + " px/mm  (pixel size = " + gp_pixW + " mm)");

    if (gp_W > gp_H) { gp_axis = "vertical"; }
    else              { gp_axis = "horizontal"; }

    // ---- Load seed points: overlay-first, ROI Manager fallback ----
    // Transfer only POINT ROIs from the overlay into the ROI Manager.
    // We iterate overlay elements individually rather than using
    // run("To ROI Manager"), which would wipe the entire ROI Manager
    // (destroying any bounding lines or other polylines the user placed there).
    gp_nBefore = roiManager("count");
    gp_overlayLoaded = 0;

    // Only load seeds from overlay if the ROI Manager has no point ROIs yet.
    // On re-runs the seeds are already in the manager; loading the overlay
    // again would create duplicates.
    gp_hasSeeds = 0;
    for (gp_i = 0; gp_i < gp_nBefore; gp_i++) {
        roiManager("select", gp_i);
        if (selectionType() == 10) { gp_hasSeeds = 1; gp_i = gp_nBefore; }
    }
    if (Overlay.size > 0 && !gp_hasSeeds) {
        for (gp_i = 0; gp_i < Overlay.size; gp_i++) {
            Overlay.activateSelection(gp_i);
            if (selectionType() == 10) {
                roiManager("Add");
                gp_overlayLoaded = 1;
            }
        }
        run("Select None");
    }

    // ---- Remove any stale Ring_N_GP, Seg_N, and Tang_N ROIs ----
    // Safe: only deletes by name pattern, never touches non-point ROIs.
    gp_n = roiManager("count");
    for (gp_i = gp_n - 1; gp_i >= 0; gp_i--) {
        roiManager("select", gp_i);
        gp_rName = Roi.getName();
        if (indexOf(gp_rName, "_GP") >= 0 || indexOf(gp_rName, "Seg_") >= 0 || indexOf(gp_rName, "Tang_") >= 0)
            roiManager("delete");
    }

    // ================================================================
    // CORE EDGE LINE DETECTION
    // Look for exactly two polyline ROIs that don't contain "_GP" in
    // their name. If found, use them as top/bottom core edge boundaries
    // to stop the trace walk. Falls back to margin stops if not found.
    // ================================================================
    gp_nEdge = 0;
    gp_edgeCandN = newArray(2); gp_edgeMeanY = newArray(2);
    gp_edgeName0 = ""; gp_edgeName1 = "";  // names for preservation at cleanup
    // Temporary storage for edge coordinates (pre-allocated generously)
    gp_edgeMaxN = 2000;
    gp_edgeCand0X = newArray(gp_edgeMaxN); gp_edgeCand0Y = newArray(gp_edgeMaxN);
    gp_edgeCand1X = newArray(gp_edgeMaxN); gp_edgeCand1Y = newArray(gp_edgeMaxN);

    gp_n = roiManager("count");
    for (gp_i = 0; gp_i < gp_n; gp_i++) {
        roiManager("select", gp_i);
        gp_rName = Roi.getName();
        gp_rType = selectionType();
        // selectionType 6 = segmented/polyline, 5 = straight line, 3 = freehand line
        if ((gp_rType == 6 || gp_rType == 5 || gp_rType == 3) && indexOf(gp_rName, "_GP") < 0) {
            if (gp_nEdge < 2) {
                getSelectionCoordinates(gp_xs, gp_ys);
                gp_nPts2 = gp_xs.length;
                gp_sumY2 = 0;
                if (gp_nEdge == 0) {
                    for (gp_k = 0; gp_k < gp_nPts2; gp_k++) {
                        gp_edgeCand0X[gp_k] = gp_xs[gp_k];
                        gp_edgeCand0Y[gp_k] = gp_ys[gp_k];
                        gp_sumY2 += gp_ys[gp_k];
                    }
                    gp_edgeName0 = gp_rName;
                } else {
                    for (gp_k = 0; gp_k < gp_nPts2; gp_k++) {
                        gp_edgeCand1X[gp_k] = gp_xs[gp_k];
                        gp_edgeCand1Y[gp_k] = gp_ys[gp_k];
                        gp_sumY2 += gp_ys[gp_k];
                    }
                    gp_edgeName1 = gp_rName;
                }
                gp_edgeCandN[gp_nEdge]  = gp_nPts2;
                gp_edgeMeanY[gp_nEdge]  = gp_sumY2 / gp_nPts2;
                gp_nEdge++;
            } else {
                gp_nEdge++;  // count excess — will trigger warning
            }
        }
    }

    gp_useEdgeLines = 0;
    if (gp_nEdge == 2) {
        // Assign top (lower mean Y) and bottom (higher mean Y)
        if (gp_edgeMeanY[0] <= gp_edgeMeanY[1]) {
            gp_edgeTopX = gp_edgeCand0X;  gp_edgeTopY = gp_edgeCand0Y;
            gp_edgeTopN = gp_edgeCandN[0];
            gp_edgeBotX = gp_edgeCand1X;  gp_edgeBotY = gp_edgeCand1Y;
            gp_edgeBotN = gp_edgeCandN[1];
        } else {
            gp_edgeTopX = gp_edgeCand1X;  gp_edgeTopY = gp_edgeCand1Y;
            gp_edgeTopN = gp_edgeCandN[1];
            gp_edgeBotX = gp_edgeCand0X;  gp_edgeBotY = gp_edgeCand0Y;
            gp_edgeBotN = gp_edgeCandN[0];
        }
        gp_useEdgeLines = 1;
        // Rename boundary lines to standard names in ROI Manager.
        // top = lower mean Y (candidate with smaller gp_edgeMeanY).
        // We rename by scanning for each original name, which avoids
        // index-shift issues. After renaming, update the saved names
        // so the end-of-run cleanup preserves them correctly.
        if (gp_edgeMeanY[0] <= gp_edgeMeanY[1]) { gp_topName = gp_edgeName0; gp_botName = gp_edgeName1; }
        else                                       { gp_topName = gp_edgeName1; gp_botName = gp_edgeName0; }
        gp_n = roiManager("count");
        for (gp_k = 0; gp_k < gp_n; gp_k++) {
            roiManager("select", gp_k);
            gp_thisName = Roi.getName();
            if (gp_thisName == gp_topName) roiManager("Rename", "Core_boundary_top");
            if (gp_thisName == gp_botName) roiManager("Rename", "Core_boundary_bottom");
        }
        gp_edgeName0 = "Core_boundary_top";
        gp_edgeName1 = "Core_boundary_bottom";
        print("Core edge lines found: top meanY=" + gp_edgeMeanY[0] +
              "  bot meanY=" + gp_edgeMeanY[1]);
    } else if (gp_nEdge == 0) {
        print("No core edge lines found — using margin stops.");
    } else if (gp_nEdge == 1) {
        print("Only 1 edge line found (need 2) — using margin stops.");
    } else {
        print("Warning: " + gp_nEdge + " edge line candidates found (expected 2) — using margin stops.");
    }

    // ---- Collect seed points (coordinates + names), skip non-point ROIs ----
    // selectionType 10 = point, 6 = multi-point. All other types are ignored
    // and remain untouched in the ROI Manager.
    gp_n = roiManager("count");
    if (gp_n == 0) exit("No ROIs found. Please either:\n" +
                        " • Open a .tif with a seed-point overlay, or\n" +
                        " • Add Point ROIs to the ROI Manager before running.");

    gp_gX     = newArray(gp_n);
    gp_gY     = newArray(gp_n);
    gp_gName  = newArray(gp_n);
    gp_gRoiIdx = newArray(gp_n);  // original ROI Manager index, for optional removal later
    gp_nG = 0;
    for (gp_i = 0; gp_i < gp_n; gp_i++) {
        roiManager("select", gp_i);
        gp_rType = selectionType();
        gp_rName = Roi.getName();
        // Accept single-point (10) and multi-point (6) ROIs as seeds.
        // Exclude type-6 ROIs that are bounding edge lines (identified earlier by name).
        gp_isSeed = 0;
        if (gp_rType == 10) gp_isSeed = 1;
        if (gp_rType == 6 && gp_rName != gp_edgeName0 && gp_rName != gp_edgeName1) gp_isSeed = 1;
        if (gp_isSeed) {
            getSelectionCoordinates(gp_xs, gp_ys);
            gp_gX[gp_nG]      = gp_xs[0];
            gp_gY[gp_nG]      = gp_ys[0];
            gp_gName[gp_nG]   = gp_rName;
            gp_gRoiIdx[gp_nG] = gp_i;
            gp_nG++;
        }
    }
    if (gp_nG == 0) exit("No Point ROIs found. Non-point ROIs (polygons, lines, etc.) are ignored.\n" +
                         "Please add Point ROIs or open a .tif with a seed-point overlay.");
    if (gp_overlayLoaded) { print("Seeds collected: " + gp_nG + " point ROIs (from ROI Manager via overlay)"); }
    else                  { print("Seeds collected: " + gp_nG + " point ROIs (from ROI Manager directly)"); }
    gp_gX      = Array.trim(gp_gX,      gp_nG);
    gp_gY      = Array.trim(gp_gY,      gp_nG);
    gp_gName   = Array.trim(gp_gName,   gp_nG);
    gp_gRoiIdx = Array.trim(gp_gRoiIdx, gp_nG);
    gp_gX    = Array.trim(gp_gX,    gp_nG);
    gp_gY    = Array.trim(gp_gY,    gp_nG);
    gp_gName = Array.trim(gp_gName, gp_nG);
    // Sort along the walk axis; gpSortNamed keeps gp_gName in sync
    if (gp_axis == "vertical") { gpSortNamed(gp_gX, gp_gY, gp_gName, gp_nG); }
    else                       { gpSortNamed(gp_gY, gp_gX, gp_gName, gp_nG); }

    // Split the sorted seed sequence into coherent lines at each multi1
    // label.  A multi1 point begins a new segment; the break is between
    // it and the point immediately before it.
    //
    // Each segment is represented by its start/end indices into gp_gX/Y.
    // Segments with >= GP_SEG_MIN points are "coherent"; shorter ones are
    // "isolated" and borrow their angle from neighbouring coherent lines.
    // ================================================================
    GP_SEG_MIN = 3;  // minimum points for a coherent line

    // --- Pass 1: record segment start indices ---
    gp_segStart = newArray(gp_nG);  // over-allocated
    gp_nSeg = 0;
    gp_segStart[gp_nSeg++] = 0;  // first point always starts segment 0
    for (gp_i = 1; gp_i < gp_nG; gp_i++) {
        if (indexOf(gp_gName[gp_i], "multi1") >= 0) {
            gp_segStart[gp_nSeg++] = gp_i;
        }
    }
    gp_segStart = Array.trim(gp_segStart, gp_nSeg);

    // Derive end index for each segment (inclusive)
    gp_segEnd = newArray(gp_nSeg);
    for (gp_i = 0; gp_i < gp_nSeg - 1; gp_i++) {
        gp_segEnd[gp_i] = gp_segStart[gp_i + 1] - 1;
    }
    gp_segEnd[gp_nSeg - 1] = gp_nG - 1;

    // Segment lengths
    gp_segLen = newArray(gp_nSeg);
    for (gp_i = 0; gp_i < gp_nSeg; gp_i++) {
        gp_segLen[gp_i] = gp_segEnd[gp_i] - gp_segStart[gp_i] + 1;
    }

    // --- Pass 2: least-squares fit for each coherent segment ---
    // For vertical images: regress X (lateral) on Y (walk axis).
    //   lateral = slope * walk + intercept
    // The line angle (tangent direction) = atan2(1, slope) for vertical,
    //   or atan2(slope, 1) for horizontal — stored in gp_segTang[].
    // Isolated segments get NaN-sentinel (-9999) initially.
    gp_segTang      = newArray(gp_nSeg);
    gp_segSlope     = newArray(gp_nSeg);
    gp_segIntercept = newArray(gp_nSeg);
    gp_segCoherent  = newArray(gp_nSeg);  // 1 = coherent, 0 = isolated

    for (gp_si = 0; gp_si < gp_nSeg; gp_si++) {
        gp_s0 = gp_segStart[gp_si];
        gp_s1 = gp_segEnd[gp_si];
        gp_sN = gp_segLen[gp_si];

        if (gp_sN < GP_SEG_MIN) {
            gp_segCoherent[gp_si]  = 0;
            gp_segTang[gp_si]      = -9999;
            gp_segSlope[gp_si]     = -9999;
            gp_segIntercept[gp_si] = -9999;
        } else {
            gp_segCoherent[gp_si] = 1;
            // Accumulate sums for OLS: lateral ~ walk
            gp_sumW = 0; gp_sumL = 0; gp_sumWW = 0; gp_sumWL = 0;
            for (gp_k = gp_s0; gp_k <= gp_s1; gp_k++) {
                if (gp_axis == "vertical") {
                    gp_walk = gp_gY[gp_k]; gp_lat = gp_gX[gp_k];
                } else {
                    gp_walk = gp_gX[gp_k]; gp_lat = gp_gY[gp_k];
                }
                gp_sumW  += gp_walk;
                gp_sumL  += gp_lat;
                gp_sumWW += gp_walk * gp_walk;
                gp_sumWL += gp_walk * gp_lat;
            }
            gp_denom = gp_sN * gp_sumWW - gp_sumW * gp_sumW;
            if (abs(gp_denom) < 1e-9) {
                // Perfectly vertical (no walk-axis variance) — ring is orthogonal
                gp_segSlope[gp_si]     = 0;
                gp_segIntercept[gp_si] = gp_sumL / gp_sN;
            } else {
                gp_segSlope[gp_si]     = (gp_sN * gp_sumWL - gp_sumW * gp_sumL) / gp_denom;
                gp_segIntercept[gp_si] = (gp_sumL - gp_segSlope[gp_si] * gp_sumW) / gp_sN;
            }
            // Tang = direction along the line of points (walk axis is the dominant axis)
            if (gp_axis == "vertical") {
                gp_segTang[gp_si] = atan2(1, gp_segSlope[gp_si]);  // dY=1, dX=slope
            } else {
                gp_segTang[gp_si] = atan2(gp_segSlope[gp_si], 1);  // dY=slope, dX=1
            }
        }
        if (gp_segCoherent[gp_si]) {
            print("Segment " + (gp_si+1) + ": pts=" + gp_sN +
                  "  coherent=1  slope=" + gp_segSlope[gp_si] +
                  "  tang=" + (gp_segTang[gp_si]*180/PI) + "deg");
        } else {
            print("Segment " + (gp_si+1) + ": pts=" + gp_sN +
                  "  coherent=0  (isolated)");
        }
    }

    // --- Pass 3: assign angles to isolated segments ---
    // Find nearest coherent segment index (by position in segment list).
    // Edge case: if NO coherent segments exist at all, fall back to
    // the default axis-perpendicular tangent.
    gp_anyCoherent = 0;
    for (gp_si = 0; gp_si < gp_nSeg; gp_si++) {
        if (gp_segCoherent[gp_si]) gp_anyCoherent = 1;
    }

    for (gp_si = 0; gp_si < gp_nSeg; gp_si++) {
        if (gp_segCoherent[gp_si] == 0) {
            if (gp_anyCoherent == 0) {
                // No coherent lines anywhere — use axis default
                if (gp_axis == "vertical") { gp_segTang[gp_si] = PI/2; }
                else                       { gp_segTang[gp_si] = 0; }
            } else {
                // Find nearest coherent segment before and after
                gp_prevTang = -9999; gp_nextTang = -9999;
                for (gp_sj = gp_si - 1; gp_sj >= 0; gp_sj--) {
                    if (gp_segCoherent[gp_sj]) { gp_prevTang = gp_segTang[gp_sj]; gp_sj = -1; }
                }
                for (gp_sj = gp_si + 1; gp_sj < gp_nSeg; gp_sj++) {
                    if (gp_segCoherent[gp_sj]) { gp_nextTang = gp_segTang[gp_sj]; gp_sj = gp_nSeg; }
                }
                if (gp_prevTang == -9999) {
                    gp_segTang[gp_si] = gp_nextTang;  // edge: use next
                } else if (gp_nextTang == -9999) {
                    gp_segTang[gp_si] = gp_prevTang;  // edge: use prev
                } else {
                    // Average via circular mean of the two flanking tangs
                    gp_segTang[gp_si] = atan2(
                        (sin(gp_prevTang) + sin(gp_nextTang)) / 2,
                        (cos(gp_prevTang) + cos(gp_nextTang)) / 2
                    );
                }
            }
            print("  Segment " + (gp_si+1) + " isolated → assigned tang=" +
                  (gp_segTang[gp_si]*180/PI) + "deg");
        }
    }

    // --- Pass 4: segment grain polylines are drawn AFTER the dialog ---
    // (so the gp_showOverlays toggle is known). See the drawing block that
    // follows the parameter dialog. The segment computation above is complete.
    print("Segment detection done: " + gp_nSeg + " segments.");

    // ---- Build per-seed segment index lookup ----
    // Built here (before tang lines) so gp_seedSeg is available for both
    // the overlay drawing below and the ring loop later.
    // gp_seedSeg[g] = index into gp_segTang[] for seed point g.
    gp_seedSeg = newArray(gp_nG);
    gp_curSeg  = 0;
    for (gp_g = 0; gp_g < gp_nG; gp_g++) {
        gp_advancing = 1;
        while (gp_advancing) {
            if (gp_curSeg >= gp_nSeg - 1) {
                gp_advancing = 0;
            } else if (gp_g >= gp_segStart[gp_curSeg + 1]) {
                gp_curSeg++;
            } else {
                gp_advancing = 0;
            }
        }
        gp_seedSeg[gp_g] = gp_curSeg;
    }

    // ---- Compute per-seed LOCAL line tangent ----
    // The single OLS fit per segment (gp_segTang) gives one angle for the
    // whole transect, which is wrong where the core grain curves gradually
    // across a long segment. Instead, each seed's local tangent is computed
    // from its immediate neighbours WITHIN THE SAME SEGMENT — never across a
    // multi1 break, since that connection is an artifact, not real grain.
    //
    // Interior seed: central difference (prev → next).
    // Segment-edge seed: one-sided difference toward its in-segment neighbour.
    // Single-seed (isolated) segment: fall back to the segment's borrowed angle.
    gp_seedLineTang = newArray(gp_nG);
    for (gp_g = 0; gp_g < gp_nG; gp_g++) {
        gp_mySeg = gp_seedSeg[gp_g];
        gp_segS0 = gp_segStart[gp_mySeg];
        gp_segS1 = gp_segEnd[gp_mySeg];
        gp_hasPrev = (gp_g > gp_segS0);
        gp_hasNext = (gp_g < gp_segS1);
        if (gp_hasPrev && gp_hasNext) {
            // Central difference between in-segment neighbours
            gp_dxT = gp_gX[gp_g + 1] - gp_gX[gp_g - 1];
            gp_dyT = gp_gY[gp_g + 1] - gp_gY[gp_g - 1];
            gp_seedLineTang[gp_g] = atan2(gp_dyT, gp_dxT);
        } else if (gp_hasNext) {
            // First seed in segment — forward difference
            gp_dxT = gp_gX[gp_g + 1] - gp_gX[gp_g];
            gp_dyT = gp_gY[gp_g + 1] - gp_gY[gp_g];
            gp_seedLineTang[gp_g] = atan2(gp_dyT, gp_dxT);
        } else if (gp_hasPrev) {
            // Last seed in segment — backward difference
            gp_dxT = gp_gX[gp_g] - gp_gX[gp_g - 1];
            gp_dyT = gp_gY[gp_g] - gp_gY[gp_g - 1];
            gp_seedLineTang[gp_g] = atan2(gp_dyT, gp_dxT);
        } else {
            // Single-seed segment — no in-segment neighbour. Borrow the
            // segment's (isolated → nearest-coherent) angle computed earlier.
            gp_seedLineTang[gp_g] = gp_segTang[gp_mySeg];
        }
    }

    // ---- Seed tang lines are drawn AFTER the dialog (so gp_showOverlays
    // is known). See the drawing block following the parameter dialog. ----

    // ---- Derive default GP_HW_MM from seed points ----
    // For each seed find its nearest neighbour; take the min of those distances.
    // Also compute mean NND for use as the touch threshold — mean is robust
    // against collocated seeds that would collapse the minimum to zero.
    // Floor at 0.05 mm. Convert seed pixel coords to mm for the distance calculation.
    if (gp_nG >= 2) {
        gp_minNND  = 1e18;
        gp_sumNND  = 0;
        for (gp_i = 0; gp_i < gp_nG; gp_i++) {
            gp_nnDist = 1e18;
            for (gp_j = 0; gp_j < gp_nG; gp_j++) {
                if (gp_j != gp_i) {
                    gp_dx = (gp_gX[gp_i] - gp_gX[gp_j]) / gp_pxMm;  // mm
                    gp_dy = (gp_gY[gp_i] - gp_gY[gp_j]) / gp_pxMm;  // mm
                    gp_d  = sqrt(gp_dx*gp_dx + gp_dy*gp_dy);
                    if (gp_d < gp_nnDist) gp_nnDist = gp_d;
                }
            }
            if (gp_nnDist < gp_minNND) gp_minNND = gp_nnDist;
            gp_sumNND += gp_nnDist;
        }
        gp_meanNND = gp_sumNND / gp_nG;  // mean NND in mm — kept for logging
        GP_HW_MM = gp_minNND;
        if (GP_HW_MM < 0.05) GP_HW_MM = 0.05;  // floor at 0.05mm minimum
        print("Seed min NND = " + gp_minNND + " mm  mean NND = " + gp_meanNND +
              " mm  →  GP_HW default = " + GP_HW_MM + " mm");
    } else {
        GP_HW_MM   = 0.05;
        gp_meanNND = GP_HW_MM;  // fallback: only one seed
        print("Only 1 seed point — GP_HW defaulting to 0.05 mm");
    }

    // ---- Single unified dialog ----
    Dialog.create("RingTracerCORE-1.0 — Parameters");
    Dialog.addMessage("Image: " + gp_W + " x " + gp_H + " px    Scale: " + gp_pxMm + " px/mm    Ring axis: " + gp_axis);

    Dialog.addMessage("─── Image processing options ─────────────────");
    Dialog.addNumber("Edge blur sigma (mm):", GP_BLUR_MM);
    Dialog.addNumber("Remove Outliers radius (mm, 0 = skip):", GP_OUTLIER_MM);
    Dialog.addCheckbox("Keep intermediate processing windows open", false);

    Dialog.addMessage("─── Ring tracing options ─────────────────────");
    Dialog.addNumber("Ring width — search half-width (mm):", GP_HW_MM);
    Dialog.addNumber("Max turn per step (degrees):", GP_MAX_TURN);
    Dialog.addNumber("Heading smoothing (steps):", GP_SMOOTH);
    Dialog.addNumber("Trajectory preference (0=edge strength only, 5=strict):", GP_ALPHA);
    Dialog.addNumber("Walk step size (mm):", GP_STEP_MM);
    Dialog.addNumber("Output subsample factor:", GP_SUBSAMPLE);
    Dialog.addNumber("Fallback margin from top of image (mm):", GP_MARGIN_TOP_MM);
    Dialog.addNumber("Fallback margin from bottom of image (mm):", GP_MARGIN_BOT_MM);
    Dialog.addCheckbox("Add seed points, segment fit lines, and Tang indicators to ROI Manager", false);
    Dialog.show();

    GP_BLUR_MM       = Dialog.getNumber();
    GP_OUTLIER_MM    = Dialog.getNumber();
    gp_keepWindows   = Dialog.getCheckbox();
    GP_HW_MM         = Dialog.getNumber();
    GP_MAX_TURN      = Dialog.getNumber();
    GP_SMOOTH        = Dialog.getNumber();
    GP_ALPHA         = Dialog.getNumber();
    GP_STEP_MM       = Dialog.getNumber();
    GP_SUBSAMPLE     = Dialog.getNumber();
    GP_MARGIN_TOP_MM = Dialog.getNumber();
    GP_MARGIN_BOT_MM = Dialog.getNumber();
    gp_showOverlays  = Dialog.getCheckbox();

    // ================================================================
    // Draw diagnostic overlays NOW — after the dialog, so the toggle is
    // known on the first run. (Previously these were drawn before the
    // dialog, so gp_showOverlays still held its default and nothing
    // appeared until a second run.)
    // ================================================================
    if (gp_showOverlays) {
        selectImage(gp_origID);
        // --- Segment grain polylines (red) + isolated markers (cyan) ---
        for (gp_si = 0; gp_si < gp_nSeg; gp_si++) {
            gp_s0 = gp_segStart[gp_si];
            gp_s1 = gp_segEnd[gp_si];
            gp_segPts = gp_segLen[gp_si];
            if (gp_segPts >= 2) {
                gp_segPolyX = newArray(gp_segPts);
                gp_segPolyY = newArray(gp_segPts);
                gp_pi = 0;
                for (gp_k = gp_s0; gp_k <= gp_s1; gp_k++) {
                    gp_segPolyX[gp_pi] = gp_gX[gp_k];
                    gp_segPolyY[gp_pi] = gp_gY[gp_k];
                    gp_pi++;
                }
                makeSelection("polyline", gp_segPolyX, gp_segPolyY);
                Roi.setStrokeColor("red");
                Roi.setStrokeWidth(2);
                roiManager("Add");
                roiManager("select", roiManager("count") - 1);
                roiManager("Rename", "Seg_" + (gp_si+1) + "_grain");
            } else {
                gp_cxI = gp_gX[gp_s0];
                gp_cyI = gp_gY[gp_s0];
                gp_ovalR = 10;
                makeOval(gp_cxI - gp_ovalR, gp_cyI - gp_ovalR, gp_ovalR*2, gp_ovalR*2);
                Roi.setStrokeColor("cyan");
                Roi.setStrokeWidth(2);
                roiManager("Add");
                roiManager("select", roiManager("count") - 1);
                roiManager("Rename", "Seg_" + (gp_si+1) + "_isolated");
            }
        }
        // --- Seed tang lines (orange) ---
        gp_tangHalfLen = gp_H / 2.0;
        for (gp_g = 0; gp_g < gp_nG; gp_g++) {
            gp_tSeedTang = gp_seedLineTang[gp_g] + PI/2;  // ring direction
            if (gp_axis == "vertical") { gp_tDefault = PI/2; }
            else                       { gp_tDefault = 0; }
            gp_tDot = cos(gp_tDefault)*cos(gp_tSeedTang) + sin(gp_tDefault)*sin(gp_tSeedTang);
            if (gp_tDot < 0) gp_tSeedTang = gp_tSeedTang + PI;
            gp_tX0 = gp_gX[gp_g] - gp_tangHalfLen * cos(gp_tSeedTang);
            gp_tY0 = gp_gY[gp_g] - gp_tangHalfLen * sin(gp_tSeedTang);
            gp_tX1 = gp_gX[gp_g] + gp_tangHalfLen * cos(gp_tSeedTang);
            gp_tY1 = gp_gY[gp_g] + gp_tangHalfLen * sin(gp_tSeedTang);
            makeLine(gp_tX0, gp_tY0, gp_tX1, gp_tY1);
            Roi.setStrokeColor("orange");
            Roi.setStrokeWidth(1);
            roiManager("Add");
            roiManager("select", roiManager("count") - 1);
            roiManager("Rename", "Tang_" + (gp_g+1));
        }
        roiManager("Show All");
    }

    gp_maxTurnRad = GP_MAX_TURN * PI / 180;

    // ---- Convert mm parameters to pixels for internal use ----
    GP_BLUR      = GP_BLUR_MM     * gp_pxMm;
    GP_HW        = GP_HW_MM       * gp_pxMm;
    GP_STEP      = GP_STEP_MM     * gp_pxMm;
    GP_OUTLIER   = GP_OUTLIER_MM  * gp_pxMm;
    GP_MARGIN_TOP = GP_MARGIN_TOP_MM * gp_pxMm;
    GP_MARGIN_BOT = GP_MARGIN_BOT_MM * gp_pxMm;

    print("Image: " + gp_W + "x" + gp_H + "  rings=" + gp_axis);
    print("blur=" + GP_BLUR_MM + "mm (" + GP_BLUR + "px)" +
          "  outlier=" + GP_OUTLIER_MM + "mm (" + GP_OUTLIER + "px)" +
          "  hw=" + GP_HW_MM + "mm (" + GP_HW + "px)" +
          "  maxTurn=" + GP_MAX_TURN + "deg" +
          "  smooth=" + GP_SMOOTH + "steps" +
          "  step=" + GP_STEP_MM + "mm (" + GP_STEP + "px)" +
          "  subsample=" + GP_SUBSAMPLE);

    // ---- build edge magnitude array via Find Edges ----
    // Find Edges computes sqrt(Gx²+Gy²) identically to the manual Sobel approach
    // but produces better-looking output (no faint inner-ring dropoff) and is
    // simpler. We no longer need the gradient angle array — seed tangents now come
    // from the fitted segment lines instead.
    gp_blurLabel  = "1_Blurred_8bit (blur=" + GP_BLUR_MM + "mm outlier=" + GP_OUTLIER_MM + "mm)";
    gp_edgesLabel = "2_Find_Edges";
    gp_magLabel   = "3_Edge_magnitude";

    selectImage(gp_origID);
    run("Duplicate...", "title=[" + gp_blurLabel + "]"); gp_wID = getImageID();
    selectImage(gp_wID);
    run("8-bit");  // convert to 8-bit grayscale (handles RGB and other depths)
    selectImage(gp_wID);
    if (GP_BLUR > 0) run("Gaussian Blur...", "sigma=" + GP_BLUR);
    if (GP_OUTLIER > 0) run("Remove Outliers...", "radius=" + GP_OUTLIER + " threshold=0 which=Bright");

    // Find Edges operates on the blurred/cleaned image; keep a display copy.
    // Explicitly re-select gp_wID first so the duplicate is taken from the
    // correct (now 8-bit) image rather than whatever window happens to be active.
    selectImage(gp_wID);
    run("Duplicate...", "title=[" + gp_edgesLabel + "]"); gp_edgesID = getImageID();
    selectImage(gp_edgesID);
    if (bitDepth() == 24) run("8-bit");  // safety: ensure not RGB before LUT
    run("Find Edges");
    run("Enhance Contrast", "saturated=0.35");
    run("Grays");

    // Read magnitude pixels from the Find Edges result
    gp_mag = newArray(gp_W * gp_H);
    selectImage(gp_edgesID);
    for (gp_y = 0; gp_y < gp_H; gp_y++)
        for (gp_x = 0; gp_x < gp_W; gp_x++)
            gp_mag[gp_y*gp_W+gp_x] = getPixel(gp_x, gp_y);

    // Close intermediate windows unless user asked to keep them
    if (gp_keepWindows == 0) {
        selectImage(gp_wID); close();
        selectImage(gp_edgesID); close();
    }

    // Allocate trace buffers — extra room for off-edge extrapolation
    if (gp_axis == "vertical") { gp_walkLen = gp_H; }
    else                       { gp_walkLen = gp_W; }
    gp_maxPts = gp_walkLen / GP_STEP + 200;
    gp_fwdX = newArray(gp_maxPts); gp_fwdY = newArray(gp_maxPts);
    gp_bwdX = newArray(gp_maxPts); gp_bwdY = newArray(gp_maxPts);
    gp_sBuf = newArray(GP_SMOOTH);  gp_cBuf = newArray(GP_SMOOTH);

    // Per-ring storage for post-processing intersection trim.
    // All output points are stored in flat arrays; gp_ringOffset[g] gives
    // the start index for ring g, gp_ringLen[g] its point count.
    gp_maxFlatN    = gp_nG * (gp_walkLen / GP_STEP / GP_SUBSAMPLE + 20);
    gp_flatX       = newArray(gp_maxFlatN);
    gp_flatY       = newArray(gp_maxFlatN);
    gp_flatN       = 0;
    gp_ringOffset  = newArray(gp_nG);
    gp_ringLen     = newArray(gp_nG);
    gp_ringSeedIdx = newArray(gp_nG);

    selectImage(gp_origID);

    // ================================================================
    // RING LOOP
    // ================================================================
    for (gp_g = 0; gp_g < gp_nG; gp_g++) {
        gp_seedX = round(gp_gX[gp_g]);
        gp_seedY = round(gp_gY[gp_g]);
        print("Ring " + (gp_g+1) + ": seed (" + gp_seedX + ", " + gp_seedY + ")");

        // ---- Derive seed heading from fitted segment line ----
        // The segment tang is the direction ALONG the line of seed points.
        // The ring boundary runs PERPENDICULAR to that, so we rotate 90°.
        // We then resolve the 180° ambiguity to keep the heading in the
        // same half-plane as the walk-axis default (PI/2 for vertical images).
        if (gp_axis == "vertical") { gp_tangDefault = PI/2; }
        else                       { gp_tangDefault = 0; }

        gp_lineTang = gp_seedLineTang[gp_g];          // local direction along seed line
        gp_seedTang = gp_lineTang + PI/2;             // perpendicular = ring direction
        // Normalise into -PI..PI
        while (gp_seedTang >  PI) { gp_seedTang = gp_seedTang - 2*PI; }
        while (gp_seedTang < 0-PI) { gp_seedTang = gp_seedTang + 2*PI; }

        // Resolve 180° ambiguity: keep tang in the same half as gp_tangDefault
        gp_iDot = cos(gp_tangDefault)*cos(gp_seedTang) + sin(gp_tangDefault)*sin(gp_seedTang);
        if (gp_iDot < 0) { gp_seedTang = gp_seedTang + PI; }
        // Normalise again after possible +PI
        while (gp_seedTang >  PI) { gp_seedTang = gp_seedTang - 2*PI; }
        while (gp_seedTang < 0-PI) { gp_seedTang = gp_seedTang + 2*PI; }

        print("  seg=" + (gp_seedSeg[gp_g]+1) +
              "  lineTang=" + (gp_lineTang*180/PI) + "deg" +
              "  seedTang=" + (gp_seedTang*180/PI) + "deg");

        // Run forward (pass=0) then backward (pass=1)
        for (gp_pass = 0; gp_pass <= 1; gp_pass++) {
            if (gp_pass == 0) { gp_step = GP_STEP; }
            else               { gp_step = 0 - GP_STEP; }

            gp_cx = gp_seedX; gp_cy = gp_seedY;
            print("  pass=" + gp_pass + " cx=" + gp_cx + " cy=" + gp_cy + " step=" + gp_step);

            // Forward pass uses the seed heading directly.
            // Backward pass flips 180° — it walks in the opposite direction
            // so its heading must point that way too. This ensures both passes
            // start as exact mirror images at the seed, eliminating the
            // directional discontinuity (kink) that would otherwise appear there.
            if (gp_pass == 0) {
                gp_tang = gp_seedTang;
            } else {
                gp_tang = gp_seedTang + PI;
                while (gp_tang >  PI) { gp_tang = gp_tang - 2*PI; }
                while (gp_tang < 0-PI) { gp_tang = gp_tang + 2*PI; }
            }

            for (gp_k = 0; gp_k < GP_SMOOTH; gp_k++) {
                gp_sBuf[gp_k] = sin(gp_tang);
                gp_cBuf[gp_k] = cos(gp_tang);
            }
            gp_bIdx = 0;
            gp_nPts = 0;
            gp_warmup = GP_SMOOTH;
            // Max steps per pass: 2× image height worth of steps.
            // This caps each pass at a sensible anatomical length regardless of
            // ring orientation, without cutting off rings that run diagonally.
            gp_maxSteps = round(2 * gp_H / GP_STEP) + 1;
            gp_noEdge = 0;
            // Reference heading for drift check: the starting tang of THIS pass.
            // Must be set here (not once outside the loop) so the backward pass
            // checks drift against its own starting direction, not the forward one.
            gp_passStartTang = gp_tang;

            gp_going = 1;
            while (gp_going) {
                if (gp_nPts >= gp_maxSteps) { gp_going = 0; }

                // ---- Check bounds: stop at core edge lines or margin fallback ----
                if (gp_useEdgeLines) {
                    if (gp_axis == "vertical") {
                        gp_edgeTopYq = gpEdgeY(gp_edgeTopX, gp_edgeTopY, gp_edgeTopN, gp_cx, GP_MARGIN_TOP);
                        gp_edgeBotYq = gpEdgeY(gp_edgeBotX, gp_edgeBotY, gp_edgeBotN, gp_cx, gp_H - GP_MARGIN_BOT);
                        if (gp_cy <= gp_edgeTopYq || gp_cy >= gp_edgeBotYq) gp_going = 0;
                    } else {
                        gp_edgeTopYq = gpEdgeY(gp_edgeTopX, gp_edgeTopY, gp_edgeTopN, gp_cy, GP_MARGIN_TOP);
                        gp_edgeBotYq = gpEdgeY(gp_edgeBotX, gp_edgeBotY, gp_edgeBotN, gp_cy, gp_W - GP_MARGIN_BOT);
                        if (gp_cx <= gp_edgeTopYq || gp_cx >= gp_edgeBotYq) gp_going = 0;
                    }
                } else {
                    if (gp_axis == "vertical") {
                        if (gp_cy < GP_MARGIN_TOP || gp_cy >= gp_H - GP_MARGIN_BOT) gp_going = 0;
                    } else {
                        if (gp_cx < GP_MARGIN_TOP || gp_cx >= gp_W - GP_MARGIN_BOT) gp_going = 0;
                    }
                }
                if (gp_cx < 0 || gp_cx >= gp_W) gp_going = 0;
                if (gp_cy < 0 || gp_cy >= gp_H) gp_going = 0;

                if (gp_going == 0) { } else {

                {  // trace step

                    // ---- 1. Candidate next position: step along current heading ----
                    gp_nx = gp_cx + GP_STEP * cos(gp_tang);
                    gp_ny = gp_cy + GP_STEP * sin(gp_tang);

                    // ---- 2. Search perpendicular at candidate position ----
                    // Score each candidate as:  score = edge_magnitude - GP_ALPHA * |d|
                    // This prefers edges near the predicted trajectory (small |d|) over
                    // stronger but more distant edges (e.g. threads, adjacent rings).
                    // GP_ALPHA=0 is pure edge-strength (old behavior).
                    // Only accept candidates with score > 0 so a distant weak edge
                    // cannot win over staying on the predicted path.
                    gp_ga = gp_tang - PI/2;
                    gp_bX = round(gp_nx); gp_bY = round(gp_ny);
                    gp_bScore = 0;  // best score so far; candidate must beat 0 to be accepted
                    for (gp_d = 0-GP_HW; gp_d <= GP_HW; gp_d++) {
                        gp_tx = round(gp_nx + gp_d * cos(gp_ga));
                        gp_ty = round(gp_ny + gp_d * sin(gp_ga));
                        if (gp_tx >= 0 && gp_tx < gp_W && gp_ty >= 0 && gp_ty < gp_H) {
                            gp_m2 = gp_mag[gp_ty * gp_W + gp_tx];
                            gp_sc = gp_m2 - GP_ALPHA * abs(gp_d);
                            if (gp_sc > gp_bScore) {
                                gp_bScore = gp_sc;
                                gp_bM = gp_m2;
                                gp_bX = gp_tx; gp_bY = gp_ty;
                            }
                        }
                    }
                    // If no candidate beat the threshold, bX/bY stay at tang-predicted pos
                    // and bM stays at -1 (triggers edge-loss counter below).
                    if (gp_bScore <= 0) { gp_bM = -1; }

                    // Edge-loss: stop only after a generous run of no-signal
                    // steps. Tying this to GP_SMOOTH (=4) made traces quit at
                    // faint stretches mid-core; a larger fixed tolerance lets
                    // the walk coast through weak gaps on its tang-predicted
                    // heading and re-lock when the edge reappears. Rings with
                    // a clear signal never accumulate these, so they're unaffected.
                    if (gp_bM < 8) {
                        gp_noEdge = gp_noEdge + 1;
                    } else {
                        gp_noEdge = 0;
                    }
                    if (gp_noEdge >= 12) { gp_going = 0; }

                    if (gp_going == 1) {

                    // ---- 3. Update heading from current pos → best edge hit ----
                    // During warmup: frozen at seedTang.
                    // After warmup: clamp to ±GP_MAX_TURN, then smooth.
                    if (gp_warmup > 0) {
                        gp_warmup = gp_warmup - 1;
                    } else {
                        gp_lt = atan2(gp_bY - gp_cy, gp_bX - gp_cx);
                        gp_dot = cos(gp_tang)*cos(gp_lt) + sin(gp_tang)*sin(gp_lt);
                        if (gp_dot < 0) { gp_lt = gp_lt + PI; }
                        while (gp_lt >  PI) { gp_lt = gp_lt - 2*PI; }
                        while (gp_lt < 0-PI) { gp_lt = gp_lt + 2*PI; }
                        gp_dTang = gp_lt - gp_tang;
                        if (gp_dTang >  PI) { gp_dTang = gp_dTang - 2*PI; }
                        if (gp_dTang < 0-PI) { gp_dTang = gp_dTang + 2*PI; }
                        if (gp_dTang >  gp_maxTurnRad) { gp_dTang =  gp_maxTurnRad; }
                        if (gp_dTang < 0-gp_maxTurnRad) { gp_dTang = 0-gp_maxTurnRad; }
                        gp_lt = gp_tang + gp_dTang;
                        while (gp_lt >  PI) { gp_lt = gp_lt - 2*PI; }
                        while (gp_lt < 0-PI) { gp_lt = gp_lt + 2*PI; }
                        gp_sBuf[gp_bIdx] = sin(gp_lt);
                        gp_cBuf[gp_bIdx] = cos(gp_lt);
                        gp_bIdx = (gp_bIdx + 1) % GP_SMOOTH;
                        gp_sS = 0; gp_cS = 0;
                        for (gp_k = 0; gp_k < GP_SMOOTH; gp_k++) {
                            gp_sS += gp_sBuf[gp_k]; gp_cS += gp_cBuf[gp_k];
                        }
                        gp_tang = atan2(gp_sS/GP_SMOOTH, gp_cS/GP_SMOOTH);

                        // Stop if heading has drifted >90° from this pass's start tang.
                        // Using passStartTang (not seedTang) so the backward pass
                        // checks against its own starting direction.
                        gp_drift = gp_tang - gp_passStartTang;
                        if (gp_drift >  PI) { gp_drift = gp_drift - 2*PI; }
                        if (gp_drift < 0-PI) { gp_drift = gp_drift + 2*PI; }
                        if (abs(gp_drift) > PI/2) { gp_going = 0; }
                    }

                    // ---- 4. Snap position to best edge hit, store ----
                    // No clamp here — if bX/bY is out of image the bounds check at
                    // the top of the while loop will stop the trace next iteration.
                    gp_cx = gp_bX;
                    gp_cy = gp_bY;
                    if (gp_pass == 0) {
                        gp_fwdX[gp_nPts] = gp_cx; gp_fwdY[gp_nPts] = gp_cy;
                    } else {
                        gp_bwdX[gp_nPts] = gp_cx; gp_bwdY[gp_nPts] = gp_cy;
                    }
                    gp_nPts++;

                    } // end if gp_going after edge-loss check

                } // end trace block

                } // end gp_going check
            } // end while

            if (gp_pass == 0) { gp_nFwd = gp_nPts; }
            else               { gp_nBwd = gp_nPts; }
        } // end pass loop

        print("  fwd=" + gp_nFwd + " bwd=" + gp_nBwd);

        // ---- Merge + subsample ----
        gp_total = gp_nBwd + gp_nFwd - 1;
        gp_outN  = floor(gp_total / GP_SUBSAMPLE) + 4;
        gp_outX  = newArray(gp_outN);
        gp_outY  = newArray(gp_outN);
        gp_oi = 0;

        // Reversed backward (skip index 0 = seed, which fwd also starts at)
        for (gp_k = gp_nBwd - 1; gp_k >= 1; gp_k--) {
            if ((gp_nBwd - 1 - gp_k) % GP_SUBSAMPLE == 0) {
                gp_outX[gp_oi] = gp_bwdX[gp_k];
                gp_outY[gp_oi] = gp_bwdY[gp_k];
                gp_oi++;
            }
        }
        // Forward
        for (gp_k = 0; gp_k < gp_nFwd; gp_k++) {
            if (gp_k % GP_SUBSAMPLE == 0 || gp_k == gp_nFwd - 1) {
                gp_outX[gp_oi] = gp_fwdX[gp_k];
                gp_outY[gp_oi] = gp_fwdY[gp_k];
                gp_oi++;
            }
        }

        print("  output vertices: " + gp_oi);
        gp_outX = Array.trim(gp_outX, gp_oi);
        gp_outY = Array.trim(gp_outY, gp_oi);

        // ---- Store ring for post-processing (not yet written to ROI Manager) ----
        // Seed falls at index = number of subsampled backward steps
        gp_ringSeedIdx[gp_g] = floor((gp_nBwd - 1) / GP_SUBSAMPLE);
        gp_ringLen[gp_g]     = gp_oi;
        // Flatten into 1-D storage arrays (offset = gp_ringOffset[gp_g])
        gp_ringOffset[gp_g]  = gp_flatN;
        for (gp_k = 0; gp_k < gp_oi; gp_k++) {
            gp_flatX[gp_flatN] = gp_outX[gp_k];
            gp_flatY[gp_flatN] = gp_outY[gp_k];
            gp_flatN++;
        }
    } // end ring loop

    // ================================================================
    // POST-PROCESSING: All-pairs intersection trimming
    // For every pair of rings, find the first segment-segment
    // intersection and trim each ring from its nearest end.
    // A bounding-box pre-filter skips pairs whose extents don't overlap,
    // avoiding the expensive segment loop for clearly separated rings.
    // Bounding boxes are updated after each trim so subsequent pairs
    // benefit from tighter bounds on already-trimmed rings.
    // ================================================================
    print("Post-processing: checking all pairs for intersections...");

    // ---- Precompute bounding boxes ----
    gp_bbMinX = newArray(gp_nG); gp_bbMaxX = newArray(gp_nG);
    gp_bbMinY = newArray(gp_nG); gp_bbMaxY = newArray(gp_nG);
    for (gp_g = 0; gp_g < gp_nG; gp_g++) {
        gp_oA = gp_ringOffset[gp_g];
        gp_nA = gp_ringLen[gp_g];
        gp_bbMinX[gp_g] = gp_flatX[gp_oA]; gp_bbMaxX[gp_g] = gp_flatX[gp_oA];
        gp_bbMinY[gp_g] = gp_flatY[gp_oA]; gp_bbMaxY[gp_g] = gp_flatY[gp_oA];
        for (gp_k = 1; gp_k < gp_nA; gp_k++) {
            gp_px = gp_flatX[gp_oA + gp_k]; gp_py = gp_flatY[gp_oA + gp_k];
            if (gp_px < gp_bbMinX[gp_g]) gp_bbMinX[gp_g] = gp_px;
            if (gp_px > gp_bbMaxX[gp_g]) gp_bbMaxX[gp_g] = gp_px;
            if (gp_py < gp_bbMinY[gp_g]) gp_bbMinY[gp_g] = gp_py;
            if (gp_py > gp_bbMaxY[gp_g]) gp_bbMaxY[gp_g] = gp_py;
        }
    }

    // Touch threshold: 0.5 × GP_HW (in px).
    // GP_HW = minimum euclidean NND between seeds = minimum ring width.
    // Half of that is a conservative gap — small enough not to trim
    // legitimately close distinct rings, large enough to catch noise
    // traces that have overshot into a neighboring ring's territory.
    gp_touchThresh2 = 0.5 * GP_HW;
    gp_touchThresh2 = gp_touchThresh2 * gp_touchThresh2;
    print("Touch threshold: " + (0.5 * GP_HW_MM) + " mm  (" + (0.5 * GP_HW) + " px)");

    for (gp_g = 0; gp_g < gp_nG - 1; gp_g++) {
        for (gp_h = gp_g + 1; gp_h < gp_nG; gp_h++) {

            // ---- Sorted-order early break ----
            // Seeds are sorted by X, so rings are roughly ordered left-to-right.
            // Once ring h's minX exceeds ring g's maxX, no further ring can
            // overlap ring g in X — break the inner loop entirely.
            if (gp_bbMinX[gp_h] > gp_bbMaxX[gp_g]) { gp_h = gp_nG; } else {

            // ---- Bounding box pre-filter (Y axis and reverse X) ----
            if (gp_bbMaxY[gp_g] < gp_bbMinY[gp_h] || gp_bbMinY[gp_g] > gp_bbMaxY[gp_h] ||
                gp_bbMinX[gp_g] > gp_bbMaxX[gp_h]) {
                // bboxes don't overlap — skip this pair
            } else {

            gp_oA = gp_ringOffset[gp_g];
            gp_nA = gp_ringLen[gp_g];
            gp_oB = gp_ringOffset[gp_h];
            gp_nB = gp_ringLen[gp_h];
            gp_sA = gp_ringSeedIdx[gp_g];
            gp_sB = gp_ringSeedIdx[gp_h];

            gp_hitFound = 0;

            // Scan inward from the backward end (index 0) of ring A.
            // If the first point is within threshold of any point on ring B,
            // advance inward until we're clear. Record the first safe index.
            gp_trimBwdA = 0;
            gp_ax1 = gp_flatX[gp_oA];  gp_ay1 = gp_flatY[gp_oA];
            gp_inThresh = 0;
            for (gp_j = 0; gp_j < gp_nB; gp_j++) {
                gp_dx2 = gp_ax1 - gp_flatX[gp_oB + gp_j];
                gp_dy2 = gp_ay1 - gp_flatY[gp_oB + gp_j];
                if (gp_dx2*gp_dx2 + gp_dy2*gp_dy2 < gp_touchThresh2) { gp_inThresh = 1; gp_j = gp_nB; }
            }
            if (gp_inThresh) {
                for (gp_i = 0; gp_i < gp_sA; gp_i++) {
                    gp_ax1 = gp_flatX[gp_oA + gp_i]; gp_ay1 = gp_flatY[gp_oA + gp_i];
                    gp_clear = 1;
                    for (gp_j = 0; gp_j < gp_nB; gp_j++) {
                        gp_dx2 = gp_ax1 - gp_flatX[gp_oB + gp_j];
                        gp_dy2 = gp_ay1 - gp_flatY[gp_oB + gp_j];
                        if (gp_dx2*gp_dx2 + gp_dy2*gp_dy2 < gp_touchThresh2) { gp_clear = 0; gp_j = gp_nB; }
                    }
                    if (gp_clear) { gp_trimBwdA = gp_i; gp_i = gp_sA; }
                    else          { gp_trimBwdA = gp_i + 1; }
                }
                gp_hitFound = 1;
            }

            // Scan inward from the forward end (index nA-1) of ring A.
            gp_trimFwdA = gp_nA;
            gp_ax1 = gp_flatX[gp_oA + gp_nA - 1]; gp_ay1 = gp_flatY[gp_oA + gp_nA - 1];
            gp_inThresh = 0;
            for (gp_j = 0; gp_j < gp_nB; gp_j++) {
                gp_dx2 = gp_ax1 - gp_flatX[gp_oB + gp_j];
                gp_dy2 = gp_ay1 - gp_flatY[gp_oB + gp_j];
                if (gp_dx2*gp_dx2 + gp_dy2*gp_dy2 < gp_touchThresh2) { gp_inThresh = 1; gp_j = gp_nB; }
            }
            if (gp_inThresh) {
                for (gp_i = gp_nA - 1; gp_i > gp_sA; gp_i--) {
                    gp_ax1 = gp_flatX[gp_oA + gp_i]; gp_ay1 = gp_flatY[gp_oA + gp_i];
                    gp_clear = 1;
                    for (gp_j = 0; gp_j < gp_nB; gp_j++) {
                        gp_dx2 = gp_ax1 - gp_flatX[gp_oB + gp_j];
                        gp_dy2 = gp_ay1 - gp_flatY[gp_oB + gp_j];
                        if (gp_dx2*gp_dx2 + gp_dy2*gp_dy2 < gp_touchThresh2) { gp_clear = 0; gp_j = gp_nB; }
                    }
                    if (gp_clear) { gp_trimFwdA = gp_i + 1; gp_i = -1; }
                    else          { gp_trimFwdA = gp_i; }
                }
                gp_hitFound = 1;
            }

            // Scan inward from the backward end of ring B.
            gp_trimBwdB = 0;
            gp_bx1 = gp_flatX[gp_oB]; gp_by1 = gp_flatY[gp_oB];
            gp_inThresh = 0;
            for (gp_i = 0; gp_i < gp_nA; gp_i++) {
                gp_dx2 = gp_bx1 - gp_flatX[gp_oA + gp_i];
                gp_dy2 = gp_by1 - gp_flatY[gp_oA + gp_i];
                if (gp_dx2*gp_dx2 + gp_dy2*gp_dy2 < gp_touchThresh2) { gp_inThresh = 1; gp_i = gp_nA; }
            }
            if (gp_inThresh) {
                for (gp_j = 0; gp_j < gp_sB; gp_j++) {
                    gp_bx1 = gp_flatX[gp_oB + gp_j]; gp_by1 = gp_flatY[gp_oB + gp_j];
                    gp_clear = 1;
                    for (gp_i = 0; gp_i < gp_nA; gp_i++) {
                        gp_dx2 = gp_bx1 - gp_flatX[gp_oA + gp_i];
                        gp_dy2 = gp_by1 - gp_flatY[gp_oA + gp_i];
                        if (gp_dx2*gp_dx2 + gp_dy2*gp_dy2 < gp_touchThresh2) { gp_clear = 0; gp_i = gp_nA; }
                    }
                    if (gp_clear) { gp_trimBwdB = gp_j; gp_j = gp_sB; }
                    else          { gp_trimBwdB = gp_j + 1; }
                }
                gp_hitFound = 1;
            }

            // Scan inward from the forward end of ring B.
            gp_trimFwdB = gp_nB;
            gp_bx1 = gp_flatX[gp_oB + gp_nB - 1]; gp_by1 = gp_flatY[gp_oB + gp_nB - 1];
            gp_inThresh = 0;
            for (gp_i = 0; gp_i < gp_nA; gp_i++) {
                gp_dx2 = gp_bx1 - gp_flatX[gp_oA + gp_i];
                gp_dy2 = gp_by1 - gp_flatY[gp_oA + gp_i];
                if (gp_dx2*gp_dx2 + gp_dy2*gp_dy2 < gp_touchThresh2) { gp_inThresh = 1; gp_i = gp_nA; }
            }
            if (gp_inThresh) {
                for (gp_j = gp_nB - 1; gp_j > gp_sB; gp_j--) {
                    gp_bx1 = gp_flatX[gp_oB + gp_j]; gp_by1 = gp_flatY[gp_oB + gp_j];
                    gp_clear = 1;
                    for (gp_i = 0; gp_i < gp_nA; gp_i++) {
                        gp_dx2 = gp_bx1 - gp_flatX[gp_oA + gp_i];
                        gp_dy2 = gp_by1 - gp_flatY[gp_oA + gp_i];
                        if (gp_dx2*gp_dx2 + gp_dy2*gp_dy2 < gp_touchThresh2) { gp_clear = 0; gp_i = gp_nA; }
                    }
                    if (gp_clear) { gp_trimFwdB = gp_j + 1; gp_j = -1; }
                    else          { gp_trimFwdB = gp_j; }
                }
                gp_hitFound = 1;
            }

            if (gp_hitFound) {
                // Apply backward trim to ring A if needed
                if (gp_trimBwdA > 0) {
                    gp_trimLen = gp_nA - gp_trimBwdA;
                    for (gp_k = 0; gp_k < gp_trimLen; gp_k++) {
                        gp_flatX[gp_oA + gp_k] = gp_flatX[gp_oA + gp_trimBwdA + gp_k];
                        gp_flatY[gp_oA + gp_k] = gp_flatY[gp_oA + gp_trimBwdA + gp_k];
                    }
                    gp_ringLen[gp_g]     = gp_trimLen;
                    gp_ringSeedIdx[gp_g] = gp_sA - gp_trimBwdA;
                    if (gp_ringSeedIdx[gp_g] < 0) gp_ringSeedIdx[gp_g] = 0;
                    gp_trimFwdA = gp_trimFwdA - gp_trimBwdA;  // adjust for shift
                    if (gp_trimFwdA < 1) gp_trimFwdA = 1;
                    gp_nA = gp_trimLen;
                    print("    Ring " + (gp_g+1) + ": trimmed backward end → " + gp_trimLen + " pts");
                }
                // Apply forward trim to ring A if needed
                if (gp_trimFwdA < gp_nA) {
                    if (gp_trimFwdA < 1) gp_trimFwdA = 1;
                    gp_ringLen[gp_g] = gp_trimFwdA;
                    gp_nA = gp_trimFwdA;
                    print("    Ring " + (gp_g+1) + ": trimmed forward end → " + gp_trimFwdA + " pts");
                }
                // Update bbox for ring A
                gp_bbMinX[gp_g] = gp_flatX[gp_oA]; gp_bbMaxX[gp_g] = gp_flatX[gp_oA];
                gp_bbMinY[gp_g] = gp_flatY[gp_oA]; gp_bbMaxY[gp_g] = gp_flatY[gp_oA];
                for (gp_k = 1; gp_k < gp_nA; gp_k++) {
                    gp_px = gp_flatX[gp_oA + gp_k]; gp_py = gp_flatY[gp_oA + gp_k];
                    if (gp_px < gp_bbMinX[gp_g]) gp_bbMinX[gp_g] = gp_px;
                    if (gp_px > gp_bbMaxX[gp_g]) gp_bbMaxX[gp_g] = gp_px;
                    if (gp_py < gp_bbMinY[gp_g]) gp_bbMinY[gp_g] = gp_py;
                    if (gp_py > gp_bbMaxY[gp_g]) gp_bbMaxY[gp_g] = gp_py;
                }

                // Apply backward trim to ring B if needed
                if (gp_trimBwdB > 0) {
                    gp_trimLen = gp_nB - gp_trimBwdB;
                    for (gp_k = 0; gp_k < gp_trimLen; gp_k++) {
                        gp_flatX[gp_oB + gp_k] = gp_flatX[gp_oB + gp_trimBwdB + gp_k];
                        gp_flatY[gp_oB + gp_k] = gp_flatY[gp_oB + gp_trimBwdB + gp_k];
                    }
                    gp_ringLen[gp_h]     = gp_trimLen;
                    gp_ringSeedIdx[gp_h] = gp_sB - gp_trimBwdB;
                    if (gp_ringSeedIdx[gp_h] < 0) gp_ringSeedIdx[gp_h] = 0;
                    gp_trimFwdB = gp_trimFwdB - gp_trimBwdB;
                    if (gp_trimFwdB < 1) gp_trimFwdB = 1;
                    gp_nB = gp_trimLen;
                    print("    Ring " + (gp_h+1) + ": trimmed backward end → " + gp_trimLen + " pts");
                }
                // Apply forward trim to ring B if needed
                if (gp_trimFwdB < gp_nB) {
                    if (gp_trimFwdB < 1) gp_trimFwdB = 1;
                    gp_ringLen[gp_h] = gp_trimFwdB;
                    gp_nB = gp_trimFwdB;
                    print("    Ring " + (gp_h+1) + ": trimmed forward end → " + gp_trimFwdB + " pts");
                }
                // Update bbox for ring B
                gp_bbMinX[gp_h] = gp_flatX[gp_oB]; gp_bbMaxX[gp_h] = gp_flatX[gp_oB];
                gp_bbMinY[gp_h] = gp_flatY[gp_oB]; gp_bbMaxY[gp_h] = gp_flatY[gp_oB];
                for (gp_k = 1; gp_k < gp_nB; gp_k++) {
                    gp_px = gp_flatX[gp_oB + gp_k]; gp_py = gp_flatY[gp_oB + gp_k];
                    if (gp_px < gp_bbMinX[gp_h]) gp_bbMinX[gp_h] = gp_px;
                    if (gp_px > gp_bbMaxX[gp_h]) gp_bbMaxX[gp_h] = gp_px;
                    if (gp_py < gp_bbMinY[gp_h]) gp_bbMinY[gp_h] = gp_py;
                    if (gp_py > gp_bbMaxY[gp_h]) gp_bbMaxY[gp_h] = gp_py;
                }

                print("  Ring " + (gp_g+1) + " & " + (gp_h+1) + ": trimmed"
                      + " (bwdA=" + gp_trimBwdA + " fwdA=" + gp_trimFwdA
                      + " bwdB=" + gp_trimBwdB + " fwdB=" + gp_trimFwdB + ")");
            }

            } // end bbox overlap check
            } // end sorted-order X range check
        }
    }

    // ================================================================
    // Write all (trimmed) rings to ROI Manager
    // ================================================================
    gp_nSkipped = 0;
    gp_skippedList = "";
    for (gp_g = 0; gp_g < gp_nG; gp_g++) {
        gp_oA = gp_ringOffset[gp_g];
        gp_nA = gp_ringLen[gp_g];
        // Skip degenerate traces with fewer than 2 vertices. These arise on
        // micro rings where both walks terminate immediately, collapsing the
        // trace to a single point. A single point can't be measured and would
        // create a spurious vertical edge plus an extra year in ResinDuctSummary.
        if (gp_nA < 2) {
            print("  WARNING: Ring " + (gp_g+1) + " collapsed to " + gp_nA +
                  " point — not written. Likely a micro ring too narrow to trace; " +
                  "draw its boundary manually if you need it measured.");
            gp_nSkipped++;
            if (gp_skippedList == "") gp_skippedList = "" + (gp_g+1);
            else                      gp_skippedList = gp_skippedList + ", " + (gp_g+1);
            continue;
        }
        gp_outX = newArray(gp_nA);
        gp_outY = newArray(gp_nA);
        for (gp_k = 0; gp_k < gp_nA; gp_k++) {
            gp_outX[gp_k] = gp_flatX[gp_oA + gp_k];
            gp_outY[gp_k] = gp_flatY[gp_oA + gp_k];
        }
        makeSelection("polyline", gp_outX, gp_outY);
        roiManager("Add");
        roiManager("select", roiManager("count") - 1);
        roiManager("Rename", "Ring_" + (gp_g+1) + "_GP");
    }
    if (gp_nSkipped > 0) {
        print("  " + gp_nSkipped + " degenerate ring trace(s) skipped.");
    }

    // ---- Remove seed point ROIs if overlay display not requested ----
    // Walk backwards through the recorded seed ROI indices so that deletions
    // don't shift the indices of remaining entries. Non-point ROIs are never
    // in gp_gRoiIdx so they are unaffected.
    if (!gp_showOverlays) {
        // Delete seed point ROIs (type 10 and type 6 multi-point).
        // Preserve: ring traces (_GP), and edge lines (matched by name).
        gp_n = roiManager("count");
        for (gp_i = gp_n - 1; gp_i >= 0; gp_i--) {
            roiManager("select", gp_i);
            gp_rType2 = selectionType();
            if (gp_rType2 == 10 || gp_rType2 == 6) {
                gp_rName = Roi.getName();
                if (indexOf(gp_rName, "_GP") >= 0) continue;
                if (gp_rName == gp_edgeName0 || gp_rName == gp_edgeName1) continue;
                roiManager("delete");
            }
        }
    }

    selectImage(gp_origID);
    roiManager("Show All");

    // ---- Auto-save RoiSet as sampleID_RoiSet.zip ----
    gp_imgPath = getDirectory("image");
    gp_imgTitle = getTitle();
    // Strip extension from title to get sampleID
    gp_sampleID = gp_imgTitle;
    if (endsWith(gp_sampleID, ".tif"))  gp_sampleID = substring(gp_sampleID, 0, lengthOf(gp_sampleID) - 4);
    if (endsWith(gp_sampleID, ".tiff")) gp_sampleID = substring(gp_sampleID, 0, lengthOf(gp_sampleID) - 5);
    gp_roiPath = gp_imgPath + gp_sampleID + "_RoiSet.zip";
    gp_doSave = 1;
    if (File.exists(gp_roiPath)) {
        gp_doSave = getBoolean(gp_sampleID + "_RoiSet.zip already exists.\nOverwrite it?");
    }
    if (gp_doSave) {
        roiManager("Deselect");
        roiManager("Save", gp_roiPath);
        print("ROI set saved: " + gp_roiPath);
    } else {
        print("ROI set save skipped (user chose not to overwrite).");
    }

    print("RingTracerCORE-1.0 done.");
    gp_nWritten = gp_nG - gp_nSkipped;
    gp_doneMsg = "Traced " + gp_nWritten + " rings.";
    if (gp_nSkipped > 0) {
        gp_doneMsg = gp_doneMsg + "\n \n⚠ " + gp_nSkipped + " ring(s) could not be traced and were skipped:\n" +
                     "Ring " + gp_skippedList + "\n \n" +
                     "These are likely micro rings too narrow to trace automatically. " +
                     "Draw their boundaries manually if you need them measured.";
    }
    gp_doneMsg = gp_doneMsg + "\n \nROI set saved to:\n" + gp_roiPath;
    showMessage("RingTracerCORE-1.0", gp_doneMsg);
}

// Interpolate Y on a polyline edge at a given X position.
// Returns the interpolated Y, or fallback if X is out of the edge's range.
// edgeX/edgeY are the polyline vertex arrays, edgeN is the vertex count.
function gpEdgeY(edgeX, edgeY, edgeN, queryX, fallback) {
    // Walk vertices to find bracketing segment
    for (gp_ei = 0; gp_ei < edgeN - 1; gp_ei++) {
        gp_ex1 = edgeX[gp_ei];   gp_ey1 = edgeY[gp_ei];
        gp_ex2 = edgeX[gp_ei+1]; gp_ey2 = edgeY[gp_ei+1];
        // Handle both left-to-right and right-to-left edge segments
        gp_eXlo = gp_ex1; gp_eXhi = gp_ex2;
        if (gp_ex2 < gp_ex1) { gp_eXlo = gp_ex2; gp_eXhi = gp_ex1; }
        if (queryX >= gp_eXlo && queryX <= gp_eXhi) {
            if (abs(gp_ex2 - gp_ex1) < 0.001) { return (gp_ey1 + gp_ey2) / 2; }
            gp_t = (queryX - gp_ex1) / (gp_ex2 - gp_ex1);
            return gp_ey1 + gp_t * (gp_ey2 - gp_ey1);
        }
    }
    return fallback;  // queryX outside edge range — caller uses margin fallback
}

function gpSort(gp_a, gp_b, gp_len) {
    for (gp_si = 1; gp_si < gp_len; gp_si++) {
        gp_ka = gp_a[gp_si]; gp_kb = gp_b[gp_si];
        gp_sj = gp_si - 1; gp_sc = 1;
        while (gp_sj >= 0 && gp_sc) {
            if (gp_a[gp_sj] > gp_ka) {
                gp_a[gp_sj+1] = gp_a[gp_sj];
                gp_b[gp_sj+1] = gp_b[gp_sj];
                gp_sj--;
            } else { gp_sc = 0; }
        }
        gp_a[gp_sj+1] = gp_ka; gp_b[gp_sj+1] = gp_kb;
    }
}

// gpSortNamed: insertion sort on gp_a, keeping gp_b and gp_c (name array) in sync.
function gpSortNamed(gp_a, gp_b, gp_c, gp_len) {
    for (gp_si = 1; gp_si < gp_len; gp_si++) {
        gp_ka = gp_a[gp_si]; gp_kb = gp_b[gp_si]; gp_kc = gp_c[gp_si];
        gp_sj = gp_si - 1; gp_sc = 1;
        while (gp_sj >= 0 && gp_sc) {
            if (gp_a[gp_sj] > gp_ka) {
                gp_a[gp_sj+1] = gp_a[gp_sj];
                gp_b[gp_sj+1] = gp_b[gp_sj];
                gp_c[gp_sj+1] = gp_c[gp_sj];
                gp_sj--;
            } else { gp_sc = 0; }
        }
        gp_a[gp_sj+1] = gp_ka; gp_b[gp_sj+1] = gp_kb; gp_c[gp_sj+1] = gp_kc;
    }
}

// MACRO 3: ResinDuctSummary-1.0
// ============================================================

macro "ResinDuctSummary-1.0 [d]" {

// ===== ResinDuctSummary-1.0 =====
// 
// VERSION HISTORY:
// v8.1.1 - Year input dialog now requires user to enter values (no defaults)
// v8.1   - Added robust ROI validation with detailed diagnostics for corrupted ROIs
// v8.0   - Base version with polygon method, damage area handling, cross-dating validation
//
// This macro performs a complete workflow for tree core analysis:
// 1. Removes duplicate ROIs
// 2. Sorts rings by distance from bark and assigns years
// 3. Connects consecutive ring boundaries to create closed ring polygons
// 4. Subtracts damage/missing areas from ring polygons
// 5. Measures ring lengths and ring areas (corrected for damage)
// 6. Assigns ducts to rings based on polygon containment
// 7. Exports combined data to CSV files
//
// IMPORTANT: You must trace ALL ring boundaries including the innermost year!
// Example: If outermost is 2019 and innermost is 1969, trace boundaries for
// 2019, 2018, 2017, ... 1970, AND 1969
//
// USER WORKFLOW:
// - Mark all ring boundaries as segmented lines (any name)
// - Mark all ducts as ellipses (any name)
// - Mark any damage/missing areas as polygon selections (any name)
// - Run this macro
// - Specify outer year
// - Click on bark location
// - Get organized ROIs and exported data

print("\\Clear");
print("=== ResinDuctSummary-1.0 ===");

print("");

// --- Check prerequisites ---
if (nImages == 0) {
    exit("No image is open. Please open an image first.");
}

imgID = getImageID();
imgTitle = getTitle();
// Remove file extension from title for output filename
dotIndex = lastIndexOf(imgTitle, ".");
if (dotIndex > 0) {
    baseTitle = substring(imgTitle, 0, dotIndex);
} else {
    baseTitle = imgTitle;
}

if (!isOpen("ROI Manager")) {
    exit("ROI Manager is not open. Please add ROIs to the ROI Manager first.");
}

n = roiManager("count");
if (n == 0) {
    exit("ROI Manager is empty. Please add ring and duct ROIs first.");
}

print("Starting with " + n + " ROIs");
print("");

// Get calibration
getPixelSize(unit, pixelWidth, pixelHeight);
if (unit != "mm") {
    Dialog.create("Calibration Check");
    Dialog.addMessage("Current calibration unit: " + unit);
    Dialog.addMessage("Expected unit: mm");
    Dialog.addCheckbox("Continue anyway?", false);
    Dialog.show();
    if (!Dialog.getCheckbox()) {
        exit("Macro cancelled. Please set spatial calibration to mm.");
    }
}

// ===== STEP 1: CHECK FOR PROBLEMATIC ROIs =====
print("STEP 1: Checking for problematic ROIs...");
print("  Total ROIs in manager: " + n);
print("");

// Try a different approach - check each ROI and stop at first problem
for (i = 0; i < n; i++) {
    // Report progress every 50 ROIs
    if (i % 50 == 0 && i > 0) {
        print("  Checked " + i + " ROIs successfully...");
    }
    
    // Clear any previous selection
    roiManager("deselect");
    run("Select None");
    
    // Try to select the ROI
    roiManager("select", i);
    
    // Check if selection actually worked
    roiType = selectionType();
    
    if (roiType == -1) {
        // We have a corrupted ROI - stop here and report
        print("ERROR: Found corrupted ROI at index " + i);
        print("");
        print("Diagnostic information:");
        print("  ROI index: " + i);
        print("  Selection type: " + roiType + " (no selection)");
        print("  Total ROIs in manager: " + roiManager("count"));
        print("");
        
        // Try to look at surrounding ROIs for context
        print("Context - nearby ROIs:");
        startIdx = i - 3;
        if (startIdx < 0) startIdx = 0;
        endIdx = i + 3;
        if (endIdx > n - 1) endIdx = n - 1;
        
        for (j = startIdx; j <= endIdx; j++) {
            roiManager("deselect");
            run("Select None");
            roiManager("select", j);
            checkType = selectionType();
            checkName = "unknown";
            if (checkType != -1) {
                checkName = Roi.getName();
            }
            if (j == i) {
                marker = " <<< PROBLEM";
            } else {
                marker = "";
            }
            print("  ROI #" + j + ": type=" + checkType + ", name=" + checkName + marker);
        }
        print("");
        
        // Select the problematic ROI
        roiManager("select", i);
        
        exit("Corrupted ROI found at index " + i + ".\n \n" +
             "This ROI cannot be selected properly.\n" +
             "Please examine ROI #" + i + " in the ROI Manager.\n \n" +
             "Possible solutions:\n" +
             "1. Delete this ROI if it's not needed\n" +
             "2. Check if the ROI file is corrupted\n" +
             "3. Try re-saving the ROI set\n \n" +
             "See Log window for detailed diagnostics.");
    }
    
    // Also check for point ROIs
    if (roiType == 10) {
        roiName = Roi.getName();
        print("Found Point ROI at index " + i + ": " + roiName);
        roiManager("select", i);
        
        exit("Point ROI found at index " + i + ": " + roiName + "\n \n" +
             "Point ROIs cannot be used for ring/duct analysis.\n" +
             "This ROI is now selected in the ROI Manager.\n \n" +
             "Please delete it and run the macro again.");
    }
}

print("  All " + n + " ROIs checked successfully");
print("");

// ===== STEP 2: REMOVE GEOMETRIC DUPLICATES =====
print("STEP 2: Removing duplicate ROIs...");

toDelete = newArray(0);

for (i = 0; i < n; i++) {
    roiManager("select", i);
    Roi.getCoordinates(xpoints1, ypoints1);
    
    // Compare with all subsequent ROIs
    for (j = i + 1; j < n; j++) {
        roiManager("select", j);
        Roi.getCoordinates(xpoints2, ypoints2);
        
        // Check if ROIs are identical
        if (xpoints1.length == xpoints2.length) {
            identical = true;
            for (k = 0; k < xpoints1.length; k++) {
                if (xpoints1[k] != xpoints2[k] || ypoints1[k] != ypoints2[k]) {
                    identical = false;
                    break;
                }
            }
            
            if (identical) {
                toDelete = Array.concat(toDelete, j);
            }
        }
    }
}

// Delete duplicates
if (toDelete.length > 0) {
    Array.sort(toDelete);
    uniqueDelete = newArray(0);
    for (i = 0; i < toDelete.length; i++) {
        alreadyAdded = false;
        for (j = 0; j < uniqueDelete.length; j++) {
            if (toDelete[i] == uniqueDelete[j]) {
                alreadyAdded = true;
                break;
            }
        }
        if (!alreadyAdded) {
            uniqueDelete = Array.concat(uniqueDelete, toDelete[i]);
        }
    }
    
    for (i = uniqueDelete.length - 1; i >= 0; i--) {
        roiManager("select", uniqueDelete[i]);
        roiManager("delete");
    }
    
    print("  Deleted " + uniqueDelete.length + " duplicate ROIs");
} else {
    print("  No duplicate ROIs found");
}

roiManager("deselect");
run("Select None");
print("");

// ===== STEP 3: GET OUTER AND INNER YEARS FROM USER =====
print("STEP 3: Getting outer and inner years from user...");

// Loop until valid years are entered
validYears = false;
while (!validYears) {
    Dialog.create("Enter cross-dated outer & inner years");
    Dialog.addNumber("Outer year (bark side):", NaN);
    Dialog.addNumber("Inner year (pith side):", NaN);
    Dialog.show();
    outerYear = Dialog.getNumber();
    innerYear = Dialog.getNumber();
    
    // Check if values were actually entered
    if (isNaN(outerYear) || isNaN(innerYear)) {
        showMessage("Missing Year Values", 
            "Please enter both outer and inner years.\n \n" +
            "Both fields are required.");
        continue;
    }
    
    // Validate that inner year is less than outer year
    if (innerYear >= outerYear) {
        showMessage("Invalid Year Range", 
            "Inner year (" + innerYear + ") must be less than outer year (" + outerYear + ").\n \n" +
            "Please enter valid years.");
        continue;
    }
    
    // If we got here, years are valid
    validYears = true;
}

print("  Outer year set to: " + outerYear);
print("  Inner year set to: " + innerYear);
print("");

// ===== STEP 4: GET BARK LOCATION AND SORT RINGS =====
print("STEP 4: Sorting rings by distance from bark...");

n = roiManager("count");
print("  Working with " + n + " unique ROIs");

// Ask user to click on bark
setTool("point");
waitForUser("Click on the BARK (outer edge/latest rings), then click OK");

// Get bark coordinates
if (selectionType() == 10) {
    getSelectionCoordinates(barkX, barkY);
    barkX = barkX[0];
    barkY = barkY[0];
    
    print("  Bark location: (" + barkX + ", " + barkY + ")");
    
    // Delete any AREA_ polygons from previous runs
    areaROIs = newArray(0);
    for (i = 0; i < n; i++) {
        roiManager("select", i);
        roiName = Roi.getName();
        if (startsWith(roiName, "AREA_")) {
            areaROIs = Array.concat(areaROIs, i);
        }
    }
    
    if (areaROIs.length > 0) {
        // Delete in reverse order to maintain correct indices
        for (i = areaROIs.length - 1; i >= 0; i--) {
            roiManager("select", areaROIs[i]);
            roiManager("delete");
        }
        print("  Deleted " + areaROIs.length + " AREA_ polygon(s) from previous run");
        
        // Update ROI count after deletion
        n = roiManager("count");
    }
    
    // Detect Core_boundary lines and separate all ROI types
    ringIndices = newArray(0);
    ductIndices = newArray(0);
    damageIndices = newArray(0);
    ds_topBoundX = newArray(0); ds_topBoundY = newArray(0);
    ds_botBoundX = newArray(0); ds_botBoundY = newArray(0);
    ds_hasBounds = 0;

    for (i = 0; i < n; i++) {
        roiManager("select", i);
        roiType = Roi.getType();
        roiName = Roi.getName();

        if (roiName == "Core_boundary_top") {
            Roi.getCoordinates(ds_topBoundX, ds_topBoundY);
            ds_hasBounds = 1;
        } else if (roiName == "Core_boundary_bottom") {
            Roi.getCoordinates(ds_botBoundX, ds_botBoundY);
            ds_hasBounds = 1;
        } else if (roiType == "polyline" || roiType == "freeline") {
            // Ring boundaries (excluding Core_boundary lines above).
            // Skip degenerate traces with fewer than 2 points — these arise
            // from micro rings where the tracer produced only a single point,
            // and they would create a spurious vertical edge plus an extra year.
            Roi.getCoordinates(ds_chkX, ds_chkY);
            if (ds_chkX.length >= 2) {
                ringIndices = Array.concat(ringIndices, i);
            } else {
                print("  WARNING: skipping degenerate ring trace \"" + roiName +
                      "\" (" + ds_chkX.length + " point) — likely a micro ring. " +
                      "Re-trace it with more points to include it.");
            }
        } else if (roiType == "freehand") {
            // Ducts (elliptical selections)
            ductIndices = Array.concat(ductIndices, i);
        } else if (roiType == "polygon" || roiType == "traced") {
            // Damage areas (user-drawn polygons)
            damageIndices = Array.concat(damageIndices, i);
        }
    }

    // Validate: need both boundaries or neither
    if (ds_topBoundX.length > 0 && ds_botBoundX.length == 0) {
        print("  WARNING: Core_boundary_top found but not Core_boundary_bottom — using endpoint connections.");
        ds_hasBounds = 0;
    }
    if (ds_botBoundX.length > 0 && ds_topBoundX.length == 0) {
        print("  WARNING: Core_boundary_bottom found but not Core_boundary_top — using endpoint connections.");
        ds_hasBounds = 0;
    }
    if (ds_hasBounds) {
        // Sort both boundary lines by X so interpolation always walks left→right.
        // Users may draw lines in either direction; sorting makes it direction-agnostic.
        // Sort both boundary lines by X using Array.sort(key, values) which
        // reorders 'values' to match the sorted 'key' — done in-place, no
        // function call needed (avoids ImageJ array-return-from-function issues).
        Array.sort(ds_topBoundX, ds_topBoundY);
        Array.sort(ds_botBoundX, ds_botBoundY);
        print("  Core boundary lines detected — polygons will follow core edges.");
    } else {
        print("  No core boundary lines — using endpoint connections.");
    }

    nRings = ringIndices.length;
    nDucts = ductIndices.length;
    nDamage = damageIndices.length;

    print("  Found " + nRings + " rings, " + nDucts + " ducts, and " + nDamage + " damage areas");
    
    if (nRings == 0) {
        exit("No ring ROIs found.");
    }
    
    if (nRings < 2) {
        exit("Need at least 2 ring boundaries to create ring area polygons.");
    }
    
    // Calculate distance from bark for rings only
    ringDistances = newArray(nRings);
    
    for (i = 0; i < nRings; i++) {
        roiManager("select", ringIndices[i]);
        Roi.getBounds(x, y, width, height);
        centerX = x + width / 2;
        centerY = y + height / 2;
        ringDistances[i] = sqrt((centerX - barkX) * (centerX - barkX) + (centerY - barkY) * (centerY - barkY));
    }
    
    // Sort ring indices by distance
    sortedRingIndices = Array.copy(ringIndices);
    Array.sort(ringDistances, sortedRingIndices);
    
    print("  Sorted " + nRings + " rings by distance from bark");
    print("");
    
    // ===== STEP 5: CREATE RING AREA POLYGONS =====
    print("STEP 5: Creating ring area polygons and measuring...");
    
    ringNames = newArray(nRings - 1); // n-1 polygons from n boundaries
    ringLengths = newArray(nRings - 1);
    ringAreas = newArray(nRings - 1);
    
    run("Set Measurements...", "area redirect=None decimal=3");
    
    // Store polygon selections for later containment testing
    ringPolygons = newArray(nRings - 1);
    
    // Create polygons: connect each pair of consecutive ring boundaries
    for (r = 0; r < nRings - 1; r++) {
        year = outerYear - r;
        ringNames[r] = "" + year;
        
        // Get coordinates of outer ring boundary (closer to bark)
        roiManager("select", sortedRingIndices[r]);
        Roi.getCoordinates(x1, y1);
        
        // Measure length of outer boundary
        run("Measure");
        ringLengths[r] = getResult("Length", nResults - 1);
        run("Clear Results");
        
        // Get coordinates of inner ring boundary (farther from bark)
        roiManager("select", sortedRingIndices[r + 1]);
        Roi.getCoordinates(x2, y2);
        
        if (ds_hasBounds) {
        // ---- Build closed polygon from intersection points ----
        // Strategy: find where each ring trace crosses Core_boundary_top and
        // Core_boundary_bottom. Clip each ring to that span. Connect clipped
        // rings via boundary segments. Fall back to direct endpoint connection
        // only when a boundary intersection is missing (e.g. pith rings).
        //
        // Polygon winding: outer ring (top-intersect → bot-intersect) +
        //   bot boundary segment (outer-bot → inner-bot) +
        //   inner ring reversed (inner-bot → inner-top) +
        //   top boundary segment (inner-top → outer-top)

        // Ensure both rings are oriented start=top end=bottom
        // (start Y < end Y, since Y increases downward in ImageJ)
        if (y1[0] > y1[x1.length-1]) { Array.reverse(x1); Array.reverse(y1); }
        if (y2[0] > y2[x2.length-1]) { Array.reverse(x2); Array.reverse(y2); }

        // ---- Find intersection indices for each ring with each boundary ----
        // Returns index i such that ring crosses boundary between i and i+1.
        // -1 = no intersection found.
        // We search from each end inward so we get the outermost intersection.

        // Ring 1 vs top boundary (search from start=top end of ring)
        ds_r1TopIdx = -1;
        for (ds_ii = 0; ds_ii < x1.length-1; ds_ii++) {
            ds_bry0 = 0; for (ds_jj=0; ds_jj<ds_topBoundX.length-1; ds_jj++) { if (x1[ds_ii]>=ds_topBoundX[ds_jj] && x1[ds_ii]<=ds_topBoundX[ds_jj+1]) { ds_t=(x1[ds_ii]-ds_topBoundX[ds_jj])/(ds_topBoundX[ds_jj+1]-ds_topBoundX[ds_jj]); ds_bry0=ds_topBoundY[ds_jj]+ds_t*(ds_topBoundY[ds_jj+1]-ds_topBoundY[ds_jj]); ds_jj=ds_topBoundX.length; } }
            ds_bry1 = 0; for (ds_jj=0; ds_jj<ds_topBoundX.length-1; ds_jj++) { if (x1[ds_ii+1]>=ds_topBoundX[ds_jj] && x1[ds_ii+1]<=ds_topBoundX[ds_jj+1]) { ds_t=(x1[ds_ii+1]-ds_topBoundX[ds_jj])/(ds_topBoundX[ds_jj+1]-ds_topBoundX[ds_jj]); ds_bry1=ds_topBoundY[ds_jj]+ds_t*(ds_topBoundY[ds_jj+1]-ds_topBoundY[ds_jj]); ds_jj=ds_topBoundX.length; } }
            if ((y1[ds_ii]-ds_bry0)*(y1[ds_ii+1]-ds_bry1) <= 0) { ds_r1TopIdx = ds_ii; ds_ii = x1.length; }
        }
        // Ring 1 vs bot boundary (search from end=bottom end of ring)
        ds_r1BotIdx = -1;
        for (ds_ii = x1.length-2; ds_ii >= 0; ds_ii--) {
            ds_bry0 = 0; for (ds_jj=0; ds_jj<ds_botBoundX.length-1; ds_jj++) { if (x1[ds_ii]>=ds_botBoundX[ds_jj] && x1[ds_ii]<=ds_botBoundX[ds_jj+1]) { ds_t=(x1[ds_ii]-ds_botBoundX[ds_jj])/(ds_botBoundX[ds_jj+1]-ds_botBoundX[ds_jj]); ds_bry0=ds_botBoundY[ds_jj]+ds_t*(ds_botBoundY[ds_jj+1]-ds_botBoundY[ds_jj]); ds_jj=ds_botBoundX.length; } }
            ds_bry1 = 0; for (ds_jj=0; ds_jj<ds_botBoundX.length-1; ds_jj++) { if (x1[ds_ii+1]>=ds_botBoundX[ds_jj] && x1[ds_ii+1]<=ds_botBoundX[ds_jj+1]) { ds_t=(x1[ds_ii+1]-ds_botBoundX[ds_jj])/(ds_botBoundX[ds_jj+1]-ds_botBoundX[ds_jj]); ds_bry1=ds_botBoundY[ds_jj]+ds_t*(ds_botBoundY[ds_jj+1]-ds_botBoundY[ds_jj]); ds_jj=ds_botBoundX.length; } }
            if ((y1[ds_ii]-ds_bry0)*(y1[ds_ii+1]-ds_bry1) <= 0) { ds_r1BotIdx = ds_ii; ds_ii = -1; }
        }
        // Ring 2 vs top boundary
        ds_r2TopIdx = -1;
        for (ds_ii = 0; ds_ii < x2.length-1; ds_ii++) {
            ds_bry0 = 0; for (ds_jj=0; ds_jj<ds_topBoundX.length-1; ds_jj++) { if (x2[ds_ii]>=ds_topBoundX[ds_jj] && x2[ds_ii]<=ds_topBoundX[ds_jj+1]) { ds_t=(x2[ds_ii]-ds_topBoundX[ds_jj])/(ds_topBoundX[ds_jj+1]-ds_topBoundX[ds_jj]); ds_bry0=ds_topBoundY[ds_jj]+ds_t*(ds_topBoundY[ds_jj+1]-ds_topBoundY[ds_jj]); ds_jj=ds_topBoundX.length; } }
            ds_bry1 = 0; for (ds_jj=0; ds_jj<ds_topBoundX.length-1; ds_jj++) { if (x2[ds_ii+1]>=ds_topBoundX[ds_jj] && x2[ds_ii+1]<=ds_topBoundX[ds_jj+1]) { ds_t=(x2[ds_ii+1]-ds_topBoundX[ds_jj])/(ds_topBoundX[ds_jj+1]-ds_topBoundX[ds_jj]); ds_bry1=ds_topBoundY[ds_jj]+ds_t*(ds_topBoundY[ds_jj+1]-ds_topBoundY[ds_jj]); ds_jj=ds_topBoundX.length; } }
            if ((y2[ds_ii]-ds_bry0)*(y2[ds_ii+1]-ds_bry1) <= 0) { ds_r2TopIdx = ds_ii; ds_ii = x2.length; }
        }
        // Ring 2 vs bot boundary
        ds_r2BotIdx = -1;
        for (ds_ii = x2.length-2; ds_ii >= 0; ds_ii--) {
            ds_bry0 = 0; for (ds_jj=0; ds_jj<ds_botBoundX.length-1; ds_jj++) { if (x2[ds_ii]>=ds_botBoundX[ds_jj] && x2[ds_ii]<=ds_botBoundX[ds_jj+1]) { ds_t=(x2[ds_ii]-ds_botBoundX[ds_jj])/(ds_botBoundX[ds_jj+1]-ds_botBoundX[ds_jj]); ds_bry0=ds_botBoundY[ds_jj]+ds_t*(ds_botBoundY[ds_jj+1]-ds_botBoundY[ds_jj]); ds_jj=ds_botBoundX.length; } }
            ds_bry1 = 0; for (ds_jj=0; ds_jj<ds_botBoundX.length-1; ds_jj++) { if (x2[ds_ii+1]>=ds_botBoundX[ds_jj] && x2[ds_ii+1]<=ds_botBoundX[ds_jj+1]) { ds_t=(x2[ds_ii+1]-ds_botBoundX[ds_jj])/(ds_botBoundX[ds_jj+1]-ds_botBoundX[ds_jj]); ds_bry1=ds_botBoundY[ds_jj]+ds_t*(ds_botBoundY[ds_jj+1]-ds_botBoundY[ds_jj]); ds_jj=ds_botBoundX.length; } }
            if ((y2[ds_ii]-ds_bry0)*(y2[ds_ii+1]-ds_bry1) <= 0) { ds_r2BotIdx = ds_ii; ds_ii = -1; }
        }

        // ---- Compute intersection coordinates (interpolated) ----
        // For each found intersection, interpolate the exact X,Y on the ring
        // at the crossing point with the boundary line.
        // If not found, use the ring endpoint.

        // Ring 1 top intersection point
        if (ds_r1TopIdx >= 0) {
            ds_ii = ds_r1TopIdx;
            ds_bry0=0; for (ds_jj=0;ds_jj<ds_topBoundX.length-1;ds_jj++){if(x1[ds_ii]>=ds_topBoundX[ds_jj]&&x1[ds_ii]<=ds_topBoundX[ds_jj+1]){ds_t=(x1[ds_ii]-ds_topBoundX[ds_jj])/(ds_topBoundX[ds_jj+1]-ds_topBoundX[ds_jj]);ds_bry0=ds_topBoundY[ds_jj]+ds_t*(ds_topBoundY[ds_jj+1]-ds_topBoundY[ds_jj]);ds_jj=ds_topBoundX.length;}}
            ds_bry1=0; for (ds_jj=0;ds_jj<ds_topBoundX.length-1;ds_jj++){if(x1[ds_ii+1]>=ds_topBoundX[ds_jj]&&x1[ds_ii+1]<=ds_topBoundX[ds_jj+1]){ds_t=(x1[ds_ii+1]-ds_topBoundX[ds_jj])/(ds_topBoundX[ds_jj+1]-ds_topBoundX[ds_jj]);ds_bry1=ds_topBoundY[ds_jj]+ds_t*(ds_topBoundY[ds_jj+1]-ds_topBoundY[ds_jj]);ds_jj=ds_topBoundX.length;}}
            ds_denom=(y1[ds_ii+1]-y1[ds_ii])-(ds_bry1-ds_bry0); if(abs(ds_denom)<0.001){ds_t2=0;}else{ds_t2=(ds_bry0-y1[ds_ii])/ds_denom;}
            ds_r1TopX=x1[ds_ii]+ds_t2*(x1[ds_ii+1]-x1[ds_ii]); ds_r1TopY=y1[ds_ii]+ds_t2*(y1[ds_ii+1]-y1[ds_ii]);
            ds_r1TopClip=ds_ii+1;  // first ring point to INCLUDE (after intersection)
        } else { ds_r1TopX=x1[0]; ds_r1TopY=y1[0]; ds_r1TopClip=0; }

        // Ring 1 bot intersection point
        if (ds_r1BotIdx >= 0) {
            ds_ii = ds_r1BotIdx;
            ds_bry0=0; for (ds_jj=0;ds_jj<ds_botBoundX.length-1;ds_jj++){if(x1[ds_ii]>=ds_botBoundX[ds_jj]&&x1[ds_ii]<=ds_botBoundX[ds_jj+1]){ds_t=(x1[ds_ii]-ds_botBoundX[ds_jj])/(ds_botBoundX[ds_jj+1]-ds_botBoundX[ds_jj]);ds_bry0=ds_botBoundY[ds_jj]+ds_t*(ds_botBoundY[ds_jj+1]-ds_botBoundY[ds_jj]);ds_jj=ds_botBoundX.length;}}
            ds_bry1=0; for (ds_jj=0;ds_jj<ds_botBoundX.length-1;ds_jj++){if(x1[ds_ii+1]>=ds_botBoundX[ds_jj]&&x1[ds_ii+1]<=ds_botBoundX[ds_jj+1]){ds_t=(x1[ds_ii+1]-ds_botBoundX[ds_jj])/(ds_botBoundX[ds_jj+1]-ds_botBoundX[ds_jj]);ds_bry1=ds_botBoundY[ds_jj]+ds_t*(ds_botBoundY[ds_jj+1]-ds_botBoundY[ds_jj]);ds_jj=ds_botBoundX.length;}}
            ds_denom=(y1[ds_ii+1]-y1[ds_ii])-(ds_bry1-ds_bry0); if(abs(ds_denom)<0.001){ds_t2=0;}else{ds_t2=(ds_bry0-y1[ds_ii])/ds_denom;}
            ds_r1BotX=x1[ds_ii]+ds_t2*(x1[ds_ii+1]-x1[ds_ii]); ds_r1BotY=y1[ds_ii]+ds_t2*(y1[ds_ii+1]-y1[ds_ii]);
            ds_r1BotClip=ds_ii;  // last ring point to INCLUDE (before intersection)
        } else { ds_r1BotX=x1[x1.length-1]; ds_r1BotY=y1[x1.length-1]; ds_r1BotClip=x1.length-1; }

        // Ring 2 top intersection point
        if (ds_r2TopIdx >= 0) {
            ds_ii = ds_r2TopIdx;
            ds_bry0=0; for (ds_jj=0;ds_jj<ds_topBoundX.length-1;ds_jj++){if(x2[ds_ii]>=ds_topBoundX[ds_jj]&&x2[ds_ii]<=ds_topBoundX[ds_jj+1]){ds_t=(x2[ds_ii]-ds_topBoundX[ds_jj])/(ds_topBoundX[ds_jj+1]-ds_topBoundX[ds_jj]);ds_bry0=ds_topBoundY[ds_jj]+ds_t*(ds_topBoundY[ds_jj+1]-ds_topBoundY[ds_jj]);ds_jj=ds_topBoundX.length;}}
            ds_bry1=0; for (ds_jj=0;ds_jj<ds_topBoundX.length-1;ds_jj++){if(x2[ds_ii+1]>=ds_topBoundX[ds_jj]&&x2[ds_ii+1]<=ds_topBoundX[ds_jj+1]){ds_t=(x2[ds_ii+1]-ds_topBoundX[ds_jj])/(ds_topBoundX[ds_jj+1]-ds_topBoundX[ds_jj]);ds_bry1=ds_topBoundY[ds_jj]+ds_t*(ds_topBoundY[ds_jj+1]-ds_topBoundY[ds_jj]);ds_jj=ds_topBoundX.length;}}
            ds_denom=(y2[ds_ii+1]-y2[ds_ii])-(ds_bry1-ds_bry0); if(abs(ds_denom)<0.001){ds_t2=0;}else{ds_t2=(ds_bry0-y2[ds_ii])/ds_denom;}
            ds_r2TopX=x2[ds_ii]+ds_t2*(x2[ds_ii+1]-x2[ds_ii]); ds_r2TopY=y2[ds_ii]+ds_t2*(y2[ds_ii+1]-y2[ds_ii]);
            ds_r2TopClip=ds_ii+1;
        } else { ds_r2TopX=x2[0]; ds_r2TopY=y2[0]; ds_r2TopClip=0; }

        // Ring 2 bot intersection point
        if (ds_r2BotIdx >= 0) {
            ds_ii = ds_r2BotIdx;
            ds_bry0=0; for (ds_jj=0;ds_jj<ds_botBoundX.length-1;ds_jj++){if(x2[ds_ii]>=ds_botBoundX[ds_jj]&&x2[ds_ii]<=ds_botBoundX[ds_jj+1]){ds_t=(x2[ds_ii]-ds_botBoundX[ds_jj])/(ds_botBoundX[ds_jj+1]-ds_botBoundX[ds_jj]);ds_bry0=ds_botBoundY[ds_jj]+ds_t*(ds_botBoundY[ds_jj+1]-ds_botBoundY[ds_jj]);ds_jj=ds_botBoundX.length;}}
            ds_bry1=0; for (ds_jj=0;ds_jj<ds_botBoundX.length-1;ds_jj++){if(x2[ds_ii+1]>=ds_botBoundX[ds_jj]&&x2[ds_ii+1]<=ds_botBoundX[ds_jj+1]){ds_t=(x2[ds_ii+1]-ds_botBoundX[ds_jj])/(ds_botBoundX[ds_jj+1]-ds_botBoundX[ds_jj]);ds_bry1=ds_botBoundY[ds_jj]+ds_t*(ds_botBoundY[ds_jj+1]-ds_botBoundY[ds_jj]);ds_jj=ds_botBoundX.length;}}
            ds_denom=(y2[ds_ii+1]-y2[ds_ii])-(ds_bry1-ds_bry0); if(abs(ds_denom)<0.001){ds_t2=0;}else{ds_t2=(ds_bry0-y2[ds_ii])/ds_denom;}
            ds_r2BotX=x2[ds_ii]+ds_t2*(x2[ds_ii+1]-x2[ds_ii]); ds_r2BotY=y2[ds_ii]+ds_t2*(y2[ds_ii+1]-y2[ds_ii]);
            ds_r2BotClip=ds_ii;
        } else { ds_r2BotX=x2[x2.length-1]; ds_r2BotY=y2[x2.length-1]; ds_r2BotClip=x2.length-1; }

        // ---- Extract boundary segments between intersection points ----
        // Bot segment: from r1BotX to r2BotX along Core_boundary_bottom (or direct if neither found)
        // Top segment: from r2TopX to r1TopX along Core_boundary_top (or direct if neither found)

        ds_botSegX = newArray(ds_botBoundX.length+2); ds_botSegY = newArray(ds_botBoundX.length+2); ds_botSegN = 0;
        if (ds_r1BotIdx >= 0 || ds_r2BotIdx >= 0) {
            ds_bxA=ds_r1BotX; ds_bxB=ds_r2BotX;
            ds_xLo=ds_bxA; ds_xHi=ds_bxB; if(ds_bxA>ds_bxB){ds_xLo=ds_bxB;ds_xHi=ds_bxA;}
            ds_iy=ds_r1BotY; for(ds_jj=0;ds_jj<ds_botBoundX.length-1;ds_jj++){if(ds_bxA>=ds_botBoundX[ds_jj]&&ds_bxA<=ds_botBoundX[ds_jj+1]){ds_t=(ds_bxA-ds_botBoundX[ds_jj])/(ds_botBoundX[ds_jj+1]-ds_botBoundX[ds_jj]);ds_iy=ds_botBoundY[ds_jj]+ds_t*(ds_botBoundY[ds_jj+1]-ds_botBoundY[ds_jj]);ds_jj=ds_botBoundX.length;}}
            ds_botSegX[0]=ds_bxA; ds_botSegY[0]=ds_iy; ds_botSegN=1;
            // Collect interior vertices in direction matching segment (bxA→bxB)
            if (ds_bxA <= ds_bxB) {
                for(ds_jj=0;ds_jj<ds_botBoundX.length;ds_jj++){if(ds_botBoundX[ds_jj]>ds_xLo&&ds_botBoundX[ds_jj]<ds_xHi){ds_botSegX[ds_botSegN]=ds_botBoundX[ds_jj];ds_botSegY[ds_botSegN]=ds_botBoundY[ds_jj];ds_botSegN++;}}
            } else {
                for(ds_jj=ds_botBoundX.length-1;ds_jj>=0;ds_jj--){if(ds_botBoundX[ds_jj]>ds_xLo&&ds_botBoundX[ds_jj]<ds_xHi){ds_botSegX[ds_botSegN]=ds_botBoundX[ds_jj];ds_botSegY[ds_botSegN]=ds_botBoundY[ds_jj];ds_botSegN++;}}
            }
            ds_iy=ds_r2BotY; for(ds_jj=0;ds_jj<ds_botBoundX.length-1;ds_jj++){if(ds_bxB>=ds_botBoundX[ds_jj]&&ds_bxB<=ds_botBoundX[ds_jj+1]){ds_t=(ds_bxB-ds_botBoundX[ds_jj])/(ds_botBoundX[ds_jj+1]-ds_botBoundX[ds_jj]);ds_iy=ds_botBoundY[ds_jj]+ds_t*(ds_botBoundY[ds_jj+1]-ds_botBoundY[ds_jj]);ds_jj=ds_botBoundX.length;}}
            ds_botSegX[ds_botSegN]=ds_bxB; ds_botSegY[ds_botSegN]=ds_iy; ds_botSegN++;

        } else {
            // Neither ring intersects bottom boundary — direct connection
            ds_botSegX[0]=ds_r1BotX; ds_botSegY[0]=ds_r1BotY;
            ds_botSegX[1]=ds_r2BotX; ds_botSegY[1]=ds_r2BotY; ds_botSegN=2;
        }

        ds_topSegX = newArray(ds_topBoundX.length+2); ds_topSegY = newArray(ds_topBoundX.length+2); ds_topSegN = 0;
        if (ds_r1TopIdx >= 0 || ds_r2TopIdx >= 0) {
            ds_bxA=ds_r2TopX; ds_bxB=ds_r1TopX;
            ds_xLo=ds_bxA; ds_xHi=ds_bxB; if(ds_bxA>ds_bxB){ds_xLo=ds_bxB;ds_xHi=ds_bxA;}
            ds_iy=ds_r2TopY; for(ds_jj=0;ds_jj<ds_topBoundX.length-1;ds_jj++){if(ds_bxA>=ds_topBoundX[ds_jj]&&ds_bxA<=ds_topBoundX[ds_jj+1]){ds_t=(ds_bxA-ds_topBoundX[ds_jj])/(ds_topBoundX[ds_jj+1]-ds_topBoundX[ds_jj]);ds_iy=ds_topBoundY[ds_jj]+ds_t*(ds_topBoundY[ds_jj+1]-ds_topBoundY[ds_jj]);ds_jj=ds_topBoundX.length;}}
            ds_topSegX[0]=ds_bxA; ds_topSegY[0]=ds_iy; ds_topSegN=1;
            // Collect interior vertices in direction matching segment (bxA→bxB)
            if (ds_bxA <= ds_bxB) {
                for(ds_jj=0;ds_jj<ds_topBoundX.length;ds_jj++){if(ds_topBoundX[ds_jj]>ds_xLo&&ds_topBoundX[ds_jj]<ds_xHi){ds_topSegX[ds_topSegN]=ds_topBoundX[ds_jj];ds_topSegY[ds_topSegN]=ds_topBoundY[ds_jj];ds_topSegN++;}}
            } else {
                for(ds_jj=ds_topBoundX.length-1;ds_jj>=0;ds_jj--){if(ds_topBoundX[ds_jj]>ds_xLo&&ds_topBoundX[ds_jj]<ds_xHi){ds_topSegX[ds_topSegN]=ds_topBoundX[ds_jj];ds_topSegY[ds_topSegN]=ds_topBoundY[ds_jj];ds_topSegN++;}}
            }
            ds_iy=ds_r1TopY; for(ds_jj=0;ds_jj<ds_topBoundX.length-1;ds_jj++){if(ds_bxB>=ds_topBoundX[ds_jj]&&ds_bxB<=ds_topBoundX[ds_jj+1]){ds_t=(ds_bxB-ds_topBoundX[ds_jj])/(ds_topBoundX[ds_jj+1]-ds_topBoundX[ds_jj]);ds_iy=ds_topBoundY[ds_jj]+ds_t*(ds_topBoundY[ds_jj+1]-ds_topBoundY[ds_jj]);ds_jj=ds_topBoundX.length;}}
            ds_topSegX[ds_topSegN]=ds_bxB; ds_topSegY[ds_topSegN]=ds_iy; ds_topSegN++;

        } else {
            ds_topSegX[0]=ds_r2TopX; ds_topSegY[0]=ds_r2TopY;
            ds_topSegX[1]=ds_r1TopX; ds_topSegY[1]=ds_r1TopY; ds_topSegN=2;
        }

        // ---- Assemble polygon ----
        // Each boundary segment already includes the intersection points as its
        // first and last elements, so we do NOT add intersection points separately.
        // Winding order:
        //   ring1 clipped (top→bot) + bot boundary seg (r1bot→r2bot) +
        //   ring2 clipped reversed (bot→top) + top boundary seg (r2top→r1top)
        ds_r1Len = ds_r1BotClip - ds_r1TopClip + 1; if(ds_r1Len<0)ds_r1Len=0;
        ds_r2Len = ds_r2BotClip - ds_r2TopClip + 1; if(ds_r2Len<0)ds_r2Len=0;
        ds_totalN = ds_r1Len + ds_botSegN + ds_r2Len + ds_topSegN;
        polyX = newArray(ds_totalN); polyY = newArray(ds_totalN);
        ds_idx = 0;
        // 1. Clipped ring 1 interior points (top clip → bot clip)
        for(ds_ii=ds_r1TopClip; ds_ii<=ds_r1BotClip; ds_ii++){polyX[ds_idx]=x1[ds_ii];polyY[ds_idx]=y1[ds_ii];ds_idx++;}
        // 2. Bottom boundary segment (r1bot → r2bot), endpoints included in segment
        for(ds_ii=0;ds_ii<ds_botSegN;ds_ii++){polyX[ds_idx]=ds_botSegX[ds_ii];polyY[ds_idx]=ds_botSegY[ds_ii];ds_idx++;}
        // 3. Clipped ring 2 interior points reversed (bot clip → top clip)
        for(ds_ii=ds_r2BotClip; ds_ii>=ds_r2TopClip; ds_ii--){polyX[ds_idx]=x2[ds_ii];polyY[ds_idx]=y2[ds_ii];ds_idx++;}
        // 4. Top boundary segment (r2top → r1top), endpoints included in segment
        for(ds_ii=0;ds_ii<ds_topSegN;ds_ii++){polyX[ds_idx]=ds_topSegX[ds_ii];polyY[ds_idx]=ds_topSegY[ds_ii];ds_idx++;}
        // Trim to actual size used
        polyX = Array.trim(polyX, ds_idx); polyY = Array.trim(polyY, ds_idx);

        } else {
            // --- No Core_boundary lines: legacy endpoint-connection method ---
            dist_start1_start2 = sqrt((x1[0]-x2[0])*(x1[0]-x2[0]) + (y1[0]-y2[0])*(y1[0]-y2[0]));
            dist_start1_end2   = sqrt((x1[0]-x2[x2.length-1])*(x1[0]-x2[x2.length-1]) + (y1[0]-y2[y2.length-1])*(y1[0]-y2[y2.length-1]));
            dist_end1_start2   = sqrt((x1[x1.length-1]-x2[0])*(x1[x1.length-1]-x2[0]) + (y1[y1.length-1]-y2[0])*(y1[y1.length-1]-y2[0]));
            dist_end1_end2     = sqrt((x1[x1.length-1]-x2[x2.length-1])*(x1[x1.length-1]-x2[x2.length-1]) + (y1[y1.length-1]-y2[y2.length-1])*(y1[y1.length-1]-y2[y2.length-1]));
            pattern1_total = dist_start1_start2 + dist_end1_end2;
            pattern2_total = dist_start1_end2   + dist_end1_start2;
            polyX = newArray(x1.length + x2.length);
            polyY = newArray(y1.length + y2.length);
            if (pattern1_total <= pattern2_total) {
                for (i = 0; i < x1.length; i++) { polyX[i] = x1[i]; polyY[i] = y1[i]; }
                for (i = 0; i < x2.length; i++) { polyX[x1.length+i] = x2[x2.length-1-i]; polyY[x1.length+i] = y2[x2.length-1-i]; }
            } else {
                for (i = 0; i < x1.length; i++) { polyX[i] = x1[i]; polyY[i] = y1[i]; }
                for (i = 0; i < x2.length; i++) { polyX[x1.length+i] = x2[i]; polyY[x1.length+i] = y2[i]; }
            }
        }

        // Create polygon selection
        makeSelection("polygon", polyX, polyY);
        
        // Measure area
        run("Measure");
        ringAreas[r] = getResult("Area", nResults - 1);
        run("Clear Results");
        
        // Store polygon for later use
        ringPolygons[r] = r; // Just store index, we'll recreate when needed
        
        print("  " + ringNames[r] + ": length=" + d2s(ringLengths[r], 3) + " mm, area=" + d2s(ringAreas[r], 3) + " mm²");
        
        // Add to ROI manager with year name
        roiManager("add");
        roiManager("select", roiManager("count") - 1);
        roiManager("rename", "AREA_" + year);
    }
    
    run("Select None");
    print("");
    
    // Validate that measured inner year matches cross-dated inner year
    measuredInnerYear = outerYear - (nRings - 2);  // The last ring created
    if (measuredInnerYear != innerYear) {
        exit("Measured inner year (" + measuredInnerYear + ") does not match cross-dated inner year (" + innerYear + ").");
    }
    print("  Inner year validation: Measured " + measuredInnerYear + " matches cross-dated " + innerYear);
    print("");
    
    // ===== STEP 5.5: CALCULATE DAMAGE AREAS PER RING =====
    if (nDamage > 0) {
        print("STEP 4.5: Calculating damage area overlaps...");
        
        ringDamageAreas = newArray(nRings - 1);
        
        for (r = 0; r < nRings - 1; r++) {
            totalDamageArea = 0;
            
            // Find and select the AREA_ polygon for this ring
            ringPolygonName = "AREA_" + ringNames[r];
            ringPolygonIndex = -1;
            
            for (roi_i = 0; roi_i < roiManager("count"); roi_i++) {
                roiManager("select", roi_i);
                if (Roi.getName() == ringPolygonName) {
                    ringPolygonIndex = roi_i;
                    break;
                }
            }
            
            if (ringPolygonIndex >= 0) {
                // For each damage polygon, calculate intersection with this ring
                for (d = 0; d < nDamage; d++) {
                    // Select both the ring polygon and damage polygon
                    roiManager("select", newArray(ringPolygonIndex, damageIndices[d]));
                    
                    // Create intersection using AND operation
                    roiManager("AND");
                    
                    // Check if there's an intersection
                    if (selectionType() != -1) {
                        // Measure intersection area
                        run("Measure");
                        intersectionArea = getResult("Area", nResults - 1);
                        run("Clear Results");
                        totalDamageArea += intersectionArea;
                    }
                }
            }
            
            ringDamageAreas[r] = totalDamageArea;
            
            if (totalDamageArea > 0) {
                print("  " + ringNames[r] + ": damage area = " + d2s(totalDamageArea, 3) + " mm²");
            }
        }
        
        // Subtract damage areas from ring areas
        for (r = 0; r < nRings - 1; r++) {
            ringAreas[r] = ringAreas[r] - ringDamageAreas[r];
        }
        
        print("  Ring areas adjusted for damage");
        print("");
    } else {
        print("STEP 4.5: No damage areas to process");
        ringDamageAreas = newArray(nRings - 1);
        for (r = 0; r < nRings - 1; r++) {
            ringDamageAreas[r] = 0;
        }
        print("");
    }
    
    // ===== STEP 6: ASSIGN DUCTS TO RING POLYGONS =====
    print("STEP 6: Assigning ducts to ring area polygons...");
    
    if (nDucts > 0) {
        ductAreas = newArray(nDucts);
        ductCentersX = newArray(nDucts);
        ductCentersY = newArray(nDucts);
        ductRings = newArray(nDucts);
        ductNames = newArray(nDucts);
        
        run("Set Measurements...", "area centroid redirect=None decimal=3");
        
        // Measure each duct
        ductCounter = 0;
        for (i = 0; i < n; i++) {
            roiManager("select", i);
            roiType = Roi.getType();
            
            if (roiType == "oval" || roiType == "freehand") {
                run("Measure");
                ductAreas[ductCounter] = getResult("Area", nResults - 1);
                
                // Get centroid in calibrated units (mm)
                xMM = getResult("X", nResults - 1);
                yMM = getResult("Y", nResults - 1);
                
                // Convert to pixel coordinates for containment testing
                ductCentersX[ductCounter] = xMM / pixelWidth;
                ductCentersY[ductCounter] = yMM / pixelHeight;
                
                ductNames[ductCounter] = Roi.getName();
                ductCounter++;
            }
        }
        
        run("Clear Results");
        
        // Now assign each duct to a ring polygon
        unassignedDucts = newArray(0);
        
        print("  Testing duct containment...");
        
        for (d = 0; d < nDucts; d++) {
            assignedRing = "Unassigned";
            
            // Check each ring polygon to see if it contains this duct's centroid
            for (r = 0; r < nRings - 1; r++) {
                // Find the AREA_ polygon for this ring
                ringPolygonName = "AREA_" + ringNames[r];
                polygonIndex = -1;
                
                for (roi_i = 0; roi_i < roiManager("count"); roi_i++) {
                    roiManager("select", roi_i);
                    if (Roi.getName() == ringPolygonName) {
                        polygonIndex = roi_i;
                        break;
                    }
                }
                
                if (polygonIndex >= 0) {
                    roiManager("select", polygonIndex);
                    
                    // Check if duct centroid is inside this polygon
                    if (Roi.contains(ductCentersX[d], ductCentersY[d])) {
                        assignedRing = ringNames[r];
                        print("    Duct " + (d+1) + " (" + ductNames[d] + ") -> " + ringNames[r]);
                        break;
                    }
                }
            }
            
            ductRings[d] = assignedRing;
            
            if (assignedRing == "Unassigned") {
                unassignedDucts = Array.concat(unassignedDucts, d);
                print("    Duct " + (d+1) + " (" + ductNames[d] + ") at (" + d2s(ductCentersX[d],1) + "," + d2s(ductCentersY[d],1) + ") -> UNASSIGNED");
            }
        }
        
        // Check for unassigned ducts
        if (unassignedDucts.length > 0) {
            print("");
            print("WARNING: " + unassignedDucts.length + " duct(s) not contained in any ring polygon!");
            print("This may mean you're missing the innermost ring boundary.");
            print("Unassigned ducts:");
            for (i = 0; i < unassignedDucts.length; i++) {
                d = unassignedDucts[i];
                print("  - " + ductNames[d] + " at (" + d2s(ductCentersX[d], 1) + ", " + d2s(ductCentersY[d], 1) + ")");
            }
            print("");
            
            Dialog.create("Unassigned Ducts Found");
            Dialog.addMessage(unassignedDucts.length + " duct(s) are not contained in any ring polygon.");
            Dialog.addMessage("This usually means you're missing the innermost ring boundary.");
            Dialog.addMessage(" ");
            Dialog.addMessage("Options:");
            Dialog.addMessage("1. Cancel and add the missing ring boundary");
            Dialog.addMessage("2. Continue anyway (unassigned ducts will be excluded)");
            Dialog.addCheckbox("Continue anyway?", false);
            Dialog.show();
            
            if (!Dialog.getCheckbox()) {
                exit("Macro cancelled. Please add the missing ring boundary and try again.");
            }
        }
        
        // Calculate summary statistics per ring
        ringDuctCounts = newArray(nRings - 1);
        ringTotalDuctArea = newArray(nRings - 1);
        
        for (r = 0; r < nRings - 1; r++) {
            count = 0;
            totalArea = 0;
            
            for (d = 0; d < nDucts; d++) {
                if (ductRings[d] == ringNames[r]) {
                    count++;
                    totalArea += ductAreas[d];
                }
            }
            
            ringDuctCounts[r] = count;
            ringTotalDuctArea[r] = totalArea;
            
            print("  " + ringNames[r] + ": " + count + " ducts, total duct area = " + d2s(totalArea, 3) + " mm²");
        }
        
    } else {
        print("  No ducts to measure");
        ringDuctCounts = newArray(nRings - 1);
        ringTotalDuctArea = newArray(nRings - 1);
        for (r = 0; r < nRings - 1; r++) {
            ringDuctCounts[r] = 0;
            ringTotalDuctArea[r] = 0;
        }
    }
    
    print("");
    
    // ===== STEP 7: CREATE OVERLAY =====
    print("STEP 7: Creating visualization overlay...");
    
    run("Remove Overlay");
    Overlay.remove;
    
    // Add original ring boundaries in red
    for (r = 0; r < nRings; r++) {
        roiManager("select", sortedRingIndices[r]);
        Roi.setStrokeColor("red");
        Roi.setStrokeWidth(3);
        Overlay.addSelection;
    }
    
    // Add ring area polygons in black
    for (r = 0; r < nRings - 1; r++) {
        ringPolygonName = "AREA_" + ringNames[r];
        for (roi_i = 0; roi_i < roiManager("count"); roi_i++) {
            roiManager("select", roi_i);
            if (Roi.getName() == ringPolygonName) {
                Roi.setStrokeColor("black");
                Roi.setStrokeWidth(2);
                Overlay.addSelection;
                break;
            }
        }
    }
    
    // Add ducts in blue
    if (nDucts > 0) {
        for (d = 0; d < nDucts; d++) {
            roiManager("select", ductIndices[d]);
            Roi.setStrokeColor("blue");
            Roi.setStrokeWidth(2);
            Overlay.addSelection;
        }
    }
    
    // Add damage polygons in green
    if (nDamage > 0) {
        for (d = 0; d < nDamage; d++) {
            roiManager("select", damageIndices[d]);
            Roi.setStrokeColor("green");
            Roi.setStrokeWidth(2);
            Overlay.addSelection;
        }
    }
    
    Overlay.show;
    run("Select None");
    
    print("  Overlay created (boundaries=red, areas=black, ducts=blue, damage=green)");
    print("");
    
    // ===== STEP 8: EXPORT DATA =====
    print("STEP 8: Exporting data...");
    
    // Get the directory where the image is located
    imagePath = getInfo("image.directory");
    if (imagePath == "") {
        // Image hasn't been saved yet, ask user for output location
        outputDir = getDirectory("Image not saved. Choose output folder for files");
    } else {
        outputDir = imagePath;
    }
    
    print("  Output directory: " + outputDir);
    
    // Find next available version number for output files
    version = 0;
    summaryFile = outputDir + baseTitle + "_ring_summary.csv";
    detailFile = outputDir + baseTitle + "_duct_details.csv";
    roiSetFile = outputDir + baseTitle + "_final_ROIset.zip";
    
    // Check if base filenames exist, if so find next version number
    if (File.exists(summaryFile) || File.exists(detailFile) || File.exists(roiSetFile)) {
        version = 1;
        while (true) {
            summaryFile = outputDir + baseTitle + "_ring_summary_" + version + ".csv";
            detailFile = outputDir + baseTitle + "_duct_details_" + version + ".csv";
            roiSetFile = outputDir + baseTitle + "_final_ROIset_" + version + ".zip";
            
            // If none of these versioned files exist, we can use this version number
            if (!File.exists(summaryFile) && !File.exists(detailFile) && !File.exists(roiSetFile)) {
                print("  Output files will be versioned as: _" + version);
                break;
            }
            version++;
            
            // Safety check to prevent infinite loop
            if (version > 1000) {
                exit("Too many versions already exist (>1000). Please clean up output directory.");
            }
        }
    } else {
        print("  Creating new output files (no versioning needed)");
    }
    
    // Export ring summary CSV
    run("Clear Results");
    for (r = 0; r < nRings - 1; r++) {
        setResult("series", r, baseTitle);
        setResult("year", r, ringNames[r]);
        setResult("ring.length.mm", r, ringLengths[r]);
        setResult("ring.area.mm2", r, ringAreas[r]);
        setResult("damage.area.mm2", r, ringDamageAreas[r]);
        setResult("n.ducts", r, ringDuctCounts[r]);
        setResult("total.duct.area.mm2", r, ringTotalDuctArea[r]);
    }
    updateResults();
    
    saveAs("Results", summaryFile);
    print("  Saved ring summary: " + summaryFile);
    
    // Export duct details CSV (if ducts exist)
    if (nDucts > 0) {
        run("Clear Results");
        for (d = 0; d < nDucts; d++) {
            setResult("series", d, baseTitle);
            setResult("ductID", d, ductNames[d]);
            setResult("year", d, ductRings[d]);
            setResult("area.mm2", d, ductAreas[d]);
            setResult("x", d, ductCentersX[d]);
            setResult("y", d, ductCentersY[d]);
        }
        updateResults();
        
        saveAs("Results", detailFile);
        print("  Saved duct details: " + detailFile);
    }
    
    // Save ROI set with all ROIs (ring boundaries, area polygons, and ducts)
    roiManager("deselect");
    roiManager("save", roiSetFile);
    print("  Saved ROI set: " + roiSetFile);
    
    print("");
    print("=== ANALYSIS COMPLETE ===");
    print("Rings analyzed: " + (nRings - 1) + " (" + ringNames[0] + " to " + ringNames[nRings - 2] + ")");
    print("Ring summary: " + summaryFile);
    if (nDucts > 0) {
        print("Duct details: " + detailFile);
    }
    print("ROI set: " + roiSetFile);
    print("Overlay applied to image");
    
    // Final message
    if (nDucts > 0) {
        assignedCount = nDucts - unassignedDucts.length;
        showMessage("Analysis Complete!", 
            "Complete ring and duct analysis finished!\n \n" +
            "Results:\n" +
            "- " + (nRings - 1) + " ring areas created\n" +
            "- " + assignedCount + " of " + nDucts + " ducts assigned\n" +
            "- Years: " + ringNames[nRings - 2] + " to " + ringNames[0] + "\n \n" +
            "Files saved:\n" +
            "- Ring summary CSV (with areas)\n" +
            "- Duct details CSV\n" +
            "- ROI set ZIP\n \n" +
            "See Log window for details.");
    } else {
        showMessage("Analysis Complete!", 
            "Ring analysis finished!\n \n" +
            "Results:\n" +
            "- " + (nRings - 1) + " ring areas measured\n" +
            "- Years: " + ringNames[nRings - 2] + " to " + ringNames[0] + "\n \n" +
            "Files saved:\n" +
            "- Ring summary CSV\n" +
            "- ROI set ZIP\n \n" +
            "See Log window for details.");
    }
    
} else {
    print("ERROR: No bark point selected. Analysis cancelled.");
    exit("No bark point selected. Please run the macro again and click on the bark location.");
}

// ---- ResinDuctSummary helper functions ----





