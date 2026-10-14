# Cylinder — World and Implementation Design

> **Status:** Living design document. This document separates the **fictional world and player experience** from **implementation decisions**. Possibilities are not commitments. Illustrative examples are not mandatory plot events or finalized data schemas.

## Part I — What Happens: World, History, and Story

This part describes what inhabitants and players experience, not how the software produces it.

### Core vision

*Cylinder* is envisioned as a persistent, living world in which stories arise from understandable causes and consequences. The player inhabits an artificial rotating habitat populated by ecosystems and uplifted civilizations. Animals, characters, communities, and environmental systems continue to exist and change independently of the player's immediate attention.

The goal is **plausible, internally consistent behavior**, not exhaustive physical or biological simulation. Simulate only the detail needed to produce meaningful observable consequences, within the hardware budget. A grazing animal need only recognize edible vegetation in its biome, choose to graze, and update the relevant resource and hunger states; the animation expresses the action rather than driving its logic.

The experience has **no mandatory ultimate conclusion**. It progresses through discoveries, responsibilities, relationships, and potentially many milestones. A coherent storyline can emerge through the same causal machinery that drives the world, rather than forcing every playthrough through predetermined plot events.

### The setting and its origins

#### The habitat

- The world is an O'Neill-style rotating cylinder with curved terrain, biomes, seasons, weather, and artificial gravity.
- Clockwise and counterclockwise rotation are supported in the underlying concept. Counter-rotating habitats can also help balance angular momentum in a larger installation.
- The cylinder may be one of **hundreds of experimental habitats**, analogous to Petri dishes housed within one research complex.
- A zero-gravity transit corridor could connect habitats near their rotational axes. Alternatively or additionally, automated transit capsules or elevator-like boxes could accept destination addresses.
- Inhabitants may initially believe their own cylinder is the entirety of their world. Discovering the larger complex becomes a major milestone.

#### Origins

Human researchers created the cylinders and began an **uplift experiment**: provide selected species with resources and opportunities to develop intelligence and civilization, then observe what happens and test hypotheses. Humans may have departed more than ten thousand years before the playable era. Their absence need not imply disaster; leaving the experiments alone may have been intentional.

The original hypothesis is not yet fixed. One possibility: can deliberately uplifted species develop independent intelligence, culture, and technological understanding in an isolated but well-supported environment? A later phase might ask whether those societies can understand and steward the systems that sustain them.

#### Uplifted peoples

Two illustrative civilizations are:

- **Raccoons:** Often imagined as agrarian farmers and ranchers, with their own settlements, architecture, and traditions.
- **Canines:** Often imagined as hunters, with distinct settlements, practices, and social organization.

These are starting ideas, **not immutable biological or cultural roles**. The societies generally coexist without extensive interaction, but circumstances may bring individuals together. Their cultures and identities are their own achievements, even if the AI and researchers supplied favorable initial conditions. The experiment need not be cruel or exploitative, and discovery of its origins need not provoke universal resentment.

Over millennia, the inhabitants may have developed mythologies about the world and its ancient caretakers. The truth of the habitat can be discovered gradually through observation, archaeology, engineering, and interaction.

### Living ecosystems

#### Habitats and resources

Existing biome and environmental data can define habitat suitability, edible vegetation, water, cover, terrain, temperature, and seasonal availability. These factors influence animal distribution, migration, and survival.

Vegetation can be represented as a regional resource pool with growth and depletion rules, rather than individual simulated plants. Rainfall and seasons affect growth; grazing reduces availability; excessive consumption can lead to overgrazing and population pressure.

#### Animals and needs

Potential state variables include hunger/satiation, thirst, energy, stamina, health, age, reproductive status, and species-specific environmental preferences. Animals may graze, drink, rest, wander, seek shelter, reproduce, defend offspring, migrate, or flee.

Examples include horses, deer, cattle, and other grazers; large cats and other predators; vultures and additional scavengers. **Horses are hindgut fermenters, not ruminants**, though both can participate in grazing systems.

#### Predation and scavenging

Predators select targets based on hunger, risk, accessibility, perceived vulnerability, and available alternatives. A hungry predator might attack the player, but attacks should not be inevitable: well-fed predators may avoid risky encounters. Defensive or territorial aggression is distinct from hunting.

A death leaves a carcass with remaining biomass, freshness, and decomposition state. Scavengers can discover and feed on it. Vultures circling over a carcass can become a useful environmental clue, not merely decoration. Decomposition eventually returns nutrients to the environment, at an abstraction level appropriate to the simulation.

#### Population dynamics

Reproduction, mortality, food availability, and predation affect populations over time. Predator–prey cycles, migration, and ecological recovery can emerge without hand-authored sequences. The system need not resolve every individual interaction in unloaded regions; aggregate population changes may be sufficient.

### Discovery, culture, and stewardship

#### Narrative philosophy

The game is not intended to have a single final victory or a compulsory sequence of plot checkpoints. It may offer **hundreds of milestones**, with different players reaching different discoveries at different times. The director can encourage developments, but outcomes remain contingent on autonomous behavior and player action.

A compelling storyline can be reconstructed or developed from events, motivations, and consequences. Narrative coherence is desirable, but should not require secretly resetting the world to prescribed states.

#### Possible long-term progression

A possible, **nonmandatory** arc:

1. Live within a seemingly natural world and learn its ecology and societies.
2. Observe unusual phenomena and discover ancient infrastructure.
3. Cooperate across raccoon and canine communities.
4. Discover the habitat's artificial construction and the original uplift experiment.
5. Establish communication with the caretaker AI.
6. Develop enough understanding to contribute to habitat stewardship.
7. Discover other experimental cylinders and connect with their inhabitants.

These are conceptual milestones, **not required chapter gates**. Different characters could reach them in different ways or not at all.

#### Uplift and stewardship

The uplift experiment may have begun simply to test a scientific hypothesis and see what happens. The AI supplied resources and opportunities, while the inhabitants independently built their own cultures, knowledge, and identities.

A natural later development is that inhabitants who understand the cylinder become capable of helping maintain it. **Stewardship follows from understanding**, rather than being awarded for obedience. The caretaker and the inhabitants may eventually become collaborators and fellow investigators.

A catastrophe is **not required** to justify this progression. Potential external threats, radiation events, structural crises, or manufacturing failures were explored but none has been selected as canon. The discussion favored avoiding implausible vulnerabilities in a mature, highly redundant habitat with advanced recycling and fabrication systems. A continuation of the experiment may be sufficient motivation.

#### Ethical tone

The uplift need not be portrayed as intrinsically exploitative. The inhabitants' cultures remain their own, and many might welcome learning that their ancestors were given an opportunity to flourish. Individuals can still disagree about interventions, but universal resentment or an obligatory villain is not part of the premise.

### Other cylinders and cooperation

#### Independent experiments

Each player's game may take place in a different cylinder within a much larger complex. The cylinders share underlying simulation rules but can develop distinct ecosystems, cultures, histories, and achievements. Whether starting conditions or species differ between cylinders is undecided.

#### Communication and visiting

Inter-cylinder contact could be a milestone achieved through understanding the habitat and accessing its infrastructure. Possible modes include:

- Remote communication between players or maintenance AIs.
- Remote participation through robotic avatars.
- Physical travel via zero-g corridors near cylinder axes.
- Addressable automated transit capsules/elevators connecting destinations.

The zero-g transfer mechanism must account for the transition between rotating habitats and nonrotating infrastructure; opposite rotation directions may also affect inhabitants' experience of motion.

#### Cooperation

Players can invite others to their cylinders and help one another achieve goals: ecological restoration, research, engineering, infrastructure repair, or discoveries. Ideally, cooperation uses the **same agent action and event system** rather than a separate class of multiplayer quests.

World access permissions, persistent identity, and individual knowledge should be independent of the host cylinder. An address can identify a destination; invitations or authorization determine who may enter. The previously discussed IRC-based communication concept may be suitable for non-time-critical messaging, though transport and security details remain implementation decisions.

### An illustrative chain of events

This example demonstrates the intended cause-and-effect model, **not a required quest**:

1. Seasonal rainfall drops in a grassland region.
2. Vegetation grows more slowly and herbivores begin moving toward better forage.
3. A predator follows the migrating herd toward farmland.
4. The predator kills a goat and leaves a carcass.
5. Scavengers gather; vultures overhead make the death visible from a distance.
6. A farmer discovers the loss and tells neighbors.
7. A hunter investigates, while others form competing explanations.
8. The maintenance AI observes the events and may introduce a new environmental condition or opportunity.
9. The player can investigate, intervene, ignore the situation, or collaborate with others.
10. Whatever happens becomes part of the cylinder's persistent history.

The world does not need to generate an explicit quest marker or guarantee a particular resolution. Dialogue, trade, animal behavior, and future events can all reflect the consequences.

## Part II — How It Works: Simulation and Implementation

This part describes the technical approach discussed so far. Proposed implementation sequences and unsettled choices remain explicitly provisional.

### Engineering principles

1. **Causality over spectacle.** Events should have understandable causes and consequences.
2. **Autonomy over scripts.** Animals and sentient characters make decisions based on their own needs, knowledge, and capabilities.
3. **Consistency over exhaustive realism.** Model only what matters; preserve consequences across changes in simulation detail.
4. **One agent architecture.** Animals, people, players, and the maintenance AI can share perception, goals, action selection, and event handling; capabilities differ.
5. **World state is not agent knowledge.** Characters may misunderstand, forget, learn, and pass along information.
6. **Data and simulation are separate from presentation.** The simulation must not depend on every entity being an active Godot scene node.
7. **Story through milestones, not mandatory endings.** Progress is discovery and increased understanding or capability, not necessarily a fixed win state.
8. **Player agency is genuine.** The world should not secretly undo consequences merely to force a preferred plot.

### Perception and agent decisions

#### Senses

Agents should perceive their surroundings rather than receive omniscient lists of nearby entities. Possible senses:

- **Vision:** range, field of view, line of sight, target size, contrast, motion thresholds, and occlusion.
- **Hearing:** sound events with intensity, approximate direction, and distance attenuation.
- **Smell:** optional later extension using proximity, scent persistence, and possibly wind.
- **Obstacle awareness:** terrain and nearby objects relevant to navigation and avoidance.

Detection and recognition are different. Movement in brush might be noticed before the agent identifies a deer, player, or predator.

#### Memory and relationships

Perceived entities can have last-known positions, identity confidence, and remembered interactions. Friend, foe, neutral, prey, and threat classifications should be contextual, not permanent universal labels. An agent can react differently depending on hunger, prior experience, territoriality, and offspring.

#### Decision-making

A practical starting point is **utility-based action selection plus finite-state behavior execution**. A utility score chooses among needs and opportunities; a state machine handles actions such as stalking, chasing, feeding, and resting. Hysteresis prevents constant switching. Individual variation and limited memory can make behavior less mechanical without neural-network simulation.

Sentient NPCs extend the same machinery with more elaborate memory, social relationships, language, abstract goals, planning, and cultural knowledge. A deer seeks forage; a farmer checks stored food or trades; a hunter tracks prey. The underlying need may be similar while available actions differ.

### Actions, effects, and the event log

#### Common causal mechanism

The central abstraction is:

**Observed state and events → agent evaluation → chosen action → effects → new world state and events.**

Actions can have prerequisites, permissions/capabilities, costs, and effects. Events record what happened, to whom, where, and—where known—what caused it. The same mechanism can serve wildlife, people, players, and system-level agents.

Example:

```yaml
# Illustrative conceptual schema, not a finalized file format
actor: deer_104
observes:
  biome: meadow
  edible_vegetation: true
state:
  hunger: 0.75
action: graze
preconditions:
  - food_accessible
  - can_feed
effects:
  - hunger: decrease
  - local_vegetation: decrease
  - event: animal_grazed
```

#### Event history and causality

Maintain a durable event history and, where useful, causal links among events. A drought can reduce grass growth, cause migration, draw predators toward livestock, and create a dispute between neighbors. Those are not necessarily scripted steps; each agent and subsystem responds to changing circumstances.

Event logs also support debugging, retrospective narratives, continuity, and explanations of why the world looks different when a player returns.

#### Dialogue as an event consumer

Conversation can respond to knowledge, relationships, and current events. A farmer may discuss lost livestock; a hunter may discuss tracks; an uninformed villager may say nothing. Dialogue can communicate knowledge and produce additional effects, such as sharing a discovery or accepting a request for help.

Rumors can propagate through NPC-to-NPC conversation, with imperfect information and differing perspectives. Dialogue should not assume that every character knows the global event log.

### Maintenance AI capabilities

The narrative director is **not fundamentally a separate kind of system**. It is another agent operating through the same observation, decision, action, and event mechanisms, but with access to broader effects.

Ordinary agents may graze, build, trade, hunt, or converse. The maintenance AI may also alter environmental controls, change weather, activate infrastructure, or initiate other large-scale events beyond the capabilities of ordinary inhabitants.

It can read the event history, identify developing conditions, and choose actions that create further consequences. It may be guided by causal objectives or a desired *direction* of world-state change, without dictating exactly how NPCs or players respond.

For example, the AI might influence rainfall. Reduced vegetation then affects grazers, predators, settlements, and conversation through ordinary simulation rules. It does not need to order a specific farmer to migrate or force a particular quest outcome.

This agent may be understood in-world as the cylinder's ancient **maintenance/caretaker AI**. Its historical responsibilities include preserving the habitat and continuing the uplift experiment. Its exact goals, authority limits, and degree of intervention remain open design questions.

### Simulation fidelity and performance

The world should continue evolving without keeping every animal, NPC, plant, or carcass as a live Godot node.

| Scope | Possible representation |
|---|---|
| Near the player | Active individual agents, perception, navigation, interaction, and animation |
| Distant but relevant | Simplified agents, herds, event-driven updates, and resource accounting |
| Unloaded regions | Aggregated populations, resource pools, elapsed-time calculations, and durable events |

Use spatial indexing for nearby candidates before expensive visibility tests. Update perception and behavior at rates appropriate to urgency. Use event-driven sound or other immediate stimuli when useful. Calculate processes such as decomposition or vegetation regrowth from elapsed time rather than updating every entity continuously.

**Critical continuity requirement:** transitioning between detailed and aggregate simulation must not arbitrarily create or erase meaningful history. Preserve important identities, ownership, manually placed objects, player changes, and significant events. Whether every animal has a persistent identity or only selected individuals do is an open choice.

This is especially important given the existing Godot scene-tree/rendering performance constraints. Simulation entities and their persistent data should remain independent of render nodes and animation.

### Possible implementation sequence

These are recommendations, not commitments:

1. **Shared event/action model:** define events, preconditions, effects, permissions, and event history independently of Godot presentation.
2. **Minimal herbivore loop:** hungry animal detects edible biome resource, grazes, rests, and changes local vegetation availability.
3. **Perception and memory:** candidate detection, line of sight, moving targets, and remembered last-known positions.
4. **Predator and carcass loop:** hunting, death, scavenger attraction, and elapsed-time decomposition.
5. **Regional ecology:** vegetation regrowth, reproduction, mortality, migration, and aggregate offscreen simulation.
6. **Sentient agents and dialogue:** knowledge, relationships, conversations conditioned on events, and knowledge transfer.
7. **Maintenance AI capabilities:** a normal agent able to trigger broader environmental effects and respond to the event log.
8. **Milestones and connected worlds:** discoveries, stewardship capabilities, addresses, invitations, and inter-cylinder communication/travel.

## Part III — Unresolved Questions and Design Direction

### Open decisions

- What exactly were the original uplift hypotheses, and how deliberately did the humans vary conditions between cylinders?
- How many species and societies exist, and how much do their roles vary?
- Which animals and NPCs retain persistent identities, family histories, and individual memory across unloaded regions?
- How should ecological resource pools be partitioned across biomes and map regions?
- What are the event schema, causal-link representation, action permission model, and durable storage format?
- How does the maintenance AI choose among possible large-scale interventions without forcing narrative outcomes?
- How should generated dialogue be represented, and how does information spread between agents?
- What qualifies as a milestone, and which capabilities emerge from knowledge versus access permissions?
- Are the cylinders physically adjacent, connected through a shared structure, or distributed across a larger complex?
- How are remote visits, persistent identity, multiplayer authorization, and offline simulation reconciled?
- What is the smallest practical prototype that demonstrates ecology, event propagation, and meaningful emergent consequences?

### Guiding principle

> Build a world that behaves consistently whether or not anyone is watching. Let its inhabitants pursue their own lives, let causes produce consequences, and let discovery and understanding open new possibilities. The simulation provides the world; the story is what happens within it.


