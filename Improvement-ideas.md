# Improvement ideas for intervals-icu-mcp

Gaps noticed while using the server for day-to-day training analysis. Each entry describes what is
missing, why it matters, and a suggested approach. Examples are illustrative.

## Activities

### Saving intervals on an activity

There are only read tools (`icu_get_activity_intervals`, `icu_search_intervals`), but no tool to
create or edit intervals on an activity (API: `PUT /api/v1/activity/{id}/intervals` and
`PUT /api/v1/activity/{id}/intervals/{intervalId}`). Use case: marking the best 3-minute effort
of a ramp test as an interval.

Suggestion: a tool `icu_update_activity_intervals` taking start/end second, label and type.

### `icu_get_activity_intervals`: missing fields, and some never filled

The tool returns only `id`, `type` and a `performance` block with average watts, average/max HR,
average cadence, average speed and distance. Part of the mapping does not even work: the model
reads `start`, `end`, `duration`, `normalized_power` and `target`, but the API sends
`start_time` / `end_time`, `elapsed_time` / `moving_time`, `weighted_average_watts` and `label`.
So start/end second, duration, NP and the interval label are never returned. The
`rest_intervals` count also stays 0 when rests come back as type `RECOVERY`.

The API's `Interval` object has many more fields (only non-null ones are sent). Useful ones,
grouped:

* Power: `min_watts` / `max_watts`, `average_watts_kg` / `max_watts_kg`, `intensity` (% FTP),
  `zone`, `training_load`, `joules`, `joules_above_ftp`, `wbal_start` / `wbal_end`, `decoupling`,
  `w5s_variability`, `average_torque` / `max_torque`.
* Pedalling: `avg_lr_balance` (L/R), `min_cadence` / `max_cadence`.
* Breathing (e.g. Tymewear): `average_respiration` (BR, breaths/min), `average_tidal_volume`,
  `average_tidal_volume_min` (VE, L/min).
* HRV and muscle oxygen: `average_dfa_a1`, `average_smo2` / `average_thb` (plus `_2` for a second
  sensor), `average_lactate`.
* Speed and terrain: `min_speed` / `max_speed`, `gap`, `total_elevation_gain`,
  `average_gradient`, temperature and wind.
* Running dynamics: stance time, vertical oscillation and ratio, step length, and so on.
* Custom interval fields defined in the account come back as extra keys (e.g. `VEEF`).
* `icu_groups` in the response summarises repeated intervals (e.g. "3 × 5 min"), with the same
  averages plus `count`.

Suggestion: fix the field mapping first (start/end, duration, NP, label). Then return all
non-null API fields grouped like above, including custom interval fields and `icu_groups`.
Optionally add a `fields` filter to keep responses small.


## Sport settings

### Custom activity field defaults are not readable or writable

Sport settings can hold default values for custom activity fields, e.g. thresholds from a breathing
or HRV sensor test: ventilatory thresholds (VT1/VT2) as power, VE and breathing rate, VO2max power,
resting/max breathing rate, DFA-α1 thresholds. `icu_get_sport_settings` does not return these
values, and `icu_update_sport_settings` only covers FTP, FTHR, max HR, thresholds and zones, so they
have to be entered by hand in the web UI.

For illustration, these are my personal custom fields for Ride (names as I defined them in my
account, not Intervals.icu built-ins):

* Power: VT endurance, VT1, VT2, VO2max power (tyme)
* VO2max: VO2max (vol/time/weight)
* VE thresholds: VT endurance, VT1, VT2, VT topZ4, VT VO2max
* Breathing rate: VT endurance, VT1, VT2 breathing rate, BRrest, BRmax
* DFA-α1: VT1, VT2

Cause: the API does send them, as `custom_field_values` (field code → value) in the SportSettings
object, with the field definitions referenced by `custom_field_ids` / `activity_field_ids`. But the
`SportSettings` model has no such field (and no `extra="allow"`), so Pydantic drops the key while
parsing, and `format_sport_settings_entry` has nothing to print. Writing fails the same way:
`icu_update_sport_settings` only forwards its known parameters.

Suggestion:

1. Read: add `custom_field_values: dict[str, Any]` to the `SportSettings` model and emit it from
   `format_sport_settings_entry` as `custom_fields`. Resolve code → display name via the account's
   `ACTIVITY_FIELD` custom items (same lookup as `icu_get_custom_items`), so the output reads
   `{code, name, value}` instead of bare codes. Fall back to the bare code if the lookup fails.
2. Write: add a `custom_fields: dict` parameter (name or code → value) to
   `icu_update_sport_settings`. Map names to codes, and merge into the existing
   `custom_field_values` before the PUT so unmentioned fields are not wiped (verify against the
   API whether it replaces or merges the object).
3. Optional: return zones derived from those fields.

Tests: respx-mocked GET with `custom_field_values`, and a PUT test asserting the merged payload.
This is non-breaking (added field and optional parameter), so it can ship as a minor.


## Streams

### Computing DFA-α1 from the `hrv` stream

Device-recorded `dfa_a1` / `RRa1` streams are sometimes unusable (the value stays frozen for the
whole activity), while the raw RR intervals in the `hrv` stream are complete. This is not a bug in
the server, but a helper or tool that computes DFA-α1 from the `hrv` stream (e.g. 120 s window,
box sizes 4–16 beats) would make threshold analysis possible in that case.
I believe Marco Altini has [code for this](https://colab.research.google.com/drive/1GUZVjZGhc2_JqV-J5m1mgbvbiTBV9WzZ?usp=sharing#scrollTo=dPto519o_Cq1).
