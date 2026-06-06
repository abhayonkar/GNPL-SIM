import os
import re

files_to_check = [
    "export/exportDataset.m",
    "exportDataset.m",
    "run_48h_continuous.m",
    "run_24h_sweep.m",
    "scripts/evaluate_cross_regime.py"
]

print("🔍 Scanning for the 'Fault Label' bug...")
print("   (Faults incorrectly setting label=1 alongside Attacks)\n")

for fpath in files_to_check:
    if not os.path.exists(fpath):
        continue
        
    with open(fpath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    changed = False
    for i, line in enumerate(lines):
        # MATLAB pattern: .label = ... | ... FAULT ...
        if fpath.endswith('.m') and re.search(r'\.label\s*=', line):
            if '|' in line or 'FAULT' in line.upper() or 'logFault' in line:
                print(f"❌ Found bug in {fpath} (Line {i+1}):\n   {line.strip()}")
                
                # Try to patch it
                if 'T.label' in line or 'dataset.label' in line:
                    prefix = line.split('.label')[0].strip()
                    lines[i] = f"    {prefix}.label = double({prefix}.ATTACK_ID > 0);\n"
                else:
                    lines[i] = f"    % PATCHED: Removed FAULT_ID from label\n    {line}"
                
                print(f"✅ Patched to:\n   {lines[i].strip()}\n")
                changed = True
                
        # Python pattern: df['label'] = ... | ... FAULT ...
        elif fpath.endswith('.py') and re.search(r'\[\'label\'\]\s*=', line):
            if '|' in line or 'FAULT' in line.upper():
                print(f"❌ Found bug in {fpath} (Line {i+1}):\n   {line.strip()}")
                
                match = re.search(r'([A-Za-z0-9_]+)\[\'label\'\]', line)
                if match:
                    df_var = match.group(1)
                    lines[i] = f"    {df_var}['label'] = ({df_var}['ATTACK_ID'] > 0).astype(int)\n"
                    print(f"✅ Patched to:\n   {lines[i].strip()}\n")
                    changed = True

    if changed:
        with open(fpath, 'w', encoding='utf-8') as f:
            f.writelines(lines)
        print(f"💾 Saved changes to {fpath}\n")

print("🎯 Scan complete! Run `python .\\scripts\\diagnose_48h_labels.py` again.")
print("   (The label count for '1' should now drop to 0 for these clean runs).")