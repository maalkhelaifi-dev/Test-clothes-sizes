# Testing accuracy against tape-measure measurements

Camera estimates in Measure Me are **uncalibrated**. This protocol measures how far they are from tape-measure values and produces calibration factors for `CalibrationProfile` (`MeasureMeKit/Sources/MeasureMeCore/Estimation/MeasurementEstimator.swift`).

## 1. Participants and consent
- Recruit adult volunteers (18+) who give written consent. Aim for at least 30 people covering a wide range of heights and body shapes.
- Record only what the study needs: measurements, device model and capture conditions. Don't record names next to the data; use participant codes.

## 2. Reference measurements (ground truth)
- Use a calibrated, non-stretch tailor's tape and a stadiometer (or a wall and a set square) for height.
- Follow the definitions in `MeasurementKind.howToMeasure`. They match what the app estimates; for example, inseam is crotch to floor, barefoot.
- Take every measurement **twice**, ideally by two different measurers, and use the mean. Large disagreements between measurers tell you how precise a tape measurement really is (often ±1–2 cm for waist and hips).
- Participants wear the same fitted clothing for tape and camera measurements.

## 3. Camera captures
For each participant, record:
- device model (Pro with LiDAR or not), camera used, LiDAR on or off;
- room lighting (approximate lux if possible), background, camera height and distance;
- whether the participant was barefoot and what they wore.

Then:
1. Enter the participant's **measured** height in their profile.
2. Run the full camera flow **three times**, stepping out of frame between runs. This gives repeatability.
3. Record the estimates, confidence levels and uncertainty for each run. They are shown on the results screen and in the session history.
4. Optionally repeat with deliberate deviations: loose clothing, phone tilted 10°, feet together, dim light. This checks that the live checks and confidence levels respond.

## 4. Metrics per measurement
For each measurement kind, compute over all participants and runs:
- **Bias**: mean(camera − tape).
- **MAE**: mean absolute error, in cm.
- **95% limits of agreement** (Bland–Altman): bias ± 1.96 × SD of the differences.
- **Repeatability**: SD across the three runs of the same participant.
- **Coverage of the stated uncertainty**: the share of runs where |camera − tape| ≤ the displayed ± value. The bands are meant as roughly one standard deviation, so about 68% is expected. Much lower means the app is over-confident.
- **Confidence calibration**: MAE split by confidence level. High should beat medium, and medium should beat low.
- **Size outcome**: for a few real verified charts, how often the recommended size from camera values matches the size from tape values, and how often the tape-based size appears as the alternative.

## 5. Calibration
- For each measurement, fit a multiplicative factor `k = median(tape / camera_raw)` on a **training** subset (for example, 70% of participants). Use raw estimates with all factors set to 1.0.
- Evaluate MAE and coverage on the held-out subset before and after applying `k`.
- Store the factors in a `CalibrationProfile` and use it in `MeasurementEstimator.estimate(..., calibration:)`. Record the study date, device set and sample size next to the profile.
- If a single factor doesn't remove the bias (for example, errors grow with body size), a multiplicative factor isn't enough: you need a learned regression or body-shape model.
- Update the uncertainty values in the estimator (`put(... unc ...)` calls) to match the measured SD, so the ± values shown to users are honest.

## 6. Acceptance targets (suggested)
These are starting points to agree with your product owner:

| Measurement | Target MAE vs tape |
|---|---|
| Chest, waist, hips | ≤ 3 cm |
| Inseam, arm length | ≤ 2 cm |
| Rough girths (thigh, neck, …) | Report only; keep low-confidence labelling until a trained model exists |

Don't remove low-confidence labels or "estimate" wording on the strength of a small study.

## 7. Regression tests
When you change the estimator, keep the synthetic-silhouette tests in `MeasurementEstimatorTests` passing. Consider adding anonymised **mask + joint** fixtures (never photos) from the study as regression tests.
