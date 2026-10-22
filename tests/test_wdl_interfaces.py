"""Static interface checks for the repository's simple WDL task layout.

These checks catch duplicate task declarations and stale call input names. They
do not replace a full WDL parser such as WOMtool.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DECLARATION = re.compile(r"^\s*(?:File|String|Int|Boolean|Array\[[^]]+\]\+?)\??\s+(\w+)", re.M)
CALL = re.compile(r"call\s+(\w+)\.(\w+)\s+as\s+(\w+)\s*\{\s*input:\s*(.*?)\n\s*\}", re.S)


def declarations(source, section):
    match = re.search(r"\b" + section + r"\s*\{([^}]*)\}", source, re.S)
    if not match:
        raise AssertionError(f"Missing {section} section")
    return DECLARATION.findall(match.group(1))


class WdlInterfacesTest(unittest.TestCase):
    def test_task_inputs_and_outputs_have_distinct_names(self):
        for path in sorted((ROOT / "tasks").glob("*.wdl")):
            with self.subTest(task=path.name):
                source = path.read_text(encoding="utf-8")
                names = declarations(source, "input") + declarations(source, "output")
                self.assertEqual(len(names), len(set(names)))

    def test_workflow_call_inputs_exist_on_imported_tasks(self):
        workflow = (ROOT / "workflow.wdl").read_text(encoding="utf-8")
        imports = dict(re.findall(r'import "(tasks/[^\"]+\.wdl)" as (\w+)', workflow))
        namespaces = {namespace: ROOT / path for path, namespace in imports.items()}
        calls = list(CALL.finditer(workflow))
        self.assertTrue(calls)
        for call in calls:
            namespace, task, alias, arguments = call.groups()
            with self.subTest(call=alias):
                source = namespaces[namespace].read_text(encoding="utf-8")
                self.assertRegex(source, r"\btask\s+" + re.escape(task) + r"\s*\{")
                inputs = set(declarations(source, "input"))
                supplied = set(re.findall(r"(?:^|,)\s*(\w+)\s*=", arguments))
                self.assertTrue(supplied, f"No inputs found for {alias}")
                self.assertEqual(supplied - inputs, set())


if __name__ == "__main__":
    unittest.main()
