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


## Streams

### Computing DFA-α1 from the `hrv` stream

Device-recorded `dfa_a1` / `RRa1` streams are sometimes unusable (the value stays frozen for the
whole activity), while the raw RR intervals in the `hrv` stream are complete. This is not a bug in
the server, but a helper or tool that computes DFA-α1 from the `hrv` stream (e.g. 120 s window,
box sizes 4–16 beats) would make threshold analysis possible in that case.
I believe Marco Altini has [code for this](https://colab.research.google.com/drive/1GUZVjZGhc2_JqV-J5m1mgbvbiTBV9WzZ?usp=sharing#scrollTo=dPto519o_Cq1).
