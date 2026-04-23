# Crash Ideas

These are hypotheses for the persistent hard crash during AI move enumeration/search.
None of these are confirmed. The goal is to preserve the likely causes worth testing later.

1. Search-time `ActionUIData` controls are being added to the live scene tree, and one of them triggers recursive notifications or signals until Godot segfaults.

2. A specific custom `ActionUIData` scene assumes real `ActionButtons` state and dereferences it in a way that produces unstable engine behavior when called from the AI search path.

3. `ParryActionUIData` is still a suspect because it reads `action_buttons.opponent_action_buttons.current_button`, and the stub may not match the full live object shape expected by downstream code.

4. `HurtGrounded` is probably not the root cause; it may just be the last logged search state before the next candidate scene is instantiated and crashes the engine.

5. One of the temporary UI scenes may contain a `Timer`, deferred signal, or visibility/layout callback that becomes unsafe when created repeatedly during deep search.

6. The crash may come from `Node::_notification` recursion caused by ephemeral controls being attached and freed rapidly while Godot is still processing layout or draw notifications.

7. A child widget such as `XYPlot`, `8Way`, `CountOption`, or a character-specific control may require `_ready()`/tree state, and search is activating it in a partial state that normal gameplay never hits.

8. Some search-time UI data scene may be emitting `data_changed` or another signal that loops back into update logic, creating a stack overflow rather than a script exception.

9. A candidate move may have a malformed or unexpected `data_ui_scene` in a modded character state, so the AI path is instancing something the real UI only uses under stricter conditions.

10. A freed temporary control may still be referenced by a deferred call or connected signal, and the next idle/notification cycle trips over a stale object pointer.

11. The crash may involve the ghost game and the temporary UI scene together: search copies state into ghost objects, then a UI script reads fighter data that is mid-copy or not fully synchronized.

12. The repeated `Timer was not added to the SceneTree` warnings may be secondary, but they strongly suggest at least one UI helper scene is being exercised outside the assumptions it was written for.

13. Search branching itself may be exposing a vanilla game bug: the player can enter a legal-but-rare state combination where the normal UI never instantiates the same data scene as often as the AI does.

14. There may be a character-specific action data scene outside the currently inspected list that overrides `_notification`, `fighter_update()`, or `get_data()` in a way that is only unsafe under search spam.

15. The crash could still be caused by non-UI code, but the coredump signature dominated by `Object::emit_signal`, `GDScriptInstance::call`, and `Node::_notification` makes a UI/control recursion bug the leading theory.
