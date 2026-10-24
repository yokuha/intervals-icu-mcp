# Improvement ideas for intervals-icu-mcp

Gaps noticed while using the server for day-to-day training analysis. Each entry describes what is
missing, why it matters, and a suggested approach. Examples are illustrative.

## Activities

### `icu_update_activity`: missing writable fields

The tool currently accepts only `name`, `description`, `activity_type`, `trainer`, `commute`,
`feel` and `perceived_exertion`. The Intervals.icu API accepts more fields on activity update that
are useful in practice:

* `distance` (meters): add or correct the distance, e.g. for indoor rides where the trainer app
  knows the distance but the uploaded file does not. Passing `distance=...` currently fails with
  "Unexpected keyword argument", so the value has to be entered by hand in the web UI.
* `carbs_ingested` (grams): log fueling per session.
* Worth checking as well: `calories`, `gear`, `average_speed`, `icu_rpe`, `tags`.

Suggestion: add these as optional parameters, or – maybe better – add a generic `fields: dict`
pass-through to `PUT /api/v1/activity/{id}` for any other API field.


### Saving intervals on an activity

There are only read tools (`icu_get_activity_intervals`, `icu_search_intervals`), but no tool to
create or edit intervals on an activity (API: `PUT /api/v1/activity/{id}/intervals` and
`PUT /api/v1/activity/{id}/intervals/{intervalId}`). Use case: marking the best 3-minute effort
of a ramp test as an interval.

Suggestion: a tool `icu_update_activity_intervals` taking start/end second, label and type.


## Power curves

### `icu_get_power_curves`: only rolling windows, no seasons or date ranges

The tool supports only `days_back` and `time_period` (`week`/`month`/`year`/`all`). Comparing
"this season / last season / all-time" needs the seasons defined in Intervals.icu. A rolling
approximation, e.g., 365 days instead of the season, shifts the window and drops or adds bests near
its edges, so the numbers differ from what the Intervals.icu UI shows.

Suggestion: add `start_date` / `end_date` and `season` (name or ID) parameters, ideally accepting
several ranges in one call so comparisons need a single request. The API already supports this:
`GET /api/v1/athlete/{id}/power-curves` with the `curves` parameter (e.g. `s0,s1,all` or
`r.YYYY-MM-DD.YYYY-MM-DD`).

### `icu_get_power_curves`: duration range and extra data

* The description mentions 5 s to 1 h. Durability analysis for long events needs durations up to
  about 6 h (2 h, 3 h, 4 h, 5 h, 6 h bests). Check whether the tool returns them; add them if not.
* Missing: best values in W/kg (using the weight for the period), the period's weight, activity ID
  and date per duration (only partly present), and the full-resolution curve (all durations instead
  of the standard points).
* Missing: power models (CP / W' / Pmax, FTP estimates such as `MORTON_3P`, `MS_2P`, `FFT_CURVES`,
  `ECP`), the VO2max estimate (`vo2max_5m`) and MAP from the curve object. Currently only the simple
  FTP estimate (95 % of 20 min) is available.

Suggestion: a separate tool `icu_get_power_curve_models`, or include the models in the curve
response.

### Listing seasons

There is no tool to list the athlete's Intervals.icu seasons (name, start, end). It would pair
well with season-based curve queries.


## Sport settings

### Custom activity field defaults are not readable or writable

Sport settings can hold default values for custom activity fields, e.g. thresholds from a breathing
or HRV sensor test: ventilatory thresholds (VT1/VT2) as power, VE and breathing rate, VO2max power,
resting/max breathing rate, DFA-α1 thresholds. `icu_get_sport_settings` does not return these
values, and `icu_update_sport_settings` only covers FTP, FTHR, max HR, thresholds and zones, so they
have to be entered by hand in the web UI.

Suggestion: include the sport's custom-field defaults in `icu_get_sport_settings` (field name, code,
value) and add a `custom_fields: dict` parameter (name or code → value) to
`icu_update_sport_settings`. Optionally also return zones derived from those fields.


## Streams

### Computing DFA-α1 from the `hrv` stream

Device-recorded `dfa_a1` / `RRa1` streams are sometimes unusable (the value stays frozen for the
whole activity), while the raw RR intervals in the `hrv` stream are complete. This is not a bug in
the server, but a helper or tool that computes DFA-α1 from the `hrv` stream (e.g. 120 s window,
box sizes 4–16 beats) would make threshold analysis possible in that case.
I believe Marco Altini has [code for this](https://colab.research.google.com/drive/1GUZVjZGhc2_JqV-J5m1mgbvbiTBV9WzZ?usp=sharing#scrollTo=dPto519o_Cq1).
