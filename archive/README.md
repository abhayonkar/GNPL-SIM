# Archive Directory

This directory stores baseline preservation artifacts for the gas pipeline cyber-physical testbed.

## Purpose

The archive directory maintains immutable snapshots of system outputs at key milestones, enabling:
- Reproducibility verification
- Performance regression detection
- Historical comparison of detector performance

## Structure

```
archive/
├── README.md                           # This file
├── ml_outputs_baseline_YYYYMMDD.tar.gz # Archived ml_outputs directory
└── baseline_results.json               # Baseline performance metrics
```

## Archive Naming Convention

Archives follow the pattern: `ml_outputs_baseline_YYYYMMDD.tar.gz`

- `YYYYMMDD`: ISO 8601 date format (e.g., 20260421)
- Archives are created with read-only permissions (444)
- Each archive corresponds to a git tag (e.g., baseline-v0-phase-c)

## Usage

### Creating a Baseline Archive

```bash
./scripts/create_baseline.sh
```

This will:
1. Create git tag `baseline-v0-phase-c`
2. Archive the `ml_outputs/` directory with timestamp
3. Store archive in this directory with read-only permissions

### Validating a Baseline

```bash
./scripts/validate_baseline.sh baseline-v0-phase-c
```

This will:
1. Checkout the specified baseline tag
2. Re-run detector training
3. Compare results against archived baseline
4. Report validation status (pass/fail)

## Requirements Traceability

- **Requirement 1.1**: Baseline tag naming convention
- **Requirement 1.2**: Archive with timestamp in filename
- **Requirement 1.3**: Read-only storage format
- **Requirement 1.4**: Tag references exact commit state

## Maintenance

- Archives should NOT be deleted without team consensus
- Archives should NOT be modified (read-only enforcement)
- New archives should be created for each major milestone
- Archive integrity should be verified periodically

## Related Documentation

- Requirements: `.kiro/specs/phase-0-baseline-audit/requirements.md`
- Design: `.kiro/specs/phase-0-baseline-audit/design.md`
- Tasks: `.kiro/specs/phase-0-baseline-audit/tasks.md`
