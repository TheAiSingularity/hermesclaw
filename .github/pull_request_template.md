## Summary

<!-- One paragraph: what does this PR change and why? -->

## Type of change

- [ ] Bug fix
- [ ] New feature / policy preset
- [ ] Documentation improvement
- [ ] CI / tooling
- [ ] Refactor (no behaviour change)

## Testing done

<!-- What did you run? Paste relevant output below. -->

```
# ./scripts/doctor.sh --quick output:

# ./scripts/test.sh --quick output (last 10 lines):
```

## Checklist

- [ ] `./scripts/doctor.sh --quick` passes with no new `FAIL` entries
- [ ] `./scripts/test.sh --quick` runs to completion
- [ ] `shellcheck` passes on any modified shell scripts
- [ ] All modified YAML files parse without errors (`python3 -c "import yaml; yaml.safe_load(open('file.yaml'))"`)
- [ ] `docs/test-results.md` regenerated if feature coverage changed (`./scripts/test.sh --quick`)
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] Docs updated in `docs/features.md` if a feature was added or removed

## Screenshots / output (if applicable)

<!-- Delete this section if not relevant -->
