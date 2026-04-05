from pathlib import Path

from lib.registry import Registry


def test_registry_round_trip(tmp_path: Path):
    registry = Registry(tmp_path)
    instance = registry.create_instance(
        pid=999,
        port=17700,
        root_path="/tmp/docs",
        target_path="/tmp/docs/index.md",
        theme="github",
        watch=True,
    )
    listed = registry.list_instances()
    assert listed[0]["id"] == instance["id"]
    assert listed[0]["port"] == 17700


def test_delete_instance_removes_registry_file(tmp_path: Path):
    registry = Registry(tmp_path)
    instance = registry.create_instance(
        pid=1,
        port=17700,
        root_path="/tmp/docs",
        target_path="/tmp/docs/index.md",
        theme="github",
        watch=True,
    )
    registry.delete_instance(instance["id"])
    assert registry.list_instances() == []
