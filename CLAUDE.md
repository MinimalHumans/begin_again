## Project Overview

Begin Again is a post-apocalyptic community survival simulation built in Godot 4.5 with GDScript. The player leads a small settlement through daily ticks, managing stats via passive simulation and responding to tiered narrative events. All persistent data is stored in two SQLite databases accessed through the godot-sqlite plugin.

## Architecture at a Glance

The game uses two SQLite databases: `library.db` (read-only reference data seeded on first run) and `save.db` (mutable game state written each tick). Three autoload singletons (`DatabaseManager`, `GameData`, `TickManager`) form the backbone. `TickManager._run_tick()` drives the simulation each game-day: it loads state, runs passive stat changes, processes population lifecycle, resolves deferred outcomes, fires chain stages, selects and fires Tier 1/2 events, then updates the UI. Events are defined in the `events` table with JSON eligibility, actor requirements, choices, and chain metadata. Static helper classes in `scripts/game/` and `scripts/simulation/` handle eligibility checks, actor casting, template resolution, dice rolls, flags, deferred outcomes, and chain progression.

## Database Layer

### library.db (`res://database/library.db`)

Opened by `DatabaseManager.open_library()`. Created and seeded on first run. Read-only at runtime except during initial seeding.

| Table | Contents |
|---|---|
| `stats` | Stat definitions: id, display_name, min/max/default, warning/critical thresholds, format_type |
| `simulation_config` | Key-value config constants (FOOD_DRAIN_PER_PERSON, decay rates, season multipliers, birth/death rates) |
| `apocalypses` | Apocalypse scenarios with stat_modifiers, environment_tags, daily_health_pressure |
| `origins` | Origin stories with population range, stat/skill/personality weights |
| `locations` | Settlement locations with stat_modifiers, event_tags, terrain_tags, structures array |
| `name_pool` | First names with gender for population generation |
| `skills` | Skill definitions (medicine, farming, combat, engineering, teaching) with stat_links |
| `personalities` | Personality types with behavior_profile, event_weights, ambient_templates |
| `roles` | Assignable roles (medic, farmer, guard, teacher, scavenger, builder) with required_skills, stat_bonuses, max_slots |
| `community_types` | 8 community archetypes (commonwealth, bastion, etc.) with roll_modifiers, reveal_text, thresholds |
| `events` | All event definitions: tier, eligibility JSON, description_template, actor_requirements, choices JSON, chain fields |

### save.db (`user://save.db`)

Opened by `DatabaseManager.open_save()`. Reset on new game. Written every tick.

| Table | Written when |
|---|---|
| `game_state` | Every tick (game_day, season, difficulty_time_factor, food_production). Single row, id=1 |
| `world_tags` | New game only. Tag + source pairs from apocalypse/location |
| `current_stats` | Every tick. stat_id → current value + trend |
| `stat_history` | Every 7 days. Snapshots for trend calculation |
| `population` | Every tick (deaths, births, departures, role changes, flag changes, last_mentioned) |
| `community_scores` | On Tier 2/chain choice (community_scores field in choice JSON) |
| `event_log` | Every tick (ambient events, warnings) + on Tier 2 choice resolution |
| `pending_deferred` | On Tier 2 choice with deferred block; marked fired on resolution |
| `active_chains` | On chain start; updated on advance; deleted on end |
| `flags` | On event outcome flags_set/flags_cleared |
| `cooldowns` | After each event fires. event_id or exclusion_group + expires_day |
| `event_occurrence_counts` | After each event fires. Tracks max_occurrences |

All DB access goes through `DatabaseManager`. Direct SQLite calls must never appear in other scripts.

## Autoloads

### DatabaseManager (`scripts/autoloads/DatabaseManager.gd`)

Singleton managing both SQLite connections. Creates schemas and seeds data on first open.

- `open_library() -> bool` — opens library.db, creates schema and seeds if needed
- `open_save(path: String) -> bool` — opens save.db at path, creates schema if needed
- `reset_save(path: String)` — closes, deletes, and re-opens save.db (used on new game)
- `close_all()` — closes both databases
- `query_library(sql, params=[]) -> Array` — SELECT against library.db, returns array of dicts
- `query_save(sql, params=[]) -> Array` — SELECT against save.db
- `execute_save(sql, params=[])` — INSERT/UPDATE/DELETE against save.db
- `execute_library(sql, params=[])` — write operations against library.db (seeding only)

State: `_library_db: SQLite`, `_save_db: SQLite`

### GameData (`scripts/autoloads/GameData.gd`)

Cached read-only accessor for library.db reference data.

- `get_all_skill_ids() -> Array[String]` — cached list of skill IDs
- `get_all_events() -> Array` — cached full event rows
- `get_personality(id: String) -> Dictionary` — cached personality row lookup
- `get_config(key: String) -> float` — single simulation_config value
- `get_all_stats() -> Array` — all stat definitions ordered by display_order
- `get_stat(id: String) -> Dictionary` — single stat definition
- `get_all_roles() -> Array` — all role definitions

State: `_skill_ids_cache`, `_events_cache`, `_personality_cache` (all populated on first access)

### TickManager (`scripts/autoloads/TickManager.gd`)

Drives the simulation loop. Emits signals for UI updates.

- `set_speed(speed: int)` — 0=paused, 1=normal (2s/tick), 2=fast (0.333s/tick)
- `register_ui(event_log, stats_panel)` — stores UI node references for direct updates
- `_run_tick()` — the main simulation step (see Tick Sequence below)

Signals: `day_advanced(new_day, new_season)`, `log_entry_added(entry)`, `game_over_triggered(reason)`

State: `current_speed`, `_popup_active`, `_pending_chain_stages`, `_current_state_tags`, `_current_world_tags`, `_current_flags`, `_current_cooldowns`, `_current_occurrence_counts`, `_current_game_day`, `_stat_defs`, `_location_structures_cache`

## Game Systems

### NewGameGenerator (`scripts/game/NewGameGenerator.gd`)
- Type: static (class_name, all static methods)
- Purpose: generates a complete new game — rolls apocalypse/origin/location, creates population, calculates starting stats, writes all save.db tables
- `generate() -> Dictionary` — returns `{"opening_text": String}`
- `_weighted_random(rows) -> Dictionary` — weighted selection by `weight` field
- `_generate_person(index, name_pool, all_skills, used_names) -> Dictionary`
- `_roll_age() -> int` — weighted bands: 18-35 (50%), 36-55 (30%), 56-70 (10%), 5-17 (8%), 0-4 (2%)
- `_calculate_skill_bonuses(people, all_skills) -> Dictionary` — +2.0 per person per stat-linked skill
- `_calculate_season(starting_day_of_year, game_day) -> String`
- Called by: `Main.start_new_game()`

### TemplateResolver (`scripts/game/TemplateResolver.gd`)
- Type: static
- Purpose: resolves template variables in event text and opening crawl
- `resolve(template, context) -> String` — simple {key} → value replacement
- `resolve_event(template, actors, stats, game_state, location_structures, chain_memory) -> String` — full multi-pass resolution (see Key Conventions)
- Called by: TickManager (ambient, tier2, chain firing), DeferredOutcomeSystem, NewGameGenerator

### PassiveSimulation (`scripts/simulation/PassiveSimulation.gd`)
- Type: static
- Purpose: calculates per-tick stat deltas from drains, role bonuses, and drift formulas
- `run_tick(stats, game_state, role_bonuses, config, role_food_production) -> Dictionary` — returns stat_id → delta map
- Called by: TickManager step 3

### PopulationLifecycle (`scripts/simulation/PopulationLifecycle.gd`)
- Type: static
- Purpose: determines births, deaths, and departures per tick
- `run_tick(population, stats, game_state, config) -> Dictionary` — returns `{"births":[], "deaths":[], "departures":[]}`
- Deaths capped at 2/tick, departures at 1/tick, births at 1/tick
- Called by: TickManager step 5

### RollEngine (`scripts/game/RollEngine.gd`)
- Type: static (extends RefCounted)
- Purpose: resolves choice outcomes using 3d6 bell curve + stat/context bonuses
- `roll(choice, stats, actors, game_state, flags, world_tags) -> Dictionary` — returns `{"outcome_tier": String, "outcome_score": float}`
- Outcome tiers: catastrophic (<-1.0), bad (<-0.3), mixed (<=0.3), good (<=1.0), exceptional (>1.0)
- `_evaluate_condition(condition, ...)` — parses colon-delimited conditions: `actor_has_skill:X`, `actor_personality:X`, `flag:X`, `season:X`, `stat_above:X:N`, `stat_below:X:N`, `world_tag:X`
- `_find_nearest_tier(target, outcomes)` — fallback when rolled tier has no outcome defined
- Called by: TickManager (tier2 + chain choice resolution), DeferredOutcomeSystem

### StateTagSystem (`scripts/game/StateTagSystem.gd`)
- Type: static (extends RefCounted)
- Purpose: computes current state tags from stats, population, and game state for eligibility checks
- `compute(stats, population, game_state, known_skill_ids, recent_log_days) -> Array[String]`
- Tags generated: `{stat}_critical/low/moderate/good/high`, `food_critical/low/moderate/adequate`, population bands (`solo`, `tiny_group`, `small_group`, `medium_group`, `large_group`, `settlement`), `has_skill_{id}`, `role_vacant_{id}`, `season_{name}`, `recent_death`, `recent_birth`, `newcomers_present`
- Called by: TickManager step 4b

### EligibilityEngine (`scripts/game/EligibilityEngine.gd`)
- Type: static (extends RefCounted)
- Purpose: checks whether an event passes all eligibility constraints
- `is_eligible(event, world_tags, state_tags, stats, flags, population, game_day, cooldowns, occurrence_counts) -> bool`
- Checks: required/excluded world_tags, required/excluded state_tags, stat_above/stat_below, population_min/max, min/max_game_day, required/excluded flags, requires_actor, cooldowns, exclusion_group cooldowns, max_occurrences
- Special: `stat_below` supports `food_weeks` as a virtual stat
- Called by: TickManager (ambient firing, tier2 firing, chain stage firing)

### ActorCaster (`scripts/game/ActorCaster.gd`)
- Type: static (extends RefCounted)
- Purpose: selects population members to fill actor slots in events
- `cast(event, population, game_day) -> Dictionary` — returns `{"actor_1": person_dict, "actor_2": person_dict, ...}` or empty dict on failure
- Filters by: required_skills (any match), required_personality, required_role, excluded_flags
- Weighting: deprioritises recently mentioned (×0.3 if within 7 days), applies personality event_weights for category
- No double-casting across slots
- Called by: TickManager (ambient, tier2, chain stage firing)

### FlagSystem (`scripts/game/FlagSystem.gd`)
- Type: static (extends RefCounted) with static cache
- Purpose: manages global flags (save.db `flags` table) and per-actor flags (population `flags` JSON column)
- Global: `set_flag(name, game_day, source)`, `clear_flag(name)`, `has_flag(name) -> bool`, `get_all_flags() -> Array[String]`
- Per-actor: `set_actor_flag(person_id, flag_name)`, `clear_actor_flag(person_id, flag_name)`, `actor_has_flag(person_id, flag_name) -> bool`, `get_actor_flags(person_id) -> Array[String]`
- `invalidate_cache()` — clears `_actor_flags_cache`, called at start of each tick
- Called by: TickManager (outcome processing), EligibilityEngine (indirectly via flags array)

### DeferredOutcomeSystem (`scripts/game/DeferredOutcomeSystem.gd`)
- Type: static (extends RefCounted)
- Purpose: schedules and resolves delayed event outcomes
- `schedule(event_id, choice_id, source_log_id, actor_ids, deferred_block, game_day)` — writes to `pending_deferred`
- `tick(game_day, stats, game_state, flags, world_tags) -> Array` — fires pending hints, resolves matured outcomes using RollEngine
- Resolution probability: `1/window_days` per day, forced at `latest_fire_day`
- Called by: TickManager step 5b

### ChainSystem (`scripts/game/ChainSystem.gd`)
- Type: static (extends RefCounted)
- Purpose: manages multi-stage event chains with persistent memory
- `start_chain(chain_id, first_stage_id, game_day, initial_memory)` — inserts into `active_chains`, next_fire_day = +3..10 days
- `advance_chain(chain_id, next_stage_id, memory_writes, game_day)` — merges memory, sets next_fire_day = +5..20 days
- `end_chain(chain_id)` — deletes from `active_chains`
- `get_memory(chain_id) -> Dictionary` — reads chain memory JSON
- `get_due_chains(game_day) -> Array` — returns chains where next_fire_day <= game_day
- Called by: TickManager (chain stage processing, tier2/chain choice outcomes)

## Tick Sequence

Exact order inside `TickManager._run_tick()`:

1. **Load state** — query game_state, current_stats, living population, roles, all simulation_config values, cache stat definitions
2. **Load event engine state** — invalidate FlagSystem cache, load world_tags, flags, cooldowns, occurrence_counts
3. **Calculate role bonuses** — iterate assigned roles, sum stat_bonuses for qualified members (up to max_slots)
4. **Run PassiveSimulation** — `PassiveSimulation.run_tick()` returns stat deltas
5. **Apply stat deltas** — positive deltas × stability_factor, negative in full, clamp to min/max, write to DB
6. **Compute state tags** — `StateTagSystem.compute()` using current stats + recent log
7. **Run PopulationLifecycle** — process deaths, departures, births; update population stat
8. **Process deferred outcomes** — `DeferredOutcomeSystem.tick()` fires hints and resolves matured outcomes
9. **Process chain stages** — `_tick_chains()` fires at most one due chain stage per tick (may show popup)
10. **Fire Tier 1 ambient events** — re-fetch living population, roll 0-3 events, filter by eligibility, weighted select, cast actors, resolve templates, write to log
11. **Attempt Tier 2 decision event** — 3% base probability per tick, only if no popup active; shows EventPopup, pauses game
12. **Generate stat warnings** — 10% chance of a narrative warning about low stats
13. **Update season** — recalculate from day_of_year
14. **Snapshot stat history** — every 7 days
15. **Update stat trends** — every 14 days (rising/stable/falling based on ±3.0 threshold)
16. **Increment difficulty_time_factor** — +0.025/30 per tick (widens roll divisor)
17. **Check loss conditions** — population < 3, food <= 0, or cohesion <= 0 triggers game over
18. **Advance game_day** — increment by 1
19. **Notify UI** — emit day_advanced signal, refresh stats panel, flush pending log entries

## UI Layer

### Main (`scripts/ui/Main.gd`)
- Scene: `scenes/Main.tscn`
- Purpose: root controller — opens databases, wires signals, manages new game flow
- On ready: opens DBs, registers UI with TickManager, connects signals, auto-starts new game if no save exists
- `start_new_game()` — resets save, generates via NewGameGenerator, shows OpeningCrawl
- `_enter_gameplay()` — builds stats panel, loads event log, starts paused

### StatsPanel (`scripts/ui/StatsPanel.gd`)
- Scene: `scenes/Main.tscn` (child node `Layout/StatsPanel`)
- Purpose: displays all stats with colored bars/values, day/season, new game and roster buttons
- `build(stat_definitions)` — creates UI rows for each stat
- `refresh()` — pulls current values from save.db, updates bars/labels/colors
- Signals: `new_game_requested`, `roster_requested`
- Data: pulls from DB on each `refresh()` call (pushed by TickManager after each tick)

### EventLog (`scripts/ui/EventLog.gd`)
- Scene: `scenes/Main.tscn` (child node `Layout/RightArea/EventLog`)
- Purpose: scrollable log of narrative events
- `load_from_db()` — loads all event_log entries on game start
- `append_entry(entry)` — adds a new label, auto-scrolls if at bottom
- `clear()` — removes all entries
- Data: pushed by TickManager via `_ui_event_log.append_entry()`; Tier 1 entries dim, Tier 2 primary color

### TimeControls (`scripts/ui/TimeControls.gd`)
- Scene: `scenes/Main.tscn` (child node `Layout/RightArea/TimeControls`)
- Purpose: pause/normal/fast speed buttons
- Signal: `speed_changed(speed: int)` — connected to `TickManager.set_speed()` by Main
- `set_speed(speed)` / `get_speed() -> int`

### EventPopup (`scripts/ui/EventPopup.gd`)
- Scene: `scenes/ui/EventPopup.tscn`
- Purpose: modal popup for Tier 2 and chain decision events
- `present(event, resolved_description, choices, relevant_stat_names)` — builds title, description, choice buttons, stat hints
- Signal: `choice_made(choice_index: int)` — connected to TickManager's choice handler
- Instantiated dynamically by TickManager, calls `queue_free()` on choice selection

### OpeningCrawl (`scripts/ui/OpeningCrawl.gd`)
- Scene: `scenes/ui/OpeningCrawl.tscn`
- Purpose: full-screen opening text overlay on new game
- `show_text(text)` — sets crawl label text
- Signal: `dismissed` — connected to Main._on_crawl_dismissed()

### RosterPanel (`scripts/ui/RosterPanel.gd`)
- Scene: `scenes/Main.tscn` (child node `RosterPanel`)
- Purpose: lists living population with name/age/skills and role assignment dropdowns
- `refresh()` — queries population + roles, builds member rows with OptionButton for role assignment
- `_assign_role(person_id, role_id)` — updates population table, recalculates food_production, warns if over max_slots
- Signal: `closed`
- Data: pulls from DB on each `refresh()` call

## Event System Summary

### Tier 1 (Ambient)
Each tick rolls 0-3 events (15%/45%/30%/10%). Pool filtered by `EligibilityEngine.is_eligible()`. Weighted random selection. Actors cast via `ActorCaster.cast()`. Template resolved via `TemplateResolver.resolve_event()`. Written to `event_log` as tier=1. No player choice.

### Tier 2 (Decision)
3% base chance per tick (skipped if popup already active). Eligible non-chain tier=2 events filtered. Up to 4 casting attempts. Game pauses, EventPopup shown. On choice: immediate_effects applied → community_scores updated → RollEngine.roll() → outcome effects applied → flags set/cleared → outcome text resolved → written to event_log as tier=2 with is_highlighted=1. May schedule deferred outcomes or start chains.

### Deferred Outcomes
Scheduled when a choice has a `deferred` block. Stored in `pending_deferred` with fire window (delay_min_days..delay_max_days). Each tick: fire pending log_hints at their day_offset, then attempt resolution with probability `1/remaining_window` (forced at latest day). Resolution uses RollEngine against check_config, applies effects and flags.

### Chains
Started by a Tier 2 outcome's `chain_to` field. `ChainSystem.start_chain()` writes to `active_chains` with initial memory. Each tick, `get_due_chains()` returns chains past their `next_fire_day`. At most one chain stage processed per tick. Stages are events in the library with `chain_id` and `chain_stage` set. Stages without choices auto-resolve (log as tier=1, follow `chain_auto_next`). Stages with choices show EventPopup. Outcomes can write to chain memory, advance to `next_stage_id`, or end the chain (no next_stage_id). Chain memory persists across stages.

### Event Row Structure
```
id, tier, category, title, eligibility (JSON), description_template,
actor_requirements (JSON), choices (JSON), chain_id, chain_stage,
chain_memory_schema (JSON), chain_auto_next, cooldown_days,
exclusion_group, max_occurrences, content_tags, seasonal_tags, weight
```

### Choice JSON Structure
```json
{
  "id": "choice_id",
  "text_template": "Do the thing with {actor_1}",
  "immediate_effects": {"morale": 5, "resources": -3},
  "community_scores": {"commonwealth": 2},
  "roll": {
    "base_value": 0.0,
    "relevant_stats": [{"stat": "security", "weight": 1.0}],
    "context_bonuses": [{"condition": "actor_has_skill:combat", "bonus": 0.3}]
  },
  "outcomes": {
    "good": {"text": "It worked.", "effects": {"security": 5}, "flags_set": [], "flags_cleared": [], "next_stage_id": null, "chain_memory_write": {}, "chain_to": null},
    "bad": {"text": "It failed.", "effects": {"security": -5}}
  },
  "deferred": {
    "delay_min_days": 7, "delay_max_days": 30,
    "check": {"base_value": 0.0, "relevant_stats": []},
    "outcomes": {"good": {"text": "...", "effects": {}}, "bad": {"text": "...", "effects": {}}},
    "log_hints": [{"day_offset": 3, "text": "Something is stirring..."}]
  }
}
```

## Key Conventions

**JSON fields**: stored as TEXT columns, always parsed with `JSON.parse_string(str(value))`. Always check for null return.

**Stat deltas**: positive deltas multiplied by `stability_factor` (0.5 + stability/200), negative applied in full, then clamped to stat min/max.

**TemplateResolver.resolve_event() resolution order**:
1. Actor variables: `{actor_N}` → name, `{actor_N_modifier}` → random description_modifier from personality behavior_profile, `{actor_N_mention}` → mention_context
2. Stat bands: `{stat.morale}` etc → critical/low/moderate/good/high (thresholds: ≤20/≤40/≤60/≤80/>80). `{stat.food}` → food weeks band (critical <1wk, low <3, moderate <6, adequate ≥6)
3. Chain memory: `{memory.key_name}` → value from chain memory dict
4. Location/state: `{building}` → random structure, `{season}` → capitalized, `{population_count}`, `{game_day}`, `{outcome_label}` → outcome tier description
5. Remaining `{key}` tokens stripped via regex

**Weighted random**: accumulate `weight` field, roll `randf() * total_weight`, return first item where cumulative >= roll.

**Event ID conventions**: `amb_*` (tier 1 ambient), `tier2_*` (tier 2 standalone), `chain_*_N` (chain stage N).

**food_production**: baseline stored in `game_state.food_production` (sum of farmer count × farmer role bonus). Recalculated by RosterPanel on role change. In PassiveSimulation, effective = (baseline + role_food_production) × season_modifier.

**Actor flag syntax in outcomes**: `"actor_1:flag_name"` targets actor's personal flags JSON; plain `"flag_name"` targets global flags table.

## What Is Not Yet Implemented

- Tier 3 full-screen event popup
- Tier 4 defining moment events
- Community scoring roll modifiers (scores accumulate but don't yet affect rolls)
- Loss condition game-over screen and ending sequences
- Endgame / community type reveal screen
- Stat detail click-through panel (trend charts, derived values)
- Save/load system (always uses `user://save.db`, no save slots)
- Escalation links between Tier 2 and Tier 3
- Chain merging system
- Difficulty scaling beyond time_factor widening rolls
- Multiple apocalypse/origin/location variants (currently one of each seeded)
- Multiple personality types (currently only "caregiver" is seeded and assigned)

## Common Tasks

### Adding a new Tier 1 event
Insert into library.db `events` table. Minimum fields:
```sql
INSERT INTO events (id, tier, category, title, eligibility, description_template, actor_requirements, cooldown_days, weight)
VALUES ('amb_new_event', 1, 'ambient', 'New Event', '{}', '{actor_1} did something near {building}.', '{"actor_1":{"required_skills":[],"required_personality":null,"excluded_flags":[],"prefer_not_recent":true}}', 3, 1.0);
```
Set `actor_requirements` to NULL if no actors needed. Use eligibility JSON for state/world tag gating.

### Adding a new Tier 2 event
Same as above with `tier=2`, plus `choices` JSON array. Each choice needs at minimum: `id`, `text_template`, `roll` (with `base_value` and `relevant_stats`), `outcomes` (at least `good` and `bad` with `text` and `effects`).

### Adding a stat
1. Add row to library.db `stats` table with unique id, display_name, min/max/default, thresholds, display_order, format_type
2. NewGameGenerator will auto-create `current_stats` row on new game using default_value
3. Add passive simulation logic in PassiveSimulation.run_tick() if it should drift

### Adding a simulation_config constant
1. Insert into library.db `simulation_config`: `(key, value, description)`
2. Add key to `config_keys` array in TickManager._run_tick() step 1
3. Use via `config["KEY_NAME"]` in PassiveSimulation or PopulationLifecycle

### Adding a new personality
Insert into library.db `personalities` table:
```sql
INSERT INTO personalities (id, display_name, description, stat_links, event_weights, behavior_profile, ambient_templates)
VALUES ('warrior', 'Warrior', 'Description...', '{"security":0.2}', '{"dispute":1.5,"combat":2.0}',
'{"instigator_weight":1.5,"helper_weight":0.5,"departure_threshold":10,"description_modifiers":["fiercely","sharply"]}',
'["{actor_1} sharpened a blade near {building}."]');
```
Then update NewGameGenerator._generate_person() to assign personalities beyond "caregiver".

### Extending TemplateResolver
Add new token handling in `resolve_event()`. Resolution order: actors (pass 1) → stat bands (pass 2) → chain memory (pass 2b) → location/state (pass 3) → base resolve (pass 4) → strip unresolved (final). New tokens should be added in the appropriate pass based on their data source.
