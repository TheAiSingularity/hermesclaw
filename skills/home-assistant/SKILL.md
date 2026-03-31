---
name: home-assistant
description: Natural language smart home control — parses commands and invokes Home Assistant via MCP, learns your routines and auto-creates cron skills for them
license: MIT
compatibility: [macOS, Linux]
user-invocable: true
metadata:
  version: 0.1.0
  author: TheAiSingularity
  tags: [home-automation, home-assistant, telegram, cron, mcp]
  requires_tools: [memory, cron]
  required_environment_variables:
    - name: HA_TOKEN
      prompt: "Your Home Assistant Long-Lived Access Token"
      help_url: "https://www.home-assistant.io/docs/authentication/"
---

# home-assistant-control

This skill handles natural language smart home commands by invoking the Home Assistant MCP server. It learns your preferences and routines from repeated use.

## When to invoke

- When the user gives any home control command (lights, thermostat, locks, sensors)
- When the user asks for home status ("is anything left on?", "what's the temperature?")
- When the user asks to create an automation or routine

## Steps to execute

1. **Parse the command**
   - Identify: action (turn on/off/dim/set/check), entity (lights, thermostat, lock, TV), room/area, value (brightness %, temperature)
   - Check MEMORY.md for user preferences: "always leave porch light on after 9pm", "default dim level 40%"
   - If the command is ambiguous, ask one clarifying question

2. **Check Home Assistant for entity names**
   - Use the HA MCP `list_entities` tool to find the correct entity IDs for the named devices
   - Example: "living room lights" → `light.living_room`, `light.living_room_lamp`
   - Cache entity mappings in memory for faster future lookups

3. **Execute the action**
   - Call the appropriate HA MCP service:
     - Lights: `light.turn_on`, `light.turn_off`, `light.set_brightness`
     - Climate: `climate.set_temperature`, `climate.set_hvac_mode`
     - Locks: `lock.lock`, `lock.unlock`
     - Switches: `switch.turn_on`, `switch.turn_off`
     - Media: `media_player.turn_off`, `media_player.volume_set`
   - Confirm the result from the MCP response

4. **Confirm to user**
   - Report what was done: "Done. Living room lights turned off. Thermostat set to 68°F."
   - If any devices failed (offline, unreachable): report which ones and suggest checking HA

5. **Learn routines**
   - Track patterns in MEMORY.md: if the user gives the same combination of commands repeatedly
   - After 3+ similar requests: "I notice you often turn off lights and lock the door together in the evening. Want me to create a 'goodnight' routine?"
   - If user agrees: create a named cron skill for it using the `cron` tool

6. **Handle routine triggers**
   - If user says "goodnight", "leaving", "morning" etc.: check MEMORY.md for saved routines
   - Execute the matched routine if one exists
   - If no routine exists: execute reasonable defaults and ask if they want to save it

## Common command patterns

- "Turn off all lights" → iterate `light.*` entities and turn off all
- "Set thermostat to 70" → `climate.set_temperature` on climate entity
- "Lock the front door" → `lock.lock` on door lock entity
- "Is anyone home?" → check `person.*` entities or `group.all_devices` tracker
- "What's the temperature outside?" → read weather or outdoor sensor entity

## Output format

```
Done. [What was done]
[Any failures or notes]
```

For status checks:
```
Home status:
• Lights: [on: living room, kitchen | off: all others]
• Temperature: [inside: 72°F | outside: 58°F]
• Doors: [front: locked | garage: unlocked ⚠️]
• [Any alerts or anomalies]
```

## Notes

- This skill requires the Home Assistant MCP server to be configured in hermes.yaml
- Entity names vary by HA installation — the skill discovers them dynamically via `list_entities`
- Preferences and routines recorded in MEMORY.md persist across sessions (volume-mounted)
