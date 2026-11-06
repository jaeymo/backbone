# Changelog

## Unreleased (0.2.0)

### CharacterController

CharacterController no longer depends on EntityController. Characters stay where Roblox puts
them (no more Entity container Model), and both realms track them straight from `Players`.

- **Added** `:GetLocalCharacter()`: the local `CharacterObject`, or nil.
- **Added** `:GetLocalCharacterAsync()`: a Promise for the local `CharacterObject`. It resolves
  immediately if the character is loaded, otherwise when the next one loads.
- **Added** `:GetCharacterForPlayerAsync(player)`: the same, for any player. It rejects if the
  player leaves first.
- **Added** `:GetCharacterFromInstance(instance)`: resolves a part (or the Model) to its
  `CharacterObject`.
- **Added** `character.Janitor`, which is cleaned up when the character is removed.
- **Changed** `CharacterObject` fields are flat: `.Model`, `.Humanoid`, `.Root`, `.Animator`.
- **Changed** `character.Animation` only exists for the local character. Previously every
  character on the client shared one animation group, and after a respawn that group stayed
  bound to the dead character's Animator.
- **Changed** characters are also removed when their Model is destroyed or replaced without
  `CharacterRemoving` firing.
- **Fixed** listeners connected in any module's `OnStart` now receive characters that already
  existed when Backbone started.

### PhysicsController

- **Changed** `COLLISION_MATRIX` / `:ApplyCollisionMatrix()` only need the pairs that should
  collide. Undeclared pairs of different groups named in the matrix are now non-collidable
  (previously they were left at Roblox's default, collidable). A group's collision with itself,
  and groups the matrix doesn't name, still only change when declared.
- **Added** config validation for the matrix: malformed rows, non-boolean entries, and pairs
  declared with conflicting values.

### Migration

| Before | After |
| --- | --- |
| `CharacterController.LocalCharacter` | `CharacterController.LocalCharacterObject` or `:GetLocalCharacter()` ¹ |
| `:BindRemovingToPlayer()` | `:BindRemovedToPlayer()` ¹ |
| `character.Agent:GetModel()` / `:GetHumanoid()` / `:GetRoot()` / `:GetAnimator()` | `character.Model` / `.Humanoid` / `.Root` / `.Animator` ² |
| `character.Agent.Janitor` | `character.Janitor` |
| `character.Entity`, `EntityController` lookups for characters | `CharacterController:GetCharacterFromInstance()`, `:GetCharacters()` ² |
| `Backbone.Character` type | `Backbone.CharacterObject` (`Character` remains as a deprecated alias) |
| `Backbone.Agent`, `Backbone.CharacterRuntimeBuildDefinition` types | Removed |
| `CHARACTER.CLIENT_CHARACTER_MODEL_TIMEOUT` | `CHARACTER.LOAD_TIMEOUT` (now applies on both realms) ³ |
| `TAGS.AGENT` | Removed ³ |
| `ENABLED_CONTROLLERS.CHARACTER` required `ENTITY` | No longer required |
| Collision matrix pairs you relied on being collidable without declaring them | Declare them `true` |

¹ Still works, but warns once with a stack trace.
² Reading `character.Agent` or `character.Entity` errors with a pointer to the replacement.
³ Config validation names the replacement instead of reporting an unknown setting.
