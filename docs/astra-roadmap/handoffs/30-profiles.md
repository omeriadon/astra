# 30-profiles

Task / selected scope: Packet30 capability/product gate.

Decision: keep Astra's existing **Spaces** model and do not introduce browser profiles in this implementation cycle.

Branch / baseline: `astra/roadmap/30-profiles`; baseline packet28 HEAD `dd78aefebfff4453343da9cb939cdd4a88beccf6`. Packet22 remains a merge prerequisite for the final integrated tree, but no profile code is selected here.

Status: closed by the task's explicit gate; no source changes are required beyond this handoff.

Rationale grounded in the packet contract:

- Spaces currently organize tabs while sharing the normal browser website-data/session/service ownership model. They are intentionally not isolation/security boundaries.
- A real profile implementation would require separate persistent WebKit website data stores plus profile-scoped history, bookmarks, extensions, settings, download policy, persistence, sync identity and private-window routing.
- Implementing only a visual profile switcher or separate tab groups while reusing cookies/extensions/storage would violate the packet's isolation acceptance criteria.
- The task explicitly permits a product decision to keep spaces without profiles and close the packet without code.

Preserved behavior:

- Existing users retain one normal browser data universe and their current Spaces unchanged.
- No cookie/history/bookmark/extension migration occurs.
- Private windows retain the current private-session isolation contract and are not redefined relative to a profile model.
- Packet29 synchronization IDs/timestamps remain unchanged; no profile identity dimension is added to the sync format.

Future activation requirements, if profiles are later selected:

- Prove the intended persistent multi-data-store WebKit API on all supported OS targets before migration work.
- Specify migration of existing normal data into a stable default-profile ID without losing cookies or changing synchronized entity IDs.
- Make extension manager, website data, history/bookmarks/settings/download routing profile-scoped before exposing a switcher.
- Define profile deletion/export/reset semantics and sync identity so deleting one profile cannot remove another profile's files/data.
- Re-run private-window and task29 timestamp/isolation matrices with two persistent profiles across relaunch.

Data/privacy/migration impact: none. This is deliberately safer than presenting non-isolated Spaces as profiles.

Merge prerequisites: packets04,18,22,28,29 only matter if profiles are activated later. User-controlled integration only.
