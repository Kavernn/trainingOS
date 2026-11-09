#!/usr/bin/env python3
"""Strict catalogue gate. Reports all rows, including archived taxonomy defects."""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'api'))
from exercise_taxonomy import validate_catalogue

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot',type=Path)
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    findings=validate_catalogue(json.loads(args.snapshot.read_text()))
    report=json.dumps(findings,ensure_ascii=False,indent=2)+'\n'
    if args.output:args.output.write_text(report)
    else:print(report,end='')
    return bool(findings)
if __name__=='__main__':raise SystemExit(main())
