# Developer Documentation

Knowledge about this widget that the code alone does not tell you. Usage,
installation and the file overview are in the
[project README](../README.md).

| File | Contents |
| --- | --- |
| [architecture.md](architecture.md) | How ObsClient, panel indicator and mixer work together; connection states, protocol, data flow |
| [decisions.md](decisions.md) | Decisions with their reasons, grouped by topic |
| [development.md](development.md) | Workflow after code changes, testing with and without OBS, new texts and settings, release |

## What goes where

- **Code comment:** quirks tied to exactly one place in the code (e.g. why
  the mixer opens with a delay). That is where you see them when changing
  the code.
- **`docs/`:** relationships across several files, decisions with their
  reasons, workflows.
- **README:** everything users of the widget need.

A decision tied to a place in the code is documented there as a comment and
additionally in [decisions.md](decisions.md) with a reference to that place,
so it can be found without searching the code.
