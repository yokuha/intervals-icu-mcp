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
