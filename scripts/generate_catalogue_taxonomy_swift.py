#!/usr/bin/env python3
"""Generate the client vocabulary from the backend's pure data module."""
import json
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'api'))
from exercise_taxonomy_data import TAXONOMY as T

def swift(v):
    if isinstance(v,dict):return '['+',\n'.join(swift(k)+': '+swift(x) for k,x in v.items())+']'
    if isinstance(v,list):return '['+', '.join(swift(x) for x in v)+']'
    return json.dumps(v,ensure_ascii=False)

def generated():
    groups=',\n'.join('('+swift(k)+', '+swift(v)+')' for k,v in T['groups'].items())
    patterns=',\n'.join('('+swift(k)+', '+swift(v)+')' for k,v in T['patterns'].items())
    # Resolve canonical spellings before case-insensitive aliases.
    return '''// BEGIN GENERATED CATALOGUE TAXONOMY — scripts/generate_catalogue_taxonomy_swift.py
// Broad reporting groups and detailed targets are separate concepts.
enum CatalogueTaxonomy {
    static let musclesByGroup: [(group: String, specifics: [String])] = [\n'''+groups+''']
    static let movementPatterns: [(String, String)] = [\n'''+patterns+''']
    static let equipmentOptions: [String] = '''+swift(T['equipment'])+'''
    static let muscleAliases: [String: String] = '''+swift(T['muscle_aliases'])+'''
    static let groupAliases: [String: String] = '''+swift(T['group_aliases'])+'''
    static let patternAliases: [String: String] = '''+swift(T['pattern_aliases'])+'''
    static func muscle(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let canonical = musclesByGroup.flatMap(\\.specifics).first(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { return canonical }
        return muscleAliases.first(where: { $0.key.caseInsensitiveCompare(value) == .orderedSame })?.value ?? value
    }
    static func group(_ value: String) -> String {
        groupAliases[value] ?? value
    }
    static func pattern(_ value: String, group: String) -> String {
        if let canonical = patternAliases[value] { return canonical }
        if value.lowercased() == "isolation" {
            switch group {
            case "Biceps", "Triceps": return "isolation_arm"
            case "Avant-bras": return "accessory_wrist"
            case "Épaules", "Trapèzes": return "isolation_shoulder"
            case "Quadriceps", "Ischio-jambiers", "Fessiers", "Mollets", "Hanches": return "isolation_leg"
            default: break
            }
        }
        return value
    }
}
// END GENERATED CATALOGUE TAXONOMY
'''

if __name__=='__main__':
    path=ROOT/'Models/MuscleMapping.swift'
    text=path.read_text();marker='// BEGIN GENERATED CATALOGUE TAXONOMY'
    base=text.split(marker)[0].rstrip()+'\n\n'
    result=base+generated()
    if '--check' in sys.argv:
        if text!=result:raise SystemExit('Generated Swift taxonomy is stale')
    else:path.write_text(result)
