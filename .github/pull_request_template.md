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
# hermesclaw doctor --quick output:

# cd cli && npm test output (last 10 lines):
```

## Checklist

- [ ] `hermesclaw doctor --quick` passes with no new FAIL entries
- [ ] `cd cli && npm test` passes
- [ ] `shellcheck` passes on any modified shell scripts
- [ ] All modified YAML files parse without errors
- [ ] `docs/test-results.md` regenerated if feature coverage changed (`bash benchmarks/compare-features.sh --quick`)
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] Docs updated in `docs/features.md` if a feature was added or removed

## Screenshots / output (if applicable)

<!-- Delete this section if not relevant -->
