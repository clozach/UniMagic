"""Create Apple's legacy workflow plist accepted by `shortcuts sign`.

Only two built-in actions: URL (constant) and Open URLs (explicit URL action-output binding).
No downloads, scripts, network requests, or third-party shortcut actions.
The explicit action-output attachment matches a shortcut authored in Apple’s
Simulator editor and read back from that test shortcut’s persisted actions.
"""
import pathlib
import plistlib
import sys
import uuid

url_action_id = str(uuid.uuid4()).upper()

workflow = {
    "WFWorkflowClientVersion": "2600.0.3",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 61440},
    "WFWorkflowInputContentItemClasses": [],
    "WFWorkflowTypes": [],
    "WFWorkflowImportQuestions": [],
    "WFWorkflowActions": [
        {"WFWorkflowActionIdentifier": "is.workflow.actions.url", "WFWorkflowActionParameters": {"WFURLActionURL": "unimagic://picker", "UUID": url_action_id}},
        {"WFWorkflowActionIdentifier": "is.workflow.actions.openurl", "WFWorkflowActionParameters": {"WFInput": {"Value": {"string": "\ufffc", "attachmentsByRange": {"{0, 1}": {"OutputUUID": url_action_id, "Type": "ActionOutput", "OutputName": "URL"}}}, "WFSerializationType": "WFTextTokenString"}}},
    ],
}
output = pathlib.Path(sys.argv[1])
output.parent.mkdir(parents=True, exist_ok=True)
output.write_bytes(plistlib.dumps(workflow, fmt=plistlib.FMT_XML))
