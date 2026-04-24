# Scripts Directory

This directory contains automation scripts for the gas pipeline cyber-physical testbed.

## Baseline Preservation Scripts

### create_baseline.sh

Creates baseline preservation artifacts for reproducibility.

**Purpose**: Freeze current system state as a reproducible reference point

**Usage**:
```bash
./scripts/create_baseline.sh
```

**Actions**:
1. Creates git tag `baseline-v0-phase-c` at current HEAD
2. Archives `ml_outputs/` directory with timestamp
3. Stores archive in `archive/` with read-only permissions
4. Verifies tag and archive creation

**Requirements**: 1.1, 1.2, 1.3, 1.4

**Status**: Scaffolding complete. Implementation in tasks 2.1 and 2.2.

---

### validate_baseline.sh

Validates baseline reproducibility by re-running detector training.

**Purpose**: Verify that baseline results can be reproduced

**Usage**:
```bash
./scripts/validate_baseline.sh <baseline-tag>
```

**Example**:
```bash
./scripts/validate_baseline.sh baseline-v0-phase-c
```

**Actions**:
1. Checks out specified baseline tag
2. Re-runs `train_temporal_graph.py` with fixed seed
3. Compares results against archived baseline
4. Checks F1 score differences within 2% tolerance
5. Runs existing MATLAB and Python tests
6. Generates validation report

**Requirements**: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6

**Status**: Scaffolding complete. Implementation in task 2.3.

---

## Script Conventions

### Exit Codes
- `0`: Success
- `1`: General error
- `2`: Invalid arguments
- `3`: Validation failure

### Error Handling
- All scripts use `set -e` to exit on first error
- Color-coded output: Red (error), Yellow (warning), Green (success)
- Detailed error messages with context

### Logging
- Scripts log to stdout/stderr
- Detailed logs can be captured: `./script.sh 2>&1 | tee script.log`

## Development Guidelines

### Adding New Scripts

1. Use bash shebang: `#!/bin/bash`
2. Include header comment with purpose and requirements
3. Use `set -e` for error handling
4. Add color-coded output for user feedback
5. Document in this README
6. Make executable: `chmod +x scripts/new_script.sh`

### Testing Scripts

1. Test on clean repository state
2. Test error conditions (missing files, invalid args)
3. Verify exit codes
4. Check output formatting

## Related Documentation

- Requirements: `.kiro/specs/phase-0-baseline-audit/requirements.md`
- Design: `.kiro/specs/phase-0-baseline-audit/design.md`
- Tasks: `.kiro/specs/phase-0-baseline-audit/tasks.md`
- Archive: `archive/README.md`
